// =============================================================================
// dma_master_engine.v
//
// DMA AXI4 Master Engine for RISC-V Configurable Data Compression SoC.
//
// Functionality:
//   - Performs autonomous 32-bit AXI4 read and write transfers to/from DMEM.
//   - Interconnect-facing: Fully compliant 32-bit AXI4 master interface with
//     independent AR, R, AW, W, and B channels.
//   - Sequencer-facing: Clean, decoupled request/data/response interface.
//   - Supports single-beat transfers (len=0) and INCR bursts (up to 256 beats).
//   - Manages WLAST and monitors RLAST.
//   - Supports partial-word writes with byte strobes (WSTRB).
//   - Fully supports backpressure on all address and data channels.
//   - Captures SLVERR and DECERR responses and reports them via error flags.
//   - Supports synchronous ABORT and asynchronous active-low reset recovery.
//
// Authors: SoC Development Team
// Date: October 2026
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module dma_master_engine #(
    parameter ADDR_WIDTH   = 32,
    parameter DATA_WIDTH   = 32,
    parameter STRB_WIDTH   = (DATA_WIDTH / 8),
    parameter ID_WIDTH     = 8,
    parameter AXI_ID       = 8'h30,       // Default DMA Master Transaction ID
    parameter ARCACHE_VAL  = 4'b0011,     // Normal Non-cacheable Bufferable
    parameter AWCACHE_VAL  = 4'b0011,     // Normal Non-cacheable Bufferable
    parameter ARPROT_VAL   = 3'b000,      // Unprivileged, Secure, Data
    parameter AWPROT_VAL   = 3'b000       // Unprivileged, Secure, Data
)(
    input  wire                    clk,
    input  wire                    rst_n,

    // =========================================================================
    // Sequencer / FSM Control & Data Interface
    // =========================================================================

    // Read Request Channel (DMA -> DMEM read)
    input  wire                    req_rd_start_i,   // Pulse: start read transaction
    input  wire [ADDR_WIDTH-1:0]   req_rd_addr_i,    // Start address in DMEM
    input  wire [7:0]              req_rd_len_i,     // Burst length: beats - 1 (0 = 1 beat)
    output wire [DATA_WIDTH-1:0]   rd_data_o,        // Read data beat to sink
    output wire                    rd_valid_o,       // Read data beat valid strobe
    input  wire                    rd_ready_i,       // Backpressure from sink (1 = ready)
    output wire                    rd_last_o,        // Final beat indication
    output reg                     rd_done_o,        // Pulsed high on successful read
    output reg                     rd_error_o,       // Pulsed high on read error (SLVERR/DECERR)
    output reg  [1:0]              rd_resp_o,        // Latched RRESP status

    // Write Request Channel (DMA -> DMEM write)
    input  wire                    req_wr_start_i,   // Pulse: start write transaction
    input  wire [ADDR_WIDTH-1:0]   req_wr_addr_i,    // Start address in DMEM
    input  wire [7:0]              req_wr_len_i,     // Burst length: beats - 1 (0 = 1 beat)
    input  wire [DATA_WIDTH-1:0]   wr_data_i,        // Write data beat from source
    input  wire [STRB_WIDTH-1:0]   wr_strb_i,        // Byte write strobes
    input  wire                    wr_valid_i,       // Write data beat valid from source
    output wire                    wr_ready_o,       // Engine ready to accept write beat
    output reg                     wr_done_o,        // Pulsed high on successful write
    output reg                     wr_error_o,       // Pulsed high on write error (SLVERR/DECERR)
    output reg  [1:0]              wr_resp_o,        // Latched BRESP status

    // Overall Status & Control
    output wire                    rd_busy_o,        // Read engine active
    output wire                    wr_busy_o,        // Write engine active
    output wire                    busy_o,           // Engine busy (read or write active)
    input  wire                    abort_i,          // Synchronous abort request

    // =========================================================================
    // AXI4 Master Interface (connected to SoC Interconnect)
    // =========================================================================

    // Read Address Channel (AR)
    output reg                     m_axi_arvalid,
    input  wire                    m_axi_arready,
    output wire [ID_WIDTH-1:0]     m_axi_arid,
    output reg  [ADDR_WIDTH-1:0]   m_axi_araddr,
    output reg  [7:0]              m_axi_arlen,
    output wire [2:0]              m_axi_arsize,
    output wire [1:0]              m_axi_arburst,
    output wire                    m_axi_arlock,
    output wire [3:0]              m_axi_arcache,
    output wire [2:0]              m_axi_arprot,
    output wire [3:0]              m_axi_arqos,
    output wire [3:0]              m_axi_arregion,
    output wire                    m_axi_aruser,

    // Read Data Channel (R)
    input  wire                    m_axi_rvalid,
    output wire                    m_axi_rready,
    input  wire [ID_WIDTH-1:0]     m_axi_rid,
    input  wire [DATA_WIDTH-1:0]   m_axi_rdata,
    input  wire [1:0]              m_axi_rresp,
    input  wire                    m_axi_rlast,
    input  wire                    m_axi_ruser,

    // Write Address Channel (AW)
    output reg                     m_axi_awvalid,
    input  wire                    m_axi_awready,
    output wire [ID_WIDTH-1:0]     m_axi_awid,
    output reg  [ADDR_WIDTH-1:0]   m_axi_awaddr,
    output reg  [7:0]              m_axi_awlen,
    output wire [2:0]              m_axi_awsize,
    output wire [1:0]              m_axi_awburst,
    output wire                    m_axi_awlock,
    output wire [3:0]              m_axi_awcache,
    output wire [2:0]              m_axi_awprot,
    output wire [3:0]              m_axi_awqos,
    output wire [3:0]              m_axi_awregion,
    output wire                    m_axi_awuser,

    // Write Data Channel (W)
    output wire                    m_axi_wvalid,
    input  wire                    m_axi_wready,
    output wire [DATA_WIDTH-1:0]   m_axi_wdata,
    output wire [STRB_WIDTH-1:0]   m_axi_wstrb,
    output wire                    m_axi_wlast,
    output wire                    m_axi_wuser,

    // Write Response Channel (B)
    input  wire                    m_axi_bvalid,
    output reg                     m_axi_bready,
    input  wire [1:0]              m_axi_bresp,
    input  wire [ID_WIDTH-1:0]     m_axi_bid,
    input  wire                    m_axi_buser
);

    // =========================================================================
    // Static / Configuration AXI Output Signals
    // =========================================================================
    assign m_axi_arid      = AXI_ID[ID_WIDTH-1:0];
    assign m_axi_arsize    = 3'b010;             // 4 bytes (32-bit transfer)
    assign m_axi_arburst   = 2'b01;              // INCR burst mode
    assign m_axi_arlock    = 1'b0;               // Normal access
    assign m_axi_arcache   = ARCACHE_VAL;
    assign m_axi_arprot    = ARPROT_VAL;
    assign m_axi_arqos     = 4'b0000;
    assign m_axi_arregion  = 4'b0000;
    assign m_axi_aruser    = 1'b0;

    assign m_axi_awid      = AXI_ID[ID_WIDTH-1:0];
    assign m_axi_awsize    = 3'b010;             // 4 bytes (32-bit transfer)
    assign m_axi_awburst   = 2'b01;              // INCR burst mode
    assign m_axi_awlock    = 1'b0;               // Normal access
    assign m_axi_awcache   = AWCACHE_VAL;
    assign m_axi_awprot    = AWPROT_VAL;
    assign m_axi_awqos     = 4'b0000;
    assign m_axi_awregion  = 4'b0000;
    assign m_axi_awuser    = 1'b0;
    assign m_axi_wuser     = 1'b0;

    // =========================================================================
    // Read Engine FSM & Datapath
    // =========================================================================
    localparam [1:0]
        RD_STATE_IDLE    = 2'd0,
        RD_STATE_ADDR    = 2'd1,
        RD_STATE_DATA    = 2'd2,
        RD_STATE_FINISH  = 2'd3;

    reg [1:0]  state_rd;
    reg [7:0]  rd_beats_expected;
    reg [7:0]  rd_beat_cnt;
    reg        rd_err_latch;
    reg [1:0]  rd_resp_latch;
    reg        rd_busy_reg;

    assign rd_busy_o = rd_busy_reg;

    // R channel handshake to sink
    // We assert m_axi_rready when in RD_STATE_DATA and the sink indicates rd_ready_i
    assign m_axi_rready = (state_rd == RD_STATE_DATA) && rd_ready_i && !abort_i;
    assign rd_data_o    = m_axi_rdata;
    assign rd_valid_o   = (state_rd == RD_STATE_DATA) && m_axi_rvalid && rd_ready_i && !abort_i;
    assign rd_last_o    = (state_rd == RD_STATE_DATA) && (m_axi_rlast || (rd_beat_cnt == rd_beats_expected))
                          && m_axi_rvalid && rd_ready_i && !abort_i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_rd          <= RD_STATE_IDLE;
            m_axi_arvalid     <= 1'b0;
            m_axi_araddr      <= {ADDR_WIDTH{1'b0}};
            m_axi_arlen       <= 8'h00;
            rd_beats_expected <= 8'h00;
            rd_beat_cnt       <= 8'h00;
            rd_err_latch      <= 1'b0;
            rd_resp_latch     <= 2'b00;
            rd_busy_reg       <= 1'b0;
            rd_done_o         <= 1'b0;
            rd_error_o        <= 1'b0;
            rd_resp_o         <= 2'b00;
        end else if (abort_i) begin
            state_rd          <= RD_STATE_IDLE;
            m_axi_arvalid     <= 1'b0;
            rd_busy_reg       <= 1'b0;
            rd_done_o         <= 1'b0;
            rd_error_o        <= 1'b0;
            rd_beat_cnt       <= 8'h00;
            rd_err_latch      <= 1'b0;
        end else begin
            // Default 1-cycle pulses
            rd_done_o  <= 1'b0;
            rd_error_o <= 1'b0;

            case (state_rd)
                RD_STATE_IDLE: begin
                    if (req_rd_start_i) begin
                        rd_busy_reg       <= 1'b1;
                        m_axi_araddr      <= req_rd_addr_i;
                        m_axi_arlen       <= req_rd_len_i;
                        rd_beats_expected <= req_rd_len_i;
                        rd_beat_cnt       <= 8'h00;
                        rd_err_latch      <= 1'b0;
                        rd_resp_latch     <= 2'b00;
                        m_axi_arvalid     <= 1'b1;
                        state_rd          <= RD_STATE_ADDR;
                    end else begin
                        rd_busy_reg       <= 1'b0;
                    end
                end

                RD_STATE_ADDR: begin
                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        state_rd      <= RD_STATE_DATA;
                    end
                end

                RD_STATE_DATA: begin
                    // Read beat accepted
                    if (m_axi_rvalid && m_axi_rready) begin
                        // Check response
                        if (m_axi_rresp[1]) begin
                            rd_err_latch  <= 1'b1;
                            rd_resp_latch <= m_axi_rresp;
                        end

                        rd_beat_cnt <= rd_beat_cnt + 1'b1;

                        // Burst end detected by rlast or beat count matching expected
                        if (m_axi_rlast || (rd_beat_cnt == rd_beats_expected)) begin
                            state_rd <= RD_STATE_FINISH;
                        end
                    end
                end

                RD_STATE_FINISH: begin
                    rd_busy_reg <= 1'b0;
                    rd_resp_o   <= rd_resp_latch;
                    if (rd_err_latch) begin
                        rd_error_o <= 1'b1;
                        rd_done_o  <= 1'b0;
                    end else begin
                        rd_done_o  <= 1'b1;
                        rd_error_o <= 1'b0;
                    end
                    state_rd <= RD_STATE_IDLE;
                end

                default: state_rd <= RD_STATE_IDLE;
            endcase
        end
    end

    // =========================================================================
    // Write Engine FSM & Datapath
    // =========================================================================
    localparam [2:0]
        WR_STATE_IDLE    = 3'd0,
        WR_STATE_ACTIVE  = 3'd1,
        WR_STATE_RESP    = 3'd2,
        WR_STATE_FINISH  = 3'd3;

    reg [2:0]  state_wr;
    reg        aw_pending;
    reg        w_pending;
    reg [7:0]  wr_beats_expected;
    reg [7:0]  wr_beat_cnt;
    reg        wr_err_latch;
    reg [1:0]  wr_resp_latch;
    reg        wr_busy_reg;

    assign wr_busy_o = wr_busy_reg;

    // W channel data & handshakes
    assign m_axi_wdata  = wr_data_i;
    assign m_axi_wstrb  = wr_strb_i;
    assign m_axi_wvalid = (state_wr == WR_STATE_ACTIVE) && w_pending && wr_valid_i && !abort_i;
    assign m_axi_wlast  = (wr_beat_cnt == wr_beats_expected);
    assign wr_ready_o   = (state_wr == WR_STATE_ACTIVE) && w_pending && m_axi_wready && !abort_i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_wr          <= WR_STATE_IDLE;
            m_axi_awvalid     <= 1'b0;
            m_axi_awaddr      <= {ADDR_WIDTH{1'b0}};
            m_axi_awlen       <= 8'h00;
            m_axi_bready      <= 1'b0;
            aw_pending        <= 1'b0;
            w_pending         <= 1'b0;
            wr_beats_expected <= 8'h00;
            wr_beat_cnt       <= 8'h00;
            wr_err_latch      <= 1'b0;
            wr_resp_latch     <= 2'b00;
            wr_busy_reg       <= 1'b0;
            wr_done_o         <= 1'b0;
            wr_error_o        <= 1'b0;
            wr_resp_o         <= 2'b00;
        end else if (abort_i) begin
            state_wr          <= WR_STATE_IDLE;
            m_axi_awvalid     <= 1'b0;
            m_axi_bready      <= 1'b0;
            aw_pending        <= 1'b0;
            w_pending         <= 1'b0;
            wr_busy_reg       <= 1'b0;
            wr_done_o         <= 1'b0;
            wr_error_o        <= 1'b0;
            wr_beat_cnt       <= 8'h00;
            wr_err_latch      <= 1'b0;
        end else begin
            // Default 1-cycle pulses
            wr_done_o  <= 1'b0;
            wr_error_o <= 1'b0;

            case (state_wr)
                WR_STATE_IDLE: begin
                    if (req_wr_start_i) begin
                        wr_busy_reg       <= 1'b1;
                        m_axi_awaddr      <= req_wr_addr_i;
                        m_axi_awlen       <= req_wr_len_i;
                        wr_beats_expected <= req_wr_len_i;
                        wr_beat_cnt       <= 8'h00;
                        wr_err_latch      <= 1'b0;
                        wr_resp_latch     <= 2'b00;
                        m_axi_awvalid     <= 1'b1;
                        aw_pending        <= 1'b1;
                        w_pending         <= 1'b1;
                        state_wr          <= WR_STATE_ACTIVE;
                    end else begin
                        wr_busy_reg       <= 1'b0;
                    end
                end

                WR_STATE_ACTIVE: begin
                    // AW Channel Handshake
                    if (m_axi_awvalid && m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        aw_pending    <= 1'b0;
                    end

                    // W Channel Handshake
                    if (m_axi_wvalid && m_axi_wready) begin
                        wr_beat_cnt <= wr_beat_cnt + 1'b1;
                        if (wr_beat_cnt == wr_beats_expected) begin
                            w_pending <= 1'b0;
                        end
                    end

                    // Transition to B response state when both AW and all W beats are done
                    // Note: We check if AW is already cleared or clearing right now, and similarly for W.
                    if ((!aw_pending || (m_axi_awvalid && m_axi_awready)) &&
                        (!w_pending  || (m_axi_wvalid  && m_axi_wready && (wr_beat_cnt == wr_beats_expected)))) begin
                        m_axi_bready <= 1'b1;
                        state_wr     <= WR_STATE_RESP;
                    end
                end

                WR_STATE_RESP: begin
                    m_axi_bready <= 1'b1;
                    if (m_axi_bvalid && m_axi_bready) begin
                        m_axi_bready  <= 1'b0;
                        wr_resp_latch <= m_axi_bresp;
                        if (m_axi_bresp[1]) begin
                            wr_err_latch <= 1'b1;
                        end
                        state_wr <= WR_STATE_FINISH;
                    end
                end

                WR_STATE_FINISH: begin
                    wr_busy_reg <= 1'b0;
                    wr_resp_o   <= wr_resp_latch;
                    if (wr_err_latch) begin
                        wr_error_o <= 1'b1;
                        wr_done_o  <= 1'b0;
                    end else begin
                        wr_done_o  <= 1'b1;
                        wr_error_o <= 1'b0;
                    end
                    state_wr <= WR_STATE_IDLE;
                end

                default: state_wr <= WR_STATE_IDLE;
            endcase
        end
    end

    // Overall Busy
    assign busy_o = rd_busy_reg | wr_busy_reg;

endmodule

`default_nettype wire
