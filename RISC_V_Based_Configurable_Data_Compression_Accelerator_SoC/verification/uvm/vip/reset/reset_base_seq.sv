// =============================================================================
// reset_base_seq.sv — Base Sequence for RESET VIP
// =============================================================================
`timescale 1ns/1ps

class reset_base_seq extends uvm_sequence #(reset_seq_item);
  `uvm_object_utils(reset_base_seq)

  function new(string name = "reset_base_seq");
    super.new(name);
  endfunction : new

  virtual task body();
    `uvm_info(get_type_name(), "Executing Reset base sequence (asserting reset for 20 cycles)", UVM_LOW)
    req = reset_seq_item::type_id::create("req");
    start_item(req);
    req.kind = reset_seq_item::RESET_COLD_POWERON;
    req.duration_cycles = 20;
    finish_item(req);
  endtask : body
endclass : reset_base_seq
