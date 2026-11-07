// =============================================================================
// axi_monitor_if.sv — Passive SystemVerilog Interface for AXI4 Bus Monitoring
// Connects non-intrusively to AXI master and slave channels across the SoC fabric.
// Strictly passive: all interface pins are input wires with default values.
// Includes testbench instrumentation debug markers for clear waveform visibility.
// =============================================================================
`timescale 1ns/1ps

`ifndef AXI_MONITOR_IF_SV
`define AXI_MONITOR_IF_SV

interface axi_monitor_if #(
  parameter DATA_WIDTH = 32,
  parameter ADDR_WIDTH = 32,
  parameter ID_WIDTH   = 8,
  parameter USER_WIDTH = 1
)(
  input wire                            clk,
  input wire                            rst_n,

  // Write Address Channel (AW)
  input wire [ID_WIDTH-1:0]             awid     = '0,
  input wire [ADDR_WIDTH-1:0]           awaddr   = '0,
  input wire [7:0]                      awlen    = 8'h0,
  input wire [2:0]                      awsize   = 3'h0,
  input wire [1:0]                      awburst  = 2'h0,
  input wire                            awlock   = 1'b0,
  input wire [3:0]                      awcache  = 4'h0,
  input wire [2:0]                      awprot   = 3'h0,
  input wire [3:0]                      awqos    = 4'h0,
  input wire [3:0]                      awregion = 4'h0,
  input wire [USER_WIDTH-1:0]           awuser   = '0,
  input wire                            awvalid  = 1'b0,
  input wire                            awready  = 1'b0,

  // Write Data Channel (W)
  input wire [DATA_WIDTH-1:0]           wdata    = '0,
  input wire [(DATA_WIDTH/8)-1:0]       wstrb    = '0,
  input wire                            wlast    = 1'b0,
  input wire [USER_WIDTH-1:0]           wuser    = '0,
  input wire                            wvalid   = 1'b0,
  input wire                            wready   = 1'b0,

  // Write Response Channel (B)
  input wire [ID_WIDTH-1:0]             bid      = '0,
  input wire [1:0]                      bresp    = 2'h0,
  input wire [USER_WIDTH-1:0]           buser    = '0,
  input wire                            bvalid   = 1'b0,
  input wire                            bready   = 1'b0,

  // Read Address Channel (AR)
  input wire [ID_WIDTH-1:0]             arid     = '0,
  input wire [ADDR_WIDTH-1:0]           araddr   = '0,
  input wire [7:0]                      arlen    = 8'h0,
  input wire [2:0]                      arsize   = 3'h0,
  input wire [1:0]                      arburst  = 2'h0,
  input wire                            arlock   = 1'b0,
  input wire [3:0]                      arcache  = 4'h0,
  input wire [2:0]                      arprot   = 3'h0,
  input wire [3:0]                      arqos    = 4'h0,
  input wire [3:0]                      arregion = 4'h0,
  input wire [USER_WIDTH-1:0]           aruser   = '0,
  input wire                            arvalid  = 1'b0,
  input wire                            arready  = 1'b0,

  // Read Data Channel (R)
  input wire [ID_WIDTH-1:0]             rid      = '0,
  input wire [DATA_WIDTH-1:0]           rdata    = '0,
  input wire [1:0]                      rresp    = 2'h0,
  input wire                            rlast    = 1'b0,
  input wire [USER_WIDTH-1:0]           ruser    = '0,
  input wire                            rvalid   = 1'b0,
  input wire                            rready   = 1'b0
);

  // ---------------------------------------------------------------------------
  // Testbench Instrumentation Debug Markers (Non-DUT signals for GTKWave)
  // ---------------------------------------------------------------------------
  wire tb_marker_aw_handshake = awvalid && awready;
  wire tb_marker_w_handshake  = wvalid  && wready;
  wire tb_marker_b_handshake  = bvalid  && bready;
  wire tb_marker_ar_handshake = arvalid && arready;
  wire tb_marker_r_handshake  = rvalid  && rready;

  modport monitor_mp (
    input clk,
    input rst_n,
    input awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos, awregion, awuser, awvalid, awready,
    input wdata, wstrb, wlast, wuser, wvalid, wready,
    input bid, bresp, buser, bvalid, bready,
    input arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arqos, arregion, aruser, arvalid, arready,
    input rid, rdata, rresp, rlast, ruser, rvalid, rready,
    input tb_marker_aw_handshake, tb_marker_w_handshake, tb_marker_b_handshake,
    input tb_marker_ar_handshake, tb_marker_r_handshake
  );

endinterface : axi_monitor_if

`endif // AXI_MONITOR_IF_SV
