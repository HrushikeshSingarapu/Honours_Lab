# Legacy 3x8 AXI Interconnect Testbench

This directory preserves the standalone unit testbench for the early **3-master × 8-slave AXI4 crossbar** (`axi_interconnect_wrap_3x8.v`) developed prior to DMA master integration.

## Contents
- `axi_interconnect_wrap_3x8.v`: 3-master x 8-slave AXI4 crossbar wrapper.
- `tb_axi_interconnect_wrap_3x8.sv`: Top-level self-checking testbench (54 checks across address decode, boundaries, handshakes, bursts, and resets).
- `axi_slave_stub.sv`: Lightweight memory-backed AXI4 slave stub model.
- `run.f`: Compilation filelist.
- `Makefile`: Synopsys VCS / Verdi build script.

## Simulation Instructions

### ModelSim / QuestaSim:
```bash
vlib work
vlog -sv -f run.f
vsim -c -do "run -all; quit -f" tb_axi_interconnect_wrap_3x8
```

### Synopsys VCS:
```bash
make
```

> [!NOTE]
> The active SoC top (`soc_top.v`) utilizes the 4-master × 8-slave crossbar (`axi_interconnect_wrap_4x8.v`) to integrate the CPU IFU, LSU, SB, and DMA Master.
