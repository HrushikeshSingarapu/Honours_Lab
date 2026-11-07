// =============================================================================
// uart_cfg.sv — Configuration Object for UART VIP
// =============================================================================
`timescale 1ns/1ps

class uart_cfg extends uvm_object;
  `uvm_object_utils(uart_cfg)

  uvm_active_passive_enum is_active = UVM_ACTIVE;
  virtual uart_if        vif;

  int  baud_rate      = 115200;
  int  clock_freq_hz  = 50_000_000; // 50 MHz default SoC clock
  int  data_bits      = 8;
  int  stop_bits      = 1;

  function int get_cycles_per_bit();
    return (clock_freq_hz / baud_rate);
  endfunction : get_cycles_per_bit

  function new(string name = "uart_cfg");
    super.new(name);
  endfunction : new
endclass : uart_cfg
