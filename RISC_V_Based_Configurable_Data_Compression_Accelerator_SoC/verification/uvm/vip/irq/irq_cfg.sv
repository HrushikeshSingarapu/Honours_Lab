// =============================================================================
// irq_cfg.sv — Configuration Object for IRQ VIP
// =============================================================================
`timescale 1ns/1ps

class irq_cfg extends uvm_object;
  `uvm_object_utils(irq_cfg)

  uvm_active_passive_enum is_active = UVM_PASSIVE;
  virtual irq_if        vif;

  int max_event_history = 512;

  function new(string name = "irq_cfg");
    super.new(name);
  endfunction : new
endclass : irq_cfg
