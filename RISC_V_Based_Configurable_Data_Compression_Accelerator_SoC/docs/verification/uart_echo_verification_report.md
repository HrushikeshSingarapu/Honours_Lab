# UART Interactive Echo Verification Report

## 1. Executive Summary

This report documents the end-to-end verification of firmware-driven interactive UART character reception and transmission on the VeeR EL2 RISC-V SoC using VCS and UVM 1.2.

The verification validates the complete bidirectional transaction path:
1. **Stimulus Generation**: The UVM UART RX driver serializes ASCII characters onto the SoC's physical `uart_rx` pin at 115200 baud.
2. **Peripheral Reception**: The on-chip UART IP receives the serial frame, samples data bits using 16x oversampling, validates framing and stop bits, and asserts the Line Status Register (LSR) Data Ready bit (`LSR[0]`).
3. **Firmware Polling & AXI Read**: VeeR EL2 CPU executes the firmware loop (`firmware/source/uart_echo.c`), polls `LSR` (offset `0x14`), reads the received byte from the Receiver Buffer Register (`RBR` at `0x10000000`) over the 64-bit/32-bit AXI interconnect.
4. **Firmware Write & Transmission**: The CPU checks `LSR[5]` (Transmitter Holding Register Empty), writes the received character to the Transmitter Holding Register (`THR` at `0x10000000`) via AXI.
5. **Peripheral Transmission**: The UART IP shifts out the character over the physical `uart_tx` pin at 115200 baud.
6. **UVM Monitoring & Verification**: The passive UVM UART Monitor samples the `uart_tx` line, deserializes each byte, and forwards it to the UVM Scoreboard (`soc_scoreboard`).
7. **Scoreboard Comparison**: The scoreboard performs exact 1-to-1 matching against the sent stimulus sequence `"ABC123"`.

---

## 2. Complete Transaction Path Architecture

```
+-----------------------------------------------------------------------------------------+
|                                    UVM TESTBENCH                                        |
|                                                                                         |
|  +--------------------+                                       +----------------------+  |
|  | uart_echo_sequence |                                       |    soc_scoreboard    |  |
|  | sends: "ABC123"    |                                       | (Expected vs Actual) |  |
|  +---------+----------+                                       +----------^-----------+  |
|            |                                                             |              |
|            v                                                             |              |
|  +--------------------+                                       +----------+-----------+  |
|  |    uart_driver     |                                       |     uart_monitor     |  |
|  | (115200 baud 8N1)  |                                       |  (115200 baud 8N1)   |  |
|  +---------+----------+                                       +----------^-----------+  |
|            |                                                             |              |
|  ==========|=============================================================|============  |
|            | uart_vif.rx                                   uart_vif.tx   |              |
|            v                                                             |              |
|  +-----------------------------------------------------------------------+-----------+  |
|  |                                  SoC TOP RTL                                      |  |
|  |                                                                                   |  |
|  |   +---------------------------------------------------------------------------+   |  |
|  |   |                             UART PERIPHERAL                               |   |  |
|  |   |   RBR (0x10000000)      LSR (0x10000014)      THR (0x10000000)            |   |  |
|  |   +---------^----------------------^-----------------------|------------------+   |  |
|  |             |                      |                       |                      |  |
|  |             +-----------------+----+-----------------------+                      |  |
|  |                               | AXI Slave M02                                     |  |
|  |                               v                                                   |  |
|  |   +---------------------------------------------------------------------------+   |  |
|  |   |                           AXI INTERCONNECT                                |   |  |
|  |   +-----------------------------------^---------------------------------------+   |  |
|  |                                       | AXI Master S00                            |  |
|  |                                       v                                           |  |
|  |   +---------------------------------------------------------------------------+   |  |
|  |   |                        VeeR EL2 RISC-V PROCESSOR                          |   |  |
|  |   |   Firmware Loop (`uart_echo.c`):                                          |   |  |
|  |   |     while(1) {                                                            |   |  |
|  |   |       while (!(UART_LSR & 0x01)); // wait for RX                          |   |  |
|  |   |       char c = UART_RBR;          // read byte                            |   |  |
|  |   |       while (!(UART_LSR & 0x20)); // wait for TX ready                    |   |  |
|  |   |       UART_THR = c;               // echo byte                            |   |  |
|  |   |     }                                                                     |   |  |
|  |   +---------------------------------------------------------------------------+   |  |
|  +-----------------------------------------------------------------------------------+  |
+-----------------------------------------------------------------------------------------+
```

---

## 3. Test Stimulus & Timing Summary

- **Clock Frequency**: 50 MHz (`CLK_PERIOD = 20 ns`)
- **Baud Rate**: 115,200 baud
- **Bit Period**: `1 / 115200 ≈ 8,680.55 ns`
- **Full Frame (10 bits: Start + 8 Data + Stop)**: `86,805.5 ns` (`86.81 µs`)
- **Stimulus Sequence**: `"ABC123"` (6 bytes)

