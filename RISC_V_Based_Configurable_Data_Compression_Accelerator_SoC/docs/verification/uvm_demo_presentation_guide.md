# UVM Virtual Interface Demonstration Presentation Guide
## 9-Step Walkthrough for Evaluators & Verification Engineers

---

## Overview

This guide provides a structured, step-by-step walkthrough to present the **Four-Agent UVM Virtual Interface Demonstration** and **Firmware-Driven UART Interactive Echo** to evaluators. 

---

## Step 1: Introduction & Architecture Overview

**What to explain to the evaluator:**
- The verification environment targets the **VeeR EL2 RV32IMC RISC-V SoC** (`soc_core_top`).
- The environment uses **exactly four UVM VIP agents**:
  1. **Reset Agent**: Controls cold reset sequence (`reset_if`).
  2. **UART Agent**: Drives serial stimulus into `uart_rx` and monitors `uart_tx` (`uart_if`).
  3. **GPIO Agent**: Monitors 32-bit bidirectional GPIO pins (`gpio_if`).
  4. **IRQ Agent**: Monitors peripheral interrupt lines (`irq_if`).
- **AXI VIP has been completely removed** from the active UVM environment, while the functional on-chip AXI interconnect RTL (`rtl/interconnect/*`) remains completely intact and operational.

---

## Step 2: Where Virtual Interfaces are Instantiated

**Source Code**: `verification/uvm/tb_soc_top.sv`

Point the evaluators to lines 29–36 of `tb_soc_top.sv`:
```systemverilog
  // Physical VIP Interface Instantiations
  reset_if reset_vif (.clk(clk));
  uart_if  uart_vif  (.clk(clk), .rst_n(reset_vif.rst_n));
  gpio_if  gpio_vif  (.clk(clk), .rst_n(reset_vif.rst_n));
  irq_if   irq_vif   (.clk(clk), .rst_n(reset_vif.rst_n));
```
Explain:
- `reset_vif` drives `clk` and generates `rst_n`.
- `uart_vif`, `gpio_vif`, and `irq_vif` are tied synchronously to `clk` and `reset_vif.rst_n`.
- Each interface connects directly to the DUT ports (`u_dut`).

---

## Step 3: Registration via `uvm_config_db::set()`

**Source Code**: `verification/uvm/tb_soc_top.sv`

Point to lines 176–189 of `tb_soc_top.sv`:
```systemverilog
  initial begin
    uvm_config_db#(virtual reset_if)::set(null, "*", "vif", reset_vif);
    `uvm_info("SOC_CONNECT", "[SOC_CONNECT] Top: Registered virtual interface 'vif' into uvm_config_db for reset_vif", UVM_LOW)

    uvm_config_db#(virtual uart_if)::set(null, "*", "vif", uart_vif);
    `uvm_info("SOC_CONNECT", "[SOC_CONNECT] Top: Registered virtual interface 'vif' into uvm_config_db for uart_vif", UVM_LOW)

    uvm_config_db#(virtual gpio_if)::set(null, "*", "vif", gpio_vif);
    `uvm_info("SOC_CONNECT", "[SOC_CONNECT] Top: Registered virtual interface 'vif' into uvm_config_db for gpio_vif", UVM_LOW)

    uvm_config_db#(virtual irq_if)::set(null, "*", "vif", irq_vif);
    `uvm_info("SOC_CONNECT", "[SOC_CONNECT] Top: Registered virtual interface 'vif' into uvm_config_db for irq_vif", UVM_LOW)

    run_test();
  end
```
Key talking point:
- Registration occurs at time `0` before `run_test()`.
- Every registration emits an explicit `[SOC_CONNECT]` log.

---

## Step 4: Retrieval and Distribution via Agents

**Source Code**:
- `verification/uvm/vip/uart/uart_agent.sv`
- `verification/uvm/vip/gpio/gpio_agent.sv`
- `verification/uvm/vip/reset/reset_agent.sv`
- `verification/uvm/vip/irq/irq_agent.sv`

Show how the agent performs a single `get()` in `build_phase()` and distributes `vif` to child components:
```systemverilog
// uart_agent.sv
if (!uvm_config_db#(virtual uart_if)::get(this, "", "vif", vif)) begin
  `uvm_fatal("NOVIF", "[SOC_CONNECT] Failed to get virtual interface 'vif'")
end

mon.vif = vif;
if (get_is_active() == UVM_ACTIVE) begin
  drv.vif = vif;
end
```
Key talking point:
- Child components (`drv`, `mon`) receive the distributed handle directly, avoiding redundant lookups and eliminating race conditions.

---

## Step 5: Driver Driving DUT Inputs

**Source Code**:
- `verification/uvm/vip/reset/reset_driver.sv`
- `verification/uvm/vip/uart/uart_driver.sv`

Explain:
- **Reset Driver**: Drives DUT `rst_n = 0` for 30 clock cycles, then deasserts synchronously.
- **UART Driver**: Serializes ASCII characters into standard 8N1 frames at 115,200 baud ($\approx 868\text{ cycles/bit}$ at 100 MHz):
  1. Start bit: `vif.uart_rx <= 1'b0` (868 cycles)
  2. 8 Data bits: `vif.uart_rx <= item.data[b]` (LSB first, 868 cycles each)
  3. Stop bit: `vif.uart_rx <= 1'b1` (868 cycles)

