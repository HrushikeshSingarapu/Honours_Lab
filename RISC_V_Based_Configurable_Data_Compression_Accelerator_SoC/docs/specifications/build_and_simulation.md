# Build and Simulation User Guide

**Project:** RISC-V Based Configurable Data Compression Accelerator SoC  
**Target Architecture:** Western Digital / CHIPS Alliance VeeR EL2 Core (RV32IMC)  
**Supported OS:** Windows 11 (Native PowerShell & CMD)  

---

## 1. Prerequisites and Toolchain Setup

The verification and build flows are configured to execute natively on Windows without requiring WSL or a Linux virtual machine.

### Required Software Tools

| Tool | Minimum Version | Path / Executable | Purpose |
|:---|:---:|:---|:---|
| **ModelSim Starter Edition** | 2020.1 | `vlog.exe`, `vsim.exe` | SystemVerilog simulation of VeeR SoC & IP blocks |
| **Icarus Verilog** | 12.0 | `iverilog.exe`, `vvp.exe` | Fast regression simulation of standalone unit tests |
| **RISC-V GNU Toolchain** | GCC 13.3.0 | `riscv64-unknown-elf-gcc.exe` | Cross-compiling bare-metal firmware (`rv32imc`) |
| **RISC-V Binutils** | 2.42 | `riscv64-unknown-elf-objcopy.exe` | Extracting raw binary and disassembly |
| **Python** | 3.10+ | `python.exe` | Generating word-formatted Verilog HEX files |
| **PowerShell** | 5.1+ | `powershell.exe` | Automated simulation scripts and test regression runner |

Verify toolchain availability from PowerShell:
```powershell
riscv64-unknown-elf-gcc --version
vsim -version
iverilog -v
python --version
```

---

## 2. Firmware Compilation Flow

Bare-metal firmware sources reside in `RISC_V_Based_Configurable_Data_Compression_Accelerator_SoC/firmware/`:
- `start.S`: Processor reset handler, MRAC CSR initialization, and stack pointer setup.
- `linker.ld`: Linker script defining IMEM (`0x8000_0000`), DMEM (`0x0004_0000`), and DCCM (`0xF004_0000`).
- `main_dma.c`: Complete CPU-controlled DMA, RLE, and CRC-32 test suite.

### Compiling Firmware to Word-Aligned HEX

To compile `main_dma.c` into `dma_test_word.hex`:

```powershell
cd "RISC_V_Based_Configurable_Data_Compression_Accelerator_SoC\firmware"

# 1. Compile assembly startup and C runtime
riscv64-unknown-elf-gcc -march=rv32imc -mabi=ilp32 -O2 -nostartfiles `
  -T linker.ld start.S main_dma.c -o dma_firmware.elf

# 2. Extract raw binary from text section
riscv64-unknown-elf-objcopy -O binary -j .text dma_firmware.elf dma_firmware.bin

# 3. Disassemble for verification and debugging
riscv64-unknown-elf-objdump -d dma_firmware.elf > dma_firmware.dump

# 4. Convert little-endian binary to 32-bit word HEX for $readmemh
python -c @"
import struct
with open('dma_firmware.bin', 'rb') as f:
    data = f.read()
with open('dma_test_word.hex', 'w') as out:
    for i in range(0, len(data), 4):
        chunk = data[i:i+4]
        if len(chunk) < 4:
            chunk = chunk.ljust(4, b'\x00')
        val = struct.unpack('<I', chunk)[0]
        out.write(f'{val:08x}\n')
