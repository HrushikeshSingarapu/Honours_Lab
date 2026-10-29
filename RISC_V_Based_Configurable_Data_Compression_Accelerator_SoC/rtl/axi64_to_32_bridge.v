// =============================================================================
// axi64_to_32_bridge.v
//
// PURPOSE:
//   Bridges a 64-bit AXI4 master interface (VeeR EL2 IFU / LSU / SB) down to a
//   32-bit AXI4 interconnect fabric.
//
// FUNCTIONALITY & ARCHITECTURE:
//   1. Read Path:
//      - 64-bit reads (arsize == 3'b011, e.g. VeeR IFU instruction fetch):
//        Converted into a 2-beat 32-bit INCR burst (arsize = 3'b010, arlen = 1).
//        Beat 0 (addr+0) is captured into a hold register.
//        Beat 1 (addr+4) is combined with Beat 0 to assemble the full 64-bit
//        word: m_axi_rdata = {beat1, beat0}, delivered with m_axi_rlast = 1.
//        Errors (rresp != 0) on either beat are propagated upstream.
//      - <= 32-bit reads (arsize <= 3'b010, e.g. VeeR LSU MMIO access):
//        Issued downstream as 32-bit single beat with exact address.
//        If addr[2] == 0: data placed on lower 32 bits [31:0], upper zero-extended.
//        If addr[2] == 1: data placed on upper 32 bits [63:32], lower zero-extended.
//   2. Write Path:
//      - Independent AW and W channel handling:
//        Supports AW-before-W, W-before-AW, and simultaneous AW/W arrival.
//      - 64-bit writes (|wstrb[3:0] && |wstrb[7:4]):
//        Converted into a 2-beat 32-bit INCR burst (awsize = 3'b010, awlen = 1).
//        Beat 0 writes m_axi_wdata[31:0] with strobes m_axi_wstrb[3:0].
//        Beat 1 writes m_axi_wdata[63:32] with strobes m_axi_wstrb[7:4].
//        Both 32-bit halves and their exact byte strobes are preserved.
//      - Single-word / Sub-word writes:
//        If only wstrb[3:0] active: writes lower word [31:0] at addr.
//        If only wstrb[7:4] active: writes upper word [63:32] at addr (addr[2]=1).
//      - Upstream write response (m_axi_bvalid) is asserted ONLY after downstream
//        write transaction completes.
//   3. Flow Control & Backpressure:
//      - Full handshake stability under downstream and upstream backpressure.
//      - Upstream arready / awready / wready throttle incoming transactions while
//        a split transaction is in flight, preventing buffer overrun and out-of-order
//        race conditions.
//      - Independent concurrent operation between Read and Write engines.
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

