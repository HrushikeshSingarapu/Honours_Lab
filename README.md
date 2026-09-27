# RISC-V Based Configurable Data Compression Accelerator SoC

**Solo Honours Project — Hrushikesh Singarapu**  
**Department of Electronics and Communication Engineering — Vasavi College of Engineering**

---

## 1. Project Overview

This project focuses on the design and integration of a **RISC-V based configurable hardware data-compression SoC**.

The system is built around a **VeeR EL2 RISC-V processor** and an AXI-based memory-mapped interconnect. The final system is intended to use dedicated hardware for:

- **RLE compression/decompression** — main custom IP
- **DMA** — hardware data movement
- **CRC/checksum** — data-integrity verification
- **UART** — status and result reporting

The project is being developed incrementally: individual IP/interface verification first, followed by processor integration and complete SoC verification.

---

## 2. Overall System Architecture

The planned system uses a **3 × 8 AXI interconnect**: three processor-side interfaces and eight memory-mapped destinations.

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

**All eight blocks below the interconnect are peer AXI destinations.**  
RLE, DMA and CRC are not shown as hierarchical children of one another.

The functional relationship between them is shown separately in Section 10.

---

## 3. Processor-Side Interfaces

The current architecture uses the following VeeR-side interfaces:

| Interface | System Role |
|-----------|-------------|
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

The exact signal-level connection is being checked against the VeeR EL2 RTL before final integration.

---

## 4. Planned Memory Map

The current interconnect testbench defines:

| Port | Region | Base Address |
|:----:|--------|--------------|
| M00 | Instruction Memory | `0x0000_0000` |
| M01 | Data Memory | `0x0004_0000` |
| M02 | UART | `0x1000_0000` |
| M03 | Timer | `0x1000_1000` |
| M04 | GPIO | `0x1000_2000` |
| M05 | RLE Accelerator | `0x1001_0000` |
| M06 | DMA Controller | `0x1001_1000` |
| M07 | CRC / Checksum | `0x1001_2000` |

This is the **current planned/testbench map** and will be finalized during integration.

---

## 5. AXI Interconnect

The AXI interconnect is the main communication fabric of the SoC.

### Current work

| Item | Status |
|------|:------:|
| AXI interconnect RTL | ✅ Present |
| Arbiter | ✅ Present |
| Priority encoder | ✅ Present |
| Wrapper generation infrastructure | ✅ Present |
| 3 × 8 wrapper | 🚧 In progress |
| Address map | ✅ Defined |
| Interconnect testbench | 🚧 Being corrected |
| Full verification | ⬜ Pending |

The interconnect work uses the project's existing `verilog-axi` infrastructure.

### 5.1 Current Development Path

```text
Existing 2 × 7 work
        |
        v
3 × 8 wrapper
        |
        v
Fix testbench / filelist
        |
        v
Verify AXI routing
        |
        v
Connect VeeR
```

---

## 6. AXI-Lite UART

The UART is an AXI4-Lite peripheral that has been **implemented and independently verified**.

It is intended to provide a software-visible interface for system status and result reporting in the final SoC.

The UART is based on the open-source `axi-lite_uart-ipcore`.

### 6.1 Register Map

| Offset | Register | Function |
|:------:|----------|----------|
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

### 6.3 Verification Results

### 6.4 TX Verification

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

### 6.4 TX Verification/RX Loopback

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

- TX start/data/stop bits
- TX return to idle
- RX data-ready
- RX data value
- TX → RX loopback
- AXI register read/write operation

UART TX/RX operation was also inspected in **Verdi using FSDB waveforms**.

### UART status

| Item | Status |
|------|:------:|
| RTL | ✅ |
| AXI-Lite | ✅ |
| TX verification | ✅ |
| RX verification | ✅ |
| Loopback | ✅ |
| Waveform analysis | ✅ |
| AXI system integration | ⬜ |

---

## 7. RLE Compression / Decompression Accelerator

The **RLE accelerator is the main custom IP contribution** of the project.

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
|------|-------------|
| Repeated data | Generate run-length pairs |
| Run length = 1 | Encode correctly |
| Non-repetitive data | Preserve data correctly |
| Long runs | Split when count field is exceeded |
| End of stream | Correct termination |
| Decompression | Reconstruct original data |
| Round trip | Original = decompressed |

### Current state

| Work | Status |
|------|:------:|
| Architecture | ⬜ Planned |
| Register interface | ⬜ Planned |
| Compressor RTL | ⬜ Not started |
| Decompressor RTL | ⬜ Not started |
| Verification | ⬜ Not started |
| SoC integration | ⬜ Pending |

---

## 8. DMA Controller

The DMA controller is intended to perform bulk data movement without requiring the processor to transfer every data item directly.

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

The current plan is to reuse or modify an existing open-source DMA IP.

| Work | Status |
|------|:------:|
| IP selection | ⬜ Pending |
| Interface adaptation | ⬜ Pending |
| RTL integration | ⬜ Pending |
| Verification | ⬜ Pending |
| SoC integration | ⬜ Pending |

