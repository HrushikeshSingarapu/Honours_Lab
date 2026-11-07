// =============================================================================
// gpio_sequencer.sv — Sequencer for GPIO VIP
// =============================================================================
`timescale 1ns/1ps

class gpio_sequencer extends uvm_sequencer #(gpio_seq_item);
  `uvm_component_utils(gpio_sequencer)

  function new(string name = "gpio_sequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction : new
endclass : gpio_sequencer