module axi64_to_32_bridge #(
    parameter ADDR_WIDTH = 32,
    parameter ID_WIDTH   = 8
)(
    input  wire                  clk,
    input  wire                  rst,    // active-high synchronous reset

    // ---- 64-bit master side (connects to VeeR IFU / LSU / SB) ----
    // Write Address Channel
    input  wire                  m_axi_awvalid,
    output reg                   m_axi_awready,
    input  wire [ID_WIDTH-1:0]   m_axi_awid,
    input  wire [ADDR_WIDTH-1:0] m_axi_awaddr,
    input  wire [7:0]            m_axi_awlen,
    input  wire [2:0]            m_axi_awsize,
    input  wire [1:0]            m_axi_awburst,
    input  wire                  m_axi_awlock,
    input  wire [3:0]            m_axi_awcache,
    input  wire [2:0]            m_axi_awprot,
    input  wire [3:0]            m_axi_awqos,
    input  wire [3:0]            m_axi_awregion,
    // Write Data Channel
    input  wire                  m_axi_wvalid,
    output reg                   m_axi_wready,
    input  wire [63:0]           m_axi_wdata,
    input  wire [7:0]            m_axi_wstrb,
    input  wire                  m_axi_wlast,
    // Write Response Channel
    output reg                   m_axi_bvalid,
    input  wire                  m_axi_bready,
    output reg  [1:0]            m_axi_bresp,
    output reg  [ID_WIDTH-1:0]   m_axi_bid,
    // Read Address Channel
    input  wire                  m_axi_arvalid,
    output reg                   m_axi_arready,
    input  wire [ID_WIDTH-1:0]   m_axi_arid,
    input  wire [ADDR_WIDTH-1:0] m_axi_araddr,
    input  wire [7:0]            m_axi_arlen,
    input  wire [2:0]            m_axi_arsize,
    input  wire [1:0]            m_axi_arburst,
    input  wire                  m_axi_arlock,
    input  wire [3:0]            m_axi_arcache,
    input  wire [2:0]            m_axi_arprot,
    input  wire [3:0]            m_axi_arqos,
    input  wire [3:0]            m_axi_arregion,
    // Read Data Channel
    output reg                   m_axi_rvalid,
    input  wire                  m_axi_rready,
    output reg  [ID_WIDTH-1:0]   m_axi_rid,
    output reg  [63:0]           m_axi_rdata,
    output reg  [1:0]            m_axi_rresp,
    output reg                   m_axi_rlast,

    // ---- 32-bit slave side (connects to AXI interconnect master port) ----
    // Write Address Channel
    output reg                   s_axi_awvalid,
    input  wire                  s_axi_awready,
    output reg  [ID_WIDTH-1:0]   s_axi_awid,
    output reg  [ADDR_WIDTH-1:0] s_axi_awaddr,
    output reg  [7:0]            s_axi_awlen,
    output reg  [2:0]            s_axi_awsize,
    output reg  [1:0]            s_axi_awburst,
    output wire                  s_axi_awlock,
    output wire [3:0]            s_axi_awcache,
    output wire [2:0]            s_axi_awprot,
    output wire [3:0]            s_axi_awqos,
    output wire                  s_axi_awuser,
    // Write Data Channel
    output reg                   s_axi_wvalid,
    input  wire                  s_axi_wready,
    output reg  [31:0]           s_axi_wdata,
    output reg  [3:0]            s_axi_wstrb,
    output reg                   s_axi_wlast,
    output wire                  s_axi_wuser,
    // Write Response Channel
    input  wire                  s_axi_bvalid,
    output reg                   s_axi_bready,
    input  wire [1:0]            s_axi_bresp,
    input  wire [ID_WIDTH-1:0]   s_axi_bid,
    input  wire                  s_axi_buser,
    // Read Address Channel
    output reg                   s_axi_arvalid,
    input  wire                  s_axi_arready,
    output reg  [ID_WIDTH-1:0]   s_axi_arid,
    output reg  [ADDR_WIDTH-1:0] s_axi_araddr,
    output reg  [7:0]            s_axi_arlen,
    output reg  [2:0]            s_axi_arsize,
    output reg  [1:0]            s_axi_arburst,
    output wire                  s_axi_arlock,
    output wire [3:0]            s_axi_arcache,
    output wire [2:0]            s_axi_arprot,
    output wire [3:0]            s_axi_arqos,
    output wire                  s_axi_aruser,
    // Read Data Channel
    input  wire                  s_axi_rvalid,
    output reg                   s_axi_rready,
    input  wire [ID_WIDTH-1:0]   s_axi_rid,
    input  wire [31:0]           s_axi_rdata,
    input  wire [1:0]            s_axi_rresp,
    input  wire                  s_axi_rlast,
    input  wire                  s_axi_ruser
);

    // Static / unused control wires
    assign s_axi_awlock  = 1'b0;
    assign s_axi_awcache = 4'b0000;
    assign s_axi_awprot  = 3'b000;
    assign s_axi_awqos   = 4'b0000;
    assign s_axi_awuser  = 1'b0;
    assign s_axi_wuser   = 1'b0;
    assign s_axi_arlock  = 1'b0;
    assign s_axi_arcache = 4'b0000;
    assign s_axi_arprot  = 3'b000;
    assign s_axi_arqos   = 4'b0000;
    assign s_axi_aruser  = 1'b0;

    // =========================================================================
    // READ PATH ENGINE
    // =========================================================================
    localparam [2:0]
        RD_STATE_IDLE       = 3'd0,
        RD_STATE_AR_WAIT    = 3'd1,
        RD_STATE_COLLECT_B0 = 3'd2,
        RD_STATE_COLLECT_B1 = 3'd3,
        RD_STATE_DIRECT_32  = 3'd4;

    reg [2:0]            rd_state;
    reg [ID_WIDTH-1:0]   rd_id_r;
    reg [ADDR_WIDTH-1:0] rd_addr_r;
    reg [2:0]            rd_size_r;
    reg [7:0]            rd_len_r;
    reg [1:0]            rd_burst_r;
    reg                  rd_lane_r;
    reg [31:0]           rdata_b0_hold;
    reg [1:0]            rresp_b0_hold;

    always @(posedge clk) begin
        if (rst) begin
            rd_state       <= RD_STATE_IDLE;
            m_axi_arready  <= 1'b0;
            s_axi_arvalid  <= 1'b0;
            s_axi_arid     <= {ID_WIDTH{1'b0}};
            s_axi_araddr   <= {ADDR_WIDTH{1'b0}};
            s_axi_arlen    <= 8'h00;
            s_axi_arsize   <= 3'b010;
            s_axi_arburst  <= 2'b01;
            m_axi_rvalid   <= 1'b0;
            m_axi_rdata    <= 64'h0;
            m_axi_rresp    <= 2'b00;
            m_axi_rid      <= {ID_WIDTH{1'b0}};
            m_axi_rlast    <= 1'b0;
            s_axi_rready   <= 1'b0;
            rd_id_r        <= {ID_WIDTH{1'b0}};
            rd_addr_r      <= {ADDR_WIDTH{1'b0}};
            rd_size_r      <= 3'b010;
            rd_len_r       <= 8'h00;
            rd_burst_r     <= 2'b01;
            rd_lane_r      <= 1'b0;
            rdata_b0_hold  <= 32'h0;
            rresp_b0_hold  <= 2'b00;
        end else begin
            case (rd_state)
                RD_STATE_IDLE: begin
                    m_axi_arready <= 1'b1;
                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arready <= 1'b0;
                        rd_id_r       <= m_axi_arid;
                        rd_addr_r     <= m_axi_araddr;
                        rd_size_r     <= m_axi_arsize;
                        rd_len_r      <= m_axi_arlen;
                        rd_burst_r    <= m_axi_arburst;
                        rd_lane_r     <= m_axi_araddr[2];

                        // Prepare downstream AR
                        s_axi_arvalid <= 1'b1;
                        s_axi_arid    <= m_axi_arid;
                        s_axi_arburst <= m_axi_arburst;

                        if (m_axi_arsize == 3'b011) begin
                            // 64-bit read: downsize to 2-beat 32-bit INCR burst
                            s_axi_araddr  <= {m_axi_araddr[31:3], 3'b000};
                            s_axi_arsize  <= 3'b010;
                            s_axi_arlen   <= (m_axi_arlen << 1) | 8'h01;
                            s_axi_arburst <= 2'b01; // INCR
                        end else begin
                            // <= 32-bit read: pass through size and address
                            s_axi_araddr  <= m_axi_araddr;
                            s_axi_arsize  <= m_axi_arsize;
                            s_axi_arlen   <= m_axi_arlen;
                        end

                        rd_state <= RD_STATE_AR_WAIT;
                    end
                end

                RD_STATE_AR_WAIT: begin
                    if (s_axi_arvalid && s_axi_arready) begin
                        s_axi_arvalid <= 1'b0;
                        s_axi_rready  <= 1'b1;
                        if (rd_size_r == 3'b011) begin
                            rd_state <= RD_STATE_COLLECT_B0;
                        end else begin
                            rd_state <= RD_STATE_DIRECT_32;
                        end
                    end
                end

                RD_STATE_COLLECT_B0: begin
                    s_axi_rready <= 1'b1;
                    if (s_axi_rvalid && s_axi_rready) begin
                        rdata_b0_hold <= s_axi_rdata;
                        rresp_b0_hold <= s_axi_rresp;
                        s_axi_rready  <= 1'b1;
                        rd_state      <= RD_STATE_COLLECT_B1;
                    end
                end

                RD_STATE_COLLECT_B1: begin
                    // Enable downstream read ready only when master is ready or not yet asserting
                    s_axi_rready <= !m_axi_rvalid || m_axi_rready;

                    if (s_axi_rvalid && s_axi_rready && !m_axi_rvalid) begin
                        // Assemble 64-bit read data: {upper_word (beat 1), lower_word (beat 0)}
                        m_axi_rdata  <= {s_axi_rdata, rdata_b0_hold};
                        m_axi_rresp  <= s_axi_rresp | rresp_b0_hold; // propagate errors
                        m_axi_rid    <= rd_id_r;
                        m_axi_rlast  <= s_axi_rlast;
                        m_axi_rvalid <= 1'b1;
                        s_axi_rready <= 1'b0;
                    end

                    if (m_axi_rvalid && m_axi_rready) begin
                        m_axi_rvalid <= 1'b0;
                        if (m_axi_rlast) begin
                            m_axi_arready <= 1'b1;
                            rd_state      <= RD_STATE_IDLE;
                        end else begin
                            s_axi_rready  <= 1'b1;
                            rd_state      <= RD_STATE_COLLECT_B0;
                        end
                    end
                end

                RD_STATE_DIRECT_32: begin
                    // Direct 32-bit pass-through with lane steering
                    s_axi_rready <= !m_axi_rvalid || m_axi_rready;

                    if (s_axi_rvalid && s_axi_rready && !m_axi_rvalid) begin
                        m_axi_rvalid <= 1'b1;
                        m_axi_rdata  <= rd_lane_r ? {s_axi_rdata, 32'h0000_0000}
                                                  : {32'h0000_0000, s_axi_rdata};
                        m_axi_rresp  <= s_axi_rresp;
                        m_axi_rid    <= s_axi_rid;
                        m_axi_rlast  <= s_axi_rlast;
                        s_axi_rready <= 1'b0;
                    end

                    if (m_axi_rvalid && m_axi_rready) begin
                        m_axi_rvalid <= 1'b0;
                        if (rd_burst_r == 2'b01) begin
                            rd_lane_r <= ~rd_lane_r; // alternate lane on INCR bursts
                        end
                        if (m_axi_rlast) begin
                            m_axi_arready <= 1'b1;
                            rd_state      <= RD_STATE_IDLE;
                        end
                    end
                end

                default: rd_state <= RD_STATE_IDLE;
            endcase
        end
    end

    // =========================================================================
    // WRITE PATH ENGINE
    // =========================================================================
    localparam [3:0]
        WR_STATE_IDLE         = 4'd0,
        WR_STATE_WAIT_W       = 4'd1,
        WR_STATE_WAIT_AW      = 4'd2,
        WR_STATE_DECIDE       = 4'd3,
        WR_STATE_SEND_SINGLE  = 4'd4,
        WR_STATE_SPLIT_AW     = 4'd5,
        WR_STATE_SPLIT_W0     = 4'd6,
        WR_STATE_SPLIT_W1     = 4'd7,
        WR_STATE_WAIT_B       = 4'd8,
        WR_STATE_RESP_UP      = 4'd9;

    reg [3:0]            wr_state;
    reg [ID_WIDTH-1:0]   wr_id_r;
    reg [ADDR_WIDTH-1:0] wr_addr_r;
    reg [2:0]            wr_size_r;
    reg [7:0]            wr_len_r;
    reg [1:0]            wr_burst_r;
    reg [63:0]           wr_wdata_r;
    reg [7:0]            wr_wstrb_r;
    reg                  wr_wlast_r;
    reg [31:0]           wr_lane_data;
    reg [3:0]            wr_lane_strb;
    reg [ADDR_WIDTH-1:0] wr_target_addr;
    reg                  aw_sent;
    reg                  w_sent;
    reg [1:0]            bresp_hold;

    always @(posedge clk) begin
        if (rst) begin
            wr_state        <= WR_STATE_IDLE;
            m_axi_awready   <= 1'b0;
            m_axi_wready    <= 1'b0;
            m_axi_bvalid    <= 1'b0;
            m_axi_bresp     <= 2'b00;
            m_axi_bid       <= {ID_WIDTH{1'b0}};
            s_axi_awvalid   <= 1'b0;
            s_axi_awid      <= {ID_WIDTH{1'b0}};
            s_axi_awaddr    <= {ADDR_WIDTH{1'b0}};
            s_axi_awlen     <= 8'h00;
            s_axi_awsize    <= 3'b010;
            s_axi_awburst   <= 2'b01;
            s_axi_wvalid    <= 1'b0;
            s_axi_wdata     <= 32'h0;
            s_axi_wstrb     <= 4'h0;
            s_axi_wlast     <= 1'b0;
            s_axi_bready    <= 1'b0;
            wr_id_r         <= {ID_WIDTH{1'b0}};
            wr_addr_r       <= {ADDR_WIDTH{1'b0}};
            wr_size_r       <= 3'b010;
            wr_len_r        <= 8'h00;
            wr_burst_r      <= 2'b01;
            wr_wdata_r      <= 64'h0;
            wr_wstrb_r      <= 8'h00;
            wr_wlast_r      <= 1'b0;
            wr_lane_data    <= 32'h0;
            wr_lane_strb    <= 4'h0;
            wr_target_addr  <= {ADDR_WIDTH{1'b0}};
            aw_sent         <= 1'b0;
            w_sent          <= 1'b0;
            bresp_hold      <= 2'b00;
        end else begin
            case (wr_state)
                WR_STATE_IDLE: begin
                    m_axi_awready <= 1'b1;
                    m_axi_wready  <= 1'b1;

                    if (m_axi_awvalid && m_axi_awready && m_axi_wvalid && m_axi_wready) begin
                        // Simultaneous AW and W handshake
                        m_axi_awready <= 1'b0;
                        m_axi_wready  <= 1'b0;
                        wr_id_r       <= m_axi_awid;
                        wr_addr_r     <= m_axi_awaddr;
                        wr_size_r     <= m_axi_awsize;
                        wr_len_r      <= m_axi_awlen;
                        wr_burst_r    <= m_axi_awburst;
                        wr_wdata_r    <= m_axi_wdata;
                        wr_wstrb_r    <= m_axi_wstrb;
                        wr_wlast_r    <= m_axi_wlast;
                        wr_state      <= WR_STATE_DECIDE;
                    end else if (m_axi_awvalid && m_axi_awready) begin
                        // AW arrived before W
                        m_axi_awready <= 1'b0;
                        m_axi_wready  <= 1'b1;
                        wr_id_r       <= m_axi_awid;
                        wr_addr_r     <= m_axi_awaddr;
                        wr_size_r     <= m_axi_awsize;
                        wr_len_r      <= m_axi_awlen;
                        wr_burst_r    <= m_axi_awburst;
                        wr_state      <= WR_STATE_WAIT_W;
                    end else if (m_axi_wvalid && m_axi_wready) begin
                        // W arrived before AW
                        m_axi_awready <= 1'b1;
                        m_axi_wready  <= 1'b0;
                        wr_wdata_r    <= m_axi_wdata;
                        wr_wstrb_r    <= m_axi_wstrb;
                        wr_wlast_r    <= m_axi_wlast;
                        wr_state      <= WR_STATE_WAIT_AW;
                    end
                end

                WR_STATE_WAIT_W: begin
                    m_axi_awready <= 1'b0;
                    m_axi_wready  <= 1'b1;
                    if (m_axi_wvalid && m_axi_wready) begin
                        m_axi_wready <= 1'b0;
                        wr_wdata_r   <= m_axi_wdata;
                        wr_wstrb_r   <= m_axi_wstrb;
                        wr_wlast_r   <= m_axi_wlast;
                        wr_state     <= WR_STATE_DECIDE;
                    end
                end

                WR_STATE_WAIT_AW: begin
                    m_axi_awready <= 1'b1;
                    m_axi_wready  <= 1'b0;
                    if (m_axi_awvalid && m_axi_awready) begin
                        m_axi_awready <= 1'b0;
                        wr_id_r       <= m_axi_awid;
                        wr_addr_r     <= m_axi_awaddr;
                        wr_size_r     <= m_axi_awsize;
                        wr_len_r      <= m_axi_awlen;
                        wr_burst_r    <= m_axi_awburst;
                        wr_state      <= WR_STATE_DECIDE;
                    end
                end

                WR_STATE_DECIDE: begin
                    m_axi_awready <= 1'b0;
                    m_axi_wready  <= 1'b0;
                    aw_sent       <= 1'b0;
                    w_sent        <= 1'b0;

                    if ((|wr_wstrb_r[3:0]) && (|wr_wstrb_r[7:4])) begin
                        // True 64-bit write across both words -> Split into 2-beat 32-bit burst
                        s_axi_awvalid <= 1'b1;
                        s_axi_awid    <= wr_id_r;
                        s_axi_awaddr  <= {wr_addr_r[31:3], 3'b000};
                        s_axi_awsize  <= 3'b010; // 32-bit
                        s_axi_awlen   <= 8'h01; // 2 beats
                        s_axi_awburst <= 2'b01; // INCR
                        wr_state      <= WR_STATE_SPLIT_AW;
                    end else if ((|wr_wstrb_r[7:4]) || ((wr_wstrb_r == 8'h00) && wr_addr_r[2])) begin
                        // Single-beat write to upper 32-bit word lane
                        wr_lane_data   <= wr_wdata_r[63:32];
                        wr_lane_strb   <= wr_wstrb_r[7:4];
                        wr_target_addr <= {wr_addr_r[31:3], 1'b1, wr_addr_r[1:0]};

                        s_axi_awvalid  <= 1'b1;
                        s_axi_awid     <= wr_id_r;
                        s_axi_awaddr   <= {wr_addr_r[31:3], 1'b1, wr_addr_r[1:0]};
                        s_axi_awlen    <= 8'h00;
                        s_axi_awsize   <= (wr_size_r == 3'b011) ? 3'b010 : wr_size_r;
                        s_axi_awburst  <= wr_burst_r;

                        s_axi_wvalid   <= 1'b1;
                        s_axi_wdata    <= wr_wdata_r[63:32];
                        s_axi_wstrb    <= wr_wstrb_r[7:4];
                        s_axi_wlast    <= 1'b1;

                        wr_state       <= WR_STATE_SEND_SINGLE;
                    end else begin
                        // Single-beat write to lower 32-bit word lane
                        wr_lane_data   <= wr_wdata_r[31:0];
                        wr_lane_strb   <= wr_wstrb_r[3:0];
                        wr_target_addr <= {wr_addr_r[31:3], 1'b0, wr_addr_r[1:0]};

                        s_axi_awvalid  <= 1'b1;
                        s_axi_awid     <= wr_id_r;
                        s_axi_awaddr   <= {wr_addr_r[31:3], 1'b0, wr_addr_r[1:0]};
                        s_axi_awlen    <= 8'h00;
                        s_axi_awsize   <= (wr_size_r == 3'b011) ? 3'b010 : wr_size_r;
                        s_axi_awburst  <= wr_burst_r;

                        s_axi_wvalid   <= 1'b1;
                        s_axi_wdata    <= wr_wdata_r[31:0];
                        s_axi_wstrb    <= wr_wstrb_r[3:0];
                        s_axi_wlast    <= 1'b1;

                        wr_state       <= WR_STATE_SEND_SINGLE;
                    end
                end

                WR_STATE_SEND_SINGLE: begin
                    if (s_axi_awvalid && s_axi_awready) begin
                        s_axi_awvalid <= 1'b0;
                        aw_sent       <= 1'b1;
                    end
                    if (s_axi_wvalid && s_axi_wready) begin
                        s_axi_wvalid <= 1'b0;
                        w_sent       <= 1'b1;
                    end

                    if ((aw_sent || (s_axi_awvalid && s_axi_awready)) &&
                        (w_sent  || (s_axi_wvalid && s_axi_wready))) begin
                        s_axi_bready <= 1'b1;
                        wr_state     <= WR_STATE_WAIT_B;
                    end
                end

                WR_STATE_SPLIT_AW: begin
                    if (s_axi_awvalid && s_axi_awready) begin
                        s_axi_awvalid <= 1'b0;

                        // Send Beat 0 (lower 32-bit word)
                        s_axi_wvalid  <= 1'b1;
                        s_axi_wdata   <= wr_wdata_r[31:0];
                        s_axi_wstrb   <= wr_wstrb_r[3:0];
                        s_axi_wlast   <= 1'b0;
                        wr_state      <= WR_STATE_SPLIT_W0;
                    end
                end

                WR_STATE_SPLIT_W0: begin
                    if (s_axi_wvalid && s_axi_wready) begin
                        // Send Beat 1 (upper 32-bit word)
                        s_axi_wvalid <= 1'b1;
                        s_axi_wdata  <= wr_wdata_r[63:32];
                        s_axi_wstrb  <= wr_wstrb_r[7:4];
                        s_axi_wlast  <= 1'b1;
                        wr_state     <= WR_STATE_SPLIT_W1;
                    end
                end

                WR_STATE_SPLIT_W1: begin
                    if (s_axi_wvalid && s_axi_wready) begin
                        s_axi_wvalid <= 1'b0;
                        s_axi_bready <= 1'b1;
                        wr_state     <= WR_STATE_WAIT_B;
                    end
                end

                WR_STATE_WAIT_B: begin
                    s_axi_bready <= 1'b1;
                    if (s_axi_bvalid && s_axi_bready) begin
                        s_axi_bready <= 1'b0;
                        bresp_hold   <= s_axi_bresp;
                        m_axi_bvalid <= 1'b1;
                        m_axi_bresp  <= s_axi_bresp;
                        m_axi_bid    <= wr_id_r;
                        wr_state     <= WR_STATE_RESP_UP;
                    end
                end

                WR_STATE_RESP_UP: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        m_axi_bvalid  <= 1'b0;
                        m_axi_awready <= 1'b1;
                        m_axi_wready  <= 1'b1;
                        wr_state      <= WR_STATE_IDLE;
                    end
                end

                default: wr_state <= WR_STATE_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
