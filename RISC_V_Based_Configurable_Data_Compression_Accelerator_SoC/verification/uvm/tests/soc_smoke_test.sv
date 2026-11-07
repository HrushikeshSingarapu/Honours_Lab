// =============================================================================
// soc_smoke_test.sv — End-to-End System Smoke Test for SoC
// Coordinates power-on reset, firmware boot, and UART transmission checking.
// =============================================================================
`timescale 1ns/1ps

`ifndef SOC_SMOKE_TEST_SV
`define SOC_SMOKE_TEST_SV

class soc_smoke_test extends uvm_test;
  `uvm_component_utils(soc_smoke_test)

  soc_env     env;
  soc_env_cfg cfg;

  function new(string name = "soc_smoke_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction : new

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    cfg = soc_env_cfg::type_id::create("cfg");
    cfg.expected_uart_string = "HI";
    cfg.clock_freq_hz        = 100_000_000;
    cfg.baud_rate            = 115200;

    uvm_config_db#(soc_env_cfg)::set(this, "env", "cfg", cfg);
    env = soc_env::type_id::create("env", this);
  endfunction : build_phase

  virtual task run_phase(uvm_phase phase);
    soc_smoke_seq seq;
    phase.raise_objection(this, "Starting soc_smoke_test");

    `uvm_info("SOC_SMOKE_TEST", "==========================================================", UVM_NONE)
    `uvm_info("SOC_SMOKE_TEST", "  Starting Unified SoC Smoke Test (VeeR EL2 Boot & UART)   ", UVM_NONE)
    `uvm_info("SOC_SMOKE_TEST", "==========================================================", UVM_NONE)

    // Execute power-on reset sequence via Reset VIP sequencer
    seq = soc_smoke_seq::type_id::create("seq");
    seq.start(env.reset_agnt.seqr);

    // Concurrently observe UART transmission vs watchdog timeout
    fork
      begin
        wait (env.scb.uart_test_passed == 1'b1);
        `uvm_info("SOC_SMOKE_TEST", "Scoreboard passed all checks. Holding for line stabilization...", UVM_LOW)
        #5000ns;
      end
      begin
        // Watchdog timeout: 500 us (50,000 clock cycles at 100 MHz)
        #500_000ns;
        `uvm_error("SOC_SMOKE_TEST", "Watchdog timeout (500 us) exceeded waiting for UART 'HI' output from firmware!")
      end
    join_any
    disable fork;

    `uvm_info("SOC_SMOKE_TEST", "Completing soc_smoke_test objection drop.", UVM_LOW)
    phase.drop_objection(this, "Completed soc_smoke_test");
  endtask : run_phase

endclass : soc_smoke_test

`endif // SOC_SMOKE_TEST_SV
