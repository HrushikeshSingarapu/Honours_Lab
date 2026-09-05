# README — AXI4 Interconnect Testbench

Testbench for `axi_interconnect_wrap_2x7.v` only.  
All other SoC blocks (RLE accelerator, DMA controller, CRC engine, UART, Timer,  
GPIO, VeeR EL2 core) are **out of scope** and are represented by lightweight stubs.

---

## Files

| File | Role |
|---|---|
| `tb_axi_interconnect_wrap_2x7.sv` | Top-level self-checking testbench |
| `axi_slave_stub.sv` | Test-only AXI4 slave stub (memory-backed, all 7 ports) |
| `Makefile` | VCS build + run script |
| `README_tb.md` | This file |

### What is real RTL under test

```
rtl/axi_interconnect_wrap_2x7.v   ← DUT (wrapper)
rtl/axi_interconnect.v            ← instantiated by the wrapper
rtl/arbiter.v                     ← used by axi_interconnect.v
rtl/priority_encoder.v            ← used by axi_interconnect.v
```

### What is test-only stub model

```
tb/axi_slave_stub.sv  — one instance per master port (m00–m06).
                        Does NOT model real peripheral behaviour.
                        Exists only to complete AXI transactions cleanly.
```

---

## How to run

```bash
cd tb/
make          # compile + simulate
make compile  # compile only
make sim      # simulate only (after compile)
make clean    # remove all artefacts
```

Requires Synopsys VCS in `PATH`.

---

## Test groups

| Group | What is checked |
|---|---|
| 1 | Address decode at each base address (write + read, all 7 mapped ports) |
| 2 | Region boundary addresses (upper boundary of window, first address of next region) |
| 3 | Unmapped / gap addresses → DECERR |
| 4 | Write channel handshake timing, wstrb byte-enable, BID correlation |
| 5 | Read channel handshake, RID correlation, RLAST for single-beat, IFU path (s01) |
| 6 | Back-to-back transactions to different regions, no cross-talk |
| 7 | INCR burst (awlen=3, 4 beats) write then per-beat readback |
| 8 | Reset mid-transaction, post-reset clean state, post-reset transaction |

Each test case prints `PASS` or `FAIL` with the address/values involved on failure.  
A summary line at the end shows total/pass/fail counts.

---

## Discrepancies between the spec and the RTL

### DISC-1 — Module name in task prompt vs. actual file

| | Value |
|---|---|
| Task prompt references | `axi_interconnect_wrap_ax7.v` |
| Actual file in repo | `axi_interconnect_wrap_2x7.v` |

**Action taken:** This testbench targets the file that **exists** in the repo:  
`axi_interconnect_wrap_2x7.v`.  Confirm whether `_ax7` is a typo or a different  
file that needs to be created separately.

---

### DISC-2 — Data width: spec says 64-bit, wrapper default is 32-bit

| | Value |
|---|---|
| Spec §3.4 (LSU AXI4 interface) | `lsu_axi_wdata[63:0]` — 64-bit |
| Spec §3.5 (IFU AXI4 interface) | IFU rdata 64 bits wide |
| `axi_interconnect_wrap_2x7.v` default | `parameter DATA_WIDTH = 32` |
| Existing `tb_axi_interconnect.v` | `DATA_WIDTH = 32` |
| Existing `simv` build artefacts | Compiled with 32-bit |

**Assumption [A-1]:** This testbench uses `TB_DATA_WIDTH = 32` to match the  
existing wrapper default and existing simulation artefacts.  
**Action required:** When the SoC wrapper is updated to use 64-bit data, change  
`TB_DATA_WIDTH` to 64 and update `awsize`/`arsize` in the BFM tasks from  
`3'b010` (4 bytes) to `3'b011` (8 bytes).

---

### DISC-3 — 8 address regions in spec vs. 7 master ports in the DUT

Spec Table 1 (§2.2) lists **8 regions**:

| Base address | Region |
|---|---|
| 0x0000\_0000 | Instruction Memory |
| 0x0004\_0000 | Data Memory |
| 0x1000\_0000 | UART |
| 0x1000\_1000 | Timer |
| 0x1000\_2000 | GPIO |
| 0x1001\_0000 | RLE Accelerator |
| 0x1001\_1000 | DMA Controller |
| 0x1001\_2000 | CRC/Checksum Engine |

