// =============================================================================
// reset_cfg.sv — Configuration Object for RESET VIP
// =============================================================================
`timescale 1ns/1ps

class reset_cfg extends uvm_object;
  `uvm_object_utils(reset_cfg)

  uvm_active_passive_enum is_active = UVM_ACTIVE;
  virtual reset_if        vif;

  int default_poweron_cycles = 30;

  function new(string name = "reset_cfg");
    super.new(name);
  endfunction : new
endclass : reset_cfg
