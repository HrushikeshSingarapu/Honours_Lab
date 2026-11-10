# SoC Address Map & Register Specification

**Authoritative Reference:** `archive/phase1/Full_Soc_Address_Map.xlsx`
**SoC Top RTL:** [soc_top.v](../../rtl/soc/soc_top.v), [soc_core_top.sv](../../rtl/soc/soc_core_top.sv)
**Interconnect Fabric:** [axi_interconnect_wrap_4x8.v](../../rtl/interconnect/axi_interconnect_wrap_4x8.v) (`S00` IFU, `S01` LSU, `S02` SB, `S03` DMA Master x `M00`–`M07`)

---

## 1. System Address Map (`Full_Soc_Address_Map.xlsx`)

| Region / IP | Base Address | End Address | Size | Port | Crossbar Decode `{R1, R0}` | Status & Behavior |
|---|---|---|---:|:---:|---|---|
| **Instruction Memory (IMEM)** | `0x0000_0000` | `0x0000_FFFF` | 64 KB | `M00` | `0x0000_0000/16` | Implemented (`u_imem`, `16,384` words, R/W/X) |
| **Instruction Memory (Reset Alias)** | `0x8000_0000` | `0x8000_FFFF` | 64 KB | `M00` | `0x8000_0000/16` | Implemented (VeeR `rst_vec` alias to `u_imem`) |
| **Data Memory (DMEM)** | `0x0001_0000` | `0x0002_FFFF` | 128 KB | `M01` | `{0x0002_0000/16, 0x0001_0000/16}` | Implemented (`u_dmem`, `32,768` words, R/W) |
| **UART (AXI4-Lite)** | `0x0003_0000` | `0x0003_0FFF` | 4 KB | `M02` | `0x0003_0000/12` | Implemented (`u_uart`, `axi_uart_top`) |
| *Post-UART Unallocated Gap* | `0x0003_1000` | `0x0004_FFFF` | ~124 KB | — | Unallocated | Unimplemented (`DECERR` `2'b11`) |
| **Timer (64-bit MTIME)** | `0x0005_0000` | `0x0005_0FFF` | 4 KB | `M03` | `0x0005_0000/12` | Implemented (`u_timer`, `timer_top`) |
| **GPIO (32-bit)** | `0x0006_0000` | `0x0006_0FFF` | 4 KB | `M04` | `0x0006_0000/12` | Implemented (`u_gpio`, `gpio_top`) |
| **Packet FIFO** | `0x0007_0000` | `0x0007_0FFF` | 4 KB | — | Unallocated | Reserved / Not implemented (`DECERR`) |
| **Packet Counter** | `0x0008_0000` | `0x0008_0FFF` | 4 KB | — | Unallocated | Reserved / Not implemented (`DECERR`) |
| **Enhanced Timer** | `0x0009_0000` | `0x0009_0FFF` | 4 KB | — | Unallocated | Reserved / Not implemented (`DECERR`) |
| **CRC-32 Accelerator** | `0x000A_0000` | `0x000A_0FFF` | 4 KB | `M07` | `0x000A_0000/12` | Implemented (`u_crc`, `crc32_top`) |
| **DMA Controller (Slave)** | `0x000B_0000` | `0x000B_FFFF` | 64 KB | `M06` | `0x000B_0000/16` | Implemented (`u_dma`, `dma_top`; `[11:0]` decode) |
| **External Interrupt Controller** | `0x000C_0000` | `0x000C_0FFF` | 4 KB | — | Unallocated | Reserved / Not implemented (`DECERR`) |
| **RLE Accelerator** | `0x000D_0000` | `0x000D_0FFF` | 4 KB | `M05` | `0x000D_0000/12` | Implemented (`u_rle`, `rle_top`, `BUFFER_DEPTH=256`) |
| **Future Expansion Bank A** | `0x000E_0000` | `0x001F_FFFF` | ~1 MB | — | Unallocated | Reserved for future expansion (`DECERR`) |