The DUT has **7 master ports** (m00–m06).  One region cannot be mapped.

**Assumption [A-2]:** CRC/Checksum (0x1001\_2000) is **not mapped** in this  
interconnect instance.  Accesses to 0x1001\_2000 return DECERR.  
The 7-port assignment used:

| Port | Region | Base | Window |
|---|---|---|---|
| m00 | Instruction Memory | 0x0000\_0000 | 256 KiB (addr\_width=18) |
| m01 | Data Memory | 0x0004\_0000 | 256 KiB (addr\_width=18) |
| m02 | UART | 0x1000\_0000 | 4 KiB (addr\_width=12) |
| m03 | Timer | 0x1000\_1000 | 4 KiB (addr\_width=12) |
| m04 | GPIO | 0x1000\_2000 | 4 KiB (addr\_width=12) |
| m05 | RLE Accelerator | 0x1001\_0000 | 4 KiB (addr\_width=12) |
| m06 | DMA Controller | 0x1001\_1000 | 4 KiB (addr\_width=12) |

**OPEN-ITEM-1:** Confirm whether CRC should be added via a 3rd master port  
(requiring an `axi_interconnect_wrap_2x8` or similar) or whether CRC traffic  
is routed to DMA's port and demultiplexed internally.

---

### DISC-4 — LSU\_BUS\_TAG width not stated numerically

| | Value |
|---|---|
| Spec §3.4 | ID width listed as "LSU\_BUS\_TAG" (symbolic, no number given) |
| VeeR EL2 PRM (default config) | 4 bits |
| `axi_interconnect_wrap_2x7.v` default | `parameter ID_WIDTH = 8` |

**Assumption [A-3]:** `ID_WIDTH = 8` (wrapper parameter default).  
If the actual VeeR EL2 configuration uses a different tag width, update  
`TB_ID_WIDTH` in the testbench to match.

---

### DISC-5 — Undefined-address response not stated in the spec

Spec §2.2 and §3.21 do not specify what the interconnect returns when an  
address falls in a gap not covered by Table 1.

**RTL behaviour (confirmed by reading `axi_interconnect.v` lines 636–643):**

```verilog
// no match; return decode error
axi_bresp_next = 2'b11;   // DECERR for writes
s_axi_rresp_int = 2'b11;  // DECERR for reads
```

Test Group 3 verifies this **actual RTL behaviour**, not a spec requirement.  
If the project spec is later updated to specify a different response  
(e.g. SLVERR from a default slave), Test 3 will need to be updated.

---

## Open items requiring answers before the testbench is treated as final

| ID | Question |
|---|---|
| OPEN-ITEM-1 | Is CRC (0x1001\_2000) intended to be connected to an 8th master port, or is it intentionally absent from this interconnect instance? |
| OPEN-ITEM-2 | Is `DATA_WIDTH` intended to be 64 for the final SoC integration, or does the interconnect wrapper intentionally downscale from the 64-bit LSU to 32-bit peripherals? |
| OPEN-ITEM-3 | What is the numeric value of `LSU_BUS_TAG` in the VeeR EL2 configuration used by this project? (Needed to set `ID_WIDTH` correctly.) |
| OPEN-ITEM-4 | Does the spec require a specific arbitration policy (fixed-priority, round-robin) between s00 (LSU) and s01 (IFU)? The Forencich `axi_interconnect.v` uses round-robin by default. |
| OPEN-ITEM-5 | Are any peripheral regions (UART, Timer, GPIO, RLE, DMA) expected to support burst transactions (awlen/arlen > 0), or are they single-beat only? |

---

## Known limitations of the current testbench

- BFM drives only `s00` (LSU) and `s01` (IFU) as AXI4 single-beat or simple INCR burst.  
  Out-of-order and interleaved IDs are not exercised.
- The slave stubs model a flat 256-word memory with word-indexed addressing;  
  sub-word addressing with mixed wstrb patterns at unaligned addresses is only  
  partially tested.
- No SVA (SystemVerilog Assertions) protocol checkers are included; adding an  
  AXI4 protocol checker (e.g. Arm AMBA VIP) would strengthen coverage.
- Arbitration fairness (simultaneous s00/s01 contention) is not stress-tested  
  because the arbitration policy is not specified in the document (OPEN-ITEM-4).
