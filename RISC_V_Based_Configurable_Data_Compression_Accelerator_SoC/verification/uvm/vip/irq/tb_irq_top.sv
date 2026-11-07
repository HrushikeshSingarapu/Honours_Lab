// =============================================================================
// tb_irq_top.sv — Standalone Sanity Testbench for IRQ VIP
// =============================================================================
`timescale 1ns/1ps

module tb_irq_top;
  import uvm_pkg::*;
  import irq_vip_pkg::*;
  `include "uvm_macros.svh"

  logic clk = 1'b0;
  always #10 clk = ~clk; // 50 MHz

  logic rst_n = 1'b0;
  initial begin
    #100 rst_n = 1'b1;
  end

  // Instantiate Interface
  irq_if vif (.clk(clk), .rst_n(rst_n));
  // Standalone sanity stimulus toggling interrupt lines
  initial begin
    vif.gpio_irq  = 1'b0;
    vif.timer_irq = 1'b0;
    vif.rle_irq   = 1'b0;
    vif.dma_irq   = 1'b0;
    wait (rst_n == 1'b1);
    #100;
    @(posedge clk); vif.timer_irq = 1'b1;
    #200;
    @(posedge clk); vif.timer_irq = 1'b0;
    #100;
    @(posedge clk); vif.dma_irq = 1'b1;
    #200;
    @(posedge clk); vif.dma_irq = 1'b0;
  end


  initial begin
    uvm_config_db#(virtual irq_if)::set(null, "uvm_test_top.*", "vif", vif);
    run_test("irq_test");
  end
endmodule : tb_irq_top
