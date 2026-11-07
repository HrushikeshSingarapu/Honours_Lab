// =============================================================================
// reset_seq_item.sv — Sequence Item for RESET VIP
// =============================================================================
`timescale 1ns/1ps

class reset_seq_item extends uvm_sequence_item;

  typedef enum bit {
    RESET_COLD_POWERON = 1'b0,
    RESET_WARM_PULSE   = 1'b1
  } reset_kind_e;

  rand reset_kind_e kind;
  rand int          duration_cycles; // Reset duration in clock cycles
  time              timestamp;

  constraint c_reset_defaults {
    duration_cycles inside {[5:100]};
    soft kind == RESET_COLD_POWERON;
    soft duration_cycles == 30;
  }

  `uvm_object_utils(reset_seq_item)

  function new(string name = "reset_seq_item");
    super.new(name);
  endfunction : new

  virtual function string convert2string();
    return $sformatf("[RESET ITEM] Kind=%s Duration=%0d cycles", kind.name(), duration_cycles);
  endfunction : convert2string
endclass : reset_seq_item
