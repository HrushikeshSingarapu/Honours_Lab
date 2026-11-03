# UVM 1.2 Verification Methodology, Reusable VIPs, Assertions & Coverage

## 1. Executive Summary

This document describes the advanced verification architecture implemented for the **RISC-V Based Configurable Data Compression Accelerator SoC**. The verification suite combines:
1. **Five Reusable External-Interface Verification IPs (VIPs)**: UART, GPIO, Reset, Interrupt Monitor, and Processor Trace Monitor.
2. **Complete UVM 1.2 Testbench for Custom RLE Accelerator (`rle_top`)**: Passive AXI4-Lite monitor, independent golden reference model, scoreboard, and functional coverage collector.
3. **Complete UVM 1.2 Testbench for Autonomous DMA Controller (`dma_top`)**: Dual-interface passive monitor (slave config + master interconnect), memory-level byte-by-byte scoreboard, and functional coverage collector.
4. **SystemVerilog Protocol Assertions**: AXI4/AXI4-Lite stability, DMA master burst alignment (WLAST/RLAST), and RLE state consistency.
5. **Unified Regression Runner (`run_uvm_regression.ps1`)**: Single-entry execution script supporting granular and full-chip regression with zero simulator license violations on Windows 11.

---

## 2. Reusable Verification IP (VIP) Architecture

Located in `tb/vip/`, the VIP suite provides modular, reusable verification components conforming to standard testbench best practices:

```
tb/vip/
├── common/
│   └── vip_types_pkg.sv         # Common types, enums (parity, severity, pulls, IRQ IDs)
├── uart/
│   ├── uart_pkg.sv              # Frame formats, baud timing parameters, sequence items
│   ├── uart_if.sv               # Physical UART TX/RX interface
│   ├── uart_driver.sv           # Configurable transmitter with glitch injection & baud rate
│   ├── uart_monitor.sv          # Receiver with start/stop/parity frame validation
│   └── uart_agent.sv            # Active/passive agent wrapper
├── gpio/
│   ├── gpio_pkg.sv              # GPIO pin configs, drive strengths, pulls
│   ├── gpio_if.sv               # Bidirectional GPIO interface with input/output/enable
│   ├── gpio_pad_model.sv        # Tri-state pad emulation with pull-up/pull-down models
│   ├── gpio_driver.sv           # External stimulus driver with contention detection
│   ├── gpio_monitor.sv          # Sample monitor tracking level changes and edge events
│   └── gpio_agent.sv            # Agent encapsulation
├── reset/
│   ├── reset_pkg.sv             # Reset timing configurations (power-on, warm reset)
│   ├── reset_if.sv              # Active-high and active-low reset interface
│   └── reset_driver.sv          # Async assert / sync deassert reset sequencer
├── irq/
│   ├── irq_pkg.sv               # Interrupt channel definitions & timing statistics
│   ├── irq_if.sv                # Multi-line interrupt bus interface
│   └── irq_monitor.sv           # Interrupt observer measuring latency & pulse width
├── trace/
│   ├── trace_pkg.sv             # RV32 instruction decoder & retirement tracker
│   ├── trace_if.sv              # Core trace bus interface (PC, Insn, Trap, Tval)
│   └── trace_monitor.sv         # RV32 disassembler, exception tracker, CPI calculator
├── vip.f                        # VIP compilation filelist
└── tb_vip_sanity.sv             # Standalone 7-test verification regression
```

### VIP Capabilities & Sanity Results

| VIP Module | Primary Verification Responsibilities | Sanity Verification Status |
| :--- | :--- | :---: |
| **Reset VIP** | Power-on sequence, warm reset, synchronous deassertion alignment | **PASS** |
| **UART VIP** | Cycle-accurate 8N1 serial framing, baud generation, character transmission/reception | **PASS** |
| **GPIO VIP** | 32-bit bidirectional driving, pull-up/down pad emulation, contention avoidance | **PASS** |
| **IRQ Monitor** | Pulse width tracking, assertion/deassertion latency, active-state accounting | **PASS** |
| **Trace Monitor** | RV32IMC instruction disassembly, core exception/trap decoding, CPI metrics | **PASS** |