### VeeR EL2 Internal Reserved Regions (Do Not Allocate on AXI)

| Region | Base Address | End Address | Size | VeeR Define / Usage |
|---|---|---|---:|---|
| **VeeR ICCM** | `0xEE00_0000` | `0xEE00_FFFF` | 64 KB | `RV_ICCM_SADR='hee000000` (internal instruction memory) |
| **VeeR DCCM** | `0xF004_0000` | `0xF004_FFFF` | 64 KB | `RV_DCCM_SADR='hf0040000` (stack top `0xF004_FFF0`) |
| **VeeR PIC** | `0xF00C_0000` | `0xF00C_7FFF` | 32 KB | `RV_PIC_BASE_ADDR='hf00c0000` (internal PIC) |

---

## 2. Reset Vector Aliasing, DMEM Splitting & MRAC Configuration

1. **Reset Vector & IMEM Alias (`0x0000_0000` <-> `0x8000_0000`):**
   - `soc_core_top.sv` ties `.rst_vec(31'h4000_0000)` (`0x8000_0000 >> 1`), matching `RV_RESET_VEC = 'h80000000` in VeeR EL2 snapshot `common_defines.vh`.
   - `M00` (`u_imem`, `DEPTH=16384` words = 64 KB) uses `M_REGIONS=2` in `soc_top.v` to decode both `0x0000_0000`–`0x0000_FFFF` and `0x8000_0000`–`0x8000_FFFF`. Because `soc_sram` indexes `(addr - 32'h0000_0000)[15:2]`, both windows map identically to physical `u_imem.mem[0..16383]`.
   - `firmware/linker/linker.ld` places `.text`/`.rodata` at `ORIGIN = 0x80000000, LENGTH = 64K`, agreeing with testbench `$readmemh` preloading into `u_imem.mem`.

2. **DMEM Non-Power-of-Two Alignment (`0x0001_0000`–`0x0002_FFFF`):**
   - `axi_interconnect.v` enforces natural power-of-two alignment `(BASE & ((1 << ADDR_WIDTH) - 1)) == 0`, so a 128 KB block starting at `0x0001_0000` cannot use a single `/17` region. `soc_top.v` maps `M01` across two aligned 64 KB regions (`0x0001_0000/16` and `0x0002_0000/16`) and configures `soc_sram u_dmem` with `BASE_ADDR=32'h0001_0000`, subtracting `BASE_ADDR` so `0x0001_0000` maps to `mem[0]` and `0x0002_FFFC` maps to `mem[32767]`.

3. **VeeR EL2 `MRAC` CSR (`0x7C0` = `0x5555_5556`):**
   - `firmware/startup/start.S` writes `0x5555_5556` to `CSR 0x7C0` before calling `main`:
     - **Region 0 (`0x0000_0000`–`0x0FFF_FFFF`):** `2'b10` (Non-cacheable, side-effect) — covers low IMEM alias, DMEM (`0x0001_0000`–`0x0002_FFFF`), and all SoC MMIO slaves (`0x0003_0000`–`0x000D_0FFF`).
     - **Region 8 (`0x8000_0000`–`0x8FFF_FFFF`):** `2'b01` (Cacheable, idempotent) — covers IMEM instruction fetch execution at the reset vector.

4. **DMEM Firmware Buffer Partition (`0x0001_0000`–`0x0002_FFFF`):**
   - Standalone DMA firmware (`main_dma.c`) uses `0x0001_0000` (`mem[0..4]`) for signature/milestone tracking, `0x0001_0100` (`SRC_BUF`), `0x0001_0300` (`COMP_BUF`), and `0x0001_0500` (`DECOMP_BUF`). Integrated E2E firmware (`soc_e2e_uvm.c`) additionally exercises lower DMEM (`0x0001_0000`) and upper DMEM (`0x0002_0000`–`0x0002_FFFF`).

---

## 3. Peripheral & Accelerator Register Maps (Verified Against RTL)

