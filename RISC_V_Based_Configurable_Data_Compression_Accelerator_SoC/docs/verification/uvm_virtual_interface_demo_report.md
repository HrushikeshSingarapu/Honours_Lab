# UVM Virtual Interface Connectivity Demonstration Report
## Four-Agent Architecture & End-to-End Firmware-Driven Verification on VeeR EL2 RISC-V SoC

---

## 1. Executive Summary

This report documents the design, implementation, and successful simulation verification of the **Four-Agent UVM Virtual Interface Connectivity Architecture** on the VeeR EL2 RISC-V System-on-Chip (`soc_core_top`). 

In strict adherence to project requirements, the active UVM verification environment contains **exactly four physical agents**:
1. **UART VIP Agent** (`uart_agnt`): Configurable active driver (`uart_rx`) and passive monitor (`uart_tx`).
2. **GPIO VIP Agent** (`gpio_agnt`): Multi-pin bidirectional monitoring and stimulus (`gpio_i`, `gpio_o`, `gpio_oe`).
3. **Reset VIP Agent** (`reset_agnt`): Synchronous power-on/cold reset driver and monitor (`rst_n`, `rst`).
4. **IRQ VIP Agent** (`irq_agnt`): Passive monitor observing SoC interrupt lines (`gpio_irq`, `timer_irq`, `rle_irq`, `dma_irq`).

All AXI VIP components were completely excised from the active UVM environment, while preserving 100% of the functional on-chip AXI crossbar RTL and peripheral interconnects.

Two end-to-end SoC verification tests were executed on Synopsys VCS U-2023.03 with zero errors:
1. `soc_smoke_test`: Boots VeeR EL2 CPU from cold reset and validates `"HI"` UART transmission (2/2 characters, 0 errors, PASS).
2. `uart_echo_test`: Injects `"ABC123"` via the UVM UART driver into DUT `uart_rx`, processed by bare-metal C firmware polling `UART_LSR` and reading `UART_RBR`, echoed back via `UART_THR` onto DUT `uart_tx`, captured by UVM UART monitor, and checked by the scoreboard (6/6 characters, 0 errors, PASS).

---

## 2. Demonstration Architecture

The demonstration architecture cleanly separates the physical hardware domain (`tb_soc_top`) from the abstract UVM object hierarchy (`soc_env`):

```
+----------------------------------------------------------------------------------------------------+
|                                      tb_soc_top (SystemVerilog)                                     |
|                                                                                                    |
|  [reset_if]           [uart_if]               [gpio_if]               [irq_if]                     |
|      |                    |                       |                       |                        |
|      | (rst_n)            | (uart_rx, uart_tx)    | (gpio_i, o, oe)       | (gpio, timer, rle, dma)|
|      v                    v                       v                       v                        |
|  +-----------------------------------------------------------------------------------------------+ |
|  |                                  soc_core_top (DUT)                                           | |
|  |  +----------------+      +------------------+      +----------------+      +---------------+  | |
|  |  | VeeR EL2 Core  | <==> | AXI Interconnect | <==> | UART 16550 IP  | <==> | GPIO / Timers |  | |
|  |  | (RV32IMC)      | AXI  | (4 Masters x     | AXI  | (0x1000_0000)  | AXI  | Interconnect  |  | |
|  |  +----------------+      |  8 Slaves)       |      +----------------+      +---------------+  | |
|  +-----------------------------------------------------------------------------------------------+ |
|      |                    |                       |                       |                        |
|      +----------+         +----------+            +----------+            +----------+             |
|                 |                    |                       |                       |             |
|                 v                    v                       v                       v             |
|          uvm_config_db         uvm_config_db           uvm_config_db           uvm_config_db       |
|          ::set(reset_vif)      ::set(uart_vif)         ::set(gpio_vif)         ::set(irq_vif)      |
+----------------------------------------------------------------------------------------------------+
                                               |
                                     uvm_config_db::get()
                                               |
+----------------------------------------------v-----------------------------------------------------+
|                                        soc_env (UVM)                                               |
|                                                                                                    |
|  +----------------------+  +----------------------+  +--------------------+  +-------------------+ |
|  |      reset_agent     |  |      uart_agent      |  |     gpio_agent     |  |     irq_agent     | |
|  |  [drv]        [mon]  |  |  [drv]        [mon]  |  | [drv]        [mon] |  |       [mon]       | |
|  +---------+------------+  +----+------------+----+  +----+-----------+---+  +---------+---------+ |
|            |                    |            |            |           |                |           |
|            | (Analysis Port)    |            |            |           | (Analysis Port)| (AP)      |
|            +--------------------+------------+------------+-----------+----------------+           |
|                                 |                                                                  |
|                                 v                                                                  |
|                  +-------------------------------+                                                 |
|                  |     soc_scoreboard (UVM)      | <--- Matches expected "HI" / "ABC123"          |
|                  +-------------------------------+                                                 |
+----------------------------------------------------------------------------------------------------+
```

