// =============================================================================
// uart_echo_seq.sv — Deterministic UART RX Stimulus Sequence for Echo Verification
// Sends characters "ABC123" into SoC UART RX line with inter-frame spacing.
// =============================================================================
`timescale 1ns/1ps

`ifndef UART_ECHO_SEQ_SV
`define UART_ECHO_SEQ_SV

class uart_echo_seq extends uvm_sequence #(uart_seq_item);
  `uvm_object_utils(uart_echo_seq)

  // Test character payload sequence
  byte test_chars[] = '{8'h41, 8'h42, 8'h43, 8'h31, 8'h32, 8'h33}; // "ABC123"

  // Inter-frame gap in nanoseconds (allow CPU to process and echo character)
  int inter_frame_delay_ns = 120_000; // 120 us (~14 bit times at 115200 baud)

  function new(string name = "uart_echo_seq");
    super.new(name);
  endfunction : new

  virtual task body();
    `uvm_info("UART_ECHO_SEQ", $sformatf("Starting UART Echo Sequence: sending %0d characters (\"ABC123\")", test_chars.size()), UVM_LOW)

    // Initial stabilization delay after reset (ensure VeeR core finishes boot and enters main loop)
    #10_000ns;

    for (int i = 0; i < test_chars.size(); i++) begin
      req = uart_seq_item::type_id::create($sformatf("item_%0d", i));
      start_item(req);
      req.data               = test_chars[i];
      req.baud_rate          = 115200;
      req.stop_bits          = 1;
      req.parity             = uart_seq_item::PARITY_NONE;
      req.inject_parity_err  = 1'b0;
      req.inject_framing_err = 1'b0;
      finish_item(req);

      `uvm_info("UART_ECHO_SEQ",
                $sformatf("[UART_ECHO_SEQ] Injected char #%0d: '%c' (0x%02h) into DUT uart_rx line at %0t ps",
                          i + 1, test_chars[i], test_chars[i], $time),
                UVM_LOW)

      // Allow CPU firmware time to poll RX, read RBR, and initiate TX echo
      #(inter_frame_delay_ns * 1ns);
    end

    `uvm_info("UART_ECHO_SEQ", "Completed injection of all echo characters into DUT uart_rx.", UVM_LOW)
  endtask : body

endclass : uart_echo_seq

`endif // UART_ECHO_SEQ_SV
