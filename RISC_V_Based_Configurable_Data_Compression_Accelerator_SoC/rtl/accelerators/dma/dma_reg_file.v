// =============================================================================
// dma_reg_file.v — CPU-Facing AXI4-Lite Register Interface for SoC DMA IP
//
// Description:
//   Provides the memory-mapped register bank for configuring and monitoring
//   the Direct Memory Access (DMA) controller.
//
// Register Map (Base: 0x000B_0000, 64 KB Aperture; Registers at +0x000..+0xFFF):
//   Offset   Register           Width  Access  Description
//   0x000    DMA_CONTROL        32     R/W     Bit 0: START (self-clearing pulse)
//                                              Bit 1: MODE (0=Compress, 1=Decompress)
//                                              Bit 2: ABORT (self-clearing pulse)
//   0x004    DMA_STATUS         32     RO      Bit 0: BUSY
//                                              Bit 1: DONE
//                                              Bit 2: ERROR
//   0x008    DMA_SRC_ADDR       32     R/W     Source address in DMEM (0x0001_0000 - 0x0002_FFFF)
//   0x00C    DMA_DST_ADDR       32     R/W     Destination address in DMEM (0x0001_0000 - 0x0002_FFFF)
//   0x010    DMA_INPUT_LEN      32     R/W     Input transfer length in bytes (1 - 256)
//   0x014    DMA_OUTPUT_LEN     32     RO      Actual output bytes produced by accelerator
//   0x018    DMA_IRQ_ENABLE     32     R/W     Bit 0: DONE_IE, Bit 1: ERROR_IE
//   0x01C    DMA_IRQ_STATUS     32     R/W1C   Bit 0: DONE_IS, Bit 1: ERROR_IS (Write 1 to clear)
//   0x020    DMA_ERROR_CODE     32     RO      Error classification code from FSM
//
// Features:
//   - Fully decoupled, independent AW and W channel handshakes.
//   - Full byte write strobe (WSTRB) handling.
//   - Self-clearing single-cycle START and ABORT pulse generation.
//   - Write-1-to-clear (W1C) interrupt status with level IRQ output.
//   - Independent of DMA master engine/FSM.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module dma_reg_file #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter ID_WIDTH   = 8,
    parameter STRB_WIDTH = (DATA_WIDTH / 8)
)(
    input  wire                   clk,
    input  wire                   rst_n,      // Active-low asynchronous/synchronous reset

    // =========================================================================
    // AXI4-Lite Slave Interface (CPU-Facing)
    // =========================================================================

    // Write Address Channel
    input  wire [ID_WIDTH-1:0]    s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]  s_axi_awaddr,
    input  wire [2:0]             s_axi_awprot,
    input  wire                   s_axi_awvalid,
    output reg                    s_axi_awready,

    // Write Data Channel
    input  wire [DATA_WIDTH-1:0]  s_axi_wdata,
    input  wire [STRB_WIDTH-1:0]  s_axi_wstrb,
    input  wire                   s_axi_wvalid,
    output reg                    s_axi_wready,

    // Write Response Channel
    output reg  [ID_WIDTH-1:0]    s_axi_bid,
    output reg  [1:0]             s_axi_bresp,
    output reg                    s_axi_bvalid,
    input  wire                   s_axi_bready,

    // Read Address Channel
    input  wire [ID_WIDTH-1:0]    s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]  s_axi_araddr,
    input  wire [2:0]             s_axi_arprot,
    input  wire                   s_axi_arvalid,
    output reg                    s_axi_arready,

    // Read Data Channel
    output reg  [ID_WIDTH-1:0]    s_axi_rid,
    output reg  [DATA_WIDTH-1:0]  s_axi_rdata,
    output reg  [1:0]             s_axi_rresp,
    output reg                    s_axi_rlast,
    output reg                    s_axi_rvalid,
    input  wire                   s_axi_rready,

    // =========================================================================
    // Control & Configuration Interface (to DMA FSM / Core)
    // =========================================================================
    output reg                    ctrl_start_pulse_o, // 1-cycle pulse to initiate DMA
    output wire                   ctrl_mode_o,        // 0 = Compress, 1 = Decompress
    output reg                    ctrl_abort_pulse_o, // 1-cycle pulse to abort DMA
    output wire [31:0]            cfg_src_addr_o,     // Source DMEM address
    output wire [31:0]            cfg_dst_addr_o,     // Destination DMEM address
    output wire [15:0]            cfg_input_len_o,    // Input transfer length in bytes

    // =========================================================================
    // Status & Error Inputs (from DMA FSM / Core)
    // =========================================================================
    input  wire                   status_busy_i,      // 1 while DMA transfer is in progress
    input  wire                   status_done_pulse_i,// 1-cycle pulse upon completion
    input  wire                   status_error_pulse_i,// 1-cycle pulse upon error
    input  wire [15:0]            status_output_len_i,// Actual output bytes produced
    input  wire [7:0]             status_error_code_i,// Error code classification

    // =========================================================================
    // Interrupt Output (to SoC PIC / Top-Level)
    // =========================================================================
    output wire                   irq_o               // Active-high interrupt request
);

    // =========================================================================
    // Register Offsets (local 12-bit decode within 4 KB window)
    // =========================================================================
    localparam [11:0] REG_DMA_CONTROL    = 12'h000;
    localparam [11:0] REG_DMA_STATUS     = 12'h004;
    localparam [11:0] REG_DMA_SRC_ADDR   = 12'h008;
    localparam [11:0] REG_DMA_DST_ADDR   = 12'h00C;
    localparam [11:0] REG_DMA_INPUT_LEN  = 12'h010;
    localparam [11:0] REG_DMA_OUTPUT_LEN = 12'h014;
    localparam [11:0] REG_DMA_IRQ_ENABLE = 12'h018;
    localparam [11:0] REG_DMA_IRQ_STATUS = 12'h01C;
    localparam [11:0] REG_DMA_ERROR_CODE = 12'h020;

    localparam [1:0]  RESP_OKAY          = 2'b00;
    localparam [1:0]  RESP_SLVERR        = 2'b10;

    // =========================================================================
    // Internal Registers
    // =========================================================================
    reg        reg_mode;
    reg        reg_done;
    reg        reg_error;
    reg [31:0] reg_src_addr;
    reg [31:0] reg_dst_addr;
    reg [15:0] reg_input_len;
    reg [15:0] reg_output_len;
    reg [1:0]  reg_irq_enable;  // [0]: DONE_IE, [1]: ERROR_IE
    reg [1:0]  reg_irq_status;  // [0]: DONE_IS, [1]: ERROR_IS (W1C)
    reg [7:0]  reg_error_code;

    // Export configuration directly
    assign ctrl_mode_o     = reg_mode;
    assign cfg_src_addr_o  = reg_src_addr;
    assign cfg_dst_addr_o  = reg_dst_addr;
    assign cfg_input_len_o = reg_input_len;

    // Level interrupt output
    assign irq_o = (reg_irq_enable[0] & reg_irq_status[0]) |
                   (reg_irq_enable[1] & reg_irq_status[1]);

    // =========================================================================
    // AXI Write Channel State Machine (Independent AW and W Channels)
    // =========================================================================
    reg                  aw_latched;
    reg                  w_latched;
    reg [ADDR_WIDTH-1:0] latched_awaddr;
    reg [DATA_WIDTH-1:0] latched_wdata;
    reg [STRB_WIDTH-1:0] latched_wstrb;
    reg [ID_WIDTH-1:0]   latched_awid;

    wire write_transaction_ready = (aw_latched || (s_axi_awvalid && s_axi_awready)) &&
                                   (w_latched  || (s_axi_wvalid  && s_axi_wready))  &&
                                   (!s_axi_bvalid || s_axi_bready);

    wire [ADDR_WIDTH-1:0] eff_awaddr = aw_latched ? latched_awaddr : s_axi_awaddr;
    wire [DATA_WIDTH-1:0] eff_wdata  = w_latched  ? latched_wdata  : s_axi_wdata;
    wire [STRB_WIDTH-1:0] eff_wstrb  = w_latched  ? latched_wstrb  : s_axi_wstrb;
    wire [ID_WIDTH-1:0]   eff_awid   = aw_latched ? latched_awid   : s_axi_awid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_awready      <= 1'b1;
            s_axi_wready       <= 1'b1;
            s_axi_bvalid       <= 1'b0;
            s_axi_bresp        <= RESP_OKAY;
            s_axi_bid          <= {ID_WIDTH{1'b0}};
            aw_latched         <= 1'b0;
            w_latched          <= 1'b0;
            latched_awaddr     <= {ADDR_WIDTH{1'b0}};
            latched_wdata      <= {DATA_WIDTH{1'b0}};
            latched_wstrb      <= {STRB_WIDTH{1'b0}};
            latched_awid       <= {ID_WIDTH{1'b0}};

            ctrl_start_pulse_o <= 1'b0;
            ctrl_abort_pulse_o <= 1'b0;
            reg_mode           <= 1'b0;
            reg_done           <= 1'b0;
            reg_error          <= 1'b0;
            reg_src_addr       <= 32'h0001_0000;
            reg_dst_addr       <= 32'h0001_0100;
            reg_input_len      <= 16'd0;
            reg_output_len     <= 16'd0;
            reg_irq_enable     <= 2'b00;
            reg_irq_status     <= 2'b00;
            reg_error_code     <= 8'h00;
        end else begin
            // Default 1-cycle pulses self-clear
            ctrl_start_pulse_o <= 1'b0;
            ctrl_abort_pulse_o <= 1'b0;

            // -----------------------------------------------------------------
            // Hardware Status Updates from DMA Core / FSM
            // -----------------------------------------------------------------
            if (status_done_pulse_i) begin
                reg_done          <= 1'b1;
                reg_irq_status[0] <= 1'b1; // Latch sticky DONE IRQ
                reg_output_len    <= status_output_len_i;
            end

            if (status_error_pulse_i) begin
                reg_error         <= 1'b1;
                reg_irq_status[1] <= 1'b1; // Latch sticky ERROR IRQ
                reg_error_code    <= status_error_code_i;
            end

            // -----------------------------------------------------------------
            // Latch Incoming Write Handshakes
            // -----------------------------------------------------------------
            if (s_axi_awvalid && s_axi_awready && !write_transaction_ready) begin
                aw_latched     <= 1'b1;
                latched_awaddr <= s_axi_awaddr;
                latched_awid   <= s_axi_awid;
                s_axi_awready  <= 1'b0;
            end

            if (s_axi_wvalid && s_axi_wready && !write_transaction_ready) begin
                w_latched     <= 1'b1;
                latched_wdata <= s_axi_wdata;
                latched_wstrb <= s_axi_wstrb;
                s_axi_wready  <= 1'b0;
            end

            // -----------------------------------------------------------------
            // Complete B-Channel Handshake
            // -----------------------------------------------------------------
            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid  <= 1'b0;
                s_axi_awready <= 1'b1;
                s_axi_wready  <= 1'b1;
            end

            // -----------------------------------------------------------------
            // Execute Register Write when Both AW and W are Available
            // -----------------------------------------------------------------
            if (write_transaction_ready) begin
                aw_latched    <= 1'b0;
                w_latched     <= 1'b0;
                s_axi_bvalid  <= 1'b1;
                s_axi_bid     <= eff_awid;
                s_axi_awready <= 1'b0;
                s_axi_wready  <= 1'b0;

                case (eff_awaddr[11:0])
                    REG_DMA_CONTROL: begin
                        s_axi_bresp <= RESP_OKAY;
                        if (eff_wstrb[0]) begin
                            // ABORT has priority
                            if (eff_wdata[2]) begin
                                ctrl_abort_pulse_o <= 1'b1;
                                reg_done           <= 1'b0;
                                reg_error          <= 1'b0;
                            end else if (eff_wdata[0]) begin
                                // START (only valid if not busy)
                                if (!status_busy_i) begin
                                    ctrl_start_pulse_o <= 1'b1;
                                    reg_mode           <= eff_wdata[1];
                                    reg_done           <= 1'b0;
                                    reg_error          <= 1'b0;
                                    reg_error_code     <= 8'h00;
                                    reg_output_len     <= 16'd0;
                                end
                            end else begin
                                // Mode update without start
                                reg_mode <= eff_wdata[1];
                            end
                        end
                    end

                    REG_DMA_SRC_ADDR: begin
                        s_axi_bresp <= RESP_OKAY;
                        if (!status_busy_i) begin
                            if (eff_wstrb[0]) reg_src_addr[ 7: 0] <= eff_wdata[ 7: 0];
                            if (eff_wstrb[1]) reg_src_addr[15: 8] <= eff_wdata[15: 8];
                            if (eff_wstrb[2]) reg_src_addr[23:16] <= eff_wdata[23:16];
                            if (eff_wstrb[3]) reg_src_addr[31:24] <= eff_wdata[31:24];
                        end else begin
                            s_axi_bresp <= RESP_SLVERR; // Cannot modify while busy
                        end
                    end

                    REG_DMA_DST_ADDR: begin
                        s_axi_bresp <= RESP_OKAY;
                        if (!status_busy_i) begin
                            if (eff_wstrb[0]) reg_dst_addr[ 7: 0] <= eff_wdata[ 7: 0];
                            if (eff_wstrb[1]) reg_dst_addr[15: 8] <= eff_wdata[15: 8];
                            if (eff_wstrb[2]) reg_dst_addr[23:16] <= eff_wdata[23:16];
                            if (eff_wstrb[3]) reg_dst_addr[31:24] <= eff_wdata[31:24];
                        end else begin
                            s_axi_bresp <= RESP_SLVERR;
                        end
                    end

                    REG_DMA_INPUT_LEN: begin
                        s_axi_bresp <= RESP_OKAY;
                        if (!status_busy_i) begin
                            if (eff_wstrb[0]) reg_input_len[ 7: 0] <= eff_wdata[ 7: 0];
                            if (eff_wstrb[1]) reg_input_len[15: 8] <= eff_wdata[15: 8];
                        end else begin
                            s_axi_bresp <= RESP_SLVERR;
                        end
                    end

                    REG_DMA_IRQ_ENABLE: begin
                        s_axi_bresp <= RESP_OKAY;
                        if (eff_wstrb[0]) begin
                            reg_irq_enable <= eff_wdata[1:0];
                        end
                    end

                    REG_DMA_IRQ_STATUS: begin
                        // Write-1-to-clear (W1C)
                        s_axi_bresp <= RESP_OKAY;
                        if (eff_wstrb[0]) begin
                            if (eff_wdata[0]) reg_irq_status[0] <= 1'b0;
                            if (eff_wdata[1]) reg_irq_status[1] <= 1'b0;
                        end
                    end

                    REG_DMA_STATUS,
                    REG_DMA_OUTPUT_LEN,
                    REG_DMA_ERROR_CODE: begin
                        // Read-Only registers: Return SLVERR on write attempt
                        s_axi_bresp <= RESP_SLVERR;
                    end

                    default: begin
                        // Unmapped offset within aperture returns SLVERR
                        s_axi_bresp <= RESP_SLVERR;
                    end
                endcase
            end
        end
    end

    // =========================================================================
    // AXI Read Channel State Machine
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_arready <= 1'b1;
            s_axi_rvalid  <= 1'b0;
            s_axi_rdata   <= {DATA_WIDTH{1'b0}};
            s_axi_rresp   <= RESP_OKAY;
            s_axi_rid     <= {ID_WIDTH{1'b0}};
            s_axi_rlast   <= 1'b1;
        end else begin
            // Complete R handshake
            if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid  <= 1'b0;
                s_axi_arready <= 1'b1;
            end

            // Accept Read Address and Form Read Response
            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_arready <= 1'b0;
                s_axi_rvalid  <= 1'b1;
                s_axi_rid     <= s_axi_arid;
                s_axi_rlast   <= 1'b1;

                case (s_axi_araddr[11:0])
                    REG_DMA_CONTROL: begin
                        // Bits: [1]=mode, [0]=0 (START pulse not readable)
                        s_axi_rdata <= {30'd0, reg_mode, 1'b0};
                        s_axi_rresp <= RESP_OKAY;
                    end

                    REG_DMA_STATUS: begin
                        // Bit 0: BUSY, Bit 1: DONE, Bit 2: ERROR
                        s_axi_rdata <= {29'd0, reg_error, reg_done, status_busy_i};
                        s_axi_rresp <= RESP_OKAY;
                    end

                    REG_DMA_SRC_ADDR: begin
                        s_axi_rdata <= reg_src_addr;
                        s_axi_rresp <= RESP_OKAY;
                    end

                    REG_DMA_DST_ADDR: begin
                        s_axi_rdata <= reg_dst_addr;
                        s_axi_rresp <= RESP_OKAY;
                    end

                    REG_DMA_INPUT_LEN: begin
                        s_axi_rdata <= {16'd0, reg_input_len};
                        s_axi_rresp <= RESP_OKAY;
                    end

                    REG_DMA_OUTPUT_LEN: begin
                        s_axi_rdata <= {16'd0, reg_output_len};
                        s_axi_rresp <= RESP_OKAY;
                    end

                    REG_DMA_IRQ_ENABLE: begin
                        s_axi_rdata <= {30'd0, reg_irq_enable};
                        s_axi_rresp <= RESP_OKAY;
                    end

                    REG_DMA_IRQ_STATUS: begin
                        s_axi_rdata <= {30'd0, reg_irq_status};
                        s_axi_rresp <= RESP_OKAY;
                    end

                    REG_DMA_ERROR_CODE: begin
                        s_axi_rdata <= {24'd0, reg_error_code};
                        s_axi_rresp <= RESP_OKAY;
                    end

                    default: begin
                        // Unmapped aperture read returns SLVERR
                        s_axi_rdata <= 32'hDEAD_BEEF;
                        s_axi_rresp <= RESP_SLVERR;
                    end
                endcase
            end
        end
    end

endmodule
`default_nettype wire