---

## 3. Complete Virtual Interface Registration Flow

All virtual interfaces are instantiated as physical SystemVerilog interfaces in `verification/uvm/tb_soc_top.sv` and registered into the UVM configuration database prior to invoking `run_test()`:

```systemverilog
  // verification/uvm/tb_soc_top.sv: Lines 176-189
  initial begin
    // 1. Reset VIP Interface Registration
    uvm_config_db#(virtual reset_if)::set(null, "*", "vif", reset_vif);
    `uvm_info("SOC_CONNECT", "[SOC_CONNECT] Top: Registered virtual interface 'vif' into uvm_config_db for reset_vif", UVM_LOW)

    // 2. UART VIP Interface Registration
    uvm_config_db#(virtual uart_if)::set(null, "*", "vif", uart_vif);
    `uvm_info("SOC_CONNECT", "[SOC_CONNECT] Top: Registered virtual interface 'vif' into uvm_config_db for uart_vif", UVM_LOW)

    // 3. GPIO VIP Interface Registration
    uvm_config_db#(virtual gpio_if)::set(null, "*", "vif", gpio_vif);
    `uvm_info("SOC_CONNECT", "[SOC_CONNECT] Top: Registered virtual interface 'vif' into uvm_config_db for gpio_vif", UVM_LOW)

    // 4. IRQ VIP Interface Registration
    uvm_config_db#(virtual irq_if)::set(null, "*", "vif", irq_vif);
    `uvm_info("SOC_CONNECT", "[SOC_CONNECT] Top: Registered virtual interface 'vif' into uvm_config_db for irq_vif", UVM_LOW)

    run_test();
  end
```

---

## 4. Complete Virtual Interface Retrieval Flow

Following UVM best practices, each agent retrieves its respective virtual interface at the **agent level** in `build_phase()`:

| Agent Component | Interface Type | Config DB Get Statement | Action on Failure |
|---|---|---|---|
| `uart_agent` | `virtual uart_if` | `uvm_config_db#(virtual uart_if)::get(this, "", "vif", vif)` | `UVM_FATAL("NOVIF", ...)` |
| `gpio_agent` | `virtual gpio_if` | `uvm_config_db#(virtual gpio_if)::get(this, "", "vif", vif)` | `UVM_FATAL("NOVIF", ...)` |
| `reset_agent` | `virtual reset_if` | `uvm_config_db#(virtual reset_if)::get(this, "", "vif", vif)` | `UVM_FATAL("NOVIF", ...)` |
| `irq_agent` | `virtual irq_if` | `uvm_config_db#(virtual irq_if)::get(this, "", "vif", vif)` | `UVM_FATAL("NOVIF", ...)` |

---

## 5. Agent-Level VIF Distribution Architecture