---

## 9. CRC / Checksum Engine

The CRC/checksum engine is intended to verify data integrity across the compression/decompression process.

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

The current plan is to reuse or modify an existing open-source implementation.

| Item | Status |
|------|:------:|
| Address `0x1001_2000` reserved | ✅ |
| IP selection | ⬜ Pending |
| RTL | ⬜ Pending |
| Verification | ⬜ Pending |
| SoC integration | ⬜ Pending |

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

> This is the planned end-to-end flow. It has not yet been implemented as a complete hardware path.

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
|--------|--------------|
| Instruction Memory | `0x0000_0000` |
| Data Memory | `0x0004_0000` |

The memories will eventually hold instructions, application data, input/compressed/decompressed buffers and DMA data.

### 11.2 Timer and GPIO

| Peripheral | Base Address |
|------------|--------------|
| Timer | `0x1000_1000` |
| GPIO | `0x1000_2000` |

Timer and GPIO are currently **reserved/planned interfaces**, not the immediate development focus.

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
|:----:|------|
| 1 | Verify individual IPs |
| 2 | Verify AXI interconnect |
| 3 | Integrate VeeR |
| 4 | Integrate instruction/data memory |
| 5 | Integrate UART |
| 6 | Verify processor-to-peripheral transactions |
| 7 | Implement and verify RLE |
| 8 | Integrate DMA |
| 9 | Integrate CRC/checksum |
| 10 | Full SoC verification |

---

## 13. Current Development Focus

The immediate work is the **VeeR + AXI interconnect + memory/UART foundation**.

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
1. Confirm VeeR interfaces
          ↓
2. Correct interconnect testbench/filelist
          ↓
3. Verify 3 × 8 interconnect
          ↓
4. Connect VeeR
          ↓
5. Connect memory and UART
          ↓
6. Verify VeeR → AXI → Memory / UART
          ↓
7. Start RLE accelerator development
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

Separate lab/IP work in the repository includes the standalone UART work and an unrelated AES core exercise.

---

## 15. Tools

| Area | Tool / Technology |
|------|-------------------|
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
|------|:------:|------------------|
| AXI-Lite UART | ✅ | Implemented and standalone verified |
| UART TX/RX loopback | ✅ | `0xA5` TX and `0x3C` loopback verified |
| UART waveform analysis | ✅ | Verdi/FSDB analysis completed |
| AXI interconnect RTL | ✅ | Existing RTL/supporting logic present |
| AXI 3 × 8 wrapper | 🚧 | Being prepared/verified |
| Interconnect testbench | 🚧 | Build/filelist correction required |
| VeeR EL2 integration | 🚧 | Interface investigation/planning |
| UART through AXI system | ⬜ | Pending |
| Instruction/Data Memory | ⬜ | Integration pending |
| RLE Accelerator | ⬜ | Not started |
| DMA Controller | ⬜ | Not started |
| CRC/Checksum | ⬜ | Not started |
| Full SoC Integration | ⬜ | Pending |
| Full SoC Verification | ⬜ | Pending |
| FPGA Implementation | ⬜ | Pending |

### Status Legend

- ✅ Completed / Verified
- 🚧 Currently in progress
- ⬜ Pending / Not started

---

## 17. Remaining Work

| Priority | Area | Remaining Work |
|:--------:|------|----------------|
| 1 | VeeR + AXI | Complete interface mapping and integration |
| 2 | AXI | Complete 3 × 8 testbench and verification |
| 3 | Memory/UART | Connect and verify through the system interconnect |
| 4 | RLE | Design, implement and verify compressor/decompressor |
| 5 | DMA | Select/adapt and integrate DMA IP |
| 6 | CRC | Implement/adapt and verify CRC/checksum IP |
| 7 | System | Complete end-to-end compression flow |
| 8 | Verification | Full SoC simulation and waveform analysis |
| 9 | FPGA | Synthesis and implementation |
| 10 | Documentation | Final results, resource usage and performance measurements |

---

## 18. Final Project Goal

The final SoC is intended to provide a processor-controlled hardware compression platform:

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

- RISC-V processor integration
- AXI-based SoC interconnect
- Memory-mapped peripheral access
- UART communication
- Hardware RLE compression
- Hardware RLE decompression
- DMA-based data movement
- CRC/checksum-based data verification
- Processor-controlled operation
- RTL simulation and verification
- Complete SoC integration
- FPGA implementation where applicable

---

## Project Snapshot

> **Current milestone:** VeeR EL2 + AXI 3 × 8 integration foundation  
>
> **Completed:** AXI-Lite UART implementation, TX/RX verification, loopback and waveform analysis  
>
> **In progress:** AXI 3 × 8 interconnect verification and VeeR integration preparation  
>
> **Next:** VeeR → AXI → Memory/UART integration  
>
> **Later:** RLE → DMA → CRC → Complete SoC → Full verification
