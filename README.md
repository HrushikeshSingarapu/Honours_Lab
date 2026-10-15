# RISC-V Based Configurable Data Compression Accelerator SoC

**Solo Honours Project — Hrushikesh Singarapu**  
**Department of Electronics and Communication Engineering — Vasavi College of Engineering**

---

## 1. Project Overview

This project focuses on the design and integration of a **RISC-V based
configurable hardware data-compression SoC**.

The system is built around a **VeeR EL2 RISC-V processor** and an
AXI-based memory-mapped interconnect. The final system is intended to
use dedicated hardware for:

-   **RLE compression/decompression** --- main custom IP
-   **DMA** --- hardware data movement
-   **CRC/checksum** --- data-integrity verification
-   **UART** --- status and result reporting

The project is being developed incrementally: individual IP/interface
verification first, followed by processor integration and complete SoC
verification.

---

## 2. Overall System Architecture

The planned system uses a **3 × 8 AXI interconnect**: three
processor-side interfaces and eight memory-mapped destinations.

```text
                              +------------------+
                              |     VeeR EL2     |
                              |     RISC-V       |
                              |      RV32IMC     |
                              +--------+---------+
                                       |
                         +-------------+-------------+
                         |             |             |
                        IFU           LSU        Debug / SB
                         |             |             |
                         +-------------+-------------+
                                       |
                                       v
                            +----------------------+
                            |   AXI Interconnect   |
                            |        3 × 8         |
                            +----------+-----------+
                                       |
       +----------+----------+---------+---------+----------+----------+----------+----------+
       |          |          |                   |          |          |          |          |
       v          v          v                   v          v          v          v          v
    I-MEM      D-MEM      UART                Timer      GPIO        RLE        DMA        CRC
```

**All eight blocks below the interconnect are peer AXI destinations.**\
RLE, DMA and CRC are not shown as hierarchical children of one another.

The functional relationship between them is shown separately in Section
10.

---

## 3. Processor-Side Interfaces

The current architecture uses the following VeeR-side interfaces:

| Interface | System Role |
|---|---|
| IFU | Master 0 |
| LSU | Master 1 |
| Debug / SB | Master 2 |

```text
                         +------------------+
                         |     VeeR EL2     |
                         +--------+---------+
                                  |
              +-------------------+-------------------+
              |                   |                   |
             IFU                 LSU             Debug / SB
              |                   |                   |
              +-------------------+-------------------+
                                  |
                                  v
                         AXI Interconnect
```

The exact signal-level connection is being checked against the VeeR EL2
RTL before final integration.

---

## 4. SoC Address Map

The following address map is the project's reference allocation for SoC integration. Reserved regions are not yet implemented peripherals. VeeR internal memory and PIC regions are separate from the external SoC peripheral map.

| Region / IP | Base Address | End Address | Size | Status |
|---|---|---|---|---|
| Instruction Memory | `0x0000_0000` | `0x0000_FFFF` | 64 KB | Integration pending |
| Data Memory | `0x0001_0000` | `0x0002_FFFF` | 128 KB | Integration pending |
| UART | `0x0003_0000` | `0x0003_0FFF` | 4 KB | Standalone verified |
| Timer | `0x0005_0000` | `0x0005_0FFF` | 4 KB | Standalone verified |
| GPIO | `0x0006_0000` | `0x0006_0FFF` | 4 KB | Standalone verified |
| Packet FIFO | `0x0007_0000` | `0x0007_0FFF` | 4 KB | Reserved |
| Packet Counter | `0x0008_0000` | `0x0008_0FFF` | 4 KB | Reserved |
| Enhanced Timer | `0x0009_0000` | `0x0009_0FFF` | 4 KB | Reserved |
| CRC-32 | `0x000A_0000` | `0x000A_0FFF` | 4 KB | Standalone verified |
| DMA | `0x000B_0000` | `0x000B_FFFF` | 64 KB | Pending |
| External Interrupt Controller | `0x000C_0000` | `0x000C_0FFF` | 4 KB | Reserved |
| RLE Accelerator | `0x000D_0000` | `0x000D_0FFF` | 4 KB | Standalone verified |
| Future Expansion | `0x000E_0000` | `0x001F_FFFF` | Approximately 1 MB | Reserved |

