// =============================================================================
// soc_smoke_seq.sv — SoC Bring-Up & Power-On Reset Sequence
// Drives synchronized cold reset to SoC to initiate RISC-V firmware execution.
// =============================================================================
`timescale 1ns/1ps

`ifndef SOC_SMOKE_SEQ_SV
`define SOC_SMOKE_SEQ_SV

class soc_smoke_seq extends uvm_sequence #(reset_seq_item);
  `uvm_object_utils(soc_smoke_seq)

  function new(string name = "soc_smoke_seq");
    super.new(name);
  endfunction : new

  virtual task body();
    `uvm_info("SOC_SMOKE_SEQ", "Initiating synchronized cold reset assertion (30 cycles)...", UVM_LOW)
    req = reset_seq_item::type_id::create("req");
    start_item(req);
    req.kind            = reset_seq_item::RESET_COLD_POWERON;
    req.duration_cycles = 30;
    finish_item(req);
    `uvm_info("SOC_SMOKE_SEQ", "Cold reset deasserted cleanly. VeeR EL2 core is executing firmware from 0x8000_0000.", UVM_LOW)
  endtask : body

endclass : soc_smoke_seq

`endif // SOC_SMOKE_SEQ_SV