Execution Command:
```powershell
powershell -ExecutionPolicy Bypass -File .\tb\run_uvm_regression.ps1 -Target vip
```
*Result: 7/7 checks passed (100% PASS).*

---

## 3. RLE Accelerator UVM 1.2 Verification Environment

Located in `tb/uvm/rle/`, this environment thoroughly exercises the synthesizable Run-Length Encoding accelerator (`rle_top`):

### Architecture & Decoupled Data Flow
The environment adheres strictly to decoupled UVM verification methodology:
- **`rle_driver` (Active)**: Converts sequence items into AXI4-Lite pin-level activity. Does not report results or communicate with the scoreboard.
- **`rle_monitor` (Passive)**: Independently observes interface pin handshakes:
  - Detects independent AW, W, B, AR, and R handshakes without assuming simultaneous arrival.
  - Reconstructs input streams from write strobes on `REG_INPUT_DATA` (0x010).
  - Captures operational mode from `REG_CONTROL` (0x000).
  - Tracks status and error flags from `REG_STATUS` (0x004).
  - Captures output byte count from `REG_OUTPUT_LENGTH` (0x00C) and drains output bytes from `REG_OUTPUT_DATA` (0x014).
  - Emits completed `rle_seq_item` via its analysis port `ap`.
- **`rle_scoreboard`**: Receives observed transactions exclusively through the monitor analysis port (`item_export`). Runs an independent software reference model and compares observed output byte-by-byte. Detects missing, duplicated, out-of-order, or corrupted bytes.
- **`rle_coverage`**: Subscribes to the monitor analysis port and bins transaction parameters.

### Verification Scenarios Covered
1. **Scenario 1**: Single-byte input (`[0x42]` $\rightarrow$ `[1, 0x42]`).
2. **Scenario 2**: Repeated bytes (16 bytes of `0xAA` $\rightarrow$ `[16, 0xAA]`).
3. **Scenario 3**: Maximum single-run boundary (255 bytes of `0x55` $\rightarrow$ `[255, 0x55]`).
4. **Scenario 3b**: Boundary run split (>255 bytes: 270 bytes $\rightarrow$ `[255, 0x33], [15, 0x33]`).
5. **Scenario 4**: Consecutive runs with varying symbols (`AAAAABBBCCCC`).
6. **Scenario 5**: Alternating uncompressed bytes (`0xA1, 0xB2, 0xA1, 0xB2, ...`).
7. **Scenario 6**: Lossless decompression expansion (`[10, 0x77], [5, 0x88]` $\rightarrow$ 15 bytes).
8. **Scenario 7**: Error condition: Odd input stream length for decompression.
9. **Scenario 8**: Error condition: Zero run count in decompression stream.

### Verification Results
- **Transactions Checked**: 9
- **Passed Comparisons**: 9
- **Failed Comparisons**: 0
- **Functional Coverage**: 8 / 8 bins (100.0%)
- **Protocol Assertions**: 0 Errors

---

## 4. DMA Controller UVM 1.2 Verification Environment

Located in `tb/uvm/dma/`, this environment verifies the autonomous Direct Memory Access engine (`dma_top`):

### Architecture & Memory-Level Verification
- **Dual-Interface Passive Monitor (`dma_monitor`)**:
  - **Slave Interface**: Observes CPU MMIO programming (`SRC_ADDR`, `DST_ADDR`, `INPUT_LEN`, `CONTROL`) and status readbacks (`STATUS`, `OUTPUT_LEN`, `ERROR_CODE`, `IRQ_STATUS`). Emits `dma_seq_item` on completion.
  - **Master Interface**: Observes all interconnect read and write transactions. Emits `dma_master_beat_item` containing address, data, byte strobes, response, and last signals for every beat.