"@
```

> [!IMPORTANT]
> The VeeR SoC instruction memory model loads instructions via `$readmemh("firmware.hex", mem)`. Each line of the HEX file must represent exactly one 32-bit little-endian instruction word formatted as an 8-character hexadecimal string.

---

## 3. Automated Simulation Runners

### 3.1 Linux Synopsys VCS UVM Runner (`run_soc_uvm.sh`)

The repository includes a dedicated Linux Synopsys VCS runner for the unified SoC UVM environment:  
`RISC_V_Based_Configurable_Data_Compression_Accelerator_SoC/simulation/scripts/run_soc_uvm.sh`

```bash
cd RISC_V_Based_Configurable_Data_Compression_Accelerator_SoC
./simulation/scripts/run_soc_uvm.sh [test_name]
```
- Compiles the UVM verification suite (`verification/uvm/filelists/soc_uvm.f`).
- Executes `soc_smoke_test` with waveform dumping.
- Outputs logs to `simulation/logs/` and waveforms to `simulation/waveforms/`.

### 3.2 Windows Native Simulation Runner (`run_sim.ps1`)

For Windows ModelSim environments:  
`RISC_V_Based_Configurable_Data_Compression_Accelerator_SoC/simulation/scripts/run_sim.ps1`

### Script Syntax
```powershell
.\simulation\scripts\run_sim.ps1 -Target <boot|periph|uart|dma> [-Gui] [-RebuildFirmware]
```

### Supported Targets

| Target | Testbench | Firmware Executed | Target Functionality Verified |
|:---|:---|:---|:---|
| `boot` | `verification/standalone/soc/tb_soc_core_boot.sv` | Reset entry | Validates VeeR EL2 reset vector, MRAC initialization, and initial jump |
| `periph` | `verification/standalone/soc/tb_soc_periph_test.sv` | Periph check | Validates CPU MMIO register access to UART, Timer, and GPIO |
| `uart` | `verification/standalone/soc/tb_soc_uart_firmware.sv` | Serial print | Validates CPU writing characters to UART THR and serial output reception |
| `dma` | `verification/standalone/soc/tb_soc_dma_firmware.sv` | `main_dma.c` | **Full end-to-end CPU DMA + RLE compression + CRC-32 integrity flow** |

### Example Executions

Run the flagship CPU DMA+RLE+CRC validation in batch mode:
```powershell
cd "RISC_V_Based_Configurable_Data_Compression_Accelerator_SoC"
.\simulation\scripts\run_sim.ps1 -Target dma
```

---

## 4. Standalone Subsystem & Unit Test Simulation

Standalone testbenches can be compiled and executed directly using ModelSim, Icarus Verilog, or VCS from the SoC root.

### 4.1 Running with ModelSim (Command-Line Mode)

Example: Simulating the DMA Master Engine (`tb_dma_master_engine.sv`)

```powershell
cd "RISC_V_Based_Configurable_Data_Compression_Accelerator_SoC"
if (!(Test-Path "work")) { vlib work }

vlog -sv -work work `
  +incdir+rtl/accelerators/dma `
  rtl/accelerators/dma/dma_master_engine.v `
  verification/standalone/dma/tb_dma_master_engine.sv

vsim -c -do "run -all; quit -f" work.tb_dma_master_engine
```

Example: Simulating the CRC-32 Accelerator (`tb_crc32.sv`)

```powershell
cd "RISC_V_Based_Configurable_Data_Compression_Accelerator_SoC"
if (!(Test-Path "work")) { vlib work }

vlog -sv -work work `
  +incdir+rtl/peripherals/crc `
  rtl/peripherals/crc/crc32_top.v `
  verification/standalone/crc32/tb_crc32.sv

vsim -c -do "run -all; quit -f" work.tb_crc32
```

### 4.2 Running with Icarus Verilog

Example: Simulating the AXI 64-to-32 Protocol Bridge (`tb_axi64_to_32_bridge.sv`)

```powershell
cd "RISC_V_Based_Configurable_Data_Compression_Accelerator_SoC"

iverilog -g2012 -o bridge_sim.vvp `
  -I rtl/interconnect `
  rtl/interconnect/axi64_to_32_bridge.v `
  verification/standalone/interconnect/tb_axi64_to_32_bridge.sv

vvp bridge_sim.vvp
```

Example: Simulating the DMA Register File (`tb_dma_reg_file.sv`)

```powershell
cd "RISC_V_Based_Configurable_Data_Compression_Accelerator_SoC"

iverilog -g2012 -o dma_reg_sim.vvp `
  -I rtl/accelerators/dma `
  rtl/accelerators/dma/dma_reg_file.v `
  verification/standalone/dma/tb_dma_reg_file.sv

vvp dma_reg_sim.vvp
```

---

## 5. Troubleshooting & Best Practices

### Handling Paths Containing Spaces
When invoking RISC-V GCC, paths with spaces (e.g. `H:\Hrushi pro\...`) may cause GCC linker errors (`ld.exe: cannot find pro\Hon`).
- **Solution:** Always pass relative file names (e.g., `-o dma_firmware.elf`) within the firmware directory, as handled automatically in `run_sim.ps1`.

### VeeR Memory Region Attribute Configuration (MRAC)
If the VeeR EL2 core hangs or stalls indefinitely when issuing load/store transactions to DMEM or peripherals:
- Check that CSR `0x7C0` (`mrac`) is written with `0x5555_555A` in `start.S`. Without this configuration, external AXI transactions are treated as non-cacheable side-effect transactions and burst operations are disallowed.

### ModelSim License and Starter Edition
ModelSim Intel FPGA Starter Edition requires no paid license, but has a limit of 10,000 executable lines. All testbenches in this repository are optimized to compile and simulate completely within Starter Edition limits.

