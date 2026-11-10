// =============================================================================
// soc_gpio_irq_seq.sv — Active GPIO Input Pulse Sequence for SoC UVM
// Pulses gpio_i[8] HIGH cleanly via GPIO VIP agent to trigger gpio_irq.
// =============================================================================
`timescale 1ns/1ps

`ifndef SOC_GPIO_IRQ_SEQ_SV
`define SOC_GPIO_IRQ_SEQ_SV

class soc_gpio_irq_seq extends uvm_sequence #(gpio_seq_item);
  `uvm_object_utils(soc_gpio_irq_seq)

  int pulse_pin_idx = 8;
  int pulse_cycles  = 30;

  function new(string name = "soc_gpio_irq_seq");
    super.new(name);
  endfunction : new

  virtual task body();
    `uvm_info("SOC_GPIO_SEQ", $sformatf("Pulsing gpio_i[%0d] for %0d cycles...", pulse_pin_idx, pulse_cycles), UVM_LOW)
    req = gpio_seq_item::type_id::create("gpio_irq_pulse");
    start_item(req);
    req.op            = gpio_seq_item::GPIO_PULSE_PIN;
    req.pulse_pin_idx = pulse_pin_idx;
    req.pulse_cycles  = pulse_cycles;
    req.gpio_val      = (32'h1 << pulse_pin_idx);
    req.gpio_mask     = (32'h1 << pulse_pin_idx);
    finish_item(req);
  endtask : body

endclass : soc_gpio_irq_seq

`endif // SOC_GPIO_IRQ_SEQ_SV