### 3.1 UART (`0x0003_0000`, `axi_uart_top.v`)
Decodes word address bits `[4:2]` across 5 registers; unmapped offsets return `OKAY` (`0`) in `axi_uart_top.v`:

| Offset | Register | Access | Notes / Bitfields |
|:---:|---|:---:|---|
| `0x00` | `UART_RBR` / `UART_THR` | RO / WO | Active when `LCR[7]` (`DLAB`) = `0`; RX FIFO pop / TX FIFO push |
| `0x04` | `UART_IER` | RW | `[0]` RX interrupt enable (`read_interrupt_o` is unconnected in `soc_top.v`) |
| `0x08` | `UART_BAUD_DIV` | RW | Direct clock cycles per bit divisor: `BAUD_DIV = round(CLK_FREQ / BAUD_RATE) - 1` (`867` for 115200 bps, `49` for 2 Mbps @ 100 MHz); RX samples mid-bit at `baud_div_i >> 1` |
| `0x0C` | `UART_LCR` | RW | `[2]` stop bits (`0=1, 1=2`), `[3]` parity enable, `[4]` parity mode (`0=odd, 1=even`), `[7]` `DLAB` |
| `0x14` | `UART_LSR` | RO | `[0]` Data Ready, `[5]` `THRE`, `[6]` `TEMT` |

### 3.2 64-bit Timer (`0x0005_0000`, `timer_top.v`)
Decodes `[11:0]`; unmapped/unaligned accesses return `SLVERR`:

| Offset | Register | Access | Description |
|:---:|---|:---:|---|
| `0x00` / `0x04` | `MTIME_LOW` / `MTIME_HIGH` | RW | 64-bit real-time counter |
| `0x08` / `0x0C` | `MTIMECMP_LOW` / `MTIMECMP_HIGH` | RW | 64-bit compare threshold (`timer_irq = (mtime >= mtimecmp) && IRQ_EN`) |
| `0x10` | `TIMER_CTRL` | RW | `[0]` EN (reset `1`), `[1]` IRQ_EN, `[2]` AUTO_RELOAD, `[15:8]` PRESCALE |
| `0x14` | `TIMER_STATUS` | R/W1C | `[0]` sticky `MATCH` flag |

### 3.3 32-bit GPIO (`0x0006_0000`, `gpio_top.v`)
Decodes `[11:0]`; unmapped/unaligned accesses return `SLVERR`:

| Offset | Register | Access | Description |
|:---:|---|:---:|---|
| `0x00` | `GPIO_DATA_IN` | RO | 2-stage synchronized external input pins `gpio_i[31:0]` |
| `0x04` | `GPIO_DATA_OUT` | RW | Output pin drive register `gpio_o[31:0]` |
| `0x08` | `GPIO_DIR` | RW | Output enable `gpio_oe[31:0]` (`1=output, 0=input`) |
| `0x0C` / `0x10` / `0x14` | `IRQ_EN` / `IRQ_TYPE` / `IRQ_POL` | RW | Per-pin mask, type (`0=level, 1=edge`), polarity (`0=low/fall, 1=high/rise`) |
| `0x18` | `GPIO_IRQ_STAT` | R/W1C | Sticky per-pin interrupt status (`gpio_irq = |(IRQ_STAT & IRQ_EN)`) |
| `0x1C` / `0x20` / `0x24` | `SET_OUT` / `CLR_OUT` / `TOG_OUT` | WO | Atomic bitwise set, clear, and toggle of `DATA_OUT` |

### 3.4 IEEE 802.3 CRC-32 (`0x000A_0000`, `crc32_top.v`)
Decodes `[11:0]` (reflected polynomial `0xEDB88320`, single-cycle byte-strobe ingestion, unmapped/unaligned -> `SLVERR`):

