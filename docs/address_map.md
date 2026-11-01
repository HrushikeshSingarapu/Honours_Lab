# SoC Address Map & Register Specification

**Project:** RISC-V Based Configurable Data Compression Accelerator SoC  
**Processor Core:** Western Digital / CHIPS Alliance VeeR EL2 (RV32IMC)  
**Interconnect Fabric:** 4 Masters × 8 Slaves AXI4 Crossbar (`axi_interconnect_wrap_4x8`)  

---

## 1. System Memory & Peripheral Address Map

The SoC address space is organized into memory regions and memory-mapped I/O (MMIO) peripheral apertures routed across the 4x8 AXI crossbar.

| Address Range | Size | Destination Target | Interconnect Port | Access | Cache / Side-Effect (MRAC) | Description |
|:---|:---:|:---|:---:|:---:|:---:|:---|
| `0x0000_0000` – `0x0003_FFFF` | 256 KB | Instruction SRAM (IMEM) | M00 | R/W/X | Non-cacheable, side-effect safe | Alias for low-memory boot/execution |
| `0x0004_0000` – `0x0007_FFFF` | 256 KB | Data SRAM (DMEM) | M01 | R/W | Non-cacheable, side-effect safe | Data buffers, DMA descriptors, heap |
| `0x1000_0000` – `0x1000_0FFF` | 4 KB | UART 16550 Core | M02 | R/W | Non-cacheable, side-effect (MMIO) | Serial console, baud rate generator |
| `0x1000_1000` – `0x1000_1FFF` | 4 KB | Machine Timer (MTIME) | M03 | R/W | Non-cacheable, side-effect (MMIO) | 64-bit real-time counter & compare |
| `0x1000_2000` – `0x1000_2FFF` | 4 KB | General Purpose I/O (GPIO) | M04 | R/W | Non-cacheable, side-effect (MMIO) | 32-bit bidirectional I/O pins |
| `0x1001_0000` – `0x1001_0FFF` | 4 KB | RLE Compression Engine | M05 | R/W | Non-cacheable, side-effect (MMIO) | Lossless run-length encoder/decoder |
| `0x1001_1000` – `0x1001_1FFF` | 4 KB | Autonomous DMA Controller | M06 | R/W | Non-cacheable, side-effect (MMIO) | DMA channel registers & FSM control |
| `0x1001_2000` – `0x1001_2FFF` | 4 KB | CRC-32 Accelerator | M07 | R/W | Non-cacheable, side-effect (MMIO) | IEEE 802.3 Ethernet checksum engine |
| `0x8000_0000` – `0x8003_FFFF` | 256 KB | Instruction SRAM (IMEM) | M00 | R/W/X | Cacheable, idempotent | Primary VeeR EL2 reset vector (`0x8000_0000`) |
| `0xF004_0000` – `0xF004_FFFF` | 64 KB | VeeR Internal DCCM | Local | R/W | Internal Tightly-Coupled SRAM | Fast execution stack (`sp = 0xF004_FFF0`) |

---

## 2. VeeR EL2 Core Memory Attributes (MRAC CSR `0x7C0`)

The VeeR EL2 core requires the Memory Region Attribute Control register (`MRAC`, CSR `0x7C0`) to be programmed prior to issuing transactions across the external AXI interface. Each 2-bit field corresponds to a 256 MB memory region (`0x0` through `0xF`):

- `2'b00`: Strongly ordered, side-effect (MMIO)
- `2'b01`: Side-effect (MMIO, non-cacheable)
- `2'b10`: Side-effect safe (SRAM/DRAM, non-cacheable)
- `2'b11`: Cacheable, idempotent (Cachable SRAM/DRAM)

