// =============================================================================
// uart_sequencer.sv — Sequencer for UART VIP
// =============================================================================
`timescale 1ns/1ps

class uart_sequencer extends uvm_sequencer #(uart_seq_item);
  `uvm_component_utils(uart_sequencer)

  function new(string name = "uart_sequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction : new
endclass : uart_sequencer