To eliminate redundant database lookups across child drivers and monitors, the agent distributes the handle directly:

```systemverilog
// verification/uvm/vip/uart/uart_agent.sv
virtual function void build_phase(uvm_phase phase);
  super.build_phase(phase);
  
  // 1. Agent-level retrieval
  if (!uvm_config_db#(virtual uart_if)::get(this, "", "vif", vif)) begin
    `uvm_fatal("NOVIF", $sformatf("[SOC_CONNECT] %s: Failed to get virtual interface 'vif' from uvm_config_db", get_full_name()))
  end else begin
    `uvm_info("SOC_CONNECT", $sformatf("[SOC_CONNECT] %s: Successfully retrieved virtual interface 'vif' from uvm_config_db", get_full_name()), UVM_LOW)
  end

  // 2. Direct distribution to monitor
  mon = uart_monitor::type_id::create("mon", this);
  mon.cfg = cfg;
  mon.vif = vif;

  // 3. Direct distribution to driver (if active)
  if (get_is_active() == UVM_ACTIVE) begin
    drv  = uart_driver::type_id::create("drv", this);
    drv.cfg = cfg;
    drv.vif = vif;
    seqr = uart_sequencer::type_id::create("seqr", this);
  end
endfunction : build_phase
```

Child drivers and monitors verify that `vif != null` upon entry, logging confirmation with zero redundant queries.

---

## 6. Driver Interaction with DUT Inputs

1. **Reset Driver (`reset_driver.sv`)**:
   - Drives DUT `rst_n` synchronous to 100 MHz `clk`.
   - Generates deterministic 30-cycle cold reset pulse followed by deassertion.
   - Preserves reset hold time to allow processor pipeline and AXI crossbar state machines to stabilize.

2. **UART Driver (`uart_driver.sv`)**:
   - Drives serial frames onto `uart_vif.uart_rx`, connected to DUT pin `uart_rx`.
   - Uses exact bit timing: $\text{Bit Cycles} = \frac{100\text{ MHz}}{115200\text{ Baud}} = 868\text{ clock cycles}$.
   - Format: 1 Start Bit (LOW), 8 Data Bits (LSB first), 1 Stop Bit (HIGH).
   - Enforces idle level (HIGH) between characters.

---

## 7. Monitor Observation of DUT Outputs

1. **UART Monitor (`uart_monitor.sv`)**:
   - Passive listener on `uart_vif.uart_tx`, connected to DUT pin `uart_tx`.
   - Detects falling edge of Start Bit (`negedge vif.uart_tx`).
   - Mid-bit samples each data bit (every 868 cycles) to maximize noise margin.
   - Validates Stop Bit (`vif.uart_tx === 1'b1`) and flags any framing errors.
   - Packages reconstructed byte into `uart_seq_item` and broadcasts via `uvm_analysis_port`.

2. **GPIO Monitor (`gpio_monitor.sv`)**:
   - Observes 32-bit `gpio_o` and `gpio_oe` output vectors on every clock edge.
   - Publishes `gpio_seq_item` whenever pin state or direction changes.

3. **Reset Monitor (`reset_monitor.sv`)**:
   - Measures exact duration of reset assertion and timestamp of release.
   - Publishes `reset_seq_item` to scoreboard.

4. **IRQ Monitor (`irq_monitor.sv`)**:
   - Observes asynchronous interrupt lines: `gpio_irq`, `timer_irq`, `rle_irq`, `dma_irq`.
   - Publishes `irq_seq_item` on transitions.

---

## 8. Monitor-to-Scoreboard Data Paths

The `soc_scoreboard` (`verification/uvm/env/soc_scoreboard.sv`) integrates four analysis implementations using `uvm_analysis_imp_decl`:
- `uart_agnt.mon.ap.connect(scb.uart_export)`
- `gpio_agnt.mon.ap.connect(scb.gpio_export)`
- `reset_agnt.mon.ap.connect(scb.reset_export)`
- `irq_agnt.mon.ap.connect(scb.irq_export)`

