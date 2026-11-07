// =============================================================================
// reset_scoreboard.sv — Protocol Scoreboard for RESET VIP
// =============================================================================
// Verification Responsibilities:
// 1. Verifies reset pulse width constraints:
//    - Ensures reset assertions meet the minimum required duration (>= 4 clock cycles).
// 2. Tracks total reset cycles and assertion events.
//
// Verification Limitation:
// Verifies external physical rst_n behavior. Internal reset propagation across
// AXI bridges and peripheral clock domains is checked at SoC integration.
// =============================================================================
`timescale 1ns/1ps

class reset_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(reset_scoreboard)

  uvm_analysis_imp #(reset_seq_item, reset_scoreboard) item_export;

  int unsigned reset_events_observed = 0;
  int unsigned short_pulse_errors    = 0;
  int unsigned total_reset_cycles    = 0;

  function new(string name = "reset_scoreboard", uvm_component parent = null);
    super.new(name, parent);
    item_export = new("item_export", this);
  endfunction : new

  virtual function void write(reset_seq_item item);
    reset_events_observed++;
    total_reset_cycles += item.duration_cycles;

    if (item.duration_cycles < 4) begin
      short_pulse_errors++;
      `uvm_error("RST_SHORT_PULSE", $sformatf("Reset pulse too short: %0d cycles (min required: 4 cycles)", item.duration_cycles))
    end else begin
      `uvm_info("RESET_SCB", $sformatf("Reset assertion verified: %0d cycles at %0t", item.duration_cycles, item.timestamp), UVM_MEDIUM)
    end
  endfunction : write

  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("RESET_SCB_RPT", "==================================================", UVM_LOW)
    `uvm_info("RESET_SCB_RPT", $sformatf(" Total Reset Events Verified : %0d", reset_events_observed), UVM_LOW)
    `uvm_info("RESET_SCB_RPT", $sformatf(" Total Reset Cycles          : %0d", total_reset_cycles), UVM_LOW)
    `uvm_info("RESET_SCB_RPT", $sformatf(" Short Pulse Errors          : %0d", short_pulse_errors), UVM_LOW)
    `uvm_info("RESET_SCB_RPT", "==================================================", UVM_LOW)
  endfunction : report_phase
endclass : reset_scoreboard
