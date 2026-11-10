// =============================================================================
// soc_e2e_flow_test.sv — Comprehensive End-to-End Integrated SoC UVM Test
// Drives ALL 4 active UVM VIP agents (Reset, GPIO, UART RX/TX, IRQ) while
// VeeR EL2 executes soc_e2e_uvm.hex:
//   - IMEM Base (0x0000_0000) & Reset Alias (0x8000_0000)
//   - DMEM Lower (0x0001_0000) & DMEM Upper (0x0002_0000)
//   - Timer + timer_irq assertion & W1C
//   - GPIO out + external gpio_i[8] pulse from gpio_agnt -> gpio_irq
//   - Direct RLE compress + rle_irq
//   - End-to-End Flow: Input -> DMA Compress -> DMA Decompress -> CRC-32 + dma_irq
//   - Negative error paths (DMA ERR_BAD_LEN, ERR_BAD_SRC) + Reserved Slot DECERR trap
//   - Fast interactive UART RX->TX echo ('K') & PASS signature ("TGRDEKP")
// =============================================================================
`timescale 1ns/1ps

`ifndef SOC_E2E_FLOW_TEST_SV
`define SOC_E2E_FLOW_TEST_SV

class soc_e2e_flow_test extends uvm_test;
  `uvm_component_utils(soc_e2e_flow_test)

  soc_env            env;
  soc_env_cfg        cfg;
  virtual soc_obs_if obs_vif;

  function new(string name = "soc_e2e_flow_test", uvm_component parent = null);
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
    soc_smoke_seq          rst_seq;
    soc_gpio_irq_seq       gpio_seq;
    soc_uart_echo_fast_seq echo_seq;

    phase.raise_objection(this, "Starting soc_e2e_flow_test");

    `uvm_info("SOC_E2E_TEST", "==========================================================", UVM_NONE)
    `uvm_info("SOC_E2E_TEST", "  Starting End-to-End Integrated SoC UVM Flow Test        ", UVM_NONE)
    `uvm_info("SOC_E2E_TEST", "==========================================================", UVM_NONE)

    if (obs_vif != null) begin
      obs_vif.allow_expected_cpu_fault = 1'b0;
      obs_vif.expected_cpu_ecause      = 5'd5;
      obs_vif.expected_cpu_faults_seen = 0;
    end

    // 1. Cold reset boot
    rst_seq = soc_smoke_seq::type_id::create("rst_seq");
    rst_seq.start(env.reset_agnt.seqr);

    // 2. Drive interactive VIP responses coordinated with firmware progress
    fork
      begin
        // Wait for Step B prompt 'G' -> pulse gpio_i[8]
        wait (env.scb.received_str.len() >= 2);
        gpio_seq = soc_gpio_irq_seq::type_id::create("gpio_seq");
        gpio_seq.start(env.gpio_agnt.seqr);

        // Wait for Step E marker 'E' -> inject fast UART echo char 'K'
        wait (env.scb.received_str.len() >= 5);
        echo_seq = soc_uart_echo_fast_seq::type_id::create("echo_seq");
        echo_seq.start(env.uart_agnt.seqr);

        // Wait for complete "TGRDEKP" match
        wait (env.scb.uart_test_passed == 1'b1);
        `uvm_info("SOC_E2E_TEST", "Full End-to-End SoC Flow PASSED (\"TGRDEKP\")!", UVM_LOW)
        #2_000ns;
      end
      begin
        #250_000ns; // 250 us watchdog
        `uvm_error("SOC_E2E_TEST", $sformatf("Watchdog timeout waiting for E2E flow completion! Received so far: \"%s\"", env.scb.received_str))
      end
    join_any
    disable fork;

    phase.drop_objection(this, "Completed soc_e2e_flow_test");
  endtask : run_phase

endclass : soc_e2e_flow_test

`endif // SOC_E2E_FLOW_TEST_SV
