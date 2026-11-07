// =============================================================================
// uart_base_seq.sv — Base Sequence for UART VIP
// =============================================================================
`timescale 1ns/1ps

class uart_base_seq extends uvm_sequence #(uart_seq_item);
  `uvm_object_utils(uart_base_seq)

  function new(string name = "uart_base_seq");
    super.new(name);
  endfunction : new

  virtual task body();
    `uvm_info(get_type_name(), "Executing UART base sequence (sending characters)", UVM_LOW)
    req = uart_seq_item::type_id::create("req");
    start_item(req);
    req.data = 8'h41; // 'A'
    req.baud_rate = 115200;
    req.stop_bits = 1;
    req.parity = uart_seq_item::PARITY_NONE;
    finish_item(req);

    req = uart_seq_item::type_id::create("req");
    start_item(req);
    req.data = 8'h42; // 'B'
    req.baud_rate = 115200;
    req.stop_bits = 1;
    req.parity = uart_seq_item::PARITY_NONE;
    finish_item(req);
  endtask : body
endclass : uart_base_seq
