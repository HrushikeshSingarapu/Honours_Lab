// =============================================================================
// soc_env.sv — Top-Level UVM Environment for SoC Verification
// Assembles the exact 4 active VIP agents (UART, GPIO, Reset, IRQ),
// unified Scoreboard, and Functional Coverage subscriber.
// =============================================================================
`timescale 1ns/1ps

`ifndef SOC_ENV_SV
`define SOC_ENV_SV

class soc_env extends uvm_env;
  `uvm_component_utils(soc_env)

  soc_env_cfg    cfg;
  uart_agent     uart_agnt;
  gpio_agent     gpio_agnt;
  reset_agent    reset_agnt;
  irq_agent      irq_agnt;

  soc_scoreboard scb;
  soc_coverage   cov;

  function new(string name = "soc_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction : new

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(soc_env_cfg)::get(this, "", "cfg", cfg)) begin
      `uvm_info("SOC_ENV", "No soc_env_cfg provided via config_db; creating default", UVM_MEDIUM)
      cfg = soc_env_cfg::type_id::create("cfg");
    end

    // Forward sub-VIP configuration objects down to their respective 4 agents
    if (cfg.has_uart)  uvm_config_db#(uart_cfg)::set(this, "uart_agnt*", "cfg", cfg.uart_c);
    if (cfg.has_gpio)  uvm_config_db#(gpio_cfg)::set(this, "gpio_agnt*", "cfg", cfg.gpio_c);
    if (cfg.has_reset) uvm_config_db#(reset_cfg)::set(this, "reset_agnt*", "cfg", cfg.reset_c);
    if (cfg.has_irq)   uvm_config_db#(irq_cfg)::set(this, "irq_agnt*", "cfg", cfg.irq_c);
    uvm_config_db#(soc_env_cfg)::set(this, "scb*", "cfg", cfg);
    uvm_config_db#(soc_env_cfg)::set(this, "cov*", "cfg", cfg);

    // Build the exact four active VIP agents
    if (cfg.has_uart)  uart_agnt  = uart_agent::type_id::create("uart_agnt", this);
    if (cfg.has_gpio)  gpio_agnt  = gpio_agent::type_id::create("gpio_agnt", this);
    if (cfg.has_reset) reset_agnt = reset_agent::type_id::create("reset_agnt", this);
    if (cfg.has_irq)   irq_agnt   = irq_agent::type_id::create("irq_agnt", this);

    // Build Scoreboard & Coverage components
    scb = soc_scoreboard::type_id::create("scb", this);
    cov = soc_coverage::type_id::create("cov", this);
  endfunction : build_phase

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    if (cfg != null && scb != null) begin
      scb.set_expected_string(cfg.expected_uart_string);
    end

    if (cfg.has_uart) begin
      uart_agnt.mon.ap.connect(scb.uart_export);
      uart_agnt.mon.ap.connect(cov.analysis_export);
    end

    if (cfg.has_gpio) begin
      gpio_agnt.mon.ap.connect(scb.gpio_export);
    end

    if (cfg.has_reset) begin
      reset_agnt.mon.ap.connect(scb.reset_export);
    end

    if (cfg.has_irq) begin
      irq_agnt.mon.ap.connect(scb.irq_export);
    end
  endfunction : connect_phase

endclass : soc_env

`endif // SOC_ENV_SV
