# SoC Verification Architecture, Testplan & Results

**Simulator Baseline:** ModelSim Intel FPGA Starter Edition 2020.1 (`vlog` / `vsim`, `-sv_seed 12345`)
**Firmware Compiler:** `riscv64-unknown-elf-gcc` (`-march=rv32imc_zicsr_zifencei -mabi=ilp32 -O2`)
**Master Regression Runner:** [`simulation/scripts/run_full_regression.ps1`](../../simulation/scripts/run_full_regression.ps1)

> All verification claims below reflect **RTL simulation only**. FPGA synthesis, place-and-route, timing closure, and silicon/board-level measurements are outside scope and not claimed.

---

## 1. Multi-Layer Verification Architecture

1. **Standalone IP & SoC Structural Suites (`verification/standalone/`):**
   - Unit and integration testbenches covering DMA submodules/top (`tb_dma_reg_file`, `tb_dma_master_engine`, `tb_dma_sequencer`, `tb_dma_unit`), RLE (`tb_rle_top`), CRC-32 (`tb_crc32`), UART (`tb_uart_top`), GPIO (`tb_gpio_top`), Timer (`tb_timer_top`), 64->32 bridge (`tb_axi64_to_32_bridge`), memory & reset-vector aliasing (`tb_soc_mem_access`), hardware DMA+RLE SoC integration (`tb_soc_dma_integration`), exhaustive post-migration address-map audit (`tb_soc_address_map_audit`), and 4x8 crossbar contention/reset/DECERR stress (`verification/standalone/interconnect/tb_axi_interconnect_4x8.sv`).
   - Legacy 3x8 crossbar harness (`verification/legacy/interconnect_3x8/`) is retained untouched for reference and excluded from active runs.
2. **Separate IP-Level UVM 1.2 & VIP Suites (`tb/uvm/`, `tb/vip/`):**
   - `tb_rle_uvm` (`rle_test`) and `tb_dma_uvm` (`dma_test`) independently verify accelerator/DMA corners (`BUFFER_DEPTH=512` on RLE IP, `BUFFER_DEPTH=256` & 128 KB `ref_dmem` mirror on DMA IP) with bound assertions (`+define+UVM_NO_DPI`).
   - `tb_vip_sanity` validates standalone reusable VIPs (`uart`, `gpio`, `irq`, `reset`, `trace`).
3. **VeeR EL2 Bare-Metal Firmware Suite (`verification/standalone/soc/`):**
   - Executes compiled RV32IMC C/assembly binaries directly on `soc_core_top`: `tb_soc_core_boot`, `tb_soc_periph_test`, `tb_soc_uart_firmware`, and `tb_soc_dma_firmware` (4 test patterns exercising 8 autonomous DMA transfers, compression, decompression, and hardware IEEE 802.3 CRC-32 validation).
4. **Integrated SoC 4-Agent UVM 1.2 Environment (`verification/uvm/`):**
   - [`soc_env.sv`](../../verification/uvm/env/soc_env.sv) preserves **exactly four agents** without any active AXI UVM agent (`axi_interconnect_wrap_4x8` remains real DUT RTL):
     - `uart_agnt` (`uart_vip_pkg`): active RX driver / passive TX monitor on `uart_if`.
     - `gpio_agnt` (`gpio_vip_pkg`): pin monitor + external `gpio_i` stimulus on `gpio_if`.
     - `reset_agnt` (`reset_vip_pkg`): synchronized cold power-on and mid-run warm reset pulses on `reset_if`.
     - `irq_agnt` (`irq_vip_pkg`): passive monitor over `{dma_irq, rle_irq, timer_irq, gpio_irq}` on `irq_if`.
   - **Passive Checking (`soc_obs_if` & [`soc_scoreboard.sv`](../../verification/uvm/env/soc_scoreboard.sv)):** Samples IFU32/LSU32/DMA `S03`/DMEM `M01` AXI channels plus VeeR trace ports without intrusive drivers, enforcing UART byte matching, `M01` shadow DMEM mirroring, software IEEE 802.3 CRC-32 and RLE predictions, DMA DMEM destination verification (including error codes), GPIO MMIO-to-pin equality, reset quiescence, IRQ milestones, unexpected bus error rejection, and controlled `DECERR` NMI checking.
   - **Bound Protocol Assertions (`verification/assertions/`):** Checks AXI4/AXI4-Lite handshake stability, ID matching, burst `WLAST`/`RLAST` length (`axi4_full_protocol_assertions`, `axi_protocol_assertions`), DMA master/IRQ rules (`dma_protocol_assertions`), RLE busy/done/error invariants (`rle_protocol_assertions`), and SoC pin quiescence (`soc_protocol_assertions`).

---

## 2. Integrated SoC UVM Tests & Functional Coverage Design