### Configuration Value: `0x5555_555A`
- **Region 0 (`0x0000_0000`–`0x0FFF_FFFF`):** Bits `[1:0] = 2'b10` (Side-effect safe; enables bursts to DMEM and aliased IMEM).
- **Region 1 (`0x1000_0000`–`0x1FFF_FFFF`):** Bits `[3:2] = 2'b01` (Non-cacheable, side-effect; MMIO peripherals).
- **Region 8 (`0x8000_0000`–`0x8FFF_FFFF`):** Bits `[17:16] = 2'b11` (Cacheable/idempotent; primary IMEM execution).
- **Other Regions:** Default safe attributes (`2'b01`).

---

## 3. DMEM Data Buffer Layout (Firmware & Accelerator)

In the firmware flow, DMEM (`0x0004_0000`–`0x0007_FFFF`) is partitioned as follows:

```
+-----------------------------------+ 0x0004_0000
| Status Word (DMEM[0])             |  4 Bytes (0xCAFED00D = PASS, 0xDEADBEEF = FAIL)
+-----------------------------------+ 0x0004_0004
| Reserved / Scratchpad             |  252 Bytes
+-----------------------------------+ 0x0004_0100
| Source Buffer (SRC_BUF)           |  256 Bytes (Raw uncompressed input data)
+-----------------------------------+ 0x0004_0200
| Alignment Gap                     |  256 Bytes
+-----------------------------------+ 0x0004_0300
| Compressed Buffer (COMP_BUF)      |  256 Bytes (RLE [count, symbol] tokens)
+-----------------------------------+ 0x0004_0400
| Alignment Gap                     |  256 Bytes
+-----------------------------------+ 0x0004_0500
| Decompressed Buffer (DECOMP_BUF)  |  256 Bytes (RLE reconstructed data)
+-----------------------------------+ 0x0004_0600
| General Heap / Unused DMEM        |  ~254.5 KB
+-----------------------------------+ 0x0007_FFFF
```

---

## 4. Hardware Accelerator Register Maps

### 4.1 Autonomous DMA Controller (`0x1001_1000`)

The DMA controller enables hardware-managed data movement between DMEM and the RLE engine without CPU instruction intervention during transfer.

| Offset | Register Name | Width | Access | Reset Value | Description |
|:---:|:---|:---:|:---:|:---:|:---|
| `0x00` | `DMA_CONTROL` | 32 | R/W | `0x0000_0000` | Control register (self-clearing pulse bits) |
| `0x04` | `DMA_STATUS` | 32 | RO | `0x0000_0000` | Operational status flags |
| `0x08` | `DMA_SRC_ADDR` | 32 | R/W | `0x0000_0000` | Source memory start address in DMEM |
| `0x0C` | `DMA_DST_ADDR` | 32 | R/W | `0x0000_0000` | Destination memory start address in DMEM |
| `0x10` | `DMA_INPUT_LEN` | 32 | R/W | `0x0000_0000` | Input byte transfer length (1 to 256) |
| `0x14` | `DMA_OUTPUT_LEN` | 32 | RO | `0x0000_0000` | Total output bytes produced by accelerator |
| `0x18` | `DMA_IRQ_ENABLE` | 32 | R/W | `0x0000_0000` | Interrupt mask register |
| `0x1C` | `DMA_IRQ_STATUS` | 32 | R/W1C | `0x0000_0000` | Sticky interrupt status (Write 1 to clear) |
| `0x20` | `DMA_ERROR_CODE` | 32 | RO | `0x0000_0000` | FSM error classification code |

#### DMA Register Bitfields

- **`DMA_CONTROL` (`0x00`):**
  - Bit 0: `START` (Write 1 to trigger transfer; hardware self-clearing).
  - Bit 1: `MODE` (`0` = Compression: DMEM $\rightarrow$ RLE $\rightarrow$ DMEM; `1` = Decompression: DMEM $\rightarrow$ RLE $\rightarrow$ DMEM).
  - Bit 2: `ABORT` (Write 1 to abort active transfer; hardware self-clearing).