### 4.1 VeeR EL2 Internal Memory Regions

The following regions belong to the VeeR EL2 processor and must not be allocated to external SoC peripherals.

| Region | Base Address | End Address | Size | Allocation |
|---|---|---|---|---|
| VeeR DCCM | `0xF004_0000` | `0xF004_FFFF` | 64 KB | Internal to VeeR |
| VeeR ICCM | `0xEE00_0000` | `0xEE00_FFFF` | 64 KB | Internal to VeeR |
| VeeR PIC | `0xF00C_0000` | `0xF00C_7FFF` | 32 KB | Internal to VeeR |

### 4.2 Integration Notes

- The address map represents the planned SoC allocation. Reserved regions do not imply that the corresponding IPs have been implemented.
- The VeeR reset vector is currently reported as `0x8000_0000`, whereas the instruction memory starts at `0x0000_0000`. The boot-address mapping must be reconciled before processor integration.
- The reported VeeR 64-bit data interface requires compatibility with the 32-bit SoC bus.
- The LSU path requires appropriate AXI width conversion where necessary.
- UART uses an AXI4-Lite register interface. The existing adapter, `axi4_to_axi4lite_uart_adapter.v`, must be checked against the actual RTL and integration connections.
- Register offsets, interface widths, and memory sizes must be confirmed against the actual RTL before final SoC integration.

---

## 5. AXI Interconnect

The AXI interconnect is the main communication fabric of the SoC.

### Current work

| Item | Status |
|---|---|
| AXI interconnect RTL | Present |
| Arbiter | Present |
| Priority encoder | Present |
| Wrapper generation infrastructure | Present |
| 3 × 8 wrapper | Verified |
| Address map | Defined |
| Interconnect testbench | 54/54 PASS |
| Interconnect testbench result | 54 checks, 0 errors |

The interconnect work uses the project's existing `verilog-axi`
infrastructure.

### 5.1 Current Development Path

```text
Verified AXI 3 × 8 wrapper
        |
        v
Standalone IPs verified
        |
        v
Resolve VeeR width / reset-vector compatibility
        |
        v
Integrate memory and peripherals
        |
        v
Full SoC verification
```

---

## 6. AXI-Lite UART

The UART is an AXI4-Lite peripheral that has been **implemented and
independently verified**.

It is intended to provide a software-visible interface for system status
and result reporting in the final SoC.

The UART is based on the open-source `axi-lite_uart-ipcore`.

### 6.1 Register Map

| Offset | Register | Function |
|---|---|---|
| `0x00` | THR / RBR | TX write / RX read |
| `0x04` | IER | Interrupt enable |
| `0x08` | Baud Divisor | Used when DLAB = 1 |
| `0x0C` | LCR | Line control |
| `0x14` | LSR | Line status |

### 6.2 Verification Configuration

```text
LCR = 0x83        DLAB enabled
Baud divisor = 16
LCR = 0x03        8N1
IER = 0x01
```

### 6.3 TX Verification

```text
AXI Write
    |
    v
THR = 0xA5
    |
    v
UART TX
    |
    +-- Start
    +-- Data
    +-- Stop
    |
    v
Verified TX byte = 0xA5
```

### 6.4 TX Verification / RX Loopback

```text
             +----------------+
             |      UART      |
             |                |
             | TX         RX  |
             +--+----------^--+
                |          |
                +----------+
                   Loopback

             TX = 0x3C
             RX = 0x3C
```

Verified:

-   TX start/data/stop bits
-   TX return to idle
-   RX data-ready
-   RX data value
-   TX → RX loopback
-   AXI register read/write operation

UART TX/RX operation was also inspected in **Verdi using FSDB
waveforms**.

### UART Status

