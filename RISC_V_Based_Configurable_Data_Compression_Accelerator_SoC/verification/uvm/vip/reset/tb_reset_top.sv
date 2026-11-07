// =============================================================================
// tb_reset_top.sv — Standalone Sanity Testbench for RESET VIP
// =============================================================================
`timescale 1ns/1ps

module tb_reset_top;
  import uvm_pkg::*;
  import reset_vip_pkg::*;
  `include "uvm_macros.svh"

  logic clk = 1'b0;
  always #10 clk = ~clk; // 50 MHz

  // Instantiate Interface
  reset_if vif (.clk(clk));

  initial begin
    uvm_config_db#(virtual reset_if)::set(null, "uvm_test_top.*", "vif", vif);
    run_test("reset_test");
  end
endmodule : tb_reset_top