| Character # | Character | ASCII Hex | Injected on `uart_rx` (ps) | Echoed on `uart_tx` (ps) | Scoreboard Match Time (ps) | Status |
|:-----------:|:---------:|:---------:|:--------------------------:|:------------------------:|:--------------------------:|:------:|
| 1           | `'A'`     | `0x41`    | 97,105,000                 | 93,395,000               | 175,855,000                | PASS   |
| 2           | `'B'`     | `0x42`    | 303,915,000                | 300,225,000              | 382,685,000                | PASS   |
| 3           | `'C'`     | `0x43`    | 510,725,000                | 506,985,000              | 589,445,000                | PASS   |
| 4           | `'1'`     | `0x31`    | 717,535,000                | 713,745,000              | 796,205,000                | PASS   |
| 5           | `'2'`     | `0x32`    | 924,345,000                | 920,645,000              | 1,003,105,000              | PASS   |
| 6           | `'3'`     | `0x33`    | 1,131,155,000              | 1,127,405,000            | 1,209,865,000              | PASS   |

---

## 4. Scoreboard Final Verification Report

```
UVM_INFO verification/uvm/env/soc_scoreboard.sv(149) @ 1229865000: uvm_test_top.env.scb [SCB_FINAL] ==========================================================
UVM_INFO verification/uvm/env/soc_scoreboard.sv(150) @ 1229865000: uvm_test_top.env.scb [SCB_FINAL]            SOC SCOREBOARD FINAL SUMMARY REPORT            
UVM_INFO verification/uvm/env/soc_scoreboard.sv(151) @ 1229865000: uvm_test_top.env.scb [SCB_FINAL] ==========================================================
UVM_INFO verification/uvm/env/soc_scoreboard.sv(152) @ 1229865000: uvm_test_top.env.scb [SCB_FINAL]  Expected UART String                 : "ABC123"
UVM_INFO verification/uvm/env/soc_scoreboard.sv(153) @ 1229865000: uvm_test_top.env.scb [SCB_FINAL]  Received UART String                 : "ABC123"
UVM_INFO verification/uvm/env/soc_scoreboard.sv(154) @ 1229865000: uvm_test_top.env.scb [SCB_FINAL]  Total UART Characters Received       : 6
UVM_INFO verification/uvm/env/soc_scoreboard.sv(155) @ 1229865000: uvm_test_top.env.scb [SCB_FINAL]  Matching Characters                  : 6 / 6
UVM_INFO verification/uvm/env/soc_scoreboard.sv(156) @ 1229865000: uvm_test_top.env.scb [SCB_FINAL]  UART Protocol Framing Errors         : 0
UVM_INFO verification/uvm/env/soc_scoreboard.sv(157) @ 1229865000: uvm_test_top.env.scb [SCB_FINAL]  System Reset Assertions Observed     : 1
UVM_INFO verification/uvm/env/soc_scoreboard.sv(158) @ 1229865000: uvm_test_top.env.scb [SCB_FINAL]  GPIO Pin Transitions Monitored       : 0
UVM_INFO verification/uvm/env/soc_scoreboard.sv(159) @ 1229865000: uvm_test_top.env.scb [SCB_FINAL]  Peripheral Interrupt Events Captured : 0
UVM_INFO verification/uvm/env/soc_scoreboard.sv(160) @ 1229865000: uvm_test_top.env.scb [SCB_FINAL] ==========================================================
UVM_INFO verification/uvm/env/soc_scoreboard.sv(168) @ 1229865000: uvm_test_top.env.scb [UART_SCB] [UART_SCB] Scoreboard check PASSED! All expected characters matched with zero errors - Check: PASS

--- UVM Report Summary ---
** Report counts by severity
UVM_INFO :  108
UVM_WARNING :    0
UVM_ERROR :    0
UVM_FATAL :    0
```

---

## 5. Waveform Inspection & Evaluator Demonstration Guide

To view the echo verification in Synopsys Verdi:
1. Reload waveform: **File -> Reload Waveform** (or press `Shift + L`).
2. Add the two primary verification pins:
   - `tb_soc_top.uart_vif.rx` (Input to SoC)
   - `tb_soc_top.uart_vif.tx` (Output from SoC)
3. Zoom to `0 to 1.3 ms` (`0 to 1,300,000,000 ps`):
   - You will see 6 serial packet transmissions on `uart_rx`.
   - Each transmission is followed by an exact echo on `uart_tx`.
4. Zoom in on any single character (e.g. Character 1 between `10 µs` and `180 µs`):
   - `uart_rx` shifts in `0x41` (`01000001`b, LSB first: `1, 0, 0, 0, 0, 0, 1, 0`).
   - `uart_tx` transmits identical bit sequence `0x41`.