Scoreboard verification logic performs running string accumulation and character-by-character comparison against `expected_str` (`"HI"` or `"ABC123"`).

---

## 9. Complete Dataflow: UART Interactive Echo

The complete transaction pathway for `uart_echo_test` exercises the full SoC hardware and software stack:

```
  [UVM Sequence: uart_echo_seq]
           |
           v
  [UVM UART Driver: uart_driver]
           |  (Drives 8N1 serial frame at 115200 baud)
           v
  [DUT Pin: uart_rx]
           |
           v
  [SoC UART Peripheral: axi_uart_top]
           |  (Receives byte into RX FIFO, sets LSR[0] DATA_READY = 1)
           v
  [AXI Interconnect: M02 Slave Port (0x1000_0000)]
           |  (LSU read transaction)
           v
  [VeeR EL2 Processor: RV32IMC Core]
           |  (Firmware polls LSR & 1, reads RBR 0x1000_0000)
           |  (Firmware polls LSR & 0x20, writes THR 0x1000_0000)
           v
  [AXI Interconnect: M02 Slave Port]
           |  (LSU write transaction)
           v
  [SoC UART Peripheral: axi_uart_top]
           |  (Pushes byte into TX FIFO, serializes out on transmitter)
           v
  [DUT Pin: uart_tx]
           |
           v
  [UVM UART Monitor: uart_monitor]
           |  (Reconstructs byte from serial frame)
           v
  [UVM Scoreboard: soc_scoreboard]
           |  (Verifies received character matches injected character)
           v
        [PASS]
```

---

## 10. Simulation Log Evidence

### A. UVM Config DB Connectivity Logs (`[SOC_CONNECT]`)
```
UVM_INFO tb_soc_top.sv(178) @ 0: reporter [SOC_CONNECT] Top: Registered virtual interface 'vif' into uvm_config_db for reset_vif
UVM_INFO tb_soc_top.sv(181) @ 0: reporter [SOC_CONNECT] Top: Registered virtual interface 'vif' into uvm_config_db for uart_vif
UVM_INFO tb_soc_top.sv(184) @ 0: reporter [SOC_CONNECT] Top: Registered virtual interface 'vif' into uvm_config_db for gpio_vif
UVM_INFO tb_soc_top.sv(187) @ 0: reporter [SOC_CONNECT] Top: Registered virtual interface 'vif' into uvm_config_db for irq_vif
UVM_INFO gpio_agent.sv(34) @ 0: uvm_test_top.env.gpio_agnt [SOC_CONNECT] uvm_test_top.env.gpio_agnt: Successfully retrieved virtual interface 'vif' from uvm_config_db
UVM_INFO gpio_monitor.sv(29) @ 0: uvm_test_top.env.gpio_agnt.mon [SOC_CONNECT] uvm_test_top.env.gpio_agnt.mon: Initialized with virtual interface gpio_if
UVM_INFO irq_agent.sv(32) @ 0: uvm_test_top.env.irq_agnt [SOC_CONNECT] uvm_test_top.env.irq_agnt: Successfully retrieved virtual interface 'vif' from uvm_config_db
UVM_INFO irq_monitor.sv(29) @ 0: uvm_test_top.env.irq_agnt.mon [SOC_CONNECT] uvm_test_top.env.irq_agnt.mon: Initialized with virtual interface irq_if
UVM_INFO reset_agent.sv(34) @ 0: uvm_test_top.env.reset_agnt [SOC_CONNECT] uvm_test_top.env.reset_agnt: Successfully retrieved virtual interface 'vif' from uvm_config_db
UVM_INFO reset_driver.sv(27) @ 0: uvm_test_top.env.reset_agnt.drv [SOC_CONNECT] uvm_test_top.env.reset_agnt.drv: Initialized with virtual interface reset_if
UVM_INFO reset_monitor.sv(29) @ 0: uvm_test_top.env.reset_agnt.mon [SOC_CONNECT] uvm_test_top.env.reset_agnt.mon: Initialized with virtual interface reset_if
UVM_INFO uart_agent.sv(34) @ 0: uvm_test_top.env.uart_agnt [SOC_CONNECT] uvm_test_top.env.uart_agnt: Successfully retrieved virtual interface 'vif' from uvm_config_db
UVM_INFO uart_monitor.sv(32) @ 0: uvm_test_top.env.uart_agnt.mon [SOC_CONNECT] uvm_test_top.env.uart_agnt.mon: Initialized with virtual interface uart_if
```

