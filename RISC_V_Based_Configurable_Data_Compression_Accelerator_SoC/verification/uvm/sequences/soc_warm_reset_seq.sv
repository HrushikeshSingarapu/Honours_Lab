// =============================================================================
// soc_warm_reset_seq.sv — Active Warm Reset Sequence for SoC UVM
// Drives a synchronized warm reset pulse via Reset VIP agent during operation.
// =============================================================================
`timescale 1ns/1ps

`ifndef SOC_WARM_RESET_SEQ_SV
`define SOC_WARM_RESET_SEQ_SV

class soc_warm_reset_seq extends uvm_sequence #(reset_seq_item);
  `uvm_object_utils(soc_warm_reset_seq)

  int duration_cycles = 25;

  function new(string name = "soc_warm_reset_seq");
    super.new(name);
  endfunction : new

  virtual task body();
    `uvm_info("SOC_WARM_RST_SEQ", $sformatf("Issuing warm reset pulse (%0d cycles)...", duration_cycles), UVM_LOW)
    req = reset_seq_item::type_id::create("warm_rst");
    start_item(req);
    req.kind            = reset_seq_item::RESET_WARM_PULSE;
    req.duration_cycles = duration_cycles;
    finish_item(req);
    `uvm_info("SOC_WARM_RST_SEQ", "Warm reset pulse released cleanly.", UVM_LOW)
  endtask : body

endclass : soc_warm_reset_seq

`endif // SOC_WARM_RESET_SEQ_SV