| Offset | Register | Access | Reset | Description |
|:---:|---|:---:|:---:|---|
| `0x00` | `CRC_DATA` | WO/RW | `0x0000_0000` | Writes ingest enabled `wstrb` byte lanes (LSB-first) into accumulator; read returns last written word |
| `0x04` | `CRC_RESULT` | RO | `0x0000_0000` | Current final-XORed CRC-32 (`crc_accum ^ 32'hFFFFFFFF`) |
| `0x08` | `CRC_CTRL` | RW | `0x0000_0000` | `[0]` self-clearing re-init of accumulator to `CRC_INIT` and `byte_count = 0` |
| `0x0C` | `CRC_STATUS` | RO | `0x0000_0000` | `[15:0]` processed byte count (`[31:16] = 0`) |
| `0x10` | `CRC_INIT` | RW | `0xFFFF_FFFF` | Configurable initial accumulator seed |

### 3.5 Autonomous DMA Controller (`0x000B_0000`–`0x000B_FFFF`, `dma_reg_file.v` & `dma_sequencer.v`)
Decodes `[11:0]` within the 64 KB aperture; autonomous master `S03` reads/writes DMEM (`0x0001_0000`–`0x0002_FFFF`) and targets RLE registers at `0x000D_0000`–`0x000D_0014`. Unmapped/unaligned offsets return `SLVERR`:

| Offset | Register | Access | Reset | Description |
|:---:|---|:---:|:---:|---|
| `0x00` | `DMA_CONTROL` | RW | `0x0000_0000` | `[0]` START (self-clearing), `[1]` MODE (`0=Comp, 1=Decomp`), `[2]` ABORT (self-clearing) |
| `0x04` | `DMA_STATUS` | RO | `0x0000_0000` | `[0]` BUSY, `[1]` DONE, `[2]` ERROR |
| `0x08` | `DMA_SRC_ADDR` | RW | `0x0001_0000` | Source start address in DMEM (`0x0001_0000`–`0x0002_FFFF`) |
| `0x0C` | `DMA_DST_ADDR` | RW | `0x0001_0100` | Destination start address in DMEM |
| `0x10` | `DMA_INPUT_LEN` | RW | `0x0000_0000` | Transfer byte length (`1`–`256`) |
| `0x14` | `DMA_OUTPUT_LEN` | RO | `0x0000_0000` | Output byte count produced by accelerator |
| `0x18` / `0x1C` | `DMA_IRQ_ENABLE` / `STATUS` | RW / R/W1C | `0x0000_0000` | `[0]` `DONE`, `[1]` `ERROR` (`dma_irq` level interrupt) |
| `0x20` | `DMA_ERROR_CODE` | RO | `0x0000_0000` | `0x00` NONE, `0x01` BAD_SRC, `0x02` BAD_DST, `0x03` BAD_LEN, `0x04` RD_ERR, `0x05` WR_ERR, `0x06` RLE_ERR, `0x07` TIMEOUT |

### 3.6 RLE Accelerator (`0x000D_0000`, `rle_reg_block.v`)
Parameterized at `BUFFER_DEPTH=256` on SoC; decodes `[11:0]` (busy-time writes & unmapped offsets return `SLVERR`):

| Offset | Register | Access | Description |
|:---:|---|:---:|---|
| `0x00` / `0x04` | `RLE_CONTROL` / `RLE_STATUS` | RW / RO | CONTROL `[0]` START, `[1]` MODE (`0=Comp, 1=Decomp`); STATUS `[0]` BUSY, `[1]` DONE, `[2]` ERROR |
| `0x08` / `0x0C` | `RLE_INPUT_LEN` / `RLE_OUTPUT_LEN` | RW / RO | Input byte count (`1`–`BUFFER_DEPTH`) / actual output byte count |
| `0x10` / `0x14` | `RLE_INPUT_DATA` / `RLE_OUTPUT_DATA` | WO / RO | Sequential input/output byte FIFOs (supports 1–4 byte `wstrb` pushes) |
| `0x18` / `0x1C` | `RLE_IRQ_ENABLE` / `RLE_IRQ_STATUS` | RW / R/W1C | `[0]` DONE, `[1]` ERROR (`rle_irq` level interrupt) |
