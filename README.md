
# RISC-V Based Configurable Data Compression Accelerator SoC

### VeeR EL2 • AXI Interconnect • RLE Compression / Decompression • DMA • CRC-32

[![ISA](https://img.shields.io/badge/ISA-RV32IMC-blue)](https://riscv.org/technical/specifications/)
[![Core](https://img.shields.io/badge/Core-VeeR%20EL2-informational)](https://github.com/chipsalliance/Cores-VeeR-EL2)
[![Interconnect](https://img.shields.io/badge/Interconnect-AXI-orange)]()
[![HDL](https://img.shields.io/badge/HDL-Verilog%20%2F%20SystemVerilog-blue)]()
[![Simulation](https://img.shields.io/badge/Simulation-ModelSim%20%7C%20Icarus-lightgrey)]()


**Department of Electronics and Communication Engineering --- Vasavi
College of Engineering**
:::

------------------------------------------------------------------------

## Table of Contents

1.  [Project Overview](#1-project-overview)
2.  [Project Motivation and
    Objectives](#2-project-motivation-and-objectives)
3.  [Overall SoC Architecture](#3-overall-soc-architecture)
4.  [Processor and Bus Interfaces](#4-processor-and-bus-interfaces)
5.  [AXI Interconnect and Bus
    Adaptation](#5-axi-interconnect-and-bus-adaptation)
6.  [Instruction and Data Memory](#6-instruction-and-data-memory)
7.  [UART Peripheral](#7-uart-peripheral)
8.  [RLE Compression / Decompression
    Accelerator](#8-rle-compression--decompression-accelerator)
9.  [DMA Controller](#9-dma-controller)
10. [CRC-32 Accelerator](#10-crc-32-accelerator)
11. [Timer and GPIO](#11-timer-and-gpio)
12. [End-to-End Compression Data
    Flow](#12-end-to-end-compression-data-flow)
13. [System Address Map](#13-system-address-map)
14. [Firmware and CPU-Controlled
    Operation](#14-firmware-and-cpu-controlled-operation)
15. [Repository Structure](#15-repository-structure)
16. [Tools and Simulation
    Environment](#16-tools-and-simulation-environment)
17. [Build and Run](#17-build-and-run)
18. [Verification Strategy and
    Results](#18-verification-strategy-and-results)
19. [Implementation Notes and
    Limitations](#19-implementation-notes-and-limitations)
20. [Current Project Status](#20-current-project-status)
21. [References](#21-references)
22. [Author](#22-author)

------------------------------------------------------------------------

## 1. Project Overview

This project focuses on the design, implementation and verification of a
**RISC-V based configurable hardware data-compression System-on-Chip
(SoC)**.

The system is built around the **VeeR EL2 RISC-V processor** and an
AXI-based memory-mapped interconnect. Dedicated hardware IP blocks are
integrated to perform compression/decompression, data movement and
data-integrity checking.

The main hardware components are:

-   **RLE Compression / Decompression Accelerator** --- the primary
    data-processing IP.
-   **DMA Controller** --- performs programmed data transfers between
    memory locations and accelerator-related buffers.
-   **CRC-32 Accelerator** --- calculates IEEE 802.3 CRC-32 values for
    data-integrity verification.
-   **UART** --- provides serial communication and firmware-visible
    status output.
-   **GPIO and Timer** --- provide memory-mapped peripheral
    functionality.
-   **Instruction and Data Memories** --- store processor firmware and
    application data.
-   **AXI Interconnect and Bridges** --- connect the processor-side
    interfaces, DMA and memory-mapped destinations.

The VeeR EL2 processor executes bare-metal firmware and controls the
hardware through memory-mapped registers. The accelerators perform their
assigned operations in RTL hardware.

The project has progressed from individual IP development and
verification to processor integration and end-to-end firmware-driven SoC
simulation.

## 2. Project Motivation and Objectives

Repeated data appears in many data streams. Run-Length Encoding (RLE)
represents consecutive repetitions using a value/count representation.
For suitable input patterns, this reduces the amount of data that must
be stored or transferred.

A software-only implementation requires the processor to execute the
encoding, decoding and data-transfer operations. This project explores a
hardware-assisted approach in which dedicated IP blocks perform these
operations while a RISC-V processor coordinates the system.

### Main objectives

1.  Integrate a VeeR EL2 RISC-V processor into a memory-mapped SoC.
2.  Develop and integrate an AXI-based interconnect and bus adaptation
    logic.
3.  Implement and verify an RLE compression/decompression accelerator.
4.  Integrate a DMA controller for programmed data movement.
5.  Integrate an IEEE 802.3 CRC-32 engine for data-integrity checking.
6.  Integrate memory-mapped UART, GPIO and Timer peripherals.
7.  Develop bare-metal firmware to control the hardware accelerators.
8.  Verify the system through unit-level, subsystem-level and
    processor-driven RTL simulations.

**RLE limitation:** compression is data-dependent. Repetitive input
generally benefits more than non-repetitive input; RLE does not
guarantee that every input becomes smaller.

------------------------------------------------------------------------

## 3. Overall SoC Architecture

### 3.1 High-level block diagram

The integrated system uses a **4-master × 8-slave AXI interconnect** in
the current SoC integration.

``` text
                         +----------------------+
                         |       VeeR EL2       |
                         |      RISC-V Core     |
                         |       RV32IMC        |
                         +----------+-----------+
                                    |
                    +---------------+---------------+
                    |               |               |
                   IFU             LSU          Debug / SB
                    |               |               |
                    +---------------+---------------+
                                    |
                                    v
                         +----------------------+
                         |    AXI Interconnect  |
                         |       4 × 8          |
                         +----------+-----------+
                                    |
       +------------+---------------+---------------+------------+
       |            |               |               |            |
       v            v               v               v            v
    I-MEM         D-MEM            UART            Timer         GPIO
       |            |               |               |            |
       +------------+---------------+---------------+------------+
                                    |
                 +------------------+------------------+
                 |                  |                  |
                 v                  v                  v
              RLE IP              DMA IP             CRC-32 IP
```

The diagram represents the system-level connectivity. The memory-mapped
destinations are peer interconnect targets; RLE, DMA and CRC are not
hierarchical children of one another.

### 3.2 Main functional roles

  Block                Responsibility
  -------------------- -------------------------------------------------
  VeeR EL2             Executes firmware and controls the SoC
  AXI interconnect     Routes transactions between masters and slaves
  Instruction Memory   Stores executable firmware
  Data Memory          Stores input, compressed and reconstructed data
  RLE                  Performs compression and decompression
  DMA                  Performs programmed data transfers
  CRC-32               Calculates data-integrity checksums
  UART                 Serial communication and status output
  GPIO                 General-purpose input/output
  Timer                Timer functionality

### 3.3 Functional relationship

The processor configures the hardware using memory-mapped registers. DMA
handles programmed data movement, RLE performs the data transformation,
and CRC-32 checks the original and reconstructed data.

This functional relationship is different from the RTL hierarchy: the IP
blocks remain separate interconnect destinations.

------------------------------------------------------------------------

## 4. Processor and Bus Interfaces

### 4.1 VeeR EL2 processor

The SoC integrates the open-source **VeeR EL2 RISC-V core** from CHIPS
Alliance.

  Property        Description
  --------------- ------------------------------------------------------
  Processor       VeeR EL2
  ISA             RV32IMC
  Architecture    32-bit RISC-V
  Role            System control and firmware execution
  Software        Bare-metal C firmware
  Memory access   Processor-side instruction and load/store interfaces

The VeeR EL2 core is reused as an external processor IP; it is not
designed from scratch as part of this project.

### 4.2 Processor-side interfaces

The processor-side system interfaces include:

  -----------------------------------------------------------------------
  Interface                           System role
  ----------------------------------- -----------------------------------
  IFU                                 Instruction-fetch access

  LSU                                 Load/store and memory-mapped
                                      peripheral access

  Debug / System Bus                  Debug/system-bus access

  DMA-side interface                  DMA-related access path in the
                                      integrated system
  -----------------------------------------------------------------------

The processor's bus interfaces are connected through the SoC's bus
adaptation and interconnect logic.

### 4.3 Firmware control

The CPU performs the system-level sequence:

1.  Initializes the execution environment.
2.  Prepares input data in Data Memory.
3.  Configures DMA and accelerator registers.
4.  Starts the required hardware operations.
5.  Checks operation status.
6.  Reads CRC-32 results.
7.  Compares original and reconstructed data.
8.  Writes a completion or failure result.

------------------------------------------------------------------------

## 5. AXI Interconnect and Bus Adaptation

The AXI interconnect is the communication fabric connecting the
processor-side interfaces, DMA and memory-mapped peripherals.

### 5.1 Interconnect organization

The integrated SoC uses the **4 × 8 interconnect wrapper**
(`axi_interconnect_wrap_4x8`).

A separate **3 × 8 interconnect testbench** is also maintained and
verified independently. It must not be confused with the 4 × 8 wrapper
used in the integrated SoC regression.

### 5.2 Main responsibilities

-   Address decoding and slave selection.
-   Routing read and write transactions.
-   Arbitration between active masters.
-   AXI channel handshaking.
-   Backpressure handling.
-   Connecting memory and peripheral targets.

### 5.3 Bus-width adaptation

The VeeR-side bus configuration and the 32-bit peripheral interfaces
require bus adaptation. The project includes an AXI 64-to-32 bridge and
associated testbench coverage.

### 5.4 Verification

  -----------------------------------------------------------------------
  Item                                                     Current result
  ------------------------------ ----------------------------------------
  AXI 4 × 8 integrated                Included in SoC integration testing
  interconnect                   

  Separate AXI 3 × 8                                54 / 54 checks passed
  interconnect testbench         

  AXI 64-to-32 bridge                               69 / 69 checks passed

  DMA-related bus and subsystem                Included in DMA regression
  tests                          
  -----------------------------------------------------------------------

------------------------------------------------------------------------

## 6. Instruction and Data Memory

The SoC contains separate instruction and data memory regions.

  Memory                  Base Address      Size
  -------------------- --------------- ---------
  Instruction Memory     `0x0000_0000`   256 KiB
  Data Memory            `0x0004_0000`   256 KiB

### Instruction Memory

-   Holds the processor's firmware image.
-   Provides the instruction-fetch region used during processor boot.
-   The firmware image is generated from the RISC-V application and
    loaded by the simulation environment.

### Data Memory

-   Stores input data patterns.
-   Stores compressed data.
-   Stores decompressed/reconstructed data.
-   Provides memory buffers used by DMA operations.
-   Holds test completion signatures and other firmware data.

### Firmware memory layout

The linker script places the executable image in the instruction-memory
region and the data sections in the data-memory region. The DMA firmware
uses separate source, compressed-output and reconstructed-output buffers
within Data Memory.

------------------------------------------------------------------------

## 7. UART Peripheral

The UART is an AXI4-Lite memory-mapped peripheral used for serial
communication and firmware-visible status output.

### 7.1 Main functions

-   Transmit data through the UART TX interface.
-   Receive data through the UART RX interface.
-   Configure line-control and baud-divisor registers.
-   Read line status and data-ready information.
-   Support processor-driven peripheral access.

### 7.2 Register map

The UART register offsets follow the implemented UART register
interface.

  Offset   Register       Function
  -------- -------------- -------------------------------------
  `0x00`   THR / RBR      Transmit write / receive read
  `0x04`   IER            Interrupt enable
  `0x08`   Baud Divisor   Divisor access when DLAB is enabled
  `0x0C`   LCR            Line control
  `0x14`   LSR            Line status

### 7.3 Verification coverage

The standalone UART testbench checks register access and UART
transmit/receive behavior.

The processor-driven UART firmware test additionally checks that the
VeeR-based system can execute firmware and produce the expected UART
output through the integrated SoC simulation.

The UART firmware simulation uses a testbench-side monitor for
deterministic simulation. This should not be interpreted as a physical
serial-port or FPGA demonstration.

------------------------------------------------------------------------

## 8. RLE Compression / Decompression Accelerator

The **Run-Length Encoding (RLE) accelerator is the main data-processing
IP** of the project.

RLE represents consecutive repetitions of a data value using a run
representation. The accelerator supports compression and decompression
operations through its hardware interface.

### 8.1 Compression example

``` text
Input:

A A A A A B B C

        |
        v

RLE representation:

(A,5) (B,2) (C,1)
```

### 8.2 Decompression example

``` text
Compressed input:

(A,5) (B,2) (C,1)

        |
        v

Reconstructed output:

A A A A A B B C
```

### 8.3 Functional requirements exercised

  Case                  Expected behavior
  --------------------- ------------------------------------------
  Repeated data         Encode runs correctly
  Single occurrence     Preserve run length of one
  Non-repetitive data   Preserve all input values
  Multiple runs         Encode/decode consecutive runs correctly
  Decompression         Reconstruct original sequence
  Round trip            Reconstructed data matches original

### 8.4 Integration

The RLE accelerator is memory-mapped in the SoC and is controlled by the
processor firmware. The DMA/RLE integration testbench checks the
hardware transfer and operation sequence.

### 8.5 Verification

  -----------------------------------------------------------------------
  Item                                                             Result
  ------------------------------ ----------------------------------------
  RLE standalone testbench                          65 / 65 checks passed

  SoC DMA/RLE integration                           37 / 37 checks passed
  testbench                      

  CPU-controlled end-to-end               4 compression + 4 decompression
  patterns                                                     operations
  -----------------------------------------------------------------------

------------------------------------------------------------------------

## 9. DMA Controller

The DMA controller performs programmed data movement without requiring
the CPU to copy every data item individually.

### 9.1 Main functions

-   Source address configuration.
-   Destination address configuration.
-   Transfer-length configuration.
-   Control and start operation.
-   Transfer status monitoring.
-   Completion/error status handling.
-   AXI master-side data transfers.

### 9.2 DMA register interface

The DMA register file exposes memory-mapped control and status
registers. The firmware programs the source, destination and transfer
length before starting an operation.

The exact register offsets and bit definitions are documented in
[`docs/address_map.md`](RISC_V_Based_Configurable_Data_Compression_Accelerator_SoC/docs/address_map.md)
when viewed from the repository root, or in
[`docs/address_map.md`](docs/address_map.md) from this directory.

### 9.3 DMA verification

  Verification block      Checks
  --------------------- --------
  DMA register file           63
  DMA master engine           96
  DMA sequencer               32
  DMA unit                    45
  SoC DMA integration         37

The DMA unit testbench uses ModelSim because the Icarus Verilog version
used in the project does not support the `break` construct in that
testbench.

### 9.4 End-to-end usage

The CPU configures the DMA controller through its registers. The DMA
engine performs the programmed transfers used by the
compression/decompression test sequence. The CPU then checks status and
validates the resulting data.

------------------------------------------------------------------------

## 10. CRC-32 Accelerator

The CRC-32 accelerator is used to check data integrity across the
compression/decompression flow.

The implementation uses the **IEEE 802.3 CRC-32 polynomial**:

``` text
Polynomial = 0x04C11DB7
```

### 10.1 Verification sequence

``` text
             Original Data
                   |
                   v
              CRC-32 IP
                   |
                   v
             CRC_original
                   |
                   |       Compression
                   |            |
                   |            v
                   |       Decompression
                   |            |
                   |            v
                   |    Reconstructed Data
                   |            |
                   |            v
                   |       CRC-32 IP
                   |            |
                   |            v
                   |    CRC_reconstructed
                   |            |
                   +------ Compare
                                |
                                v
                           PASS / FAIL
```

The firmware calculates the CRC of the original input and the
reconstructed output, then compares the results.

CRC-32 is an error-detection mechanism. It is not cryptographic
authentication and does not prove that every possible corruption pattern
will be detected.

### 10.2 Verification

  -----------------------------------------------------------------------
  Item                                                             Result
  ------------------------------ ----------------------------------------
  Standalone CRC-32 testbench                     147 / 147 checks passed

  End-to-end firmware CRC                           4 pattern comparisons
  comparisons                    

  Reconstructed-memory                Byte-by-byte comparison in firmware
  comparison                     
  -----------------------------------------------------------------------

### 10.3 End-to-end CRC reference values

  Pattern   Input pattern                            CRC-32
  --------- -------------------------------- --------------
  1         32 × `0xAA`                        `0x7C04E4D3`
  2         16 × `0x55`, then 16 × `0x33`      `0xBA3B6BC1`
  3         `0x00` through `0x1F`              `0x91267E8A`
  4         Mixed runs of 8 + 8 + 16 bytes     `0xE082F245`

------------------------------------------------------------------------

## 11. Timer and GPIO

### 11.1 Timer

The Timer is integrated as a memory-mapped peripheral.

  Property               Value
  ---------------------- -------------------
  Base address           `0x1000_1000`
  Address window         4 KiB
  Standalone testbench   `tb_timer_top.sv`
  Reported checks        62 / 62 passed

### 11.2 GPIO

The GPIO peripheral provides general-purpose input/output functionality
through its memory-mapped interface.

  Property               Value
  ---------------------- ------------------
  Base address           `0x1000_2000`
  Address window         4 KiB
  Standalone testbench   `tb_gpio_top.sv`
  Reported checks        62 / 62 passed

The GPIO testbench sampling interval was adjusted to account for the
synchronizer and output-register pipeline.

Both peripherals are included in the processor-driven peripheral
simulation.

------------------------------------------------------------------------

## 12. End-to-End Compression Data Flow

This section describes the **functional operation sequence**, not the
RTL hierarchy.

### 12.1 CPU-controlled sequence

``` text
                  +----------------------+
                  |      VeeR EL2        |
                  |   Bare-metal C       |
                  +----------+-----------+
                             |
                             | Configure registers
                             v
                  +----------------------+
                  |   DMA Controller     |
                  +----------+-----------+
                             |
                             | Programmed transfer
                             v
                  +----------------------+
                  |     Data Memory      |
                  |   Input / Buffers    |
                  +----------+-----------+
                             |
                             v
                  +----------------------+
                  |   RLE Accelerator    |
                  | Compress / Decompress|
                  +----------+-----------+
                             |
                             v
                  +----------------------+
                  |     Data Memory      |
                  | Compressed / Output  |
                  +----------+-----------+
                             |
                             v
                  +----------------------+
                  |     CRC-32 Engine    |
                  +----------+-----------+
                             |
                             v
                  +----------------------+
                  |    Firmware Check    |
                  | CRC + Byte Comparison|
                  +----------+-----------+
                             |
                             v
                  +----------------------+
                  |     PASS / FAIL      |
                  +----------------------+
```

### 12.2 Test patterns

The end-to-end firmware uses four input patterns:

  Pattern   Data
  --------- ----------------------------------------------------
  1         32 repetitions of `0xAA`
  2         16 bytes of `0x55`, followed by 16 bytes of `0x33`
  3         Incrementing bytes from `0x00` to `0x1F`
  4         Mixed runs of 8 + 8 + 16 bytes

### 12.3 Operation count

For each pattern:

1.  The CPU prepares/configures the operation.
2.  DMA performs the programmed data movement.
3.  RLE performs compression.
4.  The compressed result is used for the decompression operation.
5.  RLE reconstructs the original data.
6.  CRC-32 checks the original and reconstructed data.
7.  Firmware compares the CRC values and the data bytes.

Across four patterns, the firmware performs:

-   4 compression operations.
-   4 decompression operations.
-   8 DMA operations in total.
-   4 original-versus-reconstructed CRC comparisons.
-   Byte-by-byte memory comparisons.

The DMA and CRC blocks are controlled by firmware. The current
implementation should not be described as a fully autonomous hardware
pipeline in which UART directly triggers DMA, RLE and CRC without CPU
involvement.

------------------------------------------------------------------------

## 13. System Address Map

The following table summarizes the address regions used by the current
integrated SoC simulation baseline.

  Port / Target   Peripheral / Memory      Base Address    Window
  --------------- --------------------- --------------- ---------
  M00             Instruction Memory      `0x0000_0000`   256 KiB
  M01             Data Memory             `0x0004_0000`   256 KiB
  M02             UART                    `0x1000_0000`     4 KiB
  M03             Timer                   `0x1000_1000`     4 KiB
  M04             GPIO                    `0x1000_2000`     4 KiB
  M05             RLE                     `0x1001_0000`     4 KiB
  M06             DMA                     `0x1001_1000`     4 KiB
  M07             CRC-32                  `0x1001_2000`     4 KiB

### Important notes

-   The address map above reflects the current integrated simulation
    configuration.
-   The 3 × 8 interconnect testbench is a separate verification
    configuration; it should not be used to infer the master count of
    the integrated 4 × 8 SoC.
-   The detailed register offsets, bit fields and firmware memory layout
    are maintained in [`docs/address_map.md`](docs/address_map.md).

------------------------------------------------------------------------

## 14. Firmware and CPU-Controlled Operation

The SoC uses bare-metal C firmware compiled for the VeeR EL2 RISC-V
target.

### 14.1 Main firmware files

  File                            Purpose
  ------------------------------- -----------------------------------------
  `firmware/start.S`              Processor startup and initialization
  `firmware/linker.ld`            Firmware memory layout
  `firmware/main_dma.c`           CPU-controlled DMA, RLE and CRC-32 test
  `firmware/dma_test_word.hex`    DMA firmware memory image
  `firmware/uart_test_word.hex`   UART firmware memory image

### 14.2 Startup and memory configuration

The startup code initializes the processor execution environment before
transferring control to the C firmware. The linker script places the
firmware sections in the memory regions used by the SoC.

The simulation setup includes the VeeR EL2 configuration snapshot
headers required by the committed simulation configuration.

### 14.3 DMA firmware completion

The DMA firmware writes the completion signature:

``` text
0xCAFED00D
```

This signature is written only after the expected DMA operations, CRC
comparisons and reconstructed-data checks complete successfully.

A testbench watchdog and trap monitoring are also used by the end-to-end
firmware testbench.

------------------------------------------------------------------------

## 15. Repository Structure

The unified SoC project is organized into a clean, professional, maintainable structure:

``` text
RISC_V_Based_Configurable_Data_Compression_Accelerator_SoC/
│
├── README.md
├── .gitignore
│
├── docs/
│   ├── architecture/        # Architecture specification and PDF block diagrams
│   ├── specifications/      # Build, simulation, and tool guidelines
│   ├── address_map/         # Complete memory & peripheral register maps
│   ├── integration/         # Interconnect & core integration notes
│   └── verification/        # Test plans and verification summaries
│
├── rtl/
│   ├── soc/                 # SoC top and core top wrappers
│   ├── interconnect/        # AXI4 crossbar, 64-to-32 bridge, arbiters
│   ├── memory/              # Memory subsystem & models
│   ├── peripherals/         # UART, GPIO, Timer, CRC-32 RTLs
│   └── accelerators/        # Hardware RLE engine & DMA controller
│
├── firmware/
│   ├── source/              # Bare-metal C application code (main.c, main_dma.c)
│   ├── startup/             # RISC-V CRT0 boot code (start.S)
│   ├── linker/              # GNU ld script for IMEM & DMEM (linker.ld)
│   ├── include/             # C headers and register definitions
│   └── images/              # Precompiled .hex and .vh memory payloads
│
├── verification/
│   ├── uvm/                 # Unified SoC UVM Verification Environment
│   │   ├── tb_soc_top.sv    # Top-level SystemVerilog testbench
│   │   ├── interfaces/      # soc_interfaces.sv, axi_monitor_if.sv
│   │   ├── vip/             # Reusable VIPs (axi, uart, gpio, reset, irq)
│   │   ├── env/             # soc_env, scoreboard, coverage, soc_uvm_pkg
│   │   ├── config/          # Environment configurations and signal CSVs
│   │   ├── sequences/       # Stimulus sequences (soc_smoke_seq.sv)
│   │   ├── tests/           # UVM tests (soc_smoke_test.sv)
│   │   └── filelists/       # Compilation filelists (soc_uvm.f)
│   │
│   ├── assertions/          # Protocol assertion checkers (AXI4, DMA, RLE)
│   ├── standalone/          # Independent IP & subsystem testbenches
│   │   ├── crc32/           # Standalone CRC-32 testbench
│   │   ├── gpio/            # Standalone GPIO testbench
│   │   ├── rle/             # Standalone RLE testbench
│   │   ├── timer/           # Standalone Timer testbench
│   │   ├── uart/            # Standalone UART testbench
│   │   ├── interconnect/    # AXI bridge unit testbench
│   │   ├── dma/             # DMA engine, sequencer, and unit tests
│   │   ├── soc/             # Boot, memory access, and legacy firmware tests
│   │   └── filelists/       # Standalone simulation filelists
│   └── legacy/              # Archived test harnesses (interconnect_3x8)
│
├── simulation/
│   ├── scripts/             # Simulation runners (run_soc_uvm.sh, run_sim.ps1)
│   ├── filelists/           # Top-level simulation filelists
│   ├── logs/                # Compile and simulation execution logs
│   └── waveforms/           # VCD dumps, GTKWave setups, and timing diagrams
│
├── scripts/
│   ├── generators/          # Automation scripts (uvm_full_tb_generator.py, etc.)
│   └── utilities/           # Waveform parser and evidence generators
│
├── third_party/
│   └── RISC-V-VeeR-EL2/     # VeeR EL2 core repository (Apache 2.0)
│
└── archive/                 # Historical Phase 1 data and external IP reference
```
## 16. Tools and Simulation Environment

The consolidated simulation baseline was reported using the following
Windows-native environment.

  Tool                                  Version / Use
  ------------------------------------- --------------------------------------------------
  ModelSim Intel FPGA Starter Edition   2020.1 --- RTL simulation
  Icarus Verilog                        12.0 --- RTL simulation
  RISC-V GCC                            13.3.0 --- bare-metal firmware compilation
  GNU objcopy                           2.42 --- firmware image generation
  Perl                                  5.38.2 --- VeeR configuration generation support
  Python                                3.14.3 --- scripts and utilities
  Git for Windows                       Source control and repository management
  PowerShell                            Simulation automation

The project uses ModelSim for testbenches that require simulator
features not supported by the installed Icarus Verilog version. The DMA
unit testbench is one such case because its source uses the `break`
construct.

Tool paths are machine-specific. A new environment must have the
required tools installed and accessible to the PowerShell runner.

------------------------------------------------------------------------

## 17. Build and Run

The project includes a PowerShell simulation runner:

``` text
tb/run_sim.ps1
```

Open PowerShell in the SoC testbench directory:

``` powershell
cd "RISC_V_Based_Configurable_Data_Compression_Accelerator_SoC/tb"
```

### Available simulation targets

``` powershell
# VeeR EL2 processor boot test
.\run_sim.ps1 -Target boot

# Processor access to memory-mapped peripherals
.\run_sim.ps1 -Target periph

# Processor-driven UART firmware test
.\run_sim.ps1 -Target uart

# CPU-controlled DMA + RLE + CRC-32 firmware test
.\run_sim.ps1 -Target dma
```

The runner invokes the relevant compilation and simulation flow for each
target.

For tool prerequisites, firmware compilation details, filelists and
troubleshooting, see
[`docs/build_and_simulation.md`](docs/build_and_simulation.md).

------------------------------------------------------------------------

## 18. Verification Strategy and Results

Verification is performed at multiple levels:

1.  **IP-level verification** --- individual peripheral and accelerator
    testbenches.
2.  **Subsystem verification** --- bus bridge, DMA and memory
    integration.
3.  **Processor-level verification** --- VeeR boot and peripheral
    access.
4.  **Firmware-driven SoC verification** --- CPU-controlled DMA/RLE/CRC
    operation.

### 18.1 Consolidated regression

The final consolidated regression report records **16 testbenches and
759 passing checks**.

    No. Verification block        Testbench                              Checks
  ----- ------------------------- ----------------------------- ---------------
      1 AXI 64-to-32 bridge       `tb_axi64_to_32_bridge.sv`                 69
      2 DMA register file         `tb_dma_reg_file.sv`                       63
      3 DMA master engine         `tb_dma_master_engine.sv`                  96
      4 DMA sequencer             `tb_dma_sequencer.sv`                      32
      5 DMA unit                  `tb_dma_unit.sv`                           45
      6 SoC DMA integration       `tb_soc_dma_integration.sv`                37
      7 SoC memory access         `tb_soc_mem_access.sv`                     92
      8 CRC-32 engine             `tb_crc32.sv`                             147
      9 RLE accelerator           `tb_rle_top.sv`                            65
     10 UART peripheral           `tb_uart_top.sv`                           75
     11 GPIO peripheral           `tb_gpio_top.sv`                           62
     12 Timer peripheral          `tb_timer_top.sv`                          62
     13 SoC core boot             `tb_soc_core_boot.sv`                       1
     14 SoC peripheral firmware   `tb_soc_periph_test.sv`                     5
     15 SoC UART firmware         `tb_soc_uart_firmware.sv`                   1
     16 SoC DMA firmware          `tb_soc_dma_firmware.sv`                    7
        **Total**                 **16 testbenches**              **759 / 759**

A separate AXI 3 × 8 interconnect testbench passed **54 / 54** checks.
This is additional to the 16-testbench, 759-check regression total.

### 18.2 Processor and firmware simulation

The reported processor-driven simulations include:

  Test                              Reported result
  --------------------------------- -----------------
  VeeR EL2 boot                     PASS
  Memory-mapped peripheral access   PASS
  UART firmware transmission        PASS
  DMA/RLE/CRC firmware test         PASS

The DMA firmware simulation report records:

-   4 compression operations.
-   4 decompression operations.
-   8 DMA operations in total.
-   4 CRC-32 comparisons against expected values.
-   Byte-by-byte source/reconstructed memory comparisons.
-   Testbench destination-memory checks.
-   Completion signature `0xCAFED00D`.
-   25,635 reported simulation cycles.
-   5,612 reported retired instructions.
-   No reported traps or errors.

These are simulation results reported by the project's regression and
firmware test flow. They are not measured hardware performance results.

### 18.3 Detailed verification documentation

See [`docs/verification_summary.md`](docs/verification_summary.md) for
the testbench matrix, individual verification scope, patterns and
regression details.

------------------------------------------------------------------------

## 19. Implementation Notes and Limitations

The following points describe the actual scope and should be considered
when interpreting the results.

### 19.1 Simulation, not physical hardware

The project baseline is verified through RTL simulation. FPGA synthesis,
place-and-route, timing closure, resource utilization and board-level
testing are not claimed.

### 19.2 Firmware control model

The end-to-end flow is processor-controlled. The firmware configures the
DMA and accelerator registers and checks their status. The current test
does not demonstrate a fully autonomous UART-triggered DMA-to-RLE-to-CRC
hardware pipeline.

### 19.3 Polling and interrupts

The firmware-driven tests use status polling for deterministic
simulation. A complete interrupt-driven firmware demonstration is not
claimed.

### 19.4 UART simulation behavior

The UART firmware testbench uses simulation-side monitoring to check
expected output. This is not equivalent to validating a physical UART
connection at a specified baud rate on an FPGA board.

### 19.5 CRC-32

CRC-32 detects many common data errors but is not a cryptographic
integrity or authentication mechanism.

### 19.6 RLE compression ratio

The achieved compression depends on the input pattern. The project
verifies functional correctness; it does not claim a universal
compression ratio or a measured throughput advantage over software.

------------------------------------------------------------------------

## 20. Current Project Status

The current baseline has moved beyond the initial architecture and
standalone-IP stage. The processor, memory-mapped peripherals, DMA, RLE
and CRC-32 have been exercised through simulation and firmware-driven
integration tests.

  ---------------------------------------------------------------------------------
  Subsystem / Work                      Current status          Evidence / Notes
  ---------------------------- -------------------------------- -------------------
  VeeR EL2 core integration        Completed for simulation     CPU boot and
                                                                firmware tests
                                                                reported passing

  AXI 4 × 8 SoC interconnect              Integrated            Used in the
                                                                integrated SoC
                                                                regression

  Separate AXI 3 × 8                       Verified             54 / 54 checks
  interconnect test                                             passed

  AXI 64-to-32 bridge                      Verified             69 / 69 checks
                                                                passed

  Instruction Memory                 Integrated / tested        CPU boot flow

  Data Memory                        Integrated / tested        Memory access and
                                                                DMA firmware checks

  UART                                     Verified             75 / 75 standalone
                                                                checks; firmware
                                                                test

  GPIO                                     Verified             62 / 62 standalone
                                                                checks

  Timer                                    Verified             62 / 62 standalone
                                                                checks

  RLE accelerator                          Verified             65 / 65 standalone
                                                                checks

  DMA controller                           Verified             Register, engine,
                                                                sequencer, unit and
                                                                integration tests

  CRC-32 accelerator                       Verified             147 / 147
                                                                standalone checks

  CPU-controlled DMA/RLE/CRC        Verified in simulation      8 DMA operations
  flow                                                          and 4 data patterns

  Consolidated regression              Reported passing         16 testbenches, 759
                                                                / 759 checks

  Windows simulation runner               Available             `tb/run_sim.ps1`

  Architecture/address/build               Prepared             `docs/`
  documentation                                                 

  Git release commits                  Pending approval         Separate commits
                                                                planned

  Git push                        Pending explicit approval     No push without
                                                                approval

  FPGA synthesis / hardware          Not in current scope       Not claimed
  testing                                                       
  ---------------------------------------------------------------------------------

### Current milestone

**Processor-integrated RISC-V data-compression SoC with a reported
passing simulation regression and CPU-controlled DMA, RLE and CRC-32
end-to-end test.**

The remaining repository work is release hygiene: final source review,
clean documentation, separate Git commits and a separately approved
push.

------------------------------------------------------------------------

## 21. References

1.  CHIPS Alliance, **VeeR EL2 RISC-V Core** --- [GitHub
    repository](https://github.com/chipsalliance/Cores-VeeR-EL2).
2.  RISC-V International, **RISC-V Specifications** --- [Official
    specifications](https://riscv.org/technical/specifications/).
3.  Arm, **AMBA AXI Protocol Specification** --- [AMBA
    documentation](https://developer.arm.com/Architectures/AMBA).
4.  IEEE, **IEEE 802.3 Ethernet Standard** --- CRC-32 polynomial and
    Ethernet frame error-detection context.
5.  Project RTL, testbenches, firmware and architecture documentation
    maintained in this repository.

------------------------------------------------------------------------

## 22. Author

**Hrushikesh Singarapu**\
B.E. --- Electronics and Communication Engineering\
Vasavi College of Engineering

**Technical areas:** Digital VLSI Design, Verilog/SystemVerilog, RISC-V
SoC Integration, AXI Interfaces, RTL Verification and Hardware
Accelerators.

------------------------------------------------------------------------


**RISC-V Based Configurable Data Compression Accelerator SoC**

*Processor-controlled compression • Hardware data movement • CRC-based
data-integrity checking*
:::