| Item | Status |
|---|---|
| RTL | Verified |
| AXI-Lite | Verified |
| TX verification | Verified |
| RX verification | Verified |
| Loopback | Verified |
| Waveform analysis | Completed |
| AXI system integration | Pending |

---

---

## 7. RLE Compression / Decompression Accelerator

The **RLE accelerator is the main custom IP contribution** of the
project.

### 7.1 Compression

```text
Input:

A A A A A B B C

        |
        v

Output:

(A,5) (B,2) (C,1)
```

### 7.2 Decompression

```text
(A,5) (B,2) (C,1)

        |
        v

A A A A A B B C
```

The design must handle:

| Case | Requirement |
|---|---|
| Repeated data | Generate run-length pairs |
| Run length = 1 | Encode correctly |
| Non-repetitive data | Preserve data correctly |
| Long runs | Split when count field is exceeded |
| End of stream | Correct termination |
| Decompression | Reconstruct original data |
| Round trip | Original = decompressed |

### Current State

The RLE IP is implemented and has a standalone testbench. It has not yet been integrated into the complete SoC.

| Work | Status |
|---|---|
| Architecture | Implemented |
| Register interface (AXI4-Lite) | Implemented |
| Compressor RTL | Implemented |
| Decompressor RTL | Implemented |
| Standalone verification | 65/65 PASS |
| SoC integration | Pending |

---

## 8. DMA Controller

The DMA controller is intended to perform bulk data movement without
requiring the processor to transfer every data item directly.

```text
             +-------------+
             |   Memory    |
             +------+------+
                    |
                    | Data movement
                    v
             +-------------+
             |     DMA     |
             | Controller  |
             +------+------+
                    |
                    v
                RLE / Data
                  Path
```

DMA has not yet been selected or integrated. The current plan is to
reuse or adapt an existing open-source DMA IP.

| Work | Status |
|---|---|
| IP selection | Pending |
| Interface adaptation | Pending |
| RTL integration | Pending |
| Verification | Pending |
| SoC integration | Pending |

---

## 9. CRC / Checksum Engine

The CRC/checksum engine is intended to verify data integrity across the
compression/decompression process.

```text
Original Data
     |
     v
CRC / Checksum
     |
     v
Compression
     |
     v
Decompression
     |
     v
CRC / Checksum
     |
     v
   Compare
     |
     v
Verification Result
```

The standalone CRC-32 RTL and AXI4-Lite register interface are
implemented and independently verified. SoC integration remains pending.

| Item | Status |
|---|---|
| Base address `0x000A_0000` | Allocated in the SoC address map |
| CRC-32/ISO-HDLC polynomial | Implemented |
| AXI4-Lite register interface | Implemented |
| Synthesizable RTL | Implemented |
| Standalone verification | 147/147 PASS |
| SoC integration | Pending |

---

## 10. Functional Compression Data Flow

This is the **planned functional data path**, not the RTL hierarchy.

```text
                         +----------------+
                         |    VeeR EL2    |
                         | Control / SW   |
                         +-------+--------+
                                 |
                              Configure
                                 |
                                 v
                         +---------------+
                         |      DMA      |
                         +-------+-------+
                                 |
                                 v
                         +---------------+
                         |    Memory     |
                         +-------+-------+
                                 |
                              Input Data
                                 |
                                 v
                         +---------------+
                         | RLE Compressor|
                         +-------+-------+
                                 |
                          Compressed Data
                                 |
                                 v
                         +---------------+
                         |    Memory     |
                         +-------+-------+
                                 |
                                 v
                         +---------------+
                         | RLE Decompress|
                         +-------+-------+
                                 |
                         Decompressed Data
                                 |
                                 v
                         +---------------+
                         | CRC / Checksum|
                         +-------+-------+
                                 |
                                 v
                         Verification Result
                                 |
                                 v
                              VeeR EL2
                                 |
                                 v
                               UART
```

> This is the planned end-to-end flow. It has not yet been implemented
> as a complete hardware path.

---

## 11. Memory, Timer and GPIO

