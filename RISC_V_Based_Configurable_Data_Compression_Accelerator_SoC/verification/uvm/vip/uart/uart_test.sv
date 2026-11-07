// =============================================================================
// uart_test.sv — Standalone Sanity Test for UART VIP
// =============================================================================
`timescale 1ns/1ps

class uart_test extends uvm_test;
  `uvm_component_utils(uart_test)

  uart_env env;

  function new(string name = "uart_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction : new

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = uart_env::type_id::create("env", this);
  endfunction : build_phase

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    begin
      uart_base_seq seq = uart_base_seq::type_id::create("seq");
      seq.start(env.agent.seqr);
    end
    #2000;
    phase.drop_objection(this);
  endtask : run_phase
endclass : uart_test
