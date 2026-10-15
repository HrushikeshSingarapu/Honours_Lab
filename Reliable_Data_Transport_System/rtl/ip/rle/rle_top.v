// =============================================================================
// rle_top.v
//
// PURPOSE:
//   Top-level module for the RLE Compression/Decompression Accelerator.
//   Instantiates:
//     - rle_reg_block  (AXI4-Lite register file and dual 256-byte internal RAM)
//     - rle_controller (FSM sequencer and datapath multiplexer)
//     - rle_encoder    (Run-length compression engine)
//     - rle_decoder    (Run-length expansion engine)
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module rle_top #(
    parameter DATA_WIDTH   = 32,
    parameter ADDR_WIDTH   = 32,
    parameter STRB_WIDTH   = DATA_WIDTH / 8,
    parameter BUFFER_DEPTH = 256
) (
    input  wire                   clk,
    input  wire                   rst,

    // AXI4-Lite Slave Interface
    input  wire [ADDR_WIDTH-1:0]  s_axi_awaddr,
    input  wire [2:0]             s_axi_awprot,
    input  wire                   s_axi_awvalid,
    output wire                   s_axi_awready,

    input  wire [DATA_WIDTH-1:0]  s_axi_wdata,
    input  wire [STRB_WIDTH-1:0]  s_axi_wstrb,
    input  wire                   s_axi_wvalid,
    output wire                   s_axi_wready,

    output wire [1:0]             s_axi_bresp,
    output wire                   s_axi_bvalid,
    input  wire                   s_axi_bready,

    input  wire [ADDR_WIDTH-1:0]  s_axi_araddr,
    input  wire [2:0]             s_axi_arprot,
    input  wire                   s_axi_arvalid,
    output wire                   s_axi_arready,

    output wire [DATA_WIDTH-1:0]  s_axi_rdata,
    output wire [1:0]             s_axi_rresp,
    output wire                   s_axi_rvalid,
    input  wire                   s_axi_rready,

    // Interrupt output
    output wire                   irq
);

    // Controller <-> Reg Block Wires
    wire        ctrl_start;
    wire        ctrl_mode;
    wire [15:0] ctrl_in_len;
    wire        ctrl_busy;
    wire        ctrl_done;
    wire        ctrl_error;
    wire [15:0] ctrl_out_len;

    // Buffer wires between Reg Block and Engines (via Controller)
    wire [15:0] in_rd_addr;
    wire [7:0]  in_rd_data;
    wire        out_wr_en;
    wire [15:0] out_wr_addr;
    wire [7:0]  out_wr_data;

    // Controller <-> Encoder Wires
    wire        enc_start;
    wire        enc_busy;
    wire        enc_done;
    wire        enc_error;
    wire [15:0] enc_out_len;
    wire [15:0] enc_in_rd_addr;
    wire        enc_out_wr_en;
    wire [15:0] enc_out_wr_addr;
    wire [7:0]  enc_out_wr_data;

    // Controller <-> Decoder Wires
    wire        dec_start;
    wire        dec_busy;
    wire        dec_done;
    wire        dec_error;
    wire [15:0] dec_out_len;
    wire [15:0] dec_in_rd_addr;
    wire        dec_out_wr_en;
    wire [15:0] dec_out_wr_addr;
    wire [7:0]  dec_out_wr_data;

    // -------------------------------------------------------------------------
    // Register Block & Buffers
    // -------------------------------------------------------------------------
    rle_reg_block #(
        .DATA_WIDTH   (DATA_WIDTH),
        .ADDR_WIDTH   (ADDR_WIDTH),
        .STRB_WIDTH   (STRB_WIDTH),
        .BUFFER_DEPTH (BUFFER_DEPTH)
    ) u_reg_block (
        .clk            (clk),
        .rst            (rst),

        .s_axi_awaddr   (s_axi_awaddr),
        .s_axi_awprot   (s_axi_awprot),
        .s_axi_awvalid  (s_axi_awvalid),
        .s_axi_awready  (s_axi_awready),

        .s_axi_wdata    (s_axi_wdata),
        .s_axi_wstrb    (s_axi_wstrb),
        .s_axi_wvalid   (s_axi_wvalid),
        .s_axi_wready   (s_axi_wready),

        .s_axi_bresp    (s_axi_bresp),
        .s_axi_bvalid   (s_axi_bvalid),
        .s_axi_bready   (s_axi_bready),

        .s_axi_araddr   (s_axi_araddr),
        .s_axi_arprot   (s_axi_arprot),
        .s_axi_arvalid  (s_axi_arvalid),
        .s_axi_arready  (s_axi_arready),

        .s_axi_rdata    (s_axi_rdata),
        .s_axi_rresp    (s_axi_rresp),
        .s_axi_rvalid   (s_axi_rvalid),
        .s_axi_rready   (s_axi_rready),

        .ctrl_start     (ctrl_start),
        .ctrl_mode      (ctrl_mode),
        .ctrl_in_len    (ctrl_in_len),
        .ctrl_busy      (ctrl_busy),
        .ctrl_done      (ctrl_done),
        .ctrl_error     (ctrl_error),
        .ctrl_out_len   (ctrl_out_len),

        .in_rd_addr     (in_rd_addr),
        .in_rd_data     (in_rd_data),

        .out_wr_en      (out_wr_en),
        .out_wr_addr    (out_wr_addr),
        .out_wr_data    (out_wr_data),

        .irq            (irq)
    );

    // -------------------------------------------------------------------------
    // Orchestration Controller
    // -------------------------------------------------------------------------
    rle_controller #(
        .BUFFER_DEPTH   (BUFFER_DEPTH)
    ) u_controller (
        .clk            (clk),
        .rst            (rst),

        .start          (ctrl_start),
        .mode           (ctrl_mode),
        .in_len         (ctrl_in_len),
        .busy           (ctrl_busy),
        .done           (ctrl_done),
        .error          (ctrl_error),
        .out_len        (ctrl_out_len),

        .enc_start      (enc_start),
        .enc_busy       (enc_busy),
        .enc_done       (enc_done),
        .enc_error      (enc_error),
        .enc_out_len    (enc_out_len),

        .dec_start      (dec_start),
        .dec_busy       (dec_busy),
        .dec_done       (dec_done),
        .dec_error      (dec_error),
        .dec_out_len    (dec_out_len),

        .enc_in_rd_addr (enc_in_rd_addr),
        .dec_in_rd_addr (dec_in_rd_addr),
        .in_rd_addr     (in_rd_addr),

        .enc_out_wr_en  (enc_out_wr_en),
        .enc_out_wr_addr(enc_out_wr_addr),
        .enc_out_wr_data(enc_out_wr_data),

        .dec_out_wr_en  (dec_out_wr_en),
        .dec_out_wr_addr(dec_out_wr_addr),
        .dec_out_wr_data(dec_out_wr_data),

        .out_wr_en      (out_wr_en),
        .out_wr_addr    (out_wr_addr),
        .out_wr_data    (out_wr_data)
    );

    // -------------------------------------------------------------------------
    // Compression Engine
    // -------------------------------------------------------------------------
    rle_encoder #(
        .BUFFER_DEPTH   (BUFFER_DEPTH)
    ) u_encoder (
        .clk            (clk),
        .rst            (rst),

        .start          (enc_start),
        .in_len         (ctrl_in_len),
        .busy           (enc_busy),
        .done           (enc_done),
        .error          (enc_error),
        .out_len        (enc_out_len),

        .in_rd_addr     (enc_in_rd_addr),
        .in_rd_data     (in_rd_data),

        .out_wr_en      (enc_out_wr_en),
        .out_wr_addr    (enc_out_wr_addr),
        .out_wr_data    (enc_out_wr_data)
    );

    // -------------------------------------------------------------------------
    // Decompression Engine
    // -------------------------------------------------------------------------
    rle_decoder #(
        .BUFFER_DEPTH   (BUFFER_DEPTH)
    ) u_decoder (
        .clk            (clk),
        .rst            (rst),

        .start          (dec_start),
        .in_len         (ctrl_in_len),
        .busy           (dec_busy),
        .done           (dec_done),
        .error          (dec_error),
        .out_len        (dec_out_len),

        .in_rd_addr     (dec_in_rd_addr),
        .in_rd_data     (in_rd_data),

        .out_wr_en      (dec_out_wr_en),
        .out_wr_addr    (dec_out_wr_addr),
        .out_wr_data    (dec_out_wr_data)
    );

endmodule
`default_nettype wire
