// =============================================================================
// rle_encoder.v
//
// PURPOSE:
//   Lossless Run-Length Encoder for 8-bit symbols.
//   Takes input bytes from input buffer, compresses into [count, symbol] pairs.
//   Maximum run count per record is 255 (8-bit). Runs > 255 are split.
//   Detects output buffer overflow (out_len > BUFFER_DEPTH).
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module rle_encoder #(
    parameter BUFFER_DEPTH = 256
) (
    input  wire                   clk,
    input  wire                   rst,

    // Control from controller
    input  wire                   start,
    input  wire [15:0]            in_len,
    output reg                    busy,
    output reg                    done,
    output reg                    error,
    output reg  [15:0]            out_len,

    // Input buffer read interface
    output reg  [15:0]            in_rd_addr,
    input  wire [7:0]             in_rd_data,

    // Output buffer write interface
    output reg                    out_wr_en,
    output reg  [15:0]            out_wr_addr,
    output reg  [7:0]             out_wr_data
);

    localparam S_IDLE       = 3'd0;
    localparam S_INIT       = 3'd1;
    localparam S_PROC       = 3'd2;
    localparam S_EMIT_CNT   = 3'd3;
    localparam S_EMIT_SYM   = 3'd4;
    localparam S_DONE       = 3'd5;

    reg [2:0]  state;
    reg [15:0] in_idx;
    reg [7:0]  cur_sym;
    reg [7:0]  cur_cnt;
    reg [7:0]  pend_sym;
    reg [7:0]  pend_cnt;
    reg        last_record;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state       <= S_IDLE;
            busy        <= 1'b0;
            done        <= 1'b0;
            error       <= 1'b0;
            out_len     <= 16'd0;
            in_rd_addr  <= 16'd0;
            out_wr_en   <= 1'b0;
            out_wr_addr <= 16'd0;
            out_wr_data <= 8'd0;
            in_idx      <= 16'd0;
            cur_sym     <= 8'd0;
            cur_cnt     <= 8'd0;
            pend_sym    <= 8'd0;
            pend_cnt    <= 8'd0;
            last_record <= 1'b0;
        end else begin
            out_wr_en <= 1'b0;

            case (state)
                S_IDLE: begin
                    done  <= 1'b0;
                    error <= 1'b0;
                    if (start) begin
                        busy        <= 1'b1;
                        out_len     <= 16'd0;
                        last_record <= 1'b0;
                        pend_cnt    <= 8'd0;
                        if (in_len == 16'd0) begin
                            state <= S_DONE;
                        end else begin
                            in_rd_addr <= 16'd0;
                            state      <= S_INIT;
                        end
                    end else begin
                        busy <= 1'b0;
                    end
                end

                S_INIT: begin
                    cur_sym <= in_rd_data;
                    cur_cnt <= 8'd1;
                    if (in_len == 16'd1) begin
                        last_record <= 1'b1;
                        state       <= S_EMIT_CNT;
                    end else begin
                        in_rd_addr <= 16'd1;
                        in_idx     <= 16'd1;
                        state      <= S_PROC;
                    end
                end

                S_PROC: begin
                    if ((in_rd_data == cur_sym) && (cur_cnt < 8'd255)) begin
                        cur_cnt <= cur_cnt + 8'd1;
                        if (in_idx + 16'd1 < in_len) begin
                            in_rd_addr <= in_idx + 16'd1;
                            in_idx     <= in_idx + 16'd1;
                        end else begin
                            last_record <= 1'b1;
                            state       <= S_EMIT_CNT;
                        end
                    end else begin
                        // Run boundary reached
                        pend_sym <= in_rd_data;
                        pend_cnt <= 8'd1;
                        if (in_idx + 16'd1 < in_len) begin
                            in_rd_addr  <= in_idx + 16'd1;
                            in_idx      <= in_idx + 16'd1;
                            last_record <= 1'b0;
                        end else begin
                            last_record <= 1'b1;
                        end
                        state <= S_EMIT_CNT;
                    end
                end

                S_EMIT_CNT: begin
                    if (out_len >= BUFFER_DEPTH) begin
                        error <= 1'b1;
                        state <= S_DONE;
                    end else begin
                        out_wr_en   <= 1'b1;
                        out_wr_addr <= out_len;
                        out_wr_data <= cur_cnt;
                        out_len     <= out_len + 16'd1;
                        state       <= S_EMIT_SYM;
                    end
                end

                S_EMIT_SYM: begin
                    if (out_len >= BUFFER_DEPTH) begin
                        error <= 1'b1;
                        state <= S_DONE;
                    end else begin
                        out_wr_en   <= 1'b1;
                        out_wr_addr <= out_len;
                        out_wr_data <= cur_sym;
                        out_len     <= out_len + 16'd1;

                        if (last_record && (pend_cnt == 8'd0)) begin
                            state <= S_DONE;
                        end else if (last_record && (pend_cnt == 8'd1)) begin
                            cur_sym  <= pend_sym;
                            cur_cnt  <= 8'd1;
                            pend_cnt <= 8'd0;
                            state    <= S_EMIT_CNT;
                        end else begin
                            cur_sym  <= pend_sym;
                            cur_cnt  <= 8'd1;
                            pend_cnt <= 8'd0;
                            state    <= S_PROC;
                        end
                    end
                end

                S_DONE: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
`default_nettype wire
