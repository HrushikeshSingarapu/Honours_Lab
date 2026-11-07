// =============================================================================
// rle_decoder.v
//
// PURPOSE:
//   Lossless Run-Length Decoder for 8-bit symbols.
//   Expects inputs in [count, symbol] pairs.
//   Validates:
//     - in_len must be even (odd length -> error)
//     - count must be > 0 (zero count -> error)
//     - out_len + count <= BUFFER_DEPTH (overflow -> error)
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module rle_decoder #(
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
    localparam S_FETCH_CNT  = 3'd1;
    localparam S_READ_CNT   = 3'd2;
    localparam S_FETCH_SYM  = 3'd3;
    localparam S_READ_SYM   = 3'd4;
    localparam S_EXPAND     = 3'd5;
    localparam S_DONE       = 3'd6;

    reg [2:0]  state;
    reg [15:0] in_idx;
    reg [7:0]  cur_cnt;
    reg [7:0]  cur_sym;
    reg [7:0]  expand_cnt;

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
            cur_cnt     <= 8'd0;
            cur_sym     <= 8'd0;
            expand_cnt  <= 8'd0;
        end else begin
            out_wr_en <= 1'b0;

            case (state)
                S_IDLE: begin
                    done  <= 1'b0;
                    error <= 1'b0;
                    if (start) begin
                        busy    <= 1'b1;
                        out_len <= 16'd0;
                        in_idx  <= 16'd0;
                        if (in_len == 16'd0) begin
                            // Empty input stream
                            state <= S_DONE;
                        end else if (in_len[0] != 1'b0) begin
                            // Error: odd length input stream
                            error <= 1'b1;
                            state <= S_DONE;
                        end else begin
                            in_rd_addr <= 16'd0;
                            state      <= S_FETCH_CNT;
                        end
                    end else begin
                        busy <= 1'b0;
                    end
                end

                S_FETCH_CNT: begin
                    state <= S_READ_CNT;
                end

                S_READ_CNT: begin
                    cur_cnt <= in_rd_data;
                    if (in_rd_data == 8'd0) begin
                        // Error: count cannot be zero
                        error <= 1'b1;
                        state <= S_DONE;
                    end else if (out_len + in_rd_data > BUFFER_DEPTH) begin
                        // Error: decompressed buffer overflow
                        error <= 1'b1;
                        state <= S_DONE;
                    end else begin
                        in_rd_addr <= in_idx + 16'd1;
                        state      <= S_FETCH_SYM;
                    end
                end

                S_FETCH_SYM: begin
                    state <= S_READ_SYM;
                end

                S_READ_SYM: begin
                    cur_sym    <= in_rd_data;
                    expand_cnt <= cur_cnt;
                    state      <= S_EXPAND;
                end

                S_EXPAND: begin
                    if (expand_cnt > 8'd0) begin
                        out_wr_en   <= 1'b1;
                        out_wr_addr <= out_len;
                        out_wr_data <= cur_sym;
                        out_len     <= out_len + 16'd1;
                        expand_cnt  <= expand_cnt - 8'd1;
                    end

                    if (expand_cnt == 8'd1) begin
                        in_idx <= in_idx + 16'd2;
                        if (in_idx + 16'd2 >= in_len) begin
                            state <= S_DONE;
                        end else begin
                            in_rd_addr <= in_idx + 16'd2;
                            state      <= S_FETCH_CNT;
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
