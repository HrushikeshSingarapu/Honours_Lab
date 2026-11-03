// =============================================================================
// rle_axi_if.sv — Dedicated AXI4-Lite Interface for RLE Accelerator
// =============================================================================
`timescale 1ns/1ps

interface rle_axi_if (
    input wire clk,
    input wire rst
);
    // AXI4-Lite Address Write Channel
    logic [31:0] s_axi_awaddr;
    logic [2:0]  s_axi_awprot;
    logic        s_axi_awvalid;
    logic        s_axi_awready;

    // AXI4-Lite Data Write Channel
    logic [31:0] s_axi_wdata;
    logic [3:0]  s_axi_wstrb;
    logic        s_axi_wvalid;
    logic        s_axi_wready;

    // AXI4-Lite Write Response Channel
    logic [1:0]  s_axi_bresp;
    logic        s_axi_bvalid;
    logic        s_axi_bready;

    // AXI4-Lite Address Read Channel
    logic [31:0] s_axi_araddr;
    logic [2:0]  s_axi_arprot;
    logic        s_axi_arvalid;
    logic        s_axi_arready;

    // AXI4-Lite Data Read Channel
    logic [31:0] s_axi_rdata;
    logic [1:0]  s_axi_rresp;
    logic        s_axi_rvalid;
    logic        s_axi_rready;

    // Interrupt Line
    logic        irq;

endinterface: rle_axi_if

