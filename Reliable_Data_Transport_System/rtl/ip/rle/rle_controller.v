// =============================================================================
// rle_controller.v
//
// PURPOSE:
//   FSM and orchestration controller for RLE accelerator.
//   Multiplexes between rle_encoder (MODE=0) and rle_decoder (MODE=1).
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module rle_controller #(
    parameter BUFFER_DEPTH = 256
) (
    input  wire                   clk,
    input  wire                   rst,

    // Command from reg block
    input  wire                   start,
    input  wire                   mode,         // 0: compress, 1: decompress
    input  wire [15:0]            in_len,
    output wire                   busy,
    output wire                   done,
    output wire                   error,
    output wire [15:0]            out_len,

    // Encoder interface
    output wire                   enc_start,
    input  wire                   enc_busy,
    input  wire                   enc_done,
    input  wire                   enc_error,
    input  wire [15:0]            enc_out_len,

    // Decoder interface
    output wire                   dec_start,
    input  wire                   dec_busy,
    input  wire                   dec_done,
    input  wire                   dec_error,
    input  wire [15:0]            dec_out_len,

    // Buffer multiplexing
    input  wire [15:0]            enc_in_rd_addr,
    input  wire [15:0]            dec_in_rd_addr,
    output wire [15:0]            in_rd_addr,

    input  wire                   enc_out_wr_en,
    input  wire [15:0]            enc_out_wr_addr,
    input  wire [7:0]             enc_out_wr_data,

    input  wire                   dec_out_wr_en,
    input  wire [15:0]            dec_out_wr_addr,
    input  wire [7:0]             dec_out_wr_data,

    output wire                   out_wr_en,
    output wire [15:0]            out_wr_addr,
    output wire [7:0]             out_wr_data
);

    reg active_mode;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            active_mode <= 1'b0;
        end else if (start) begin
            active_mode <= mode;
        end
    end

    wire cur_mode = start ? mode : active_mode;

    assign enc_start = start & (~mode);
    assign dec_start = start & mode;

    assign busy    = (cur_mode == 1'b0) ? enc_busy    : dec_busy;
    assign done    = (cur_mode == 1'b0) ? enc_done    : dec_done;
    assign error   = (cur_mode == 1'b0) ? enc_error   : dec_error;
    assign out_len = (cur_mode == 1'b0) ? enc_out_len : dec_out_len;

    assign in_rd_addr = (cur_mode == 1'b0) ? enc_in_rd_addr : dec_in_rd_addr;

    assign out_wr_en   = (cur_mode == 1'b0) ? enc_out_wr_en   : dec_out_wr_en;
    assign out_wr_addr = (cur_mode == 1'b0) ? enc_out_wr_addr : dec_out_wr_addr;
    assign out_wr_data = (cur_mode == 1'b0) ? enc_out_wr_data : dec_out_wr_data;

endmodule
`default_nettype wire
