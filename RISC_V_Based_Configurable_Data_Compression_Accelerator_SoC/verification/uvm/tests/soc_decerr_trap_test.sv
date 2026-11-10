// =============================================================================
// soc_decerr_trap_test.sv — Reserved Address DECERR & VeeR EL2 Trap UVM Test
// Boots soc_decerr_test.hex: emits 'D' over 2 Mbps UART, then performs an
// intentional load to unimplemented reserved slot 0x0007_0000 (Packet FIFO).
// Verifies:
//   1. AXI Interconnect returns RRESP=2'b11 (DECERR) on LSU read to 0x0007_0000
//   2. VeeR EL2 takes imprecise bus-error NMI (ecause=0) -> NMI vec (0x1111_0000)
//   3. Zero UVM/scoreboard/protocol assertion errors
// =============================================================================
`timescale 1ns/1ps

`ifndef SOC_DECERR_TRAP_TEST_SV
`define SOC_DECERR_TRAP_TEST_SV

class soc_decerr_trap_test extends uvm_test;
  `uvm_component_utils(soc_decerr_trap_test)

  soc_env            env;
  soc_env_cfg        cfg;
  virtual soc_obs_if obs_vif;

  function new(string name = "soc_decerr_trap_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction : new

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    cfg = soc_env_cfg::type_id::create("cfg");
    cfg.expected_uart_string     = "D";
    cfg.apply_uart_timing(100_000_000, 2_000_000);
    cfg.uart_c.is_active         = UVM_ACTIVE;
    cfg.gpio_c.is_active         = UVM_ACTIVE;
    cfg.reset_c.is_active        = UVM_ACTIVE;
    cfg.irq_c.is_active          = UVM_PASSIVE;

    cfg.enable_uart_str_check    = 1'b1;
    cfg.enable_bus_ref_check     = 1'b1;
    cfg.allow_expected_decerr    = 1'b1;
    cfg.expected_decerr_addr     = 32'h0007_0000;
    cfg.allow_expected_cpu_fault = 1'b1;
    cfg.expected_cpu_ecause      = 5'd0; // VeeR EL2 imprecise bus error NMI on LSU DECERR
    cfg.min_expected_decerr_hits = 1;

    uvm_config_db#(soc_env_cfg)::set(this, "env", "cfg", cfg);
    env = soc_env::type_id::create("env", this);
    void'(uvm_config_db#(virtual soc_obs_if)::get(this, "", "obs_vif", obs_vif));
  endfunction : build_phase

  virtual task run_phase(uvm_phase phase);
    soc_smoke_seq rst_seq;

    phase.raise_objection(this, "Starting soc_decerr_trap_test");

    `uvm_info("SOC_DECERR_TEST", "==========================================================", UVM_NONE)
    `uvm_info("SOC_DECERR_TEST", "  Starting Reserved Slot DECERR + CPU NMI Trap UVM Test   ", UVM_NONE)
    `uvm_info("SOC_DECERR_TEST", "==========================================================", UVM_NONE)

    if (obs_vif != null) begin
      obs_vif.allow_expected_cpu_fault = 1'b1;
      obs_vif.expected_cpu_ecause      = 5'd0;
      obs_vif.expected_cpu_faults_seen = 0;
    end

    rst_seq = soc_smoke_seq::type_id::create("rst_seq");
    rst_seq.start(env.reset_agnt.seqr);

    fork
      begin
        wait (env.scb.uart_test_passed == 1'b1 &&
              env.scb.expected_decerr_hits >= 1 &&
              (obs_vif == null || obs_vif.expected_cpu_faults_seen >= 1));
        `uvm_info("SOC_DECERR_TEST",
                  $sformatf("Observed 'D' + DECERR (%0d hits) + CPU NMI trap (%0d faults)!",
                            env.scb.expected_decerr_hits,
                            (obs_vif != null) ? obs_vif.expected_cpu_faults_seen : 0),
                  UVM_LOW)
        #2_000ns;
      end
      begin
        #100_000ns; // 100 us watchdog
        `uvm_error("SOC_DECERR_TEST",
                   $sformatf("Watchdog timeout! rx=\"%s\", decerr_hits=%0d, faults=%0d",
                             env.scb.received_str, env.scb.expected_decerr_hits,
                             (obs_vif != null) ? obs_vif.expected_cpu_faults_seen : 0))
      end
    join_any
    disable fork;

    phase.drop_objection(this, "Completed soc_decerr_trap_test");
  endtask : run_phase

endclass : soc_decerr_trap_test

`endif // SOC_DECERR_TRAP_TEST_SV
