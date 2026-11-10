// =============================================================================
// soc_uart_echo_fast_seq.sv — High-Speed UART RX Stimulus Sequence (2 Mbaud)
// Injects interactive RX character into DUT uart_rx for echo verification.
// =============================================================================
`timescale 1ns/1ps

`ifndef SOC_UART_ECHO_FAST_SEQ_SV
`define SOC_UART_ECHO_FAST_SEQ_SV

class soc_uart_echo_fast_seq extends uvm_sequence #(uart_seq_item);
  `uvm_object_utils(soc_uart_echo_fast_seq)

  byte tx_char   = 8'h4B; // 'K'
  int  baud_rate = 2_000_000;

  function new(string name = "soc_uart_echo_fast_seq");
    super.new(name);
  endfunction : new

  virtual task body();
    `uvm_info("SOC_UART_SEQ", $sformatf("Sending UART RX char '%c' (0x%02h) at %0d bps...", tx_char, tx_char, baud_rate), UVM_LOW)
    req = uart_seq_item::type_id::create("fast_rx_char");
    start_item(req);
    req.data               = tx_char;
    req.baud_rate          = baud_rate;
    req.stop_bits          = 1;
    req.parity             = uart_seq_item::PARITY_NONE;
    req.inject_parity_err  = 1'b0;
    req.inject_framing_err = 1'b0;
    finish_item(req);
  endtask : body

endclass : soc_uart_echo_fast_seq

`endif // SOC_UART_ECHO_FAST_SEQ_SV