- **`DMA_STATUS` (`0x04`):**
  - Bit 0: `BUSY` (`1` = DMA transfer actively executing).
  - Bit 1: `DONE` (`1` = Transfer completed successfully).
  - Bit 2: `ERROR` (`1` = Transfer aborted due to parameter error or bus fault).

- **`DMA_IRQ_ENABLE` (`0x18`):**
  - Bit 0: `DONE_IE` (`1` = Assert IRQ when transfer completes).
  - Bit 1: `ERROR_IE` (`1` = Assert IRQ on error condition).

- **`DMA_IRQ_STATUS` (`0x1C`, Write-1-to-Clear):**
  - Bit 0: `DONE_IS` (`1` = Transfer completed interrupt pending).
  - Bit 1: `ERROR_IS` (`1` = Error interrupt pending).

- **`DMA_ERROR_CODE` (`0x20`):**
  - `0x00`: `ERR_NONE` — Normal operation.
  - `0x01`: `ERR_BAD_SRC` — Source address outside valid DMEM aperture (`0x0004_0000`–`0x0007_FFFF`).
  - `0x02`: `ERR_BAD_DST` — Destination address outside valid DMEM aperture.
  - `0x03`: `ERR_BAD_LEN` — Invalid transfer length ($< 1$ or $> 256$ bytes).
  - `0x04`: `ERR_RD_ERR` — AXI read bus error (SLVERR/DECERR) encountered by master.
  - `0x05`: `ERR_WR_ERR` — AXI write bus error encountered by master.
  - `0x06`: `ERR_RLE_ERR` — Accelerator engine signaled internal processing error.
  - `0x07`: `ERR_TIMEOUT` — Sequencer timed out waiting for RLE engine completion.

---

### 4.2 RLE Compression Engine (`0x1001_0000`)

| Offset | Register Name | Width | Access | Reset Value | Description |
|:---:|:---|:---:|:---:|:---:|:---|
| `0x00` | `RLE_CONTROL` | 32 | R/W | `0x0000_0000` | Bit 0: START, Bit 1: MODE (0=Comp, 1=Decomp) |
| `0x04` | `RLE_STATUS` | 32 | RO | `0x0000_0000` | Bit 0: BUSY, Bit 1: DONE, Bit 2: ERROR |
| `0x08` | `RLE_INPUT_LEN` | 32 | R/W | `0x0000_0000` | Input byte count (1 to 256) |
| `0x0C` | `RLE_OUTPUT_LEN` | 32 | RO | `0x0000_0000` | Output byte count produced |
| `0x10` | `RLE_INPUT_DATA` | 32 | WO | `0x0000_0000` | Sequential input data buffer FIFO push |
| `0x14` | `RLE_OUTPUT_DATA` | 32 | RO | `0x0000_0000` | Sequential output data buffer FIFO pop |
| `0x18` | `RLE_IRQ_ENABLE` | 32 | R/W | `0x0000_0000` | Bit 0: DONE_IE, Bit 1: ERROR_IE |
| `0x1C` | `RLE_IRQ_STATUS` | 32 | R/W1C | `0x0000_0000` | Bit 0: DONE_IS, Bit 1: ERROR_IS (W1C) |

---

### 4.3 CRC-32 Accelerator (`0x1001_2000`)

Calculates 32-bit CRC checksums conforming to the IEEE 802.3 Ethernet standard ($x^{32} + x^{26} + x^{23} + x^{22} + x^{16} + x^{12} + x^{11} + x^{10} + x^8 + x^7 + x^5 + x^4 + x^2 + x + 1$).

