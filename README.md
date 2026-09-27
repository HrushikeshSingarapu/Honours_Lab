# Honours_Lab

A repository for the RTL/SoC design work carried out as part of a Solo
Honours Project, along with supporting hardware IP developed alongside it.

The repository contains the ongoing Honours Project — a **RISC-V Based
Configurable Data Compression Accelerator SoC** — together with additional
hardware IP work developed during the lab, including an AXI-Lite UART core
and an AES core.

## 1. Current Work — Configurable Data Compression Accelerator SoC

### 1.1 Overview

The primary ongoing project in this repository is the design and
verification of a RISC-V based SoC that offloads data compression to
dedicated hardware, instead of doing it in software.

Embedded systems constantly generate data that has to be stored or moved,
and both cost memory and bandwidth. Compression shrinks that cost — but if
done in software, it burns processor cycles on a repetitive task. This
project moves that task into a hardware accelerator instead, so the
processor hands off the work and gets its cycles back.

The compression algorithm used is **Run-Length Encoding (RLE)** — simple
enough to design and fully verify solo, while still being a genuine,
useful compression technique for data with long repeated runs (e.g.
sensor logs, simple image/bitmap data).

### 1.2 Why This Architecture
    RISC-V (VeeR EL2)
            |
            | AXI
            v
    AXI Interconnect
            |
+-----------+------------+------------------+
|           |            |                  |

Memory UART Timer / GPIO Custom / Other IP
|
+-------------+-------------+
| | |
RLE DMA CRC/
Accelerator Controller Checksum


The RISC-V core (VeeR EL2) sits at the center, talking to everything
through a shared AXI interconnect. Input data is placed in memory, the
DMA controller moves it to the RLE accelerator without the CPU
babysitting the transfer, the accelerator compresses or decompresses
it, and the CRC/checksum engine confirms nothing was corrupted along
the way. UART reports status out.

### 1.3 Basic Operation

**Stage 1 — Configuration.** The processor writes to control registers
to configure the DMA source/destination and the RLE mode (compress or
decompress).

**Stage 2 — Data Movement.** The DMA controller moves a block of data
from memory to the accelerator without further CPU involvement.

**Stage 3 — Compression/Decompression.** The RLE accelerator scans the
incoming byte stream, counts consecutive identical values, and emits
value-count pairs (compression) — or reverses the process
(decompression) to reconstruct the original data.

**Stage 4 — Verification.** The CRC/checksum engine computes a check
value over the recovered data and compares it against the original,
confirming the round trip was lossless.

**Stage 5 — Reporting.** UART reports status, pass/fail, and
compression ratio.

### 1.4 Design Requirements

- **Data integrity** — recovered data must exactly match the original.
- **Correct edge-case handling** — non-repetitive data, maximum run
  length, single-byte runs.
- **Memory-mapped control** — every IP (RLE, DMA, CRC, UART) accessible
  through the processor via AXI registers.
- **Solo-realistic scope** — one genuinely custom IP (the RLE
  accelerator); DMA and CRC reused/modified from open-source IP rather
  than designed from scratch.
- **Synthesizable RTL** — Verilog/SystemVerilog suitable for simulation
  and, where feasible, FPGA implementation.

### 1.5 Verification

Verification across the project is intended to check:

- Interconnect address decoding, region boundaries, and unmapped-address behavior
- Read/write handshake timing and burst transactions
- RLE compression correctness against a reference model
- RLE decompression correctness (round-trip: compress → decompress → compare)
- RLE edge cases: no repetition, maximum run length, single-run-length bytes
- CRC detection of corrupted data
- DMA transfer correctness between memory and accelerator
- Full-SoC simulation once all blocks are integrated
    +------------------+
    |     RTL DUT      |
    +--------+---------+
             |
    +--------v---------+
    |    Testbench     |
    +--------+---------+
             |

+-------------+-------------+
| | |
Stimulus Monitor Checker
| | |
+-------------+-------------+
|
v
Expected vs Actual
|
v
PASS / FAIL


## 2. Additional Projects Developed Alongside

