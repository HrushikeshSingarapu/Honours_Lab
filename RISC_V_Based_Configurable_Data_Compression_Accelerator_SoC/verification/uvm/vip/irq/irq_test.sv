// =============================================================================
// irq_test.sv — Standalone Sanity Test for IRQ VIP
// =============================================================================
`timescale 1ns/1ps

class irq_test extends uvm_test;
  `uvm_component_utils(irq_test)

  irq_env env;

  function new(string name = "irq_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction : new

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = irq_env::type_id::create("env", this);
  endfunction : build_phase

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    #2000;
    phase.drop_objection(this);
  endtask : run_phase
endclass : irq_test
