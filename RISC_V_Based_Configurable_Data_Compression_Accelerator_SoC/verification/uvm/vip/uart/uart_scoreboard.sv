// =============================================================================
// uart_scoreboard.sv — Protocol Scoreboard for UART VIP
// =============================================================================
// Verification Responsibilities:
// 1. Verifies UART frame protocol integrity on monitored TX output:
//    - Flags UVM_ERROR on stop bit / framing error.
//    - Flags UVM_ERROR on parity error when parity checking is active.
// 2. Records stream of received characters in captured_chars queue.
// 3. Supports optional expected character queue matching (expected_chars[$]).
//
// Verification Limitation:
// Standalone VIP does not automatically loop back RX to TX at the pin level.
// Direct comparison of transmitted RX items against TX items requires
// SoC software echo firmware or an external loopback model.
// =============================================================================
`timescale 1ns/1ps

class uart_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(uart_scoreboard)

  uvm_analysis_imp #(uart_seq_item, uart_scoreboard) item_export;

  int unsigned items_received  = 0;
  int unsigned framing_errors  = 0;
  int unsigned parity_errors   = 0;
  byte unsigned captured_chars[$];
  byte unsigned expected_chars[$];

  function new(string name = "uart_scoreboard", uvm_component parent = null);
    super.new(name, parent);
    item_export = new("item_export", this);
  endfunction : new

  virtual function void write(uart_seq_item item);
    items_received++;
    captured_chars.push_back(item.data);

    // 1. Protocol Frame Checks
    if (item.framing_err) begin
      framing_errors++;
      `uvm_error("UART_FRAMING_ERR", $sformatf("Framing error detected at %0t on byte 0x%02h", item.timestamp, item.data))
    end
    if (item.parity_err) begin
      parity_errors++;
      `uvm_error("UART_PARITY_ERR", $sformatf("Parity error detected at %0t on byte 0x%02h", item.timestamp, item.data))
    end

    // 2. Expected byte matching (if populated)
    if (expected_chars.size() > 0) begin
      byte exp = expected_chars.pop_front();
      if (item.data !== exp) begin
        `uvm_error("UART_MISMATCH", $sformatf("UART Char mismatch: exp=0x%02h ('%c'), act=0x%02h ('%c')", exp, exp, item.data, item.data))
      end else begin
        `uvm_info("UART_MATCH", $sformatf("UART Char matched: 0x%02h ('%c')", item.data, item.data), UVM_HIGH)
      end
    end else begin
      `uvm_info("UART_SCB", $sformatf("Monitored UART byte #%0d: 0x%02h ('%c')", items_received, item.data, ((item.data >= 32 && item.data < 127) ? item.data : 8'h2e)), UVM_MEDIUM)
    end
  endfunction : write

  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("UART_SCB_RPT", "==================================================", UVM_LOW)
    `uvm_info("UART_SCB_RPT", $sformatf(" Total UART bytes captured : %0d", items_received), UVM_LOW)
    `uvm_info("UART_SCB_RPT", $sformatf(" Framing Errors           : %0d", framing_errors), UVM_LOW)
    `uvm_info("UART_SCB_RPT", $sformatf(" Parity Errors            : %0d", parity_errors), UVM_LOW)
    `uvm_info("UART_SCB_RPT", "==================================================", UVM_LOW)
  endfunction : report_phase
endclass : uart_scoreboard