### 2.1 AXI-Lite UART IP Core

A memory-mapped UART peripheral, used to understand AXI4-Lite slave
design and to give the SoC a way to report status.
         AXI4-Lite
            |
            v
  +-------------------+
  |  AXI-Lite Slave   |
  +---------+---------+
            |
            v
  +-------------------+
  |  UART Registers   |
  +---------+---------+
            |
            v
  +-------------------+
  |   UART Control    |
  +----+---------+----+
       |         |
       v         v
    UART TX    UART RX

Based on the open-source `axi-lite_uart-ipcore` (m4j0rt0m). Standalone
VCS simulation passes: TX of a byte, and TX→RX loopback, both verified
correctly against the expected values. Register map (RBR/THR, IER,
BAUD divisor, LCR, LSR) confirmed against the actual RTL.

### 2.2 AES Hardware Core

An AES encryption core, developed as a separate lab exercise —
open-source `aes_core` IP with its own testbench, simulation, and
synthesis scripts. Not part of the compression SoC; kept in the repo
as supporting IP-design experience.
      AXI Interface
            |
            v
  +------------------+
  |   AES Registers  |
  +--------+---------+
            v
  +------------------+
  |   AES Control     |
  +--------+---------+
            v
  +------------------+
  |    AES Core       |
  |  Round Logic      |
  |  S-Box            |
  |  Key Expansion    |
  +--------+---------+
            v
       Ciphertext

## 3. Repository Organization

Honours_Lab/
│
├── Hon_CBP/
│ └── RISC_V_Based_Configurable_Data_Compression_Accelerator_SoC/
│ ├── rtl/ — AXI interconnect, arbiter, priority encoder
│ ├── tb/ — interconnect testbench
│ ├── docs/ — (pending)
│ ├── reg/ — (pending)
│ └── scripts/ — interconnect wrapper generator
│
├── uart/
│ └── axi-lite_uart-ipcore/
│
└── AES/
└── aes_core/


Each IP is developed and verified independently before integration into
the full SoC — this keeps simulation environments isolated and makes it
possible to debug one block at a time.

## 4. Technologies and Tools

**Hardware Description Languages:** Verilog, SystemVerilog
**Bus/SoC Interfaces:** AXI4, AXI4-Lite, memory-mapped peripheral design
**Simulation & Debug:** Synopsys VCS, Verdi (waveform/FSDB analysis)
**Scripting:** Python (Jinja2-based interconnect wrapper generation)
**Processor Core:** RISC-V VeeR EL2 (RV32IMC)
**Version Control:** Git, GitHub — organized per-IP by branch

## 5. Development Flow

System Requirement
|
v
Architecture Design
|
v
RTL Coding (Verilog/SystemVerilog)
|
v
Testbench Development
|
v
Simulation
|
v
Functional Verification
|
v
SoC Integration
|
v
Full-System Verification


## 6. Project Status

| Component | Status |
|---|---|
| AXI Interconnect (3×8) | 🚧 In Progress |
| AXI-Lite UART IP | ✅ Verified (standalone) |
| AES Core | ✅ Developed (separate lab work) |
| VeeR EL2 Integration | 🔲 Not Started |
| RLE Accelerator | 🔲 Not Started |
| DMA Controller | 🔲 Not Started |
| CRC/Checksum Engine | 🔲 Not Started |
| Full SoC Verification | 🔲 Not Started |

## 7. Current Development Direction

The primary effort right now is finalizing the AXI interconnect
configuration (master count pending confirmation against actual VeeR
EL2 documentation) and getting its testbench running cleanly, before
connecting the processor and routing UART through it. Once that
backbone is verified, the focus moves to the RLE accelerator — the
main custom IP and the actual core of this Honours Project — followed
by DMA and CRC integration and full-SoC verification.

## 8. Author

**Hrushikesh Singarapu**
Electronics & Communication Engineering, Vasavi College of Engineering
Focus: Frontend VLSI Design, SoC Design (Honours)

## Note

This repository contains academic/honours project work in progress.
Branches are organized per IP block rather than per pull request.