### B. `soc_smoke_test` Passing Summary
```
UVM_INFO soc_scoreboard.sv(150) @ 178645000: uvm_test_top.env.scb [SCB_FINAL]            SOC SCOREBOARD FINAL SUMMARY REPORT            
UVM_INFO soc_scoreboard.sv(152) @ 178645000: uvm_test_top.env.scb [SCB_FINAL]  Expected UART String                 : "HI"
UVM_INFO soc_scoreboard.sv(153) @ 178645000: uvm_test_top.env.scb [SCB_FINAL]  Received UART String                 : "HI"
UVM_INFO soc_scoreboard.sv(154) @ 178645000: uvm_test_top.env.scb [SCB_FINAL]  Total UART Characters Received       : 2
UVM_INFO soc_scoreboard.sv(155) @ 178645000: uvm_test_top.env.scb [SCB_FINAL]  Matching Characters                  : 2 / 2
UVM_INFO soc_scoreboard.sv(156) @ 178645000: uvm_test_top.env.scb [SCB_FINAL]  UART Protocol Framing Errors         : 0
UVM_INFO soc_scoreboard.sv(168) @ 178645000: uvm_test_top.env.scb [UART_SCB] [UART_SCB] Scoreboard check PASSED! All expected characters matched with zero errors - Check: PASS
--- UVM Report Summary ---
UVM_INFO : 77, UVM_WARNING : 0, UVM_ERROR : 0, UVM_FATAL : 0
```

### C. `uart_echo_test` Passing Summary
```
UVM_INFO soc_scoreboard.sv(103) @ 1209865000: uvm_test_top.env.scb [UART_SCB] [UART_SCB] COMPLETE MATCH! Fully received expected string "ABC123" with 0 errors.
UVM_INFO soc_scoreboard.sv(150) @ 1229865000: uvm_test_top.env.scb [SCB_FINAL]            SOC SCOREBOARD FINAL SUMMARY REPORT            
UVM_INFO soc_scoreboard.sv(152) @ 1229865000: uvm_test_top.env.scb [SCB_FINAL]  Expected UART String                 : "ABC123"
UVM_INFO soc_scoreboard.sv(153) @ 1229865000: uvm_test_top.env.scb [SCB_FINAL]  Received UART String                 : "ABC123"
UVM_INFO soc_scoreboard.sv(154) @ 1229865000: uvm_test_top.env.scb [SCB_FINAL]  Total UART Characters Received       : 6
UVM_INFO soc_scoreboard.sv(155) @ 1229865000: uvm_test_top.env.scb [SCB_FINAL]  Matching Characters                  : 6 / 6
UVM_INFO soc_scoreboard.sv(156) @ 1229865000: uvm_test_top.env.scb [SCB_FINAL]  UART Protocol Framing Errors         : 0
UVM_INFO soc_scoreboard.sv(168) @ 1229865000: uvm_test_top.env.scb [UART_SCB] [UART_SCB] Scoreboard check PASSED! All expected characters matched with zero errors - Check: PASS
--- UVM Report Summary ---
UVM_INFO : 108, UVM_WARNING : 0, UVM_ERROR : 0, UVM_FATAL : 0
```