| Test Class (`verification/uvm/tests/`) | Firmware Image | Verification Scope |
|---|---|---|
| `soc_smoke_test` | `uart_test_word.hex` | Cold boot from `0x8000_0000`, 115200-baud UART TX `"HI"`, AXI/SoC quiescence |
| `uart_echo_test` | `uart_echo.hex` | Interactive 115200-baud full-duplex serial echo (`"ABC123"`) |
| `soc_e2e_flow_test` | `soc_e2e_uvm.hex` | 2 Mbps UART (`BAUDDIV=49`), lower/upper DMEM (`0x0001_0000`/`0x0002_0000`), Timer IRQ + W1C, GPIO out + external `gpio_i[8]` IRQ, Direct RLE + IRQ, DMA compress -> decompress -> CRC-32 + IRQ, DMA negative traps (`ERR_BAD_LEN`, `0x0007_0000` `ERR_BAD_SRC`, `0x0002_FFFC` spillover `ERR_BAD_SRC`, odd-length `ERR_RLE_ERR`), interactive `'K'` echo, `"TGRDEKP"` signature |
| `soc_reset_recovery_test` | `soc_e2e_uvm.hex` | 25-cycle warm reset injected mid-run (`soc_warm_reset_seq`), quiescence check, clean reboot from `0x8000_0000`, full post-reset `"TGRDEKP"` pass |
| `soc_decerr_trap_test` | `soc_decerr_test.hex` | Emits `'D'` then loads unimplemented Packet FIFO `0x0007_0000`; verifies `DECERR` (`2'b11`) and VeeR imprecise bus-error NMI (`ecause=0` -> `.nmi_vec=0x1111_0000` `ecause=1`) |

