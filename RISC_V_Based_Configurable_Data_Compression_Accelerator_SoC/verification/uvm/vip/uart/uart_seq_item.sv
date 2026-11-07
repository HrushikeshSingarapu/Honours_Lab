// =============================================================================
// uart_seq_item.sv — Sequence Item for UART VIP
// =============================================================================
`timescale 1ns/1ps

class uart_seq_item extends uvm_sequence_item;

  typedef enum bit [2:0] {
    PARITY_NONE  = 3'b000,
    PARITY_ODD   = 3'b001,
    PARITY_EVEN  = 3'b010,
    PARITY_MARK  = 3'b011,
    PARITY_SPACE = 3'b100
  } uart_parity_e;

  rand bit [7:0]      data;            // 8-bit character payload
  rand int            baud_rate;       // Target baud rate (default 115200)
  rand int            stop_bits;       // 1 or 2 stop bits
  rand uart_parity_e  parity;          // Parity configuration
  rand bit            inject_parity_err;  // Inject intentional parity error
  rand bit            inject_framing_err; // Inject framing error (bad stop bit)

  bit                 parity_err;      // Captured parity error on RX
  bit                 framing_err;     // Captured framing error on RX
  time                timestamp;

  constraint c_uart_defaults {
    baud_rate == 115200;
    stop_bits inside {1, 2};
    parity == PARITY_NONE;
    inject_parity_err == 1'b0;
    inject_framing_err == 1'b0;
  }

  `uvm_object_utils(uart_seq_item)

  function new(string name = "uart_seq_item");
    super.new(name);
  endfunction : new

  virtual function string convert2string();
    return $sformatf("[UART ITEM] Char=0x%02h ('%c') Baud=%0d Parity=%s", data, ((data >= 32 && data < 127) ? data : 8'h2e), baud_rate, parity.name());
  endfunction : convert2string
endclass : uart_seq_item
