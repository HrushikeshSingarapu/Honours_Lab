// =============================================================================
// irq_env.sv — Environment for IRQ VIP
// =============================================================================
`timescale 1ns/1ps

class irq_env extends uvm_env;
  `uvm_component_utils(irq_env)

  irq_agent      agent;
  irq_scoreboard sb;
  irq_cfg        cfg;

  function new(string name = "irq_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction : new

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(irq_cfg)::get(this, "", "cfg", cfg)) begin
      cfg = irq_cfg::type_id::create("cfg");
    end
    uvm_config_db#(irq_cfg)::set(this, "agent", "cfg", cfg);

    agent = irq_agent::type_id::create("agent", this);
    sb    = irq_scoreboard::type_id::create("sb", this);
  endfunction : build_phase

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    agent.mon.ap.connect(sb.item_export);
  endfunction : connect_phase
endclass : irq_env
