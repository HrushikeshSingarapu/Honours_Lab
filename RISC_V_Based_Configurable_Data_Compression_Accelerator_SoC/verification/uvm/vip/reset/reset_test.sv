// =============================================================================
// reset_test.sv — Standalone Sanity Test for RESET VIP
// =============================================================================
`timescale 1ns/1ps

class reset_test extends uvm_test;
  `uvm_component_utils(reset_test)

  reset_env env;

  function new(string name = "reset_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction : new

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = reset_env::type_id::create("env", this);
  endfunction : build_phase

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    begin
      reset_base_seq seq = reset_base_seq::type_id::create("seq");
      seq.start(env.agent.seqr);
    end
    #2000;
    phase.drop_objection(this);
  endtask : run_phase
endclass : reset_test