| Offset | Register Name | Width | Access | Reset Value | Description |
|:---:|:---|:---:|:---:|:---:|:---|
| `0x00` | `CRC_DATA` | 32 | WO/RW | `0x0000_0000` | Write word/subword to ingest byte(s) into CRC accumulator |
| `0x04` | `CRC_RESULT` | 32 | RO | `0x0000_0000` | Current reflected and inverted CRC-32 checksum value |
| `0x08` | `CRC_CTRL` | 32 | R/W | `0x0000_0000` | Bit 0: Re-initialize accumulator to seed & clear byte count |
| `0x0C` | `CRC_STATUS` | 32 | RO | `0x0000_0000` | `[15:0]`: Processed byte count, `[0]`: Busy (always 0) |
| `0x10` | `CRC_INIT` | 32 | R/W | `0xFFFF_FFFF` | Initial accumulator seed value |

---

## 5. Standard Peripheral Register Maps

### 5.1 UART 16550 (`0x1000_0000`)

Standard 16550-compatible serial UART controller.

| Offset | Register Name | Access | Description |
|:---:|:---|:---:|:---|
| `0x00` | `UART_RBR` | RO | Receiver Buffer Register (read incoming byte) |
| `0x00` | `UART_THR` | WO | Transmitter Holding Register (write outgoing byte) |
| `0x04` | `UART_IER` | RW | Interrupt Enable Register (RX data ready, TX empty) |
| `0x08` | `UART_BAUD_DIV` | RW | Baud Rate Divisor Register (`Clock / (16 * Baud)`) |
| `0x0C` | `UART_LCR` | RW | Line Control Register (parity, stop bits, word length) |
| `0x14` | `UART_LSR` | RO | Line Status Register (`Bit 0: Data Ready`, `Bit 5: THRE`, `Bit 6: TEMT`) |

### 5.2 64-bit Machine Timer (`0x1000_1000`)

| Offset | Register Name | Access | Description |
|:---:|:---|:---:|:---|
| `0x00` | `MTIME_LOW` | RW | Lower 32 bits of 64-bit real-time counter |
| `0x04` | `MTIME_HIGH` | RW | Upper 32 bits of 64-bit real-time counter |
| `0x08` | `MTIMECMP_LOW` | RW | Lower 32 bits of 64-bit compare register |
| `0x0C` | `MTIMECMP_HIGH`| RW | Upper 32 bits of 64-bit compare register |
| `0x10` | `TIMER_CTRL` | RW | `[0]`: Enable, `[1]`: IRQ Enable, `[2]`: Auto-reload, `[15:8]`: Prescaler |
| `0x14` | `TIMER_STATUS` | R/W1C | `[0]`: Match flag (Write 1 to clear) |

### 5.3 32-bit Bidirectional GPIO (`0x1000_2000`)

| Offset | Register Name | Access | Description |
|:---:|:---|:---:|:---|
| `0x00` | `GPIO_DATA_IN` | RO | Synchronized external input pin levels (`gpio_i[31:0]`) |
| `0x04` | `GPIO_DATA_OUT` | RW | Output pin drive register (`gpio_o[31:0]`) |
| `0x08` | `GPIO_DIR` | RW | Direction control (`1` = output, `0` = input) |
| `0x0C` | `GPIO_IRQ_EN` | RW | Per-pin interrupt enable mask |
| `0x10` | `GPIO_IRQ_TYPE` | RW | Per-pin trigger type (`0` = level, `1` = edge) |
| `0x14` | `GPIO_IRQ_POL` | RW | Per-pin trigger polarity (`0` = low/falling, `1` = high/rising) |
| `0x18` | `GPIO_IRQ_STAT` | R/W1C | Sticky interrupt status flags (Write 1 to clear) |
| `0x1C` | `GPIO_SET_OUT` | WO | Atomic bit set (`DATA_OUT <= DATA_OUT | WDATA`) |
| `0x20` | `GPIO_CLR_OUT` | WO | Atomic bit clear (`DATA_OUT <= DATA_OUT & ~WDATA`) |
| `0x24` | `GPIO_TOG_OUT` | WO | Atomic bit toggle (`DATA_OUT <= DATA_OUT ^ WDATA`) |