**Dual-Mode Coverage ([`soc_coverage.sv`](../../verification/uvm/env/soc_coverage.sv)):** Because ModelSim Starter Edition does not license runtime SystemVerilog `covergroup` evaluation (`vsim-1`), 25 portable always-on functional bin counters track IMEM Base/Alias, DMEM Lower/Upper, all 6 peripheral apertures, `OKAY`/`DECERR` responses, DMA compress/decompress/error flows, direct RLE, CRC-32, UART TX & RX->TX echo, all 4 IRQs, cold reset, and warm reset recovery. Native `covergroup cg_uart` compiles under `` `ifdef ENABLE_SV_COVERGROUP `` for Synopsys VCS (`simulation/scripts/run_soc_uvm.sh`) or Questa Prime.

---

## 3. Verified Regression Results (ModelSim Starter Edition 2020.1, `-sv_seed 12345`)

Every PASS entry below comes from clean ModelSim RTL simulation with no subsequent RTL, firmware, or SystemVerilog testbench changes: `standalone`, `interconnect`, `vip`, `rle_uvm`, `dma_uvm` (and `run_sim.ps1 -Target boot`/`-Target periph`) were executed after all runner cleanups, whereas the `firmware` (`4/4`) and `soc_uvm` (`4`) logs reflect the preceding clean regression on identical RTL/firmware/UVM sources (`uart_echo_test` and VCS `run_soc_uvm.sh` were not run on Windows).

### 3.1 Suite Summary

| Suite / Runner Command | Executed / Scope | Result & Observed Counts |
|---|---|---|
| `run_full_regression.ps1 -Suite standalone` | **13 / 13 PASS** | `1,059 / 1,059` checks (`tb_dma_reg_file` 63, `tb_dma_master_engine` 96, `tb_dma_sequencer` 32, `tb_dma_unit` 45, `tb_crc32` 192, `tb_uart_top` 89, `tb_gpio_top` 83, `tb_timer_top` 80, `tb_rle_top` 70, `tb_axi64_to_32_bridge` 69, `tb_soc_mem_access` 92, `tb_soc_dma_integration` 37, `tb_soc_address_map_audit` 111), 0 assertion errors |
| `run_full_regression.ps1 -Suite interconnect` | **1 / 1 PASS** | `tb_axi_interconnect_4x8`: `99 / 99` checks, `16 / 16` bins (`100.0%`), `0` assertion errors |
| `run_full_regression.ps1 -Suite vip` & `tb/run_uvm_regression.ps1 -Target vip` | **1 / 1 PASS** | `tb_vip_sanity`: `7 / 7` VIP checks |
| `run_full_regression.ps1 -Suite rle_uvm` & `tb/run_uvm_regression.ps1 -Target rle_uvm` | **1 / 1 PASS** | `tb_rle_uvm` (`rle_test`): `14 / 14` txns, `11 / 11` bins (`100.0%`), `UVM_ERROR=0`, `0` assertion errors |
| `run_full_regression.ps1 -Suite dma_uvm` & `tb/run_uvm_regression.ps1 -Target dma_uvm` | **1 / 1 PASS** | `tb_dma_uvm` (`dma_test`): `15 / 15` xfers, `12 / 12` bins (`100.0%`), `UVM_ERROR=0`, `0` assertion errors |
| `run_full_regression.ps1 -Suite firmware` | **4 / 4 PASS** | `fw_core_boot` (136 cyc, 5 insns, `0xCAFEBABE`), `fw_periph` (`ALL 5 PERIPHERALS PASSED`, `0xCAFEF00D`), `fw_uart` (`'H'`,`'I'`, 31 insns), `fw_dma` (`25,304` cyc, `5,626` insns, `0` traps, 8/8 DMA xfers, `0xCAFED00D`) |
| `run_full_regression.ps1 -Suite soc_uvm` | **3 / 3 Fast PASS** | `soc_decerr_trap_test` (`11,295 ns`, 6/25 bins), `soc_e2e_flow_test` (`80,735 ns`, `"TGRDEKP"` 7/7, 5/5 GPIO, T/G/R/D IRQs, 6/1/3 DMA/RLE/CRC, 23/25 bins), `soc_reset_recovery_test` (`99,305 ns`, 2 resets, `"TGRDEKP"` 7/7, 24/25 bins) — **25 / 25 (`100.0%`) union coverage**, `UVM_ERROR=0`, `TOTAL=0` assertions |
| Direct `vsim +UVM_TESTNAME=soc_smoke_test` | **1 / 1 PASS** | `"HI"` matched (`2/2`), `178,645 ns`, `5 / 25` bins, `UVM_ERROR=0`, `TOTAL=0` assertions |
| `uart_echo_test` (`-IncludeLongUvm`) | **NOT RUN** post-refactor | Deferred under Starter Edition due to ~23 min 115200-baud runtime; bidirectional RX->TX UART echo is live-verified at 2 Mbps inside `soc_e2e_flow_test` & `soc_reset_recovery_test` |
| `simulation/scripts/run_soc_uvm.sh` (Synopsys VCS) | **NOT RUN** | Requires Linux Synopsys VCS environment unavailable on Windows host |

### 3.2 Standalone Golden Data Patterns (`tb_soc_dma_firmware` / `main_dma.c`)

| Pattern | Source Stream (32 bytes / ops) | RLE Compression | Golden IEEE 802.3 CRC-32 |
|---|---|---|---:|
| Pattern 1 | 8B short runs (`4x 0xAA, 4x 0xBB`) -> 8B decompressed | 8B -> 4B | `0x679ED8AF` |
| Pattern 2 | 16B constant run (`16x 0x55`) | 16B -> 2B | `0x1493CDAF` |
| Pattern 3 | 14B mixed runs & singletons (`0x11..0x77`) | 14B -> 14B | `0x6D5FF127` |
| Pattern 4 | 32B multi-run boundary (`8x 0x10..0x40`) | 32B -> 8B | `0xBB19A46E` |

*(Direct 32-bit IEEE 802.3 test vector checks in `tb_crc32.sv` and `soc_e2e_uvm.c` also verify ASCII `"123456789"` -> `0xCBF43926`.)*

---

## 4. Defects Fixed & Known Architectural/Tooling Constraints

### Defects Fixed During Audit
1. **`rtl/accelerators/dma/dma_sequencer.v`:** Fixed `[7:0]` word-count truncation on 256-byte transfers (`src_word_cnt` / `dst_word_cnt` widened to 9 bits so `len=256` computes 64 words instead of wrapping to 0 / 256 AXI beats) and added DMEM end-address spillover checks (`> 0x0002_FFFF`) plus `rle_out_len_reg > 256` trapping.
2. **`rtl/interconnect/axi64_to_32_bridge.v`:** Fixed `RD_STATE_DIRECT_32` to drive latched `rd_id_r` onto `m_axi_rid`.
3. **Simulation & UVM Fixes:** Resolved Starter Edition `vsim-1` runtime block on `soc_coverage.sv`, fixed relative paths & nonzero exit codes in `tb/uvm/{dma,rle}/*.f` and `tb/run_uvm_regression.ps1`, corrected negative-length false errors in `rle_protocol_assertions.sv`, and aligned `run_sim.ps1` signature checks and `simulation/filelists/soc_uvm.f`.

### Known Constraints
1. **VeeR EL2 `DECERR` NMI Behavior:** LSU `DECERR` (`2'b11`) on unimplemented slots under `MRAC=0x5555_5556` raises an imprecise bus-error NMI (`ecause=0`) to `.nmi_vec` (`0x1111_0000`), which itself takes IFU `DECERR` (`ecause=1`) and parks in `_trap_handler`; `DECERR` trapping is therefore tested in dedicated `soc_decerr_trap_test`.
2. **Polling UART & Unimplemented Slots:** `axi_uart_top.read_interrupt_o` is unconnected in `soc_top.v` (CPU uses `UART_LSR` polling). Packet FIFO (`0x0007_0000`), Packet Counter (`0x0008_0000`), Enhanced Timer (`0x0009_0000`), Ext. Interrupt Controller (`0x000C_0000`), and Expansion Bank A (`0x000E_0000`–`0x001F_FFFF`) have no RTL and intentionally return `DECERR`.
3. **ModelSim Starter Edition:** Suppresses third-party VeeR `el2_lsu_bus_buffer.sv:768` enum port binding warning (`-suppress 3999,12036`) and throttles 76,898-statement VeeR EL2 simulations to ~500 ns/s simulated time without generating RTL line/toggle code-coverage databases.
4. **Legacy Test Monitor Scope:** `verification/standalone/soc/uart_tx_monitor.sv` retains a standalone `force` on `dec_tlu_mrac_ff` for `tb_soc_uart_firmware`, whereas integrated UVM `tb_soc_top` relies solely on firmware `start.S` CSR setup.
