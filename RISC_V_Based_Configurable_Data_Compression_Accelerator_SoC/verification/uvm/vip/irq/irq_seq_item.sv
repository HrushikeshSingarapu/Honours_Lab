// =============================================================================
// irq_seq_item.sv — Sequence Item for IRQ VIP
// =============================================================================
`timescale 1ns/1ps

class irq_seq_item extends uvm_sequence_item;

  bit        gpio_irq;
  bit        timer_irq;
  bit        rle_irq;
  bit        dma_irq;
  bit [3:0]  irq_status;     // {dma_irq, rle_irq, timer_irq, gpio_irq}
  int        irq_channel;    // Channel triggering this event (0-3)
  bit        is_assertion;   // 1 = assertion (rising), 0 = deassertion
  time       timestamp;
  int        active_duration_cycles;

  `uvm_object_utils(irq_seq_item)

  function new(string name = "irq_seq_item");
    super.new(name);
  endfunction : new

  virtual function string convert2string();
    return $sformatf("[IRQ ITEM] Ch=%0d (%s) IRQ_Bus=4'b%04b Time=%0t", irq_channel, (is_assertion ? "ASSERT" : "DEASSERT"), irq_status, timestamp);
  endfunction : convert2string
endclass : irq_seq_item