---

## Step 6: Monitor Observing DUT Outputs

**Source Code**:
- `verification/uvm/vip/uart/uart_monitor.sv`
- `verification/uvm/vip/gpio/gpio_monitor.sv`
- `verification/uvm/vip/irq/irq_monitor.sv`

Explain:
- **UART Monitor**: Waits for start bit falling edge on `vif.uart_tx`, mid-bit samples 8 data bits, checks stop bit validity, and writes transaction item to analysis port `ap`.
- **GPIO Monitor**: Detects transitions on `vif.gpio_o` and `vif.gpio_oe`.
- **IRQ Monitor**: Samples asynchronous edge/level transitions on SoC interrupt lines.

---

## Step 7: Scoreboard Checking and Verification

**Source Code**: `verification/uvm/env/soc_scoreboard.sv`

Explain:
- In `connect_phase()`, the monitor analysis ports connect to the scoreboard analysis exports.
- `soc_scoreboard` accumulates received bytes, checks them against `expected_str`, and reports:
  - `Character match #N PASS: expected 'X', got 'X'`
  - `COMPLETE MATCH! Fully received expected string with 0 errors.`
  - Emits final scorecard in `check_phase()`.

---

## Step 8: Simulation Execution & Passing Logs

### Command to Run `soc_smoke_test`:
```bash
./simulation/scripts/run_soc_uvm.sh soc_smoke_test
```
**Expected Outcome**: 
- Scoreboard verifies `"HI"` output.
- `UVM_INFO : 77, UVM_WARNING : 0, UVM_ERROR : 0, UVM_FATAL : 0`

### Command to Run `uart_echo_test`:
```bash
./simulation/scripts/run_soc_uvm.sh uart_echo_test
```
**Expected Outcome**:
- Injects `"ABC123"`, echoes `"ABC123"`.
- `UVM_INFO : 108, UVM_WARNING : 0, UVM_ERROR : 0, UVM_FATAL : 0`

---

## Step 9: Waveform Inspection in Verdi

### Launch Verdi:
```bash
export VERDI_HOME=/home/student/snps_tools_target/verdi/U-2023.03-SP1
export PATH=$VERDI_HOME/bin:$PATH
export SNPSLMD_LICENSE_FILE=27021@14.139.1.126

verdi -ssf simulation/waveforms/soc_uvm.fsdb &
```

### Signal Tree to Add in Verdi (nWave):
Add the following signals from the hierarchy:

1. **System Control**:
   - `tb_soc_top/clk`
   - `tb_soc_top/reset_vif/rst_n`

2. **UART External Interface**:
   - `tb_soc_top/uart_vif/uart_rx` (Injected `"ABC123"` stimulus)
   - `tb_soc_top/uart_vif/uart_tx` (Echoed `"ABC123"` response)

3. **UART Internal Controller**:
   - `tb_soc_top/u_dut/u_soc/u_uart/uart_controller_inst/uart_receiver_inst/rx_data_o[7:0]` (Received character)
   - `tb_soc_top/u_dut/u_soc/u_uart/uart_controller_inst/rx_push_o` (RX FIFO push strobe)
   - `tb_soc_top/u_dut/u_soc/u_uart/uart_lsr_reg_int[31:0]` (LSR register: bit 0 = DATA_READY, bit 5 = THRE)

4. **AXI Bus M02 (UART Port)**:
   - `tb_soc_top/u_dut/u_soc/m02_araddr[31:0]` (Address 0x1000_0014 for LSR, 0x1000_0000 for RBR)
   - `tb_soc_top/u_dut/u_soc/m02_rdata[31:0]` (Read data returning from RBR: 0x41, 0x42, etc.)
   - `tb_soc_top/u_dut/u_soc/m02_awaddr[31:0]` (Address 0x1000_0000 for THR)
   - `tb_soc_top/u_dut/u_soc/m02_wdata[31:0]` (Write data to THR: 0x41, 0x42, etc.)

5. **Processor Trace**:
   - `tb_soc_top/trace_rv_i_address_ip[31:0]` (CPU program counter executing echo loop)

### What Evaluators Will See:
- **At 10.4 $\mu$s**: `uart_rx` falls (start bit of 'A' = 0x41).
- **At 92.8 $\mu$s**: `rx_push_o` pulses HIGH, character 0x41 is stored into the RX FIFO.
- **At 93.0 $\mu$s**: CPU reads LSR (0x1000_0014) returning 0x61 (`DATA_READY=1`), then reads RBR (0x1000_0000) returning 0x41 ('A').
- **At 93.1 $\mu$s**: CPU writes 0x41 to THR (0x1000_0000).
- **At 93.6 $\mu$s**: `uart_tx` falls (start bit of echoed 'A').
- **At 180.3 $\mu$s**: Echoed frame 'A' completes on `uart_tx`.
- Subsequent characters ('B', 'C', '1', '2', '3') repeat this exact sequence cleanly!
