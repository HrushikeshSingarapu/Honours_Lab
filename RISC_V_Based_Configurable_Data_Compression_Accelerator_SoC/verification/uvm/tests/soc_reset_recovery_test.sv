// =============================================================================
// soc_reset_recovery_test.sv — Mid-Execution Warm Reset & Reboot Recovery Test
// Exercises Cold Reset -> Partial Execution -> Active Warm Reset via reset_agnt
// -> Quiescence Verification -> Full Reboot from 0x8000_0000 & E2E Pass.
// =============================================================================
`timescale 1ns/1ps

`ifndef SOC_RST_REC_TEST_SV
`define SOC_RST_REC_TEST_SV

class soc_reset_recovery_test extends uvm_test;
  `uvm_component_utils(soc_reset_recovery_test)

  soc_env            env;
  soc_env_cfg        cfg;
  virtual soc_obs_if obs_vif;

  function new(string name = "soc_reset_recovery_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction : new

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    cfg = soc_env_cfg::type_id::create("cfg");
    cfg.expected_uart_string     = "TGRDEKP";
    cfg.apply_uart_timing(100_000_000, 2_000_000);
    cfg.uart_c.is_active         = UVM_ACTIVE;
    cfg.gpio_c.is_active         = UVM_ACTIVE;
    cfg.reset_c.is_active        = UVM_ACTIVE;
    cfg.irq_c.is_active          = UVM_PASSIVE;

    cfg.enable_uart_str_check    = 1'b1;
    cfg.enable_bus_ref_check     = 1'b1;
    cfg.clear_uart_on_warm_reset = 1'b1;
    cfg.allow_expected_decerr    = 1'b0;
    cfg.allow_expected_cpu_fault = 1'b0;

    cfg.expect_timer_irq         = 1'b1;
    cfg.expect_gpio_irq          = 1'b1;
    cfg.expect_rle_irq           = 1'b1;
    cfg.expect_dma_irq           = 1'b1;
    cfg.expect_gpio_pin_check    = 1'b1;
    cfg.min_expected_dma_xfers   = 6;
    cfg.min_expected_rle_ops     = 1;
    cfg.min_expected_crc_checks  = 3;
    cfg.min_expected_decerr_hits = 0;

    uvm_config_db#(soc_env_cfg)::set(this, "env", "cfg", cfg);
    env = soc_env::type_id::create("env", this);
    void'(uvm_config_db#(virtual soc_obs_if)::get(this, "", "obs_vif", obs_vif));
  endfunction : build_phase

  virtual task run_phase(uvm_phase phase);
    soc_smoke_seq          cold_seq;
    soc_warm_reset_seq     warm_seq;
    soc_gpio_irq_seq       gpio_seq;
    soc_uart_echo_fast_seq echo_seq;

    phase.raise_objection(this, "Starting soc_reset_recovery_test");

    `uvm_info("SOC_RST_REC", "==========================================================", UVM_NONE)
    `uvm_info("SOC_RST_REC", "  Starting Mid-Operation Warm Reset & Recovery UVM Test   ", UVM_NONE)
    `uvm_info("SOC_RST_REC", "==========================================================", UVM_NONE)

    if (obs_vif != null) begin
      obs_vif.allow_expected_cpu_fault = 1'b0;
      obs_vif.expected_cpu_ecause      = 5'd5;
      obs_vif.expected_cpu_faults_seen = 0;
    end

    // 1. Initial cold power-on reset
    cold_seq = soc_smoke_seq::type_id::create("cold_seq");
    cold_seq.start(env.reset_agnt.seqr);

    fork
      begin
        // Wait until first boot reaches Timer ('T') & GPIO ('G') while UART is idle awaiting gpio_i[8]
        wait (env.scb.received_str.len() >= 2);
        `uvm_info("SOC_RST_REC", "First boot reached GPIO wait stage (\"TG\"); asserting mid-run WARM RESET!", UVM_LOW)

        // 2. Assert Warm Reset mid-execution (tests quiescence & reboot from 0x8000_0000)
        warm_seq = soc_warm_reset_seq::type_id::create("warm_seq");
        warm_seq.start(env.reset_agnt.seqr);

        // 3. After reboot, drive full E2E interactive sequence to completion
        wait (env.scb.received_str.len() >= 2);
        gpio_seq = soc_gpio_irq_seq::type_id::create("gpio_seq");
        gpio_seq.start(env.gpio_agnt.seqr);

        wait (env.scb.received_str.len() >= 5);
        echo_seq = soc_uart_echo_fast_seq::type_id::create("echo_seq");
        echo_seq.start(env.uart_agnt.seqr);

        wait (env.scb.uart_test_passed == 1'b1);
        `uvm_info("SOC_RST_REC", "Warm Reset Reboot & Full E2E Flow PASSED (\"TGRDEKP\")!", UVM_LOW)
        #2_000ns;
      end
      begin
        #350_000ns; // 350 us watchdog
        `uvm_error("SOC_RST_REC", $sformatf("Watchdog timeout during warm reset recovery! Received: \"%s\"", env.scb.received_str))
      end
    join_any
    disable fork;

    phase.drop_objection(this, "Completed soc_reset_recovery_test");
  endtask : run_phase

endclass : soc_reset_recovery_test

`endif // SOC_RST_REC_TEST_SV
