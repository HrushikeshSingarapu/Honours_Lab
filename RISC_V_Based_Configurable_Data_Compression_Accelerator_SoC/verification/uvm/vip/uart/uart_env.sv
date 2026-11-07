// =============================================================================
// uart_env.sv — Environment for UART VIP
// =============================================================================
`timescale 1ns/1ps

class uart_env extends uvm_env;
  `uvm_component_utils(uart_env)

  uart_agent      agent;
  uart_scoreboard sb;
  uart_cfg        cfg;

  function new(string name = "uart_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction : new

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(uart_cfg)::get(this, "", "cfg", cfg)) begin
      cfg = uart_cfg::type_id::create("cfg");
    end
    uvm_config_db#(uart_cfg)::set(this, "agent", "cfg", cfg);

    agent = uart_agent::type_id::create("agent", this);
    sb    = uart_scoreboard::type_id::create("sb", this);
  endfunction : build_phase

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    agent.mon.ap.connect(sb.item_export);
  endfunction : connect_phase
endclass : uart_env