- **Independent Reference-Model Scoreboard (`dma_scoreboard`)**:
  - Maintains golden reference source memory (`ref_dmem`) initialized with scenario patterns.
  - Tracks actual master read transactions to confirm source addresses and read data validity.
  - Reconstructs destination memory byte-by-byte from observed master write addresses, data, and byte strobes (`wstrb`).
  - Executes software `dma_ref_model` to generate golden expected compression/decompression output.
  - Checks performed on every transfer:
    1. Correct destination base address.
    2. Correct output length matching golden reference model.
    3. Byte-by-byte data comparison of reconstructed destination memory against golden output.
    4. Verification that no unexpected writes occurred outside the destination address range.
    5. Verification of write ordering and absence of duplicate writes.
    6. Correct hardware completion and error status codes (`ERR_BAD_LEN`).
- **Functional Coverage Collector (`dma_coverage`)**: Subscribes to the monitor's transfer analysis port to sample lengths, modes, and exception branches.

### Verification Scenarios Covered
1. **Scenario 1**: Single-byte DMA transfer (1 byte: `0x0004_0000` $\rightarrow$ `0x0005_1000`).
2. **Scenario 2**: 2-byte DMA transfer (`0x0004_0000` $\rightarrow$ `0x0005_2000`).
3. **Scenario 3**: 3-byte DMA transfer (`0x0004_0000` $\rightarrow$ `0x0005_3000`).
4. **Scenario 4**: 4-byte (1-word) DMA transfer (`0x0004_0000` $\rightarrow$ `0x0005_4000`).
5. **Scenario 5**: Standard multi-word compression flow (16 bytes: `0x0004_0000` $\rightarrow$ `0x0005_5000`).
6. **Scenario 6**: Decompression flow with accelerator feedback (4 bytes tokens $\rightarrow$ 16 bytes: `0x0005_0000` $\rightarrow$ `0x0006_0000`).
7. **Scenario 7**: Multi-word burst transfer (64 bytes: `0x0004_0000` $\rightarrow$ `0x0005_7000`).
8. **Scenario 8**: Maximum buffer capacity transfer (256 bytes: `0x0004_0000` $\rightarrow$ `0x0005_8000`).
9. **Scenario 9**: Parameter validation and error detection (zero-length transfer).

### Verification Results
- **DMA Transfers Checked**: 9
- **Passed Transfers**: 9 (Verified byte-for-byte in reconstructed memory)
- **Failed Transfers**: 0
- **Functional Coverage**: 9 / 9 bins (100.0%)
- **Protocol Assertions**: 0 Errors

---

## 5. SystemVerilog Protocol Assertions

Located in `tb/assertions/`, the assertion library enforces structural protocol rules without requiring formal verification licenses:

### 1. `axi_protocol_assertions.sv`
- **Handshake Stability (ARM IHI 0022E A2.2.1)**:
  - When `AWVALID` is asserted and stalled (`!AWREADY`), `AWVALID`, `AWADDR`, and `AWPROT` must remain perfectly stable until handshake.
  - When `WVALID` is asserted and stalled (`!WREADY`), `WVALID`, `WDATA`, `WSTRB`, and `WLAST` must remain stable.
  - When `ARVALID` is asserted and stalled (`!ARREADY`), `ARVALID`, `ARADDR`, and `ARPROT` must remain stable.
  - When `RVALID` is asserted and stalled (`!RREADY`), `RVALID`, `RDATA`, and `RRESP` must remain stable.
  - When `BVALID` is asserted and stalled (`!BREADY`), `BVALID` and `BRESP` must remain stable.
- **Response Validity**: Asserts that reserved `2'b01` (EXOKAY) is never returned by standard slave peripherals.

### 2. `dma_protocol_assertions.sv`
- **Reset Quiescence**: When `rst_n` is active low, master valid signals (`m_axi_awvalid`, `m_axi_wvalid`, `m_axi_arvalid`) and `irq_o` must remain deasserted.
- **Burst Parameter Compliance**:
  - `AWBURST` and `ARBURST` must be legal modes (`2'b00` FIXED or `2'b01` INCR).
  - `AWSIZE` and `ARSIZE` must not exceed the 32-bit bus width (`3'b010`).
  - 32-bit burst addresses must be word-aligned (`addr[1:0] == 2'b00`).