---

## 11. Signal Checklist for Evaluator Waveform Inspection

When evaluating the waveform database (`simulation/waveforms/soc_uvm.fsdb` or `.vcd`), inspectors can verify the full interactive echo loop using these specific signals:

| Signal Name in Hierarchy | Type | Function in Demo | Key Timestamps / Values |
|---|---|---|---|
| `tb_soc_top.clk` | wire | 100 MHz SoC master clock | 10 ns period |
| `tb_soc_top.reset_vif.rst_n` | wire | Synchronous reset | Deasserts at 296,000 ps (30 cycles) |
| `tb_soc_top.uart_vif.uart_rx` | wire | UVM Driver Stimulus | Injects 0x41 ('A') at 10.4 $\mu$s, 0x42 ('B') at 217 $\mu$s, 0x43 ('C') at 424 $\mu$s, 0x31 ('1') at 631 $\mu$s, 0x32 ('2') at 838 $\mu$s, 0x33 ('3') at 1.04 ms |
| `tb_soc_top.u_dut.u_soc.u_uart.uart_controller_inst.uart_receiver_inst.rx_data_o[7:0]` | reg | Received Byte Register | Latches 0x41 ('A'), 0x42 ('B'), 0x43 ('C'), 0x31 ('1'), 0x32 ('2'), 0x33 ('3') |
| `tb_soc_top.u_dut.u_soc.m02_araddr[31:0]` | wire | AXI UART Read Address | Reads 0x1000_0014 (LSR) then 0x1000_0000 (RBR) |
| `tb_soc_top.u_dut.u_soc.m02_rdata[31:0]` | wire | AXI UART Read Data | Returns 0x61 (LSR ready) then 0x41 ('A') |
| `tb_soc_top.u_dut.u_soc.m02_awaddr[31:0]` | wire | AXI UART Write Address | Writes 0x1000_0000 (THR) |
| `tb_soc_top.u_dut.u_soc.m02_wdata[31:0]` | wire | AXI UART Write Data | Writes 0x41 ('A'), 0x42 ('B'), etc. |
| `tb_soc_top.uart_vif.uart_tx` | wire | DUT UART Transmitter | Transmits echoed frame starting at 93.6 $\mu$s ('A'), 300 $\mu$s ('B'), 507 $\mu$s ('C'), 714 $\mu$s ('1'), 921 $\mu$s ('2'), 1.13 ms ('3') |

---

## 12. AXI VIP Removal Confirmation

| Component | Status | Verification Check |
|---|---|---|
| `soc_env.sv` | Active UVM Env | 0 AXI agents, 0 AXI exports |
| `soc_env_cfg.sv` | Environment Config | Contains only UART, GPIO, Reset, IRQ configs |
| `soc_scoreboard.sv` | Scoreboard | 0 AXI analysis imports, 0 AXI checking calls |
| `soc_uvm_pkg.sv` | Package | `import axi_vip_pkg::*;` removed |
| `soc_uvm.f` | Filelist | `axi_vip_pkg.sv` and `+incdir+verification/uvm/vip/axi` removed |
| `tb_soc_top.sv` | Top Testbench | 0 AXI VIP instances, 0 AXI VIP config_db sets |
| `rtl/interconnect/*` | SoC RTL Crossbar | **100% Intact & Fully Functional** (verified by AXI bus transactions during test) |

---

## 13. Final Verification Result Summary

| Test Case Name | Firmware Executed | Stimulus | Target Output | Scoreboard Match | Status | Errors |
|---|---|---|---|---|---|---|
| `soc_smoke_test` | `uart_test_word.hex` | Power-on Reset | `"HI"` via UART TX | 2 / 2 chars | **PASS** | 0 |
| `uart_echo_test` | `uart_echo.hex` | `"ABC123"` via UART RX | `"ABC123"` echoed on TX | 6 / 6 chars | **PASS** | 0 |
