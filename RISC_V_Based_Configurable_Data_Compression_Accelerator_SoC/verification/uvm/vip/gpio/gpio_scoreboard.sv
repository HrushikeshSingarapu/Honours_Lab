// =============================================================================
// gpio_scoreboard.sv — Protocol Scoreboard for GPIO VIP
// =============================================================================
// Verification Responsibilities:
// 1. Verifies GPIO output pin state integrity on gpio_o and gpio_oe:
//    - Verifies that pins enabled for output (gpio_oe[i] == 1) do not have unknown (X/Z) states.
// 2. Tracks transition history and updates last observed output state.
//
// Verification Limitation:
// Standalone VIP observes external boundary transitions. Correlation of gpio_o
// with CPU software register writes requires the SoC register reference model.
// =============================================================================
`timescale 1ns/1ps

class gpio_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(gpio_scoreboard)

  uvm_analysis_imp #(gpio_seq_item, gpio_scoreboard) item_export;

  int unsigned transitions_observed = 0;
  int unsigned illegal_x_errors      = 0;
  logic [31:0] last_gpio_o           = 32'h0;
  logic [31:0] last_gpio_oe          = 32'h0;

  function new(string name = "gpio_scoreboard", uvm_component parent = null);
    super.new(name, parent);
    item_export = new("item_export", this);
  endfunction : new

  virtual function void write(gpio_seq_item item);
    transitions_observed++;
    last_gpio_o  = item.gpio_o;
    last_gpio_oe = item.gpio_oe;

    // Check for X/Z states on active enabled output pins
    for (int i = 0; i < 32; i++) begin
      if (item.gpio_oe[i] == 1'b1) begin
        if (item.gpio_o[i] !== 1'b0 && item.gpio_o[i] !== 1'b1) begin
          illegal_x_errors++;
          `uvm_error("GPIO_XZ_ERR", $sformatf("Illegal X/Z state on enabled GPIO output pin %0d: %b", i, item.gpio_o[i]))
        end
      end
    end

    `uvm_info("GPIO_SCB", $sformatf("GPIO Transition #%0d: Out=0x%08h, OE=0x%08h", transitions_observed, item.gpio_o, item.gpio_oe), UVM_MEDIUM)
  endfunction : write

  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("GPIO_SCB_RPT", "==================================================", UVM_LOW)
    `uvm_info("GPIO_SCB_RPT", $sformatf(" Total GPIO transitions observed : %0d", transitions_observed), UVM_LOW)
    `uvm_info("GPIO_SCB_RPT", $sformatf(" Illegal X/Z errors              : %0d", illegal_x_errors), UVM_LOW)
    `uvm_info("GPIO_SCB_RPT", $sformatf(" Final Output State              : 0x%08h (OE=0x%08h)", last_gpio_o, last_gpio_oe), UVM_LOW)
    `uvm_info("GPIO_SCB_RPT", "==================================================", UVM_LOW)
  endfunction : report_phase
endclass : gpio_scoreboard
