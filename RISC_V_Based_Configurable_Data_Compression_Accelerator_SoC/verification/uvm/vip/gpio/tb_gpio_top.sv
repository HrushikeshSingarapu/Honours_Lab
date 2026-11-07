// =============================================================================
// tb_gpio_top.sv — Standalone Sanity Testbench for GPIO VIP
// =============================================================================
`timescale 1ns/1ps

module tb_gpio_top;
  import uvm_pkg::*;
  import gpio_vip_pkg::*;
  `include "uvm_macros.svh"

  logic clk = 1'b0;
  always #10 clk = ~clk; // 50 MHz

  logic rst_n = 1'b0;
  initial begin
    #100 rst_n = 1'b1;
  end

  // Instantiate Interface
  gpio_if vif (.clk(clk), .rst_n(rst_n));
  // Loopback gpio_i to gpio_o with OE enabled strictly for standalone VIP verification
  assign vif.gpio_o  = vif.gpio_i;
  assign vif.gpio_oe = 32'hFFFF_FFFF;


  initial begin
    uvm_config_db#(virtual gpio_if)::set(null, "uvm_test_top.*", "vif", vif);
    run_test("gpio_test");
  end
endmodule : tb_gpio_top
