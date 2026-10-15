// =============================================================================
// rle_reg_block.v
//
// PURPOSE:
//   AXI4-Lite register block and internal byte buffers for RLE accelerator.
//   Decoupled AW/W channels, persistent BVALID/RVALID, SLVERR on illegal offsets
//   or busy-time configuration writes.
//   Manages input append buffer, output read buffer, and sticky W1C interrupts.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module rle_reg_block #(
    parameter DATA_WIDTH   = 32,
    parameter ADDR_WIDTH   = 32,
    parameter STRB_WIDTH   = DATA_WIDTH / 8,
    parameter BUFFER_DEPTH = 256
) (
    input  wire                   clk,
    input  wire                   rst,

    // AXI4-Lite Write Address Channel
    input  wire [ADDR_WIDTH-1:0]  s_axi_awaddr,
    input  wire [2:0]             s_axi_awprot,
    input  wire                   s_axi_awvalid,
    output reg                    s_axi_awready,

    // AXI4-Lite Write Data Channel
    input  wire [DATA_WIDTH-1:0]  s_axi_wdata,
    input  wire [STRB_WIDTH-1:0]  s_axi_wstrb,
    input  wire                   s_axi_wvalid,
    output reg                    s_axi_wready,

    // AXI4-Lite Write Response Channel
    output reg  [1:0]             s_axi_bresp,
    output reg                    s_axi_bvalid,
    input  wire                   s_axi_bready,

    // AXI4-Lite Read Address Channel
    input  wire [ADDR_WIDTH-1:0]  s_axi_araddr,
    input  wire [2:0]             s_axi_arprot,
    input  wire                   s_axi_arvalid,
    output reg                    s_axi_arready,

    // AXI4-Lite Read Data Channel
    output reg  [DATA_WIDTH-1:0]  s_axi_rdata,
    output reg  [1:0]             s_axi_rresp,
    output reg                    s_axi_rvalid,
    input  wire                   s_axi_rready,

    // Controller Interface
    output reg                    ctrl_start,
    output reg                    ctrl_mode,
    output reg  [15:0]            ctrl_in_len,
    input  wire                   ctrl_busy,
    input  wire                   ctrl_done,
    input  wire                   ctrl_error,
    input  wire [15:0]            ctrl_out_len,

    // Buffer access for encoder/decoder
    input  wire [15:0]            in_rd_addr,
    output wire [7:0]             in_rd_data,

    input  wire                   out_wr_en,
    input  wire [15:0]            out_wr_addr,
    input  wire [7:0]             out_wr_data,

    // Interrupt output
    output wire                   irq
);

    // Register Offsets (local within 4KB aperture)
    localparam REG_CONTROL       = 12'h000;
    localparam REG_STATUS        = 12'h004;
    localparam REG_INPUT_LENGTH  = 12'h008;
    localparam REG_OUTPUT_LENGTH = 12'h00C;
    localparam REG_INPUT_DATA    = 12'h010;
    localparam REG_OUTPUT_DATA   = 12'h014;
    localparam REG_IRQ_ENABLE    = 12'h018;
    localparam REG_IRQ_STATUS    = 12'h01C;

    localparam RESP_OKAY   = 2'b00;
    localparam RESP_SLVERR = 2'b10;

    // Registers
    reg [1:0]  reg_mode;           // CONTROL[1]
    reg        reg_done;           // STATUS[1]
    reg        reg_error;          // STATUS[2]
    reg [15:0] reg_in_len;         // INPUT_LENGTH
    reg [15:0] in_buf_wr_ptr;      // points to next input buffer append slot
    reg [15:0] out_buf_rd_ptr;     // points to next output byte to read
    reg [1:0]  reg_irq_en;         // IRQ_ENABLE: [0]=done, [1]=error
    reg [1:0]  reg_irq_status;     // IRQ_STATUS (W1C): [0]=done, [1]=error
    reg        cfg_error;          // configuration/buffer overflow error

    // Internal Dual Buffers
    reg [7:0] in_buf  [0:BUFFER_DEPTH-1];
    reg [7:0] out_buf [0:BUFFER_DEPTH-1];

    // Asynchronous read for in_buf to ensure fast access by encoder/decoder
    assign in_rd_data = (in_rd_addr < BUFFER_DEPTH) ? in_buf[in_rd_addr] : 8'd0;

    // Write to out_buf from encoder/decoder
    always @(posedge clk) begin
        if (out_wr_en && (out_wr_addr < BUFFER_DEPTH)) begin
            out_buf[out_wr_addr] <= out_wr_data;
        end
    end

    // -------------------------------------------------------------------------
    // Decoupled Write FSM (Independent AW and W handshakes)
    // -------------------------------------------------------------------------
    reg                  aw_latched;
    reg                  w_latched;
    reg [ADDR_WIDTH-1:0] latched_awaddr;
    reg [DATA_WIDTH-1:0] latched_wdata;
    reg [STRB_WIDTH-1:0] latched_wstrb;

    integer b_lane;
    reg [15:0] temp_wr_ptr;
    reg        temp_overflow;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            s_axi_awready  <= 1'b1;
            s_axi_wready   <= 1'b1;
            s_axi_bvalid   <= 1'b0;
            s_axi_bresp    <= RESP_OKAY;
            aw_latched     <= 1'b0;
            w_latched      <= 1'b0;
            latched_awaddr <= {ADDR_WIDTH{1'b0}};
            latched_wdata  <= {DATA_WIDTH{1'b0}};
            latched_wstrb  <= {STRB_WIDTH{1'b0}};

            ctrl_start     <= 1'b0;
            ctrl_mode      <= 1'b0;
            ctrl_in_len    <= 16'd0;
            reg_mode       <= 2'd0;
            reg_done       <= 1'b0;
            reg_error      <= 1'b0;
            reg_in_len     <= 16'd0;
            in_buf_wr_ptr  <= 16'd0;
            reg_irq_en     <= 2'd0;
            reg_irq_status <= 2'd0;
            cfg_error      <= 1'b0;
        end else begin
            ctrl_start <= 1'b0;

            // Capture completion events from controller
            if (ctrl_done) begin
                reg_done       <= 1'b1;
                reg_irq_status[0] <= 1'b1; // sticky
            end
            if (ctrl_error || cfg_error) begin
                reg_error      <= 1'b1;
                reg_irq_status[1] <= 1'b1; // sticky
            end

            // 1. Latch AW Channel
            if (s_axi_awvalid && s_axi_awready) begin
                aw_latched     <= 1'b1;
                latched_awaddr <= s_axi_awaddr;
                s_axi_awready  <= 1'b0;
            end

            // 2. Latch W Channel
            if (s_axi_wvalid && s_axi_wready) begin
                w_latched     <= 1'b1;
                latched_wdata <= s_axi_wdata;
                latched_wstrb <= s_axi_wstrb;
                s_axi_wready  <= 1'b0;
            end

            // 3. Clear B channel on handshake
            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid  <= 1'b0;
                s_axi_awready <= 1'b1;
                s_axi_wready  <= 1'b1;
            end

            // 4. Process write transaction when both AW and W are latched and B channel is idle
            if (aw_latched && w_latched && !s_axi_bvalid) begin
                aw_latched   <= 1'b0;
                w_latched    <= 1'b0;
                s_axi_bvalid <= 1'b1;

                case (latched_awaddr[11:0])
                    REG_CONTROL: begin
                        s_axi_bresp <= RESP_OKAY;
                        if (latched_wstrb[0]) begin
                            reg_mode[0] <= latched_wdata[1]; // MODE
                            if (latched_wdata[0]) begin      // START
                                if (!ctrl_busy) begin
                                    if (in_buf_wr_ptr < reg_in_len) begin
                                        reg_error         <= 1'b1;
                                        reg_irq_status[1] <= 1'b1;
                                        cfg_error         <= 1'b1;
                                    end else begin
                                        ctrl_start  <= 1'b1;
                                        ctrl_mode   <= latched_wdata[1];
                                        ctrl_in_len <= reg_in_len;
                                        reg_done    <= 1'b0;
                                        reg_error   <= 1'b0;
                                        cfg_error   <= 1'b0;
                                    end
                                end
                            end
                        end
                    end

                    REG_INPUT_LENGTH: begin
                        if (ctrl_busy) begin
                            // Writing INPUT_LENGTH while BUSY returns SLVERR
                            s_axi_bresp <= RESP_SLVERR;
                        end else begin
                            s_axi_bresp   <= RESP_OKAY;
                            reg_in_len    <= latched_wdata[15:0];
                            in_buf_wr_ptr <= 16'd0; // writing INPUT_LENGTH resets input append pointer
                        end
                    end

                    REG_INPUT_DATA: begin
                        if (ctrl_busy) begin
                            // Writing INPUT_DATA while BUSY returns SLVERR
                            s_axi_bresp <= RESP_SLVERR;
                        end else begin
                            s_axi_bresp   <= RESP_OKAY;
                            temp_wr_ptr   = in_buf_wr_ptr;
                            temp_overflow = 1'b0;

                            // Append asserted wstrb byte lanes sequentially
                            if (latched_wstrb[0]) begin
                                if (temp_wr_ptr < BUFFER_DEPTH) begin
                                    in_buf[temp_wr_ptr] <= latched_wdata[7:0];
                                    temp_wr_ptr = temp_wr_ptr + 16'd1;
                                end else temp_overflow = 1'b1;
                            end
                            if (latched_wstrb[1]) begin
                                if (temp_wr_ptr < BUFFER_DEPTH) begin
                                    in_buf[temp_wr_ptr] <= latched_wdata[15:8];
                                    temp_wr_ptr = temp_wr_ptr + 16'd1;
                                end else temp_overflow = 1'b1;
                            end
                            if (latched_wstrb[2]) begin
                                if (temp_wr_ptr < BUFFER_DEPTH) begin
                                    in_buf[temp_wr_ptr] <= latched_wdata[23:16];
                                    temp_wr_ptr = temp_wr_ptr + 16'd1;
                                end else temp_overflow = 1'b1;
                            end
                            if (latched_wstrb[3]) begin
                                if (temp_wr_ptr < BUFFER_DEPTH) begin
                                    in_buf[temp_wr_ptr] <= latched_wdata[31:24];
                                    temp_wr_ptr = temp_wr_ptr + 16'd1;
                                end else temp_overflow = 1'b1;
                            end

                            in_buf_wr_ptr <= temp_wr_ptr;
                            if (temp_overflow) begin
                                cfg_error <= 1'b1;
                            end
                        end
                    end

                    REG_IRQ_ENABLE: begin
                        s_axi_bresp <= RESP_OKAY;
                        if (latched_wstrb[0]) begin
                            reg_irq_en <= latched_wdata[1:0];
                        end
                    end

                    REG_IRQ_STATUS: begin
                        // W1C semantics: write 1 to clear
                        s_axi_bresp <= RESP_OKAY;
                        if (latched_wstrb[0]) begin
                            if (latched_wdata[0]) reg_irq_status[0] <= 1'b0;
                            if (latched_wdata[1]) reg_irq_status[1] <= 1'b0;
                        end
                    end

                    default: begin
                        // Unsupported offset -> return SLVERR
                        s_axi_bresp <= RESP_SLVERR;
                    end
                endcase
            end
        end
    end

    // -------------------------------------------------------------------------
    // Read FSM
    // -------------------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            s_axi_arready  <= 1'b1;
            s_axi_rvalid   <= 1'b0;
            s_axi_rdata    <= {DATA_WIDTH{1'b0}};
            s_axi_rresp    <= RESP_OKAY;
            out_buf_rd_ptr <= 16'd0;
        end else begin
            // Reset out_buf_rd_ptr when operation starts
            if (ctrl_start) begin
                out_buf_rd_ptr <= 16'd0;
            end

            // Clear RVALID upon handshake
            if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid  <= 1'b0;
                s_axi_arready <= 1'b1;
            end

            // Accept and respond to AR transaction
            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_arready <= 1'b0;
                s_axi_rvalid  <= 1'b1;

                case (s_axi_araddr[11:0])
                    REG_CONTROL: begin
                        s_axi_rdata <= {30'd0, reg_mode[0], 1'b0};
                        s_axi_rresp <= RESP_OKAY;
                    end

                    REG_STATUS: begin
                        // Bit 0: BUSY, Bit 1: DONE, Bit 2: ERROR
                        s_axi_rdata <= {29'd0, (reg_error | ctrl_error | cfg_error), (reg_done | ctrl_done), ctrl_busy};
                        s_axi_rresp <= RESP_OKAY;
                    end

                    REG_INPUT_LENGTH: begin
                        s_axi_rdata <= {16'd0, reg_in_len};
                        s_axi_rresp <= RESP_OKAY;
                    end

                    REG_OUTPUT_LENGTH: begin
                        s_axi_rdata <= {16'd0, ctrl_out_len};
                        s_axi_rresp <= RESP_OKAY;
                    end

                    REG_OUTPUT_DATA: begin
                        s_axi_rresp <= RESP_OKAY;
                        if (out_buf_rd_ptr < BUFFER_DEPTH) begin
                            s_axi_rdata    <= {24'd0, out_buf[out_buf_rd_ptr]};
                            out_buf_rd_ptr <= out_buf_rd_ptr + 16'd1;
                        end else begin
                            s_axi_rdata <= 32'd0;
                        end
                    end

                    REG_IRQ_ENABLE: begin
                        s_axi_rdata <= {30'd0, reg_irq_en};
                        s_axi_rresp <= RESP_OKAY;
                    end

                    REG_IRQ_STATUS: begin
                        s_axi_rdata <= {30'd0, reg_irq_status};
                        s_axi_rresp <= RESP_OKAY;
                    end

                    default: begin
                        // Unsupported register offset returns SLVERR
                        s_axi_rdata <= 32'd0;
                        s_axi_rresp <= RESP_SLVERR;
                    end
                endcase
            end
        end
    end

    // Interrupt output pin
    assign irq = (reg_irq_en[0] & reg_irq_status[0]) | (reg_irq_en[1] & reg_irq_status[1]);

endmodule
`default_nettype wire
