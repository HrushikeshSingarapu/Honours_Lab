// =============================================================================
// gpio_base_seq.sv — Base Sequence for GPIO VIP
// =============================================================================
`timescale 1ns/1ps

class gpio_base_seq extends uvm_sequence #(gpio_seq_item);
  `uvm_object_utils(gpio_base_seq)

  function new(string name = "gpio_base_seq");
    super.new(name);
  endfunction : new

  virtual task body();
    `uvm_info(get_type_name(), "Executing GPIO base sequence (setting gpio_i)", UVM_LOW)
    req = gpio_seq_item::type_id::create("req");
    start_item(req);
    req.op = gpio_seq_item::GPIO_DRIVE_ALL;
    req.gpio_val = 32'hA5A5_5A5A;
    req.gpio_mask = 32'hFFFF_FFFF;
    finish_item(req);
  endtask : body
endclass : gpio_base_seq
