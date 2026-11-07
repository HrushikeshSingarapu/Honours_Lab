// =============================================================================
// soc_coverage.sv — Functional Coverage Subscriber for SoC Verification
// Collects coverage over observed UART transactions and protocol integrity.
// =============================================================================
`timescale 1ns/1ps

`ifndef SOC_COVERAGE_SV
`define SOC_COVERAGE_SV

class soc_coverage extends uvm_subscriber #(uart_seq_item);
  `uvm_component_utils(soc_coverage)

  uart_seq_item curr_item;

  covergroup cg_uart;
    option.per_instance = 1;
    option.name = "soc_uart_coverage";

    cp_data: coverpoint curr_item.data {
      bins char_H       = {8'h48}; // 'H'
      bins char_I       = {8'h49}; // 'I'
      bins char_A       = {8'h41}; // 'A'
      bins char_B       = {8'h42}; // 'B'
      bins char_C       = {8'h43}; // 'C'
      bins char_1       = {8'h31}; // '1'
      bins char_2       = {8'h32}; // '2'
      bins char_3       = {8'h33}; // '3'
      bins ascii_print  = {[8'h20 : 8'h7E]};
      bins others       = default;
    }

    cp_framing: coverpoint curr_item.framing_err {
      bins no_err = {1'b0};
      bins has_err = {1'b1};
    }

    cross_data_framing: cross cp_data, cp_framing;
  endgroup : cg_uart

  function new(string name = "soc_coverage", uvm_component parent = null);
    super.new(name, parent);
    cg_uart = new();
  endfunction : new

  virtual function void write(uart_seq_item t);
    curr_item = t;
    cg_uart.sample();
  endfunction : write

  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("SOC_COV", $sformatf("UART Functional Coverage: %0.2f%%", cg_uart.get_inst_coverage()), UVM_LOW)
  endfunction : report_phase

endclass : soc_coverage

`endif // SOC_COVERAGE_SV
