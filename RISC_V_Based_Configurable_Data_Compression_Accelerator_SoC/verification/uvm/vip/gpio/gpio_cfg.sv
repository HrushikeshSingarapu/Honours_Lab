// =============================================================================
// gpio_cfg.sv — Configuration Object for GPIO VIP
// =============================================================================
`timescale 1ns/1ps

class gpio_cfg extends uvm_object;
  `uvm_object_utils(gpio_cfg)

  uvm_active_passive_enum is_active = UVM_ACTIVE;
  virtual gpio_if        vif;

  bit enable_contention_check = 1'b1;
  int sample_history_depth    = 256;

  function new(string name = "gpio_cfg");
    super.new(name);
  endfunction : new
endclass : gpio_cfg