### 11.1 Memory

```text
              VeeR EL2
                 |
                 v
          AXI Interconnect
             /       \
            v         v
      Instruction    Data
        Memory      Memory
```

| Memory | Base Address |
|---|---|
| Instruction Memory | `0x0000_0000` |
| Data Memory | `0x0001_0000` |

The memories are intended to hold instructions, application data,
input/compressed/decompressed buffers, and DMA data once memory and SoC
integration are completed.

### 11.2 Timer and GPIO

| Peripheral | Base Address | Status |
|---|---|---|
| Timer | `0x0005_0000` | Implemented and verified (62/62 PASS) |
| GPIO | `0x0006_0000` | Implemented and verified (62/62 PASS) |

Both Timer and GPIO are **implemented as standalone AXI4-Lite
peripherals** and have passed their reported standalone testbenches.
They have not yet been verified as part of the complete SoC.

---

## 12. System Integration Strategy

The system is being integrated incrementally.

```text
                         VeeR EL2
                            |
                  IFU / LSU / Debug-SB
                            |
                            v
                  +-------------------+
                  |   AXI 3 × 8       |
                  |   Interconnect    |
                  +---------+---------+
                            |
      +---------+-----------+-----------+---------+---------+---------+---------+
      |         |           |           |         |         |         |         |
      v         v           v           v         v         v         v         v
   I-MEM     D-MEM        UART        Timer     GPIO       RLE       DMA       CRC
```

### Integration order

| Stage | Work |
|---:|---|
| 1 | Standalone IP and AXI interconnect verification — reported complete |
| 2 | Resolve VeeR AXI width and reset-vector mapping |
| 3 | Integrate VeeR and instruction/data memory |
| 4 | Integrate UART, Timer, GPIO, RLE, and CRC-32 |
| 5 | Select/adapt and integrate DMA |
| 6 | Verify processor-to-peripheral transactions |
| 7 | Verify end-to-end compression/decompression and CRC flow |
| 8 | Full SoC verification |

---

## 13. Current Development Focus

The immediate work is integrating the already-tested standalone IPs into
the **VeeR + AXI interconnect + memory/peripheral SoC**. The standalone
test results do not establish full SoC functionality.

```text
                    VeeR EL2
                       |
             +---------+---------+
             |         |         |
            IFU       LSU    Debug / SB
             |         |         |
             +---------+---------+
                       |
                       v
                AXI Interconnect
                     3 × 8
                       |
        +--------------+--------------+
        |                             |
        v                             v
     Memory                          UART
```

### Immediate sequence

```text
1. Confirm VeeR interfaces and reset-vector mapping
          ↓
2. Implement the required 64-bit/32-bit AXI width bridge
          ↓
3. Connect VeeR to the verified AXI 3 × 8 interconnect
          ↓
4. Integrate instruction/data memory and UART
          ↓
5. Verify processor-to-memory/peripheral transactions
          ↓
6. Integrate the standalone RLE, CRC-32, Timer, and GPIO IPs
          ↓
7. Select/adapt DMA and verify the end-to-end data path
```

---

## 14. Repository Structure

Main SoC work:

```text
Hon_CBP/
└── RISC_V_Based_Configurable_Data_Compression_Accelerator_SoC/
    │
    ├── rtl/
    │   ├── AXI interconnect RTL
    │   ├── arbiter
    │   └── priority encoder
    │
    ├── tb/
    │   └── interconnect testbench
    │
    ├── scripts/
    │   └── interconnect wrapper generator
    │
    ├── docs/
    ├── reg/
    ├── lib/
    └── run/
```

Separate lab/IP work in the repository includes the standalone UART work
and an unrelated AES core exercise.

---

## 15. Tools

| Area | Tool / Technology |
|---|---|
| RTL | Verilog / SystemVerilog |
| Processor | VeeR EL2 / RV32IMC |
| Bus | AXI / AXI4-Lite |
| Simulation | Synopsys VCS |
| Waveform Debug | Synopsys Verdi / FSDB |
| Interconnect Generation | Python / Jinja2 |
| Version Control | Git / GitHub |
| Development Environment | Linux |

