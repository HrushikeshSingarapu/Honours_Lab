// =============================================================================
// gpio_env.sv — Environment for GPIO VIP
// =============================================================================
`timescale 1ns/1ps

class gpio_env extends uvm_env;
  `uvm_component_utils(gpio_env)

  gpio_agent      agent;
  gpio_scoreboard sb;
  gpio_cfg        cfg;

  function new(string name = "gpio_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction : new

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(gpio_cfg)::get(this, "", "cfg", cfg)) begin
      cfg = gpio_cfg::type_id::create("cfg");
    end
    uvm_config_db#(gpio_cfg)::set(this, "agent", "cfg", cfg);

    agent = gpio_agent::type_id::create("agent", this);
    sb    = gpio_scoreboard::type_id::create("sb", this);
  endfunction : build_phase

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    agent.mon.ap.connect(sb.item_export);
  endfunction : connect_phase
endclass : gpio_env