- **Burst Length & Last Alignment**:
  - `WLAST` must assert strictly on beat `awlen + 1` of an active write burst and never prematurely.
  - `RLAST` must assert strictly on beat `arlen + 1` of an active read burst.

### 3. `rle_protocol_assertions.sv`
- **Reset Quiescence**: When `rst` is active high, all slave output valids (`s_axi_bvalid`, `s_axi_rvalid`) and `irq` must be deasserted.
- **State Consistency**: Mutual exclusivity of `busy` and `done` in the status register (`!(busy && done)`).
- **Configuration Bounds**: Configured input length must not exceed maximum accelerator buffer depth (512 bytes).
- **Output Stability**: Read data and write responses must remain stable under master backpressure.

---

## 6. Functional Coverage Summary

### RLE Functional Coverage (`rle_coverage`)
| Coverage Bin | Condition | Verification Status |
| :--- | :--- | :---: |
| `Single-Byte Run Bin` | Length = 1 byte | **1 hit** |
| `Repeated-Byte Run Bin` | Uniform repeating byte patterns | **3 hits** |
| `Max Run-Length Bin` | Run length exactly 255 bytes | **1 hit** |
| `Boundary Run Split Bin` | Run length > 255 bytes (multi-token split) | **1 hit** |
| `Alternating Data Bin` | Alternating byte patterns | **1 hit** |
| `Decompression Expansion Bin` | Expansion from tokens to decoded stream | **3 hits** |
| `Error: Odd Decomp Length Bin`| Decompression with non-even token length | **1 hit** |
| `Error: Zero Run Count Bin` | Token with count = 0 | **1 hit** |
| **Total RLE Coverage** | **8 / 8 Bins** | **100.0%** |

### DMA Functional Coverage (`dma_coverage`)
| Coverage Bin | Condition | Verification Status |
| :--- | :--- | :---: |
| `1-Byte Transfer Bin` | Transfer length = 1 byte | **1 hit** |
| `2-Byte Transfer Bin` | Transfer length = 2 bytes | **1 hit** |
| `3-Byte Transfer Bin` | Transfer length = 3 bytes | **1 hit** |
| `4-Byte (1-Word) Transfer Bin`| Transfer length = 4 bytes | **2 hits** |
| `Multi-Word Burst Bin` | Transfer length = 16 or 64 bytes | **2 hits** |
| `Maximum Capacity (256B) Bin` | Transfer length = 256 bytes | **1 hit** |
| `Compression Mode Bin` | DMA operating in compression flow | **8 hits** |
| `Decompression Mode Bin` | DMA operating in decompression flow | **1 hit** |
| `Error Detection Bin` | Parameter validation failure (length = 0) | **1 hit** |
| **Total DMA Coverage** | **9 / 9 Bins** | **100.0%** |

---

## 7. Windows Simulation & Environment Feasibility

### ModelSim Intel FPGA Starter Edition 2020.1 Compatibility & Limitations
- **Native UVM 1.2 Execution**: Fully supported using ModelSim's built-in UVM 1.2 class library (`C:/intelFPGA/20.1/modelsim_ase/verilog_src/uvm-1.2/src`).
- **Tool Licensing Limitation**: ModelSim Intel FPGA Starter Edition does not include Questa Advanced Functional Verification licenses. Consequently, native SystemVerilog `covergroup`/`coverpoint` constructs and UCDB database generation are disabled. Functional coverage is therefore tracked using deterministic transaction collectors (`rle_coverage`, `dma_coverage`) that record hit counts across explicit scenario bins.
- **DPI Compilation Flag**: When compiling custom C/C++ DPI backends or linking with UVM, `-ccflags "-DQUESTA"` must be supplied to resolve symbol references cleanly.
- **Path Spacing Workaround**: ModelSim's internal `g++.exe` DPI linker fails if the work directory contains spaces in its path. All work libraries are built in `H:\sim_build\` (`vip_work`, `uvm_work`, `soc_work`) to ensure robust operation.
- **Disk Space Management**: ModelSim compiler and simulator temporary files are routed to `H:\sim_build\temp` via `$env:TEMP` / `$env:TMP` to prevent storage exhaustion on system drive `C:`.
