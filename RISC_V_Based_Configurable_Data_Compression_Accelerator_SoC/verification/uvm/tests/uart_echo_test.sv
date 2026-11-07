// =============================================================================
// uart_echo_test.sv — End-to-End UART Interactive Echo Test for SoC
// Verifies: UVM RX Driver -> UART RX Pin -> UART Core -> VeeR EL2 CPU ->
//           UART TX Reg -> UART TX Pin -> UVM TX Monitor -> Scoreboard Check.
// =============================================================================
`timescale 1ns/1ps

`ifndef UART_ECHO_TEST_SV
`define UART_ECHO_TEST_SV

class uart_echo_test extends uvm_test;
  `uvm_component_utils(uart_echo_test)

  soc_env     env;
  soc_env_cfg cfg;

  function new(string name = "uart_echo_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction : new

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    cfg = soc_env_cfg::type_id::create("cfg");
    cfg.expected_uart_string = "ABC123";
    cfg.clock_freq_hz        = 100_000_000;
    cfg.baud_rate            = 115200;
    cfg.uart_c.is_active     = UVM_ACTIVE; // Active driver on UART RX

    uvm_config_db#(soc_env_cfg)::set(this, "env", "cfg", cfg);
    env = soc_env::type_id::create("env", this);
  endfunction : build_phase

  virtual task run_phase(uvm_phase phase);
    soc_smoke_seq rst_seq;
    uart_echo_seq echo_seq;

    phase.raise_objection(this, "Starting uart_echo_test");

    `uvm_info("UART_ECHO_TEST", "==========================================================", UVM_NONE)
    `uvm_info("UART_ECHO_TEST", "  Starting UART Interactive Echo Test (Firmware-Driven)   ", UVM_NONE)
    `uvm_info("UART_ECHO_TEST", "  Stimulus: \"ABC123\" into UART RX -> Echoed on UART TX    ", UVM_NONE)
    `uvm_info("UART_ECHO_TEST", "==========================================================", UVM_NONE)

    // 1. Initiate synchronized power-on reset
    rst_seq = soc_smoke_seq::type_id::create("rst_seq");
    rst_seq.start(env.reset_agnt.seqr);

    // 2. Start UART Echo Stimulus Sequence in background
    fork
      begin
        echo_seq = uart_echo_seq::type_id::create("echo_seq");
        echo_seq.start(env.uart_agnt.seqr);
      end
    join_none

    // 3. Concurrently observe UART TX echo matching vs watchdog timeout
    fork
      begin
        wait (env.scb.uart_test_passed == 1'b1);
        `uvm_info("UART_ECHO_TEST", "[UART_ECHO_TEST] Scoreboard confirmed all echoed characters matched (\"ABC123\")! Holding for line stabilization...", UVM_LOW)
        #20_000ns;
      end
      begin
        // Watchdog timeout: 3 ms (3,000,000 ns = 300,000 clock cycles at 100 MHz)
        #3_000_000ns;
        `uvm_error("UART_ECHO_TEST", "[UART_ECHO_TEST] Watchdog timeout (3.0 ms) exceeded waiting for UART echo output!")
      end
    join_any
    disable fork;

    `uvm_info("UART_ECHO_TEST", "Completing uart_echo_test objection drop.", UVM_LOW)
    phase.drop_objection(this, "Completed uart_echo_test");
  endtask : run_phase

endclass : uart_echo_test

`endif // UART_ECHO_TEST_SV
