// =============================================================================
// tb_uart_top.sv — Standalone Sanity Testbench for UART VIP
// =============================================================================
`timescale 1ns/1ps

module tb_uart_top;
  import uvm_pkg::*;
  import uart_vip_pkg::*;
  `include "uvm_macros.svh"

  logic clk = 1'b0;
  always #10 clk = ~clk; // 50 MHz

  logic rst_n = 1'b0;
  initial begin
    #100 rst_n = 1'b1;
  end

  // Instantiate Interface
  uart_if vif (.clk(clk), .rst_n(rst_n));
  // Loopback RX to TX strictly for standalone VIP sanity verification
  assign vif.uart_tx = vif.uart_rx;


  initial begin
    uvm_config_db#(virtual uart_if)::set(null, "uvm_test_top.*", "vif", vif);
    run_test("uart_test");
  end
endmodule : tb_uart_top