---

## 16. Project Status

| Area | Status | Current Position |
|---|---|---|
| AXI 3 × 8 Interconnect | Verified | 54/54 checks passed; routing, burst, and reset tests reported passing |
| RLE Accelerator | Verified | 65/65 checks passed; compression, decompression, IRQ, overflow, and AXI tests |
| AXI-Lite UART | Verified | 75/75 checks passed; TX/RX, loopback, baud, parity, and FIFO tests |
| CRC-32 Engine | Verified | 147/147 checks passed; CRC-32/ISO-HDLC and known vectors |
| Basic Timer | Verified | 62/62 checks passed; counter, compare, IRQ, reset, and boundary tests |
| GPIO Controller | Verified | 62/62 checks passed; direction, read/write, IRQ, and reset tests |
| Total reported standalone checks | 465/465 passed | Interconnect plus five standalone IPs |
| VeeR EL2 integration | Pending | AXI width compatibility and reset-vector mapping |
| Instruction/Data Memory | Pending | Integration |
| DMA Controller | Pending | IP selection and integration |
| Full SoC Integration | Pending | Not yet completed |
| Full SoC Verification | Pending | Not yet completed |
| FPGA Implementation | Pending | Not yet completed |

### Status Legend

- **Verified:** Standalone verification reported as passing.
- **Pending:** Not yet completed at the SoC level.

---

## 17. Remaining Work

  -----
| Priority | Area | Remaining Work |
|---:|---|---|
| 1 | VeeR + AXI | Implement/verify the 64-bit/32-bit AXI width bridge and resolve reset-vector boot mapping |
| 2 | Memory/UART | Connect verified IPs through the system interconnect to VeeR |
| 3 | DMA | Select/adapt an open-source DMA IP and validate RLE MMIO compatibility |
| 4 | System | Verify end-to-end compression flow: CPU → DMA → RLE → CRC → UART |
| 5 | Verification | Full SoC simulation and cross-IP transaction verification |
| 6 | FPGA | Synthesis and implementation |
| 7 | Documentation | Final results, resource usage, and performance measurements |

---

## 18. Final Project Goal

The final SoC is intended to provide a processor-controlled hardware
compression platform:

```text
                              +------------------+
                              |     VeeR EL2     |
                              |     RISC-V       |
                              +--------+---------+
                                       |
                         IFU / LSU / Debug-SB
                                       |
                                       v
                            +----------------------+
                            |   AXI Interconnect   |
                            |        3 × 8         |
                            +----------+-----------+
                                       |
       +----------+----------+---------+---------+----------+----------+----------+----------+
       |          |          |                   |          |          |          |          |
       v          v          v                   v          v          v          v          v
    I-MEM      D-MEM      UART                Timer      GPIO        RLE        DMA        CRC
```

The completed project should demonstrate:

-   RISC-V processor integration
-   AXI-based SoC interconnect
-   Memory-mapped peripheral access
-   UART communication
-   Hardware RLE compression
-   Hardware RLE decompression
-   DMA-based data movement
-   CRC/checksum-based data verification
-   Processor-controlled operation
-   RTL simulation and verification
-   Complete SoC integration
-   FPGA implementation where applicable

---

## Project Snapshot

> **Current milestone:** AXI 3×8 interconnect and five standalone IPs
> have reported 465/465 checks passing
>
> **Standalone verification reported:** AXI 3×8 Interconnect (54/54),
> RLE (65/65), UART (75/75), CRC-32 (147/147), Timer (62/62), GPIO
> (62/62)
>
> **In progress:** SoC integration --- VeeR EL2, AXI interconnect,
> memory, and peripheral fabric
>
> **Next:** VeeR 64→32-bit AXI bridge, instruction/data memory, and
> CPU-to-peripheral transaction verification
>
> **Later:** DMA integration → End-to-end compression flow → Full SoC
> verification → FPGA
