// =============================================================================
// dma_sequencer.v
//
// DMA Sequencer FSM for RISC-V Configurable Data Compression Accelerator SoC.
//
// Functionality:
//   1. Accepts start/abort and configuration from dma_reg_file.
//   2. Validates parameters (source, destination, length 1..256 bytes).
//   3. Reads source data from Data Memory (DMEM) via dma_master_engine.
//   4. Configures RLE accelerator input length (0x000D_0008).
//   5. Transfers source bytes into RLE input data register (0x000D_0010)
//      with precise byte enables (WSTRB) for partial final words.
//   6. Initiates RLE operation (0x000D_0000) for compression or decompression.
//   7. Polls RLE status (0x000D_0004) until DONE or ERROR (with timeout guard).
//   8. Reads RLE output byte length (0x000D_000C).
//   9. Reads RLE output bytes from output data register (0x000D_0014).
//  10. Packs output bytes sequentially into 32-bit words with correct WSTRB.
//  11. Writes packed words to destination DMEM via dma_master_engine.
//  12. Updates DMA output length, status, error code, and triggers completion IRQ.
//
// Authors: SoC Development Team
// Date: October 2026
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module dma_sequencer #(
    parameter ADDR_WIDTH     = 32,
    parameter DATA_WIDTH     = 32,
    parameter STRB_WIDTH     = (DATA_WIDTH / 8),
    parameter BUFFER_DEPTH   = 256,
    parameter TIMEOUT_CYCLES = 100000
)(
    input  wire                    clk,
    input  wire                    rst_n,

    // =========================================================================
    // Interface with dma_reg_file
    // =========================================================================
    input  wire                    ctrl_start_i,        // 1-cycle pulse to start
    input  wire                    ctrl_abort_i,        // 1-cycle pulse to abort
    input  wire                    ctrl_mode_i,         // 0 = Compress, 1 = Decompress
    input  wire [ADDR_WIDTH-1:0]   cfg_src_addr_i,      // DMEM source address
    input  wire [ADDR_WIDTH-1:0]   cfg_dst_addr_i,      // DMEM destination address
    input  wire [15:0]             cfg_input_len_i,     // Input byte count (1..256)

    output reg                     status_busy_o,       // 1 while active
    output reg                     status_done_pulse_o, // 1-cycle pulse on completion
    output reg                     status_error_pulse_o,// 1-cycle pulse on error
    output reg  [15:0]             status_output_len_o, // Actual output length in bytes
    output reg  [7:0]              status_error_code_o, // Error classification code

    // =========================================================================
    // Interface with dma_master_engine
    // =========================================================================
    // Master Read Channel
    output reg                     req_rd_start_o,
    output reg  [ADDR_WIDTH-1:0]   req_rd_addr_o,
    output reg  [7:0]              req_rd_len_o,
    input  wire [DATA_WIDTH-1:0]   rd_data_i,
    input  wire                    rd_valid_i,
    output wire                    rd_ready_o,
    input  wire                    rd_last_i,
    input  wire                    rd_done_i,
    input  wire                    rd_error_i,
    input  wire [1:0]              rd_resp_i,

    // Master Write Channel
    output reg                     req_wr_start_o,
    output reg  [ADDR_WIDTH-1:0]   req_wr_addr_o,
    output reg  [7:0]              req_wr_len_o,
    output reg  [DATA_WIDTH-1:0]   wr_data_o,
    output reg  [STRB_WIDTH-1:0]   wr_strb_o,
    output reg                     wr_valid_o,
    input  wire                    wr_ready_i,
    input  wire                    wr_done_i,
    input  wire                    wr_error_i,
    input  wire [1:0]              wr_resp_i,

    output reg                     master_abort_o       // Abort active master transfers
);

    // =========================================================================
    // RLE Accelerator Peripheral Memory Map (Slave 5 on SoC Interconnect)
    // =========================================================================
    localparam [31:0] RLE_REG_CONTROL    = 32'h000D_0000;
    localparam [31:0] RLE_REG_STATUS     = 32'h000D_0004;
    localparam [31:0] RLE_REG_INPUT_LEN  = 32'h000D_0008;
    localparam [31:0] RLE_REG_OUTPUT_LEN = 32'h000D_000C;
    localparam [31:0] RLE_REG_INPUT_DATA = 32'h000D_0010;
    localparam [31:0] RLE_REG_OUTPUT_DATA= 32'h000D_0014;

    // Error Codes
    localparam [7:0] ERR_NONE     = 8'h00;
    localparam [7:0] ERR_BAD_SRC  = 8'h01;
    localparam [7:0] ERR_BAD_DST  = 8'h02;
    localparam [7:0] ERR_BAD_LEN  = 8'h03;
    localparam [7:0] ERR_RD_ERR   = 8'h04;
    localparam [7:0] ERR_WR_ERR   = 8'h05;
    localparam [7:0] ERR_RLE_ERR  = 8'h06;
    localparam [7:0] ERR_TIMEOUT  = 8'h07;

    // Internal Buffers
    reg [31:0] src_word_buf [0:63]; // Up to 64 words (256 bytes)
    reg [7:0]  dst_byte_buf [0:255];// Up to 256 bytes

    // FSM State Encoding
    localparam [4:0]
        S_IDLE              = 5'd0,
        S_RD_DMEM_START     = 5'd1,
        S_RD_DMEM_DATA      = 5'd2,
        S_RD_DMEM_WAIT      = 5'd3,
        S_WR_RLE_LEN_START  = 5'd4,
        S_WR_RLE_LEN_WAIT   = 5'd5,
        S_WR_RLE_DATA_START = 5'd6,
        S_WR_RLE_DATA_WAIT  = 5'd7,
        S_WR_RLE_CTRL_START = 5'd8,
        S_WR_RLE_CTRL_WAIT  = 5'd9,
        S_POLL_RLE_START    = 5'd10,
        S_POLL_RLE_WAIT     = 5'd11,
        S_RD_RLE_LEN_START  = 5'd12,
        S_RD_RLE_LEN_WAIT   = 5'd13,
        S_RD_RLE_DATA_START = 5'd14,
        S_RD_RLE_DATA_WAIT  = 5'd15,
        S_WR_DMEM_START     = 5'd16,
        S_WR_DMEM_WAIT      = 5'd17,
        S_DONE              = 5'd18,
        S_ERROR             = 5'd19;

    reg [4:0]  state;

    // Latched Configuration Registers
    reg [ADDR_WIDTH-1:0] src_addr_reg;
    reg [ADDR_WIDTH-1:0] dst_addr_reg;
    reg [15:0]           in_len_reg;
    reg                  mode_reg;

    // Pointers and Counters
    reg [7:0]  src_word_cnt;     // Total words to read/write for source
    reg [7:0]  src_word_idx;     // Current source word index
    reg [15:0] rle_out_len_reg;  // Output length reported by RLE
    reg [15:0] dst_byte_idx;     // Current output byte index
    reg [7:0]  dst_word_cnt;     // Total words to write to destination DMEM
    reg [7:0]  dst_word_idx;     // Current destination word index
    reg [31:0] poll_timer;       // Safety timeout timer
    reg [7:0]  err_code_latch;   // Latched error code

    // Read channel is always ready to receive data into internal buffer
    assign rd_ready_o = 1'b1;

    // Helper: calculate byte strobes for a given word index and total byte length
    function automatic [3:0] calc_wstrb(input int word_index, input int total_bytes);
        int rem_bytes;
        begin
            rem_bytes = total_bytes - (word_index * 4);
            if (rem_bytes >= 4)
                calc_wstrb = 4'b1111;
            else if (rem_bytes == 3)
                calc_wstrb = 4'b0111;
            else if (rem_bytes == 2)
                calc_wstrb = 4'b0011;
            else if (rem_bytes == 1)
                calc_wstrb = 4'b0001;
            else
                calc_wstrb = 4'b0000;
        end
    endfunction

    // =========================================================================
    // Sequencer FSM Main Process
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state               <= S_IDLE;
            status_busy_o       <= 1'b0;
            status_done_pulse_o <= 1'b0;
            status_error_pulse_o<= 1'b0;
            status_output_len_o <= 16'd0;
            status_error_code_o <= ERR_NONE;
            req_rd_start_o      <= 1'b0;
            req_rd_addr_o       <= {ADDR_WIDTH{1'b0}};
            req_rd_len_o        <= 8'd0;
            req_wr_start_o      <= 1'b0;
            req_wr_addr_o       <= {ADDR_WIDTH{1'b0}};
            req_wr_len_o        <= 8'd0;
            wr_data_o           <= {DATA_WIDTH{1'b0}};
            wr_strb_o           <= {STRB_WIDTH{1'b0}};
            wr_valid_o          <= 1'b0;
            master_abort_o      <= 1'b0;
            src_addr_reg        <= {ADDR_WIDTH{1'b0}};
            dst_addr_reg        <= {ADDR_WIDTH{1'b0}};
            in_len_reg          <= 16'd0;
            mode_reg            <= 1'b0;
            src_word_cnt        <= 8'd0;
            src_word_idx        <= 8'd0;
            rle_out_len_reg     <= 16'd0;
            dst_byte_idx        <= 16'd0;
            dst_word_cnt        <= 8'd0;
            dst_word_idx        <= 8'd0;
            poll_timer          <= 32'd0;
            err_code_latch      <= ERR_NONE;
        end else if (ctrl_abort_i) begin
            // Synchronous Abort
            master_abort_o      <= 1'b1;
            req_rd_start_o      <= 1'b0;
            req_wr_start_o      <= 1'b0;
            wr_valid_o          <= 1'b0;
            status_busy_o       <= 1'b0;
            status_done_pulse_o <= 1'b0;
            status_error_pulse_o<= 1'b0;
            state               <= S_IDLE;
        end else begin
            // Default 1-cycle pulses & controls
            status_done_pulse_o  <= 1'b0;
            status_error_pulse_o <= 1'b0;
            req_rd_start_o       <= 1'b0;
            req_wr_start_o       <= 1'b0;
            master_abort_o       <= 1'b0;

            case (state)

                // -------------------------------------------------------------
                // S_IDLE: Awaiting CPU trigger
                // -------------------------------------------------------------
                S_IDLE: begin
                    status_busy_o <= 1'b0;
                    wr_valid_o    <= 1'b0;

                    if (ctrl_start_i) begin
                        status_busy_o   <= 1'b1;
                        src_addr_reg    <= cfg_src_addr_i;
                        dst_addr_reg    <= cfg_dst_addr_i;
                        in_len_reg      <= cfg_input_len_i;
                        mode_reg        <= ctrl_mode_i;
                        rle_out_len_reg <= 16'd0;

                        // Parameter Validations
                        if (cfg_input_len_i == 16'd0 || cfg_input_len_i > 16'd256) begin
                            err_code_latch <= ERR_BAD_LEN;
                            state          <= S_ERROR;
                        end else if (cfg_src_addr_i < 32'h0001_0000 ||
                                     cfg_src_addr_i > 32'h0002_FFFF ||
                                     (({1'b0, cfg_src_addr_i} + {17'd0, cfg_input_len_i} - 33'd1) > 33'h0_0002_FFFF)) begin
                            err_code_latch <= ERR_BAD_SRC;
                            state          <= S_ERROR;
                        end else if (cfg_dst_addr_i < 32'h0001_0000 || cfg_dst_addr_i > 32'h0002_FFFF) begin
                            err_code_latch <= ERR_BAD_DST;
                            state          <= S_ERROR;
                        end else begin
                            // Calculate number of 32-bit words needed to hold in_len bytes (1..256 -> 1..64 words)
                            // word_cnt = ceil(in_len / 4) using full 9-bit value so len=256 does not truncate to 0
                            src_word_cnt <= (cfg_input_len_i[8:0] + 9'd3) >> 2;
                            src_word_idx <= 8'd0;
                            state        <= S_RD_DMEM_START;
                        end
                    end
                end

                // -------------------------------------------------------------
                // S_RD_DMEM_START: Read source buffer from DMEM using AXI burst
                // -------------------------------------------------------------
                S_RD_DMEM_START: begin
                    req_rd_addr_o  <= src_addr_reg;
                    req_rd_len_o   <= src_word_cnt - 8'd1; // burst len = words - 1
                    req_rd_start_o <= 1'b1;
                    src_word_idx   <= 8'd0;
                    state          <= S_RD_DMEM_DATA;
                end

                // -------------------------------------------------------------
                // S_RD_DMEM_DATA: Collect arriving data beats into src_word_buf
                // -------------------------------------------------------------
                S_RD_DMEM_DATA: begin
                    if (rd_valid_i) begin
                        src_word_buf[src_word_idx] <= rd_data_i;
                        src_word_idx               <= src_word_idx + 1'b1;
                    end

                    if (rd_error_i) begin
                        err_code_latch <= ERR_RD_ERR;
                        state          <= S_ERROR;
                    end else if (rd_done_i) begin
                        state <= S_WR_RLE_LEN_START;
                    end
                end

                // -------------------------------------------------------------
                // S_WR_RLE_LEN_START: Write input length to RLE REG_INPUT_LEN
                // -------------------------------------------------------------
                S_WR_RLE_LEN_START: begin
                    req_wr_addr_o  <= RLE_REG_INPUT_LEN;
                    req_wr_len_o   <= 8'd0; // 1-beat transfer
                    wr_data_o      <= {16'd0, in_len_reg};
                    wr_strb_o      <= 4'b1111;
                    wr_valid_o     <= 1'b1;
                    req_wr_start_o <= 1'b1;
                    state          <= S_WR_RLE_LEN_WAIT;
                end

                S_WR_RLE_LEN_WAIT: begin
                    if (wr_ready_i) begin
                        wr_valid_o <= 1'b0;
                    end

                    if (wr_error_i) begin
                        err_code_latch <= ERR_WR_ERR;
                        state          <= S_ERROR;
                    end else if (wr_done_i) begin
                        src_word_idx <= 8'd0;
                        state        <= S_WR_RLE_DATA_START;
                    end
                end

                // -------------------------------------------------------------
                // S_WR_RLE_DATA_START: Write source words into RLE REG_INPUT_DATA
                // -------------------------------------------------------------
                S_WR_RLE_DATA_START: begin
                    req_wr_addr_o  <= RLE_REG_INPUT_DATA;
                    req_wr_len_o   <= 8'd0;
                    wr_data_o      <= src_word_buf[src_word_idx];
                    wr_strb_o      <= calc_wstrb(src_word_idx, in_len_reg);
                    wr_valid_o     <= 1'b1;
                    req_wr_start_o <= 1'b1;
                    state          <= S_WR_RLE_DATA_WAIT;
                end

                S_WR_RLE_DATA_WAIT: begin
                    if (wr_ready_i) begin
                        wr_valid_o <= 1'b0;
                    end

                    if (wr_error_i) begin
                        err_code_latch <= ERR_WR_ERR;
                        state          <= S_ERROR;
                    end else if (wr_done_i) begin
                        if (src_word_idx + 8'd1 == src_word_cnt) begin
                            // All source words written into RLE
                            state <= S_WR_RLE_CTRL_START;
                        end else begin
                            src_word_idx <= src_word_idx + 8'd1;
                            state        <= S_WR_RLE_DATA_START;
                        end
                    end
                end

                // -------------------------------------------------------------
                // S_WR_RLE_CTRL_START: Write START=1 to RLE REG_CONTROL
                // -------------------------------------------------------------
                S_WR_RLE_CTRL_START: begin
                    req_wr_addr_o  <= RLE_REG_CONTROL;
                    req_wr_len_o   <= 8'd0;
                    wr_data_o      <= {30'd0, mode_reg, 1'b1}; // START=1, MODE
                    wr_strb_o      <= 4'b1111;
                    wr_valid_o     <= 1'b1;
                    req_wr_start_o <= 1'b1;
                    poll_timer     <= 32'd0;
                    state          <= S_WR_RLE_CTRL_WAIT;
                end

                S_WR_RLE_CTRL_WAIT: begin
                    if (wr_ready_i) begin
                        wr_valid_o <= 1'b0;
                    end

                    if (wr_error_i) begin
                        err_code_latch <= ERR_WR_ERR;
                        state          <= S_ERROR;
                    end else if (wr_done_i) begin
                        state <= S_POLL_RLE_START;
                    end
                end

                // -------------------------------------------------------------
                // S_POLL_RLE_START: Poll RLE REG_STATUS
                // -------------------------------------------------------------
                S_POLL_RLE_START: begin
                    poll_timer <= poll_timer + 1'b1;
                    if (poll_timer >= TIMEOUT_CYCLES) begin
                        err_code_latch <= ERR_TIMEOUT;
                        state          <= S_ERROR;
                    end else begin
                        req_rd_addr_o  <= RLE_REG_STATUS;
                        req_rd_len_o   <= 8'd0;
                        req_rd_start_o <= 1'b1;
                        state          <= S_POLL_RLE_WAIT;
                    end
                end

                S_POLL_RLE_WAIT: begin
                    if (rd_error_i) begin
                        err_code_latch <= ERR_RD_ERR;
                        state          <= S_ERROR;
                    end else if (rd_done_i) begin
                        // STATUS Bit 2 = ERROR, Bit 1 = DONE, Bit 0 = BUSY
                        if (rd_data_i[2]) begin
                            err_code_latch <= ERR_RLE_ERR;
                            state          <= S_ERROR;
                        end else if (rd_data_i[1]) begin
                            // Accelerator finished!
                            state <= S_RD_RLE_LEN_START;
                        end else begin
                            // Still busy; poll again
                            state <= S_POLL_RLE_START;
                        end
                    end
                end

                // -------------------------------------------------------------
                // S_RD_RLE_LEN_START: Read RLE REG_OUTPUT_LEN
                // -------------------------------------------------------------
                S_RD_RLE_LEN_START: begin
                    req_rd_addr_o  <= RLE_REG_OUTPUT_LEN;
                    req_rd_len_o   <= 8'd0;
                    req_rd_start_o <= 1'b1;
                    state          <= S_RD_RLE_LEN_WAIT;
                end

                S_RD_RLE_LEN_WAIT: begin
                    if (rd_error_i) begin
                        err_code_latch <= ERR_RD_ERR;
                        state          <= S_ERROR;
                    end else if (rd_done_i) begin
                        rle_out_len_reg <= rd_data_i[15:0];
                        if (rd_data_i[15:0] == 16'd0) begin
                            // 0 output bytes produced
                            dst_word_cnt <= 8'd0;
                            state        <= S_DONE;
                        end else if (rd_data_i[15:0] > 16'd256) begin
                            // Guard internal 256-byte buffer against overflow
                            err_code_latch <= ERR_RLE_ERR;
                            state          <= S_ERROR;
                        end else begin
                            dst_byte_idx <= 16'd0;
                            state        <= S_RD_RLE_DATA_START;
                        end
                    end
                end

                // -------------------------------------------------------------
                // S_RD_RLE_DATA_START: Read output bytes sequentially from RLE
                // -------------------------------------------------------------
                S_RD_RLE_DATA_START: begin
                    req_rd_addr_o  <= RLE_REG_OUTPUT_DATA;
                    req_rd_len_o   <= 8'd0;
                    req_rd_start_o <= 1'b1;
                    state          <= S_RD_RLE_DATA_WAIT;
                end

                S_RD_RLE_DATA_WAIT: begin
                    if (rd_error_i) begin
                        err_code_latch <= ERR_RD_ERR;
                        state          <= S_ERROR;
                    end else if (rd_done_i) begin
                        dst_byte_buf[dst_byte_idx] <= rd_data_i[7:0];
                        if (dst_byte_idx + 16'd1 == rle_out_len_reg) begin
                            // Verify destination range fits entirely inside DMEM (0x0001_0000..0x0002_FFFF)
                            if (({1'b0, dst_addr_reg} + {17'd0, rle_out_len_reg} - 33'd1) > 33'h0_0002_FFFF) begin
                                err_code_latch <= ERR_BAD_DST;
                                state          <= S_ERROR;
                            end else begin
                                // All output bytes collected; calculate destination words (1..256 -> 1..64 words)
                                dst_word_cnt <= (rle_out_len_reg[8:0] + 9'd3) >> 2;
                                dst_word_idx <= 8'd0;
                                state        <= S_WR_DMEM_START;
                            end
                        end else begin
                            dst_byte_idx <= dst_byte_idx + 16'd1;
                            state        <= S_RD_RLE_DATA_START;
                        end
                    end
                end

                // -------------------------------------------------------------
                // S_WR_DMEM_START: Write packed words to destination DMEM
                // -------------------------------------------------------------
                S_WR_DMEM_START: begin
                    req_wr_addr_o  <= dst_addr_reg + (dst_word_idx << 2);
                    req_wr_len_o   <= 8'd0; // Word-by-word with precise WSTRB
                    wr_data_o      <= {
                        dst_byte_buf[{dst_word_idx, 2'b11}],
                        dst_byte_buf[{dst_word_idx, 2'b10}],
                        dst_byte_buf[{dst_word_idx, 2'b01}],
                        dst_byte_buf[{dst_word_idx, 2'b00}]
                    };
                    wr_strb_o      <= calc_wstrb(dst_word_idx, rle_out_len_reg);
                    wr_valid_o     <= 1'b1;
                    req_wr_start_o <= 1'b1;
                    state          <= S_WR_DMEM_WAIT;
                end

                S_WR_DMEM_WAIT: begin
                    if (wr_ready_i) begin
                        wr_valid_o <= 1'b0;
                    end

                    if (wr_error_i) begin
                        err_code_latch <= ERR_WR_ERR;
                        state          <= S_ERROR;
                    end else if (wr_done_i) begin
                        if (dst_word_idx + 8'd1 == dst_word_cnt) begin
                            // All destination words written successfully!
                            state <= S_DONE;
                        end else begin
                            dst_word_idx <= dst_word_idx + 8'd1;
                            state        <= S_WR_DMEM_START;
                        end
                    end
                end

                // -------------------------------------------------------------
                // S_DONE: Completion reporting
                // -------------------------------------------------------------
                S_DONE: begin
                    status_busy_o       <= 1'b0;
                    status_done_pulse_o <= 1'b1;
                    status_output_len_o <= rle_out_len_reg;
                    status_error_code_o <= ERR_NONE;
                    state               <= S_IDLE;
                end

                // -------------------------------------------------------------
                // S_ERROR: Error reporting
                // -------------------------------------------------------------
                S_ERROR: begin
                    status_busy_o        <= 1'b0;
                    status_error_pulse_o <= 1'b1;
                    status_output_len_o  <= 16'd0;
                    status_error_code_o  <= err_code_latch;
                    state                <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
