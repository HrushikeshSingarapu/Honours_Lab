// =============================================================================
// gpio_seq_item.sv — Sequence Item for GPIO VIP
// =============================================================================
`timescale 1ns/1ps

class gpio_seq_item extends uvm_sequence_item;

  typedef enum bit [1:0] {
    GPIO_DRIVE_ALL  = 2'b00,
    GPIO_DRIVE_MASK = 2'b01,
    GPIO_PULSE_PIN  = 2'b10,
    GPIO_SAMPLE     = 2'b11
  } gpio_op_e;

  rand gpio_op_e op;              // GPIO stimulus operation
  rand bit [31:0] gpio_val;       // Value to drive on gpio_i
  rand bit [31:0] gpio_mask;      // Active pin mask
  rand int        pulse_pin_idx;  // Pin index for single-pin pulse
  rand int        pulse_cycles;   // Duration of pulse in cycles

  bit [31:0]      gpio_o;         // Captured DUT output vector
  bit [31:0]      gpio_oe;        // Captured DUT output enable mask
  time            timestamp;

  constraint c_gpio_defaults {
    pulse_pin_idx inside {[0:31]};
    pulse_cycles inside {[1:100]};
    soft op == GPIO_DRIVE_ALL;
    soft gpio_mask == 32'hFFFF_FFFF;
  }

  `uvm_object_utils(gpio_seq_item)

  function new(string name = "gpio_seq_item");
    super.new(name);
  endfunction : new

  virtual function string convert2string();
    return $sformatf("[GPIO ITEM] Op=%s Val=0x%08h Mask=0x%08h Captured Out=0x%08h OE=0x%08h", op.name(), gpio_val, gpio_mask, gpio_o, gpio_oe);
  endfunction : convert2string
endclass : gpio_seq_item
