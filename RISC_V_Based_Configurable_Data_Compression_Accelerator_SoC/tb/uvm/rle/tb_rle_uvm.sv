// =============================================================================
// tb_rle_uvm.sv — Top-Level UVM 1.2 Testbench for RLE Accelerator
// =============================================================================
`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"
import rle_uvm_pkg::*;

module tb_rle_uvm;

    logic clk;
    logic rst;

    // Clock generator: 100 MHz (10 ns period)
    always #5 clk = ~clk;

    // Interface
    rle_axi_if axi_if (clk, rst);

    // DUT Instantiation
    rle_top #(
        .DATA_WIDTH   (32),
        .ADDR_WIDTH   (32),
        .STRB_WIDTH   (4),
        .BUFFER_DEPTH (512)
    ) u_dut (
        .clk           (clk),
        .rst           (rst),
        .s_axi_awaddr  (axi_if.s_axi_awaddr),
        .s_axi_awprot  (axi_if.s_axi_awprot),
        .s_axi_awvalid (axi_if.s_axi_awvalid),
        .s_axi_awready (axi_if.s_axi_awready),
        .s_axi_wdata   (axi_if.s_axi_wdata),
        .s_axi_wstrb   (axi_if.s_axi_wstrb),
        .s_axi_wvalid  (axi_if.s_axi_wvalid),
        .s_axi_wready  (axi_if.s_axi_wready),
        .s_axi_bresp   (axi_if.s_axi_bresp),
        .s_axi_bvalid  (axi_if.s_axi_bvalid),
        .s_axi_bready  (axi_if.s_axi_bready),
        .s_axi_araddr  (axi_if.s_axi_araddr),
        .s_axi_arprot  (axi_if.s_axi_arprot),
        .s_axi_arvalid (axi_if.s_axi_arvalid),
        .s_axi_arready (axi_if.s_axi_arready),
        .s_axi_rdata   (axi_if.s_axi_rdata),
        .s_axi_rresp   (axi_if.s_axi_rresp),
        .s_axi_rvalid  (axi_if.s_axi_rvalid),
        .s_axi_rready  (axi_if.s_axi_rready),
        .irq           (axi_if.irq)
    );

    // =========================================================================
    // Protocol Assertions
    // =========================================================================
    axi_protocol_assertions #(
        .NAME ("RLE_AXI")
    ) u_axi_assert (
        .clk     (clk),
        .rst_n   (!rst),
        .awvalid (axi_if.s_axi_awvalid),
        .awready (axi_if.s_axi_awready),
        .awaddr  (axi_if.s_axi_awaddr),
        .awprot  (axi_if.s_axi_awprot),
        .wvalid  (axi_if.s_axi_wvalid),
        .wready  (axi_if.s_axi_wready),
        .wdata   (axi_if.s_axi_wdata),
        .wstrb   (axi_if.s_axi_wstrb),
        .bvalid  (axi_if.s_axi_bvalid),
        .bready  (axi_if.s_axi_bready),
        .bresp   (axi_if.s_axi_bresp),
        .arvalid (axi_if.s_axi_arvalid),
        .arready (axi_if.s_axi_arready),
        .araddr  (axi_if.s_axi_araddr),
        .arprot  (axi_if.s_axi_arprot),
        .rvalid  (axi_if.s_axi_rvalid),
        .rready  (axi_if.s_axi_rready),
        .rdata   (axi_if.s_axi_rdata),
        .rresp   (axi_if.s_axi_rresp)
    );

    rle_protocol_assertions #(
        .NAME ("RLE_PROTO"),
        .MAX_BUFFER_DEPTH (512)
    ) u_rle_assert (
        .clk           (clk),
        .rst           (rst),
        .s_axi_awvalid (axi_if.s_axi_awvalid),
        .s_axi_awready (axi_if.s_axi_awready),
        .s_axi_awaddr  (axi_if.s_axi_awaddr),
        .s_axi_wvalid  (axi_if.s_axi_wvalid),
        .s_axi_wready  (axi_if.s_axi_wready),
        .s_axi_wdata   (axi_if.s_axi_wdata),
        .s_axi_wstrb   (axi_if.s_axi_wstrb),
        .s_axi_bvalid  (axi_if.s_axi_bvalid),
        .s_axi_bready  (axi_if.s_axi_bready),
        .s_axi_bresp   (axi_if.s_axi_bresp),
        .s_axi_arvalid (axi_if.s_axi_arvalid),
        .s_axi_arready (axi_if.s_axi_arready),
        .s_axi_araddr  (axi_if.s_axi_araddr),
        .s_axi_rvalid  (axi_if.s_axi_rvalid),
        .s_axi_rready  (axi_if.s_axi_rready),
        .s_axi_rdata   (axi_if.s_axi_rdata),
        .s_axi_rresp   (axi_if.s_axi_rresp),
        .irq           (axi_if.irq)
    );

    initial begin
        rst = 1;
        repeat (10) @(posedge clk);
        #1;
        rst = 0;
    end

    initial begin
        clk = 0;
        // Register virtual interface in UVM config database
        uvm_config_db#(virtual rle_axi_if)::set(null, "*", "vif", axi_if);
        // Start UVM run phase at time 0
        run_test("rle_test");
    end

    final begin
        $display("-----------------------------------------------------------------");
        $display("[ASSERTION REPORT] RLE AXI Protocol Errors       : %0d", u_axi_assert.get_total_assertion_errors());
        $display("[ASSERTION REPORT] RLE Protocol Errors           : %0d", u_rle_assert.get_total_assertion_errors());
        if (u_axi_assert.get_total_assertion_errors() == 0 && u_rle_assert.get_total_assertion_errors() == 0) begin
            $display("[ASSERTION STATUS] ALL PROTOCOL ASSERTIONS PASSED CLEANLY (0 Errors)");
        end else begin
            $display("[ASSERTION STATUS] FAIL: Assertion errors detected!");
        end
        $display("-----------------------------------------------------------------");
    end

endmodule
