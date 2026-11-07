// =============================================================================
// reset_env.sv — Environment for RESET VIP
// =============================================================================
`timescale 1ns/1ps

class reset_env extends uvm_env;
  `uvm_component_utils(reset_env)

  reset_agent      agent;
  reset_scoreboard sb;
  reset_cfg        cfg;

  function new(string name = "reset_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction : new

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(reset_cfg)::get(this, "", "cfg", cfg)) begin
      cfg = reset_cfg::type_id::create("cfg");
    end
    uvm_config_db#(reset_cfg)::set(this, "agent", "cfg", cfg);

    agent = reset_agent::type_id::create("agent", this);
    sb    = reset_scoreboard::type_id::create("sb", this);
  endfunction : build_phase

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    agent.mon.ap.connect(sb.item_export);
  endfunction : connect_phase
endclass : reset_env
