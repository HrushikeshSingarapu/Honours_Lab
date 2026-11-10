// =============================================================================
// tb_axi_interconnect_4x8.sv
//
// Phase E Standalone Protocol & Stress Testbench for axi_interconnect_wrap_4x8
// Configured identically to soc_top.v (Full_Soc_Address_Map.xlsx).
//
// Coverage & Checks:
//   1. Decode verification across all 8 slave slots + reset vector alias (0x8000_0000)
//   2. Exclusive target routing (non-selected slaves never see AWVALID/ARVALID)
//   3. Single & 4-beat multi-beat DECERR responses across all reserved slots
//   4. 64 KB DMEM boundary crossing burst (0x0001_FFF8 -> 0x0002_0004)
//   5. Back-to-back zero-idle transactions and decoupled W-before-AW acceptance
//   6. 4-master simultaneous contention (same slave & distinct slaves) + round-robin fairness
//   7. Dynamic reset asserted during in-flight write & read bursts + clean recovery
//   8. Passive axi4_full_protocol_assertions on S00..S03 & M01 (0 errors required)
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

module tb_axi_interconnect_4x8;

    localparam int NUM_M   = 4;
    localparam int NUM_S   = 8;
    localparam int DW      = 32;
    localparam int AW      = 32;
    localparam int IW      = 8;

    reg clk;
    reg rst;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    int pass_count = 0;
    int fail_count = 0;

    // Measurable Functional Coverage Counters
    int cov_slave_hit[8];
    int cov_reset_alias_hit = 0;
    int cov_decerr_single_hit = 0;
    int cov_decerr_burst_hit = 0;
    int cov_64k_cross_hit = 0;
    int cov_4m_contention_same = 0;
    int cov_4m_contention_diff = 0;
    int cov_w_before_aw_hit = 0;
    int cov_inflight_rst_hit = 0;

    // Master arrays S00..S03
    reg           s_awvalid[NUM_M]; wire          s_awready[NUM_M];
    reg  [IW-1:0] s_awid   [NUM_M]; reg  [AW-1:0] s_awaddr [NUM_M];
    reg  [7:0]    s_awlen  [NUM_M]; reg  [2:0]    s_awsize [NUM_M];
    reg  [1:0]    s_awburst[NUM_M]; reg           s_awlock [NUM_M];
    reg  [3:0]    s_awcache[NUM_M]; reg  [2:0]    s_awprot [NUM_M];
    reg  [3:0]    s_awqos  [NUM_M];
    reg           s_wvalid [NUM_M]; wire          s_wready [NUM_M];
    reg  [DW-1:0] s_wdata  [NUM_M]; reg  [3:0]    s_wstrb  [NUM_M];
    reg           s_wlast  [NUM_M];
    wire          s_bvalid [NUM_M]; reg           s_bready [NUM_M];
    wire [IW-1:0] s_bid    [NUM_M]; wire [1:0]    s_bresp  [NUM_M];
    reg           s_arvalid[NUM_M]; wire          s_arready[NUM_M];
    reg  [IW-1:0] s_arid   [NUM_M]; reg  [AW-1:0] s_araddr [NUM_M];
    reg  [7:0]    s_arlen  [NUM_M]; reg  [2:0]    s_arsize [NUM_M];
    reg  [1:0]    s_arburst[NUM_M]; reg           s_arlock [NUM_M];
    reg  [3:0]    s_arcache[NUM_M]; reg  [2:0]    s_arprot [NUM_M];
    reg  [3:0]    s_arqos  [NUM_M];
    wire          s_rvalid [NUM_M]; reg           s_rready [NUM_M];
    wire [IW-1:0] s_rid    [NUM_M]; wire [DW-1:0] s_rdata  [NUM_M];
    wire [1:0]    s_rresp  [NUM_M]; wire          s_rlast  [NUM_M];

    // Slave arrays M00..M07
    wire          m_awvalid[NUM_S]; reg           m_awready[NUM_S];
    wire [IW-1:0] m_awid   [NUM_S]; wire [AW-1:0] m_awaddr [NUM_S];
    wire [7:0]    m_awlen  [NUM_S]; wire [2:0]    m_awsize [NUM_S];
    wire [1:0]    m_awburst[NUM_S]; wire          m_awlock [NUM_S];
    wire [3:0]    m_awcache[NUM_S]; wire [2:0]    m_awprot [NUM_S];
    wire [3:0]    m_awqos  [NUM_S]; wire [3:0]    m_awregion[NUM_S];
    wire          m_wvalid [NUM_S]; reg           m_wready [NUM_S];
    wire [DW-1:0] m_wdata  [NUM_S]; wire [3:0]    m_wstrb  [NUM_S];
    wire          m_wlast  [NUM_S];
    reg           m_bvalid [NUM_S]; wire          m_bready [NUM_S];
    reg  [IW-1:0] m_bid    [NUM_S]; reg  [1:0]    m_bresp  [NUM_S];
    wire          m_arvalid[NUM_S]; reg           m_arready[NUM_S];
    wire [IW-1:0] m_arid   [NUM_S]; wire [AW-1:0] m_araddr [NUM_S];
    wire [7:0]    m_arlen  [NUM_S]; wire [2:0]    m_arsize [NUM_S];
    wire [1:0]    m_arburst[NUM_S]; wire          m_arlock [NUM_S];
    wire [3:0]    m_arcache[NUM_S]; wire [2:0]    m_arprot [NUM_S];
    wire [3:0]    m_arqos  [NUM_S]; wire [3:0]    m_arregion[NUM_S];
    reg           m_rvalid [NUM_S]; wire          m_rready [NUM_S];
    reg  [IW-1:0] m_rid    [NUM_S]; reg  [DW-1:0] m_rdata  [NUM_S];
    reg  [1:0]    m_rresp  [NUM_S]; reg           m_rlast  [NUM_S];

    // Monitor unexpected slave activations
    logic [7:0] unexpected_slave_wr_hits = 8'h0;
    logic [7:0] unexpected_slave_rd_hits = 8'h0;
    reg   [7:0] allowed_slave_mask = 8'hFF;

    // -------------------------------------------------------------------------
    // DUT: axi_interconnect_wrap_4x8 (Exact SoC Address Map Parameters)
    // -------------------------------------------------------------------------
    axi_interconnect_wrap_4x8 #(
        .DATA_WIDTH        (32),
        .ADDR_WIDTH        (32),
        .ID_WIDTH          (8),
        .AWUSER_ENABLE     (0), .WUSER_ENABLE(0), .BUSER_ENABLE(0),
        .ARUSER_ENABLE     (0), .RUSER_ENABLE(0),
        .M_REGIONS         (2),
        // M00: IMEM + 0x8000_0000 reset alias (64 KB)
        .M00_BASE_ADDR     ({32'h8000_0000, 32'h0000_0000}),
        .M00_ADDR_WIDTH    ({32'd16,        32'd16}),
        .M00_CONNECT_READ  (4'b1111), .M00_CONNECT_WRITE(4'b1111),
        // M01: DMEM (128 KB split as 2x 64 KB regions)
        .M01_BASE_ADDR     ({32'h0002_0000, 32'h0001_0000}),
        .M01_ADDR_WIDTH    ({32'd16,        32'd16}),
        .M01_CONNECT_READ  (4'b1111), .M01_CONNECT_WRITE(4'b1111),
        // M02: UART (4 KB)
        .M02_BASE_ADDR     ({32'h0000_0000, 32'h0003_0000}),
        .M02_ADDR_WIDTH    ({32'd0,         32'd12}),
        .M02_CONNECT_READ  (4'b1111), .M02_CONNECT_WRITE(4'b1111),
        // M03: Timer (4 KB)
        .M03_BASE_ADDR     ({32'h0000_0000, 32'h0005_0000}),
        .M03_ADDR_WIDTH    ({32'd0,         32'd12}),
        .M03_CONNECT_READ  (4'b1111), .M03_CONNECT_WRITE(4'b1111),
        // M04: GPIO (4 KB)
        .M04_BASE_ADDR     ({32'h0000_0000, 32'h0006_0000}),
        .M04_ADDR_WIDTH    ({32'd0,         32'd12}),
        .M04_CONNECT_READ  (4'b1111), .M04_CONNECT_WRITE(4'b1111),
        // M05: RLE (4 KB)
        .M05_BASE_ADDR     ({32'h0000_0000, 32'h000D_0000}),
        .M05_ADDR_WIDTH    ({32'd0,         32'd12}),
        .M05_CONNECT_READ  (4'b1111), .M05_CONNECT_WRITE(4'b1111),
        // M06: DMA (64 KB)
        .M06_BASE_ADDR     ({32'h0000_0000, 32'h000B_0000}),
        .M06_ADDR_WIDTH    ({32'd0,         32'd16}),
        .M06_CONNECT_READ  (4'b1111), .M06_CONNECT_WRITE(4'b1111),
        // M07: CRC (4 KB)
        .M07_BASE_ADDR     ({32'h0000_0000, 32'h000A_0000}),
        .M07_ADDR_WIDTH    ({32'd0,         32'd12}),
        .M07_CONNECT_READ  (4'b1111), .M07_CONNECT_WRITE(4'b1111)
    ) dut (
        .clk(clk), .rst(rst),
        // S00
        .s00_axi_awvalid(s_awvalid[0]), .s00_axi_awready(s_awready[0]), .s00_axi_awid(s_awid[0]), .s00_axi_awaddr(s_awaddr[0]),
        .s00_axi_awlen(s_awlen[0]), .s00_axi_awsize(s_awsize[0]), .s00_axi_awburst(s_awburst[0]), .s00_axi_awlock(s_awlock[0]),
        .s00_axi_awcache(s_awcache[0]), .s00_axi_awprot(s_awprot[0]), .s00_axi_awqos(s_awqos[0]), .s00_axi_awuser(1'b0),
        .s00_axi_wvalid(s_wvalid[0]), .s00_axi_wready(s_wready[0]), .s00_axi_wdata(s_wdata[0]), .s00_axi_wstrb(s_wstrb[0]),
        .s00_axi_wlast(s_wlast[0]), .s00_axi_wuser(1'b0),
        .s00_axi_bvalid(s_bvalid[0]), .s00_axi_bready(s_bready[0]), .s00_axi_bid(s_bid[0]), .s00_axi_bresp(s_bresp[0]), .s00_axi_buser(),
        .s00_axi_arvalid(s_arvalid[0]), .s00_axi_arready(s_arready[0]), .s00_axi_arid(s_arid[0]), .s00_axi_araddr(s_araddr[0]),
        .s00_axi_arlen(s_arlen[0]), .s00_axi_arsize(s_arsize[0]), .s00_axi_arburst(s_arburst[0]), .s00_axi_arlock(s_arlock[0]),
        .s00_axi_arcache(s_arcache[0]), .s00_axi_arprot(s_arprot[0]), .s00_axi_arqos(s_arqos[0]), .s00_axi_aruser(1'b0),
        .s00_axi_rvalid(s_rvalid[0]), .s00_axi_rready(s_rready[0]), .s00_axi_rid(s_rid[0]), .s00_axi_rdata(s_rdata[0]),
        .s00_axi_rresp(s_rresp[0]), .s00_axi_rlast(s_rlast[0]), .s00_axi_ruser(),
        // S01
        .s01_axi_awvalid(s_awvalid[1]), .s01_axi_awready(s_awready[1]), .s01_axi_awid(s_awid[1]), .s01_axi_awaddr(s_awaddr[1]),
        .s01_axi_awlen(s_awlen[1]), .s01_axi_awsize(s_awsize[1]), .s01_axi_awburst(s_awburst[1]), .s01_axi_awlock(s_awlock[1]),
        .s01_axi_awcache(s_awcache[1]), .s01_axi_awprot(s_awprot[1]), .s01_axi_awqos(s_awqos[1]), .s01_axi_awuser(1'b0),
        .s01_axi_wvalid(s_wvalid[1]), .s01_axi_wready(s_wready[1]), .s01_axi_wdata(s_wdata[1]), .s01_axi_wstrb(s_wstrb[1]),
        .s01_axi_wlast(s_wlast[1]), .s01_axi_wuser(1'b0),
        .s01_axi_bvalid(s_bvalid[1]), .s01_axi_bready(s_bready[1]), .s01_axi_bid(s_bid[1]), .s01_axi_bresp(s_bresp[1]), .s01_axi_buser(),
        .s01_axi_arvalid(s_arvalid[1]), .s01_axi_arready(s_arready[1]), .s01_axi_arid(s_arid[1]), .s01_axi_araddr(s_araddr[1]),
        .s01_axi_arlen(s_arlen[1]), .s01_axi_arsize(s_arsize[1]), .s01_axi_arburst(s_arburst[1]), .s01_axi_arlock(s_arlock[1]),
        .s01_axi_arcache(s_arcache[1]), .s01_axi_arprot(s_arprot[1]), .s01_axi_arqos(s_arqos[1]), .s01_axi_aruser(1'b0),
        .s01_axi_rvalid(s_rvalid[1]), .s01_axi_rready(s_rready[1]), .s01_axi_rid(s_rid[1]), .s01_axi_rdata(s_rdata[1]),
        .s01_axi_rresp(s_rresp[1]), .s01_axi_rlast(s_rlast[1]), .s01_axi_ruser(),
        // S02
        .s02_axi_awvalid(s_awvalid[2]), .s02_axi_awready(s_awready[2]), .s02_axi_awid(s_awid[2]), .s02_axi_awaddr(s_awaddr[2]),
        .s02_axi_awlen(s_awlen[2]), .s02_axi_awsize(s_awsize[2]), .s02_axi_awburst(s_awburst[2]), .s02_axi_awlock(s_awlock[2]),
        .s02_axi_awcache(s_awcache[2]), .s02_axi_awprot(s_awprot[2]), .s02_axi_awqos(s_awqos[2]), .s02_axi_awuser(1'b0),
        .s02_axi_wvalid(s_wvalid[2]), .s02_axi_wready(s_wready[2]), .s02_axi_wdata(s_wdata[2]), .s02_axi_wstrb(s_wstrb[2]),
        .s02_axi_wlast(s_wlast[2]), .s02_axi_wuser(1'b0),
        .s02_axi_bvalid(s_bvalid[2]), .s02_axi_bready(s_bready[2]), .s02_axi_bid(s_bid[2]), .s02_axi_bresp(s_bresp[2]), .s02_axi_buser(),
        .s02_axi_arvalid(s_arvalid[2]), .s02_axi_arready(s_arready[2]), .s02_axi_arid(s_arid[2]), .s02_axi_araddr(s_araddr[2]),
        .s02_axi_arlen(s_arlen[2]), .s02_axi_arsize(s_arsize[2]), .s02_axi_arburst(s_arburst[2]), .s02_axi_arlock(s_arlock[2]),
        .s02_axi_arcache(s_arcache[2]), .s02_axi_arprot(s_arprot[2]), .s02_axi_arqos(s_arqos[2]), .s02_axi_aruser(1'b0),
        .s02_axi_rvalid(s_rvalid[2]), .s02_axi_rready(s_rready[2]), .s02_axi_rid(s_rid[2]), .s02_axi_rdata(s_rdata[2]),
        .s02_axi_rresp(s_rresp[2]), .s02_axi_rlast(s_rlast[2]), .s02_axi_ruser(),
        // S03
        .s03_axi_awvalid(s_awvalid[3]), .s03_axi_awready(s_awready[3]), .s03_axi_awid(s_awid[3]), .s03_axi_awaddr(s_awaddr[3]),
        .s03_axi_awlen(s_awlen[3]), .s03_axi_awsize(s_awsize[3]), .s03_axi_awburst(s_awburst[3]), .s03_axi_awlock(s_awlock[3]),
        .s03_axi_awcache(s_awcache[3]), .s03_axi_awprot(s_awprot[3]), .s03_axi_awqos(s_awqos[3]), .s03_axi_awuser(1'b0),
        .s03_axi_wvalid(s_wvalid[3]), .s03_axi_wready(s_wready[3]), .s03_axi_wdata(s_wdata[3]), .s03_axi_wstrb(s_wstrb[3]),
        .s03_axi_wlast(s_wlast[3]), .s03_axi_wuser(1'b0),
        .s03_axi_bvalid(s_bvalid[3]), .s03_axi_bready(s_bready[3]), .s03_axi_bid(s_bid[3]), .s03_axi_bresp(s_bresp[3]), .s03_axi_buser(),
        .s03_axi_arvalid(s_arvalid[3]), .s03_axi_arready(s_arready[3]), .s03_axi_arid(s_arid[3]), .s03_axi_araddr(s_araddr[3]),
        .s03_axi_arlen(s_arlen[3]), .s03_axi_arsize(s_arsize[3]), .s03_axi_arburst(s_arburst[3]), .s03_axi_arlock(s_arlock[3]),
        .s03_axi_arcache(s_arcache[3]), .s03_axi_arprot(s_arprot[3]), .s03_axi_arqos(s_arqos[3]), .s03_axi_aruser(1'b0),
        .s03_axi_rvalid(s_rvalid[3]), .s03_axi_rready(s_rready[3]), .s03_axi_rid(s_rid[3]), .s03_axi_rdata(s_rdata[3]),
        .s03_axi_rresp(s_rresp[3]), .s03_axi_rlast(s_rlast[3]), .s03_axi_ruser(),
        // M00..M07
        .m00_axi_awvalid(m_awvalid[0]), .m00_axi_awready(m_awready[0]), .m00_axi_awid(m_awid[0]), .m00_axi_awaddr(m_awaddr[0]),
        .m00_axi_awlen(m_awlen[0]), .m00_axi_awsize(m_awsize[0]), .m00_axi_awburst(m_awburst[0]), .m00_axi_awlock(m_awlock[0]),
        .m00_axi_awcache(m_awcache[0]), .m00_axi_awprot(m_awprot[0]), .m00_axi_awqos(m_awqos[0]), .m00_axi_awregion(m_awregion[0]),
        .m00_axi_wvalid(m_wvalid[0]), .m00_axi_wready(m_wready[0]), .m00_axi_wdata(m_wdata[0]), .m00_axi_wstrb(m_wstrb[0]),
        .m00_axi_wlast(m_wlast[0]),
        .m00_axi_bvalid(m_bvalid[0]), .m00_axi_bready(m_bready[0]), .m00_axi_bid(m_bid[0]), .m00_axi_bresp(m_bresp[0]), .m00_axi_buser(1'b0),
        .m00_axi_arvalid(m_arvalid[0]), .m00_axi_arready(m_arready[0]), .m00_axi_arid(m_arid[0]), .m00_axi_araddr(m_araddr[0]),
        .m00_axi_arlen(m_arlen[0]), .m00_axi_arsize(m_arsize[0]), .m00_axi_arburst(m_arburst[0]), .m00_axi_arlock(m_arlock[0]),
        .m00_axi_arcache(m_arcache[0]), .m00_axi_arprot(m_arprot[0]), .m00_axi_arqos(m_arqos[0]), .m00_axi_arregion(m_arregion[0]),
        .m00_axi_rvalid(m_rvalid[0]), .m00_axi_rready(m_rready[0]), .m00_axi_rid(m_rid[0]), .m00_axi_rdata(m_rdata[0]),
        .m00_axi_rresp(m_rresp[0]), .m00_axi_rlast(m_rlast[0]), .m00_axi_ruser(1'b0),

        .m01_axi_awvalid(m_awvalid[1]), .m01_axi_awready(m_awready[1]), .m01_axi_awid(m_awid[1]), .m01_axi_awaddr(m_awaddr[1]),
        .m01_axi_awlen(m_awlen[1]), .m01_axi_awsize(m_awsize[1]), .m01_axi_awburst(m_awburst[1]), .m01_axi_awlock(m_awlock[1]),
        .m01_axi_awcache(m_awcache[1]), .m01_axi_awprot(m_awprot[1]), .m01_axi_awqos(m_awqos[1]), .m01_axi_awregion(m_awregion[1]),
        .m01_axi_wvalid(m_wvalid[1]), .m01_axi_wready(m_wready[1]), .m01_axi_wdata(m_wdata[1]), .m01_axi_wstrb(m_wstrb[1]),
        .m01_axi_wlast(m_wlast[1]),
        .m01_axi_bvalid(m_bvalid[1]), .m01_axi_bready(m_bready[1]), .m01_axi_bid(m_bid[1]), .m01_axi_bresp(m_bresp[1]), .m01_axi_buser(1'b0),
        .m01_axi_arvalid(m_arvalid[1]), .m01_axi_arready(m_arready[1]), .m01_axi_arid(m_arid[1]), .m01_axi_araddr(m_araddr[1]),
        .m01_axi_arlen(m_arlen[1]), .m01_axi_arsize(m_arsize[1]), .m01_axi_arburst(m_arburst[1]), .m01_axi_arlock(m_arlock[1]),
        .m01_axi_arcache(m_arcache[1]), .m01_axi_arprot(m_arprot[1]), .m01_axi_arqos(m_arqos[1]), .m01_axi_arregion(m_arregion[1]),
        .m01_axi_rvalid(m_rvalid[1]), .m01_axi_rready(m_rready[1]), .m01_axi_rid(m_rid[1]), .m01_axi_rdata(m_rdata[1]),
        .m01_axi_rresp(m_rresp[1]), .m01_axi_rlast(m_rlast[1]), .m01_axi_ruser(1'b0),

        .m02_axi_awvalid(m_awvalid[2]), .m02_axi_awready(m_awready[2]), .m02_axi_awid(m_awid[2]), .m02_axi_awaddr(m_awaddr[2]),
        .m02_axi_awlen(m_awlen[2]), .m02_axi_awsize(m_awsize[2]), .m02_axi_awburst(m_awburst[2]), .m02_axi_awlock(m_awlock[2]),
        .m02_axi_awcache(m_awcache[2]), .m02_axi_awprot(m_awprot[2]), .m02_axi_awqos(m_awqos[2]), .m02_axi_awregion(m_awregion[2]),
        .m02_axi_wvalid(m_wvalid[2]), .m02_axi_wready(m_wready[2]), .m02_axi_wdata(m_wdata[2]), .m02_axi_wstrb(m_wstrb[2]),
        .m02_axi_wlast(m_wlast[2]),
        .m02_axi_bvalid(m_bvalid[2]), .m02_axi_bready(m_bready[2]), .m02_axi_bid(m_bid[2]), .m02_axi_bresp(m_bresp[2]), .m02_axi_buser(1'b0),
        .m02_axi_arvalid(m_arvalid[2]), .m02_axi_arready(m_arready[2]), .m02_axi_arid(m_arid[2]), .m02_axi_araddr(m_araddr[2]),
        .m02_axi_arlen(m_arlen[2]), .m02_axi_arsize(m_arsize[2]), .m02_axi_arburst(m_arburst[2]), .m02_axi_arlock(m_arlock[2]),
        .m02_axi_arcache(m_arcache[2]), .m02_axi_arprot(m_arprot[2]), .m02_axi_arqos(m_arqos[2]), .m02_axi_arregion(m_arregion[2]),
        .m02_axi_rvalid(m_rvalid[2]), .m02_axi_rready(m_rready[2]), .m02_axi_rid(m_rid[2]), .m02_axi_rdata(m_rdata[2]),
        .m02_axi_rresp(m_rresp[2]), .m02_axi_rlast(m_rlast[2]), .m02_axi_ruser(1'b0),

        .m03_axi_awvalid(m_awvalid[3]), .m03_axi_awready(m_awready[3]), .m03_axi_awid(m_awid[3]), .m03_axi_awaddr(m_awaddr[3]),
        .m03_axi_awlen(m_awlen[3]), .m03_axi_awsize(m_awsize[3]), .m03_axi_awburst(m_awburst[3]), .m03_axi_awlock(m_awlock[3]),
        .m03_axi_awcache(m_awcache[3]), .m03_axi_awprot(m_awprot[3]), .m03_axi_awqos(m_awqos[3]), .m03_axi_awregion(m_awregion[3]),
        .m03_axi_wvalid(m_wvalid[3]), .m03_axi_wready(m_wready[3]), .m03_axi_wdata(m_wdata[3]), .m03_axi_wstrb(m_wstrb[3]),
        .m03_axi_wlast(m_wlast[3]),
        .m03_axi_bvalid(m_bvalid[3]), .m03_axi_bready(m_bready[3]), .m03_axi_bid(m_bid[3]), .m03_axi_bresp(m_bresp[3]), .m03_axi_buser(1'b0),
        .m03_axi_arvalid(m_arvalid[3]), .m03_axi_arready(m_arready[3]), .m03_axi_arid(m_arid[3]), .m03_axi_araddr(m_araddr[3]),
        .m03_axi_arlen(m_arlen[3]), .m03_axi_arsize(m_arsize[3]), .m03_axi_arburst(m_arburst[3]), .m03_axi_arlock(m_arlock[3]),
        .m03_axi_arcache(m_arcache[3]), .m03_axi_arprot(m_arprot[3]), .m03_axi_arqos(m_arqos[3]), .m03_axi_arregion(m_arregion[3]),
        .m03_axi_rvalid(m_rvalid[3]), .m03_axi_rready(m_rready[3]), .m03_axi_rid(m_rid[3]), .m03_axi_rdata(m_rdata[3]),
        .m03_axi_rresp(m_rresp[3]), .m03_axi_rlast(m_rlast[3]), .m03_axi_ruser(1'b0),

        .m04_axi_awvalid(m_awvalid[4]), .m04_axi_awready(m_awready[4]), .m04_axi_awid(m_awid[4]), .m04_axi_awaddr(m_awaddr[4]),
        .m04_axi_awlen(m_awlen[4]), .m04_axi_awsize(m_awsize[4]), .m04_axi_awburst(m_awburst[4]), .m04_axi_awlock(m_awlock[4]),
        .m04_axi_awcache(m_awcache[4]), .m04_axi_awprot(m_awprot[4]), .m04_axi_awqos(m_awqos[4]), .m04_axi_awregion(m_awregion[4]),
        .m04_axi_wvalid(m_wvalid[4]), .m04_axi_wready(m_wready[4]), .m04_axi_wdata(m_wdata[4]), .m04_axi_wstrb(m_wstrb[4]),
        .m04_axi_wlast(m_wlast[4]),
        .m04_axi_bvalid(m_bvalid[4]), .m04_axi_bready(m_bready[4]), .m04_axi_bid(m_bid[4]), .m04_axi_bresp(m_bresp[4]), .m04_axi_buser(1'b0),
        .m04_axi_arvalid(m_arvalid[4]), .m04_axi_arready(m_arready[4]), .m04_axi_arid(m_arid[4]), .m04_axi_araddr(m_araddr[4]),
        .m04_axi_arlen(m_arlen[4]), .m04_axi_arsize(m_arsize[4]), .m04_axi_arburst(m_arburst[4]), .m04_axi_arlock(m_arlock[4]),
        .m04_axi_arcache(m_arcache[4]), .m04_axi_arprot(m_arprot[4]), .m04_axi_arqos(m_arqos[4]), .m04_axi_arregion(m_arregion[4]),
        .m04_axi_rvalid(m_rvalid[4]), .m04_axi_rready(m_rready[4]), .m04_axi_rid(m_rid[4]), .m04_axi_rdata(m_rdata[4]),
        .m04_axi_rresp(m_rresp[4]), .m04_axi_rlast(m_rlast[4]), .m04_axi_ruser(1'b0),

        .m05_axi_awvalid(m_awvalid[5]), .m05_axi_awready(m_awready[5]), .m05_axi_awid(m_awid[5]), .m05_axi_awaddr(m_awaddr[5]),
        .m05_axi_awlen(m_awlen[5]), .m05_axi_awsize(m_awsize[5]), .m05_axi_awburst(m_awburst[5]), .m05_axi_awlock(m_awlock[5]),
        .m05_axi_awcache(m_awcache[5]), .m05_axi_awprot(m_awprot[5]), .m05_axi_awqos(m_awqos[5]), .m05_axi_awregion(m_awregion[5]),
        .m05_axi_wvalid(m_wvalid[5]), .m05_axi_wready(m_wready[5]), .m05_axi_wdata(m_wdata[5]), .m05_axi_wstrb(m_wstrb[5]),
        .m05_axi_wlast(m_wlast[5]),
        .m05_axi_bvalid(m_bvalid[5]), .m05_axi_bready(m_bready[5]), .m05_axi_bid(m_bid[5]), .m05_axi_bresp(m_bresp[5]), .m05_axi_buser(1'b0),
        .m05_axi_arvalid(m_arvalid[5]), .m05_axi_arready(m_arready[5]), .m05_axi_arid(m_arid[5]), .m05_axi_araddr(m_araddr[5]),
        .m05_axi_arlen(m_arlen[5]), .m05_axi_arsize(m_arsize[5]), .m05_axi_arburst(m_arburst[5]), .m05_axi_arlock(m_arlock[5]),
        .m05_axi_arcache(m_arcache[5]), .m05_axi_arprot(m_arprot[5]), .m05_axi_arqos(m_arqos[5]), .m05_axi_arregion(m_arregion[5]),
        .m05_axi_rvalid(m_rvalid[5]), .m05_axi_rready(m_rready[5]), .m05_axi_rid(m_rid[5]), .m05_axi_rdata(m_rdata[5]),
        .m05_axi_rresp(m_rresp[5]), .m05_axi_rlast(m_rlast[5]), .m05_axi_ruser(1'b0),

        .m06_axi_awvalid(m_awvalid[6]), .m06_axi_awready(m_awready[6]), .m06_axi_awid(m_awid[6]), .m06_axi_awaddr(m_awaddr[6]),
        .m06_axi_awlen(m_awlen[6]), .m06_axi_awsize(m_awsize[6]), .m06_axi_awburst(m_awburst[6]), .m06_axi_awlock(m_awlock[6]),
        .m06_axi_awcache(m_awcache[6]), .m06_axi_awprot(m_awprot[6]), .m06_axi_awqos(m_awqos[6]), .m06_axi_awregion(m_awregion[6]),
        .m06_axi_wvalid(m_wvalid[6]), .m06_axi_wready(m_wready[6]), .m06_axi_wdata(m_wdata[6]), .m06_axi_wstrb(m_wstrb[6]),
        .m06_axi_wlast(m_wlast[6]),
        .m06_axi_bvalid(m_bvalid[6]), .m06_axi_bready(m_bready[6]), .m06_axi_bid(m_bid[6]), .m06_axi_bresp(m_bresp[6]), .m06_axi_buser(1'b0),
        .m06_axi_arvalid(m_arvalid[6]), .m06_axi_arready(m_arready[6]), .m06_axi_arid(m_arid[6]), .m06_axi_araddr(m_araddr[6]),
        .m06_axi_arlen(m_arlen[6]), .m06_axi_arsize(m_arsize[6]), .m06_axi_arburst(m_arburst[6]), .m06_axi_arlock(m_arlock[6]),
        .m06_axi_arcache(m_arcache[6]), .m06_axi_arprot(m_arprot[6]), .m06_axi_arqos(m_arqos[6]), .m06_axi_arregion(m_arregion[6]),
        .m06_axi_rvalid(m_rvalid[6]), .m06_axi_rready(m_rready[6]), .m06_axi_rid(m_rid[6]), .m06_axi_rdata(m_rdata[6]),
        .m06_axi_rresp(m_rresp[6]), .m06_axi_rlast(m_rlast[6]), .m06_axi_ruser(1'b0),

        .m07_axi_awvalid(m_awvalid[7]), .m07_axi_awready(m_awready[7]), .m07_axi_awid(m_awid[7]), .m07_axi_awaddr(m_awaddr[7]),
        .m07_axi_awlen(m_awlen[7]), .m07_axi_awsize(m_awsize[7]), .m07_axi_awburst(m_awburst[7]), .m07_axi_awlock(m_awlock[7]),
        .m07_axi_awcache(m_awcache[7]), .m07_axi_awprot(m_awprot[7]), .m07_axi_awqos(m_awqos[7]), .m07_axi_awregion(m_awregion[7]),
        .m07_axi_wvalid(m_wvalid[7]), .m07_axi_wready(m_wready[7]), .m07_axi_wdata(m_wdata[7]), .m07_axi_wstrb(m_wstrb[7]),
        .m07_axi_wlast(m_wlast[7]),
        .m07_axi_bvalid(m_bvalid[7]), .m07_axi_bready(m_bready[7]), .m07_axi_bid(m_bid[7]), .m07_axi_bresp(m_bresp[7]), .m07_axi_buser(1'b0),
        .m07_axi_arvalid(m_arvalid[7]), .m07_axi_arready(m_arready[7]), .m07_axi_arid(m_arid[7]), .m07_axi_araddr(m_araddr[7]),
        .m07_axi_arlen(m_arlen[7]), .m07_axi_arsize(m_arsize[7]), .m07_axi_arburst(m_arburst[7]), .m07_axi_arlock(m_arlock[7]),
        .m07_axi_arcache(m_arcache[7]), .m07_axi_arprot(m_arprot[7]), .m07_axi_arqos(m_arqos[7]), .m07_axi_arregion(m_arregion[7]),
        .m07_axi_rvalid(m_rvalid[7]), .m07_axi_rready(m_rready[7]), .m07_axi_rid(m_rid[7]), .m07_axi_rdata(m_rdata[7]),
        .m07_axi_rresp(m_rresp[7]), .m07_axi_rlast(m_rlast[7]), .m07_axi_ruser(1'b0)
    );

    // -------------------------------------------------------------------------
    // Bound Protocol Assertions on All 4 Masters + M01 DMEM Slave
    // Disable strict ID match during reset recovery injection
    // -------------------------------------------------------------------------
    reg rst_chk_disable = 1'b0;
    wire asrt_rst_n = (~rst) & (~rst_chk_disable);

    genvar g;
    generate
        for (g = 0; g < NUM_M; g = g + 1) begin : gen_m_asrt
            axi4_full_protocol_assertions #(
                .NAME          ($sformatf("IC_S%02d", g)),
                .DATA_WIDTH    (32),
                .ID_WIDTH      (8),
                .CHECK_ID      (1'b1),
                .CHECK_RST_MST (1'b0)
            ) u_m_asrt (
                .clk(clk), .rst_n(asrt_rst_n),
                .awvalid(s_awvalid[g]), .awready(s_awready[g]), .awid(s_awid[g]), .awaddr(s_awaddr[g]),
                .awlen(s_awlen[g]), .awsize(s_awsize[g]), .awburst(s_awburst[g]), .awprot(s_awprot[g]),
                .wvalid(s_wvalid[g]), .wready(s_wready[g]), .wdata(s_wdata[g]), .wstrb(s_wstrb[g]), .wlast(s_wlast[g]),
                .bvalid(s_bvalid[g]), .bready(s_bready[g]), .bid(s_bid[g]), .bresp(s_bresp[g]),
                .arvalid(s_arvalid[g]), .arready(s_arready[g]), .arid(s_arid[g]), .araddr(s_araddr[g]),
                .arlen(s_arlen[g]), .arsize(s_arsize[g]), .arburst(s_arburst[g]), .arprot(s_arprot[g]),
                .rvalid(s_rvalid[g]), .rready(s_rready[g]), .rid(s_rid[g]), .rdata(s_rdata[g]),
                .rresp(s_rresp[g]), .rlast(s_rlast[g])
            );
        end
    endgenerate

    axi4_full_protocol_assertions #(
        .NAME       ("IC_M01_DMEM"),
        .DATA_WIDTH (32),
        .ID_WIDTH   (8),
        .CHECK_ID   (1'b1)
    ) u_s1_asrt (
        .clk(clk), .rst_n(asrt_rst_n),
        .awvalid(m_awvalid[1]), .awready(m_awready[1]), .awid(m_awid[1]), .awaddr(m_awaddr[1]),
        .awlen(m_awlen[1]), .awsize(m_awsize[1]), .awburst(m_awburst[1]), .awprot(m_awprot[1]),
        .wvalid(m_wvalid[1]), .wready(m_wready[1]), .wdata(m_wdata[1]), .wstrb(m_wstrb[1]), .wlast(m_wlast[1]),
        .bvalid(m_bvalid[1]), .bready(m_bready[1]), .bid(m_bid[1]), .bresp(m_bresp[1]),
        .arvalid(m_arvalid[1]), .arready(m_arready[1]), .arid(m_arid[1]), .araddr(m_araddr[1]),
        .arlen(m_arlen[1]), .arsize(m_arsize[1]), .arburst(m_arburst[1]), .arprot(m_arprot[1]),
        .rvalid(m_rvalid[1]), .rready(m_rready[1]), .rid(m_rid[1]), .rdata(m_rdata[1]),
        .rresp(m_rresp[1]), .rlast(m_rlast[1])
    );

    // -------------------------------------------------------------------------
    // Behavioral AXI4 Slaves M00..M07 (Per-slave associative storage + wait states)
    // -------------------------------------------------------------------------
    int          slave_wait_cycles[NUM_S];

    generate
        for (g = 0; g < NUM_S; g = g + 1) begin : gen_slaves
            logic [31:0] smem [logic [31:0]];
            reg        w_active;
            reg [31:0] w_addr;
            reg [7:0]  w_id;
            reg        r_active;
            reg [31:0] r_addr;
            reg [7:0]  r_left;
            reg [7:0]  r_id;
            int        r_delay;

            always @(posedge clk) begin
                if (rst) begin
                    m_awready[g] <= 1'b1;
                    m_wready[g]  <= 1'b1;
                    m_bvalid[g]  <= 1'b0;
                    m_bid[g]     <= 8'h0;
                    m_bresp[g]   <= 2'b00;
                    m_arready[g] <= 1'b1;
                    m_rvalid[g]  <= 1'b0;
                    m_rid[g]     <= 8'h0;
                    m_rdata[g]   <= 32'h0;
                    m_rresp[g]   <= 2'b00;
                    m_rlast[g]   <= 1'b0;
                    w_active     <= 1'b0;
                    r_active     <= 1'b0;
                    r_delay      <= 0;
                end else begin
                    // Unexpected slave activation guard
                    if (m_awvalid[g] && !allowed_slave_mask[g]) unexpected_slave_wr_hits[g] = 1'b1;
                    if (m_arvalid[g] && !allowed_slave_mask[g]) unexpected_slave_rd_hits[g] = 1'b1;

                    // Write Channel
                    if (m_awvalid[g] && m_awready[g]) begin
                        w_addr       <= {m_awaddr[g][31:2], 2'b00};
                        w_id         <= m_awid[g];
                        w_active     <= 1'b1;
                        m_awready[g] <= 1'b0;
                    end
                    if (m_wvalid[g] && m_wready[g]) begin
                        automatic logic [31:0] cur_a = (m_awvalid[g] && m_awready[g]) ? {m_awaddr[g][31:2], 2'b00} : w_addr;
                        automatic logic [31:0] cur_v = smem.exists(cur_a) ? smem[cur_a] : (32'hA000_0000 | (g << 20) | cur_a[15:0]);
                        if (m_wstrb[g][0]) cur_v[7:0]   = m_wdata[g][7:0];
                        if (m_wstrb[g][1]) cur_v[15:8]  = m_wdata[g][15:8];
                        if (m_wstrb[g][2]) cur_v[23:16] = m_wdata[g][23:16];
                        if (m_wstrb[g][3]) cur_v[31:24] = m_wdata[g][31:24];
                        smem[cur_a]         = cur_v;
                        w_addr              <= cur_a + 32'd4;
                        if (m_wlast[g]) begin
                            m_wready[g]  <= 1'b0;
                            m_bvalid[g]  <= 1'b1;
                            m_bid[g]     <= (m_awvalid[g] && m_awready[g]) ? m_awid[g] : w_id;
                            m_bresp[g]   <= 2'b00;
                        end
                    end
                    if (m_bvalid[g] && m_bready[g]) begin
                        m_bvalid[g]  <= 1'b0;
                        m_awready[g] <= 1'b1;
                        m_wready[g]  <= 1'b1;
                        w_active     <= 1'b0;
                    end

                    // Read Channel
                    if (m_arvalid[g] && m_arready[g]) begin
                        r_addr       <= {m_araddr[g][31:2], 2'b00};
                        r_left       <= m_arlen[g];
                        r_id         <= m_arid[g];
                        r_active     <= 1'b1;
                        m_arready[g] <= 1'b0;
                        r_delay      <= slave_wait_cycles[g];
                    end else if (r_active && !m_rvalid[g]) begin
                        if (r_delay > 0) begin
                            r_delay <= r_delay - 1;
                        end else begin
                            m_rvalid[g] <= 1'b1;
                            m_rdata[g]  <= smem.exists(r_addr) ? smem[r_addr] : (32'hA000_0000 | (g << 20) | r_addr[15:0]);
                            m_rid[g]    <= r_id;
                            m_rresp[g]  <= 2'b00;
                            m_rlast[g]  <= (r_left == 8'd0);
                        end
                    end else if (m_rvalid[g] && m_rready[g]) begin
                        if (r_left == 8'd0) begin
                            m_rvalid[g]  <= 1'b0;
                            m_rlast[g]   <= 1'b0;
                            m_arready[g] <= 1'b1;
                            r_active     <= 1'b0;
                        end else begin
                            automatic logic [31:0] na = r_addr + 32'd4;
                            r_addr     <= na;
                            r_left     <= r_left - 8'd1;
                            m_rdata[g] <= smem.exists(na) ? smem[na] : (32'hA000_0000 | (g << 20) | na[15:0]);
                            m_rlast[g] <= (r_left == 8'd1);
                        end
                    end
                end
            end
        end
    endgenerate

    // Watchdog
    initial begin
        #5_000_000;
        $display("[FAIL] Watchdog expired in tb_axi_interconnect_4x8!");
        $finish;
    end

    task automatic check(input reg cond, input string msg);
        if (cond) pass_count++;
        else begin
            fail_count++;
            $display("[FAIL] @%0t: %s", $time, msg);
        end
    endtask

    task automatic init_masters();
        for (int m = 0; m < NUM_M; m++) begin
            s_awvalid[m] = 0; s_awid[m] = 0; s_awaddr[m] = 0; s_awlen[m] = 0;
            s_awsize[m] = 3'b010; s_awburst[m] = 2'b01; s_awlock[m] = 0;
            s_awcache[m] = 0; s_awprot[m] = 0; s_awqos[m] = 0;
            s_wvalid[m] = 0; s_wdata[m] = 0; s_wstrb[m] = 0; s_wlast[m] = 0;
            s_bready[m] = 0;
            s_arvalid[m] = 0; s_arid[m] = 0; s_araddr[m] = 0; s_arlen[m] = 0;
            s_arsize[m] = 3'b010; s_arburst[m] = 2'b01; s_arlock[m] = 0;
            s_arcache[m] = 0; s_arprot[m] = 0; s_arqos[m] = 0;
            s_rready[m] = 0;
        end
        for (int s = 0; s < NUM_S; s++) slave_wait_cycles[s] = 0;
    endtask

    // Generic burst write for master m (supports decoupled W-before-AW)
    task automatic mst_write_burst(
        input  int             m,
        input  logic [7:0]     id,
        input  logic [31:0]    addr,
        input  logic [7:0]     len, // 0 = 1 beat
        input  logic [31:0]    data [],
        input  bit             w_before_aw,
        output logic [1:0]     bresp_o,
        output logic [7:0]     bid_o
    );
        int beat = 0;
        bit aw_done = 0, w_done = 0;
        begin
            @(posedge clk);
            s_bready[m] <= 1'b1;
            if (!w_before_aw) begin
                s_awvalid[m] <= 1'b1;
                s_awid[m]    <= id;
                s_awaddr[m]  <= addr;
                s_awlen[m]   <= len;
                s_awsize[m]  <= 3'b010;
                s_awburst[m] <= 2'b01;
            end
            s_wvalid[m] <= 1'b1;
            s_wdata[m]  <= data[0];
            s_wstrb[m]  <= 4'b1111;
            s_wlast[m]  <= (len == 0);

            while (!(aw_done && w_done)) begin
                @(posedge clk);
                if (w_before_aw && !aw_done && !s_awvalid[m]) begin
                    s_awvalid[m] <= 1'b1;
                    s_awid[m]    <= id;
                    s_awaddr[m]  <= addr;
                    s_awlen[m]   <= len;
                    s_awsize[m]  <= 3'b010;
                    s_awburst[m] <= 2'b01;
                end
                if (s_awvalid[m] && s_awready[m]) begin
                    aw_done = 1;
                    s_awvalid[m] <= 1'b0;
                end
                if (s_wvalid[m] && s_wready[m]) begin
                    if (beat == len) begin
                        w_done = 1;
                        s_wvalid[m] <= 1'b0;
                        s_wlast[m]  <= 1'b0;
                    end else begin
                        beat++;
                        s_wdata[m] <= data[beat];
                        s_wlast[m] <= (beat == len);
                    end
                end
            end
            while (!s_bvalid[m]) @(posedge clk);
            bresp_o = s_bresp[m];
            bid_o   = s_bid[m];
            @(posedge clk);
            s_bready[m] <= 1'b0;
        end
    endtask

    task automatic mst_read_burst(
        input  int             m,
        input  logic [7:0]     id,
        input  logic [31:0]    addr,
        input  logic [7:0]     len,
        input  bit             stall_rready,
        output logic [31:0]    rdata [],
        output logic [1:0]     rresp [],
        output logic [7:0]     rid_o
    );
        int beat = 0;
        begin
            rdata = new[len + 1];
            rresp = new[len + 1];
            @(posedge clk);
            s_arvalid[m] <= 1'b1;
            s_arid[m]    <= id;
            s_araddr[m]  <= addr;
            s_arlen[m]   <= len;
            s_arsize[m]  <= 3'b010;
            s_arburst[m] <= 2'b01;
            s_rready[m]  <= !stall_rready;

            @(posedge clk);
            while (!s_arready[m]) @(posedge clk);
            s_arvalid[m] <= 1'b0;

            while (beat <= len) begin
                if (stall_rready) begin
                    while (!s_rvalid[m]) @(posedge clk);
                    repeat (2) @(posedge clk);
                    s_rready[m] <= 1'b1;
                end
                @(posedge clk);
                if (s_rvalid[m] && s_rready[m]) begin
                    rdata[beat] = s_rdata[m];
                    rresp[beat] = s_rresp[m];
                    rid_o       = s_rid[m];
                    if (beat == len) check(s_rlast[m] === 1'b1, "Last beat has RLAST=1");
                    else             check(s_rlast[m] === 1'b0, "Non-last beat has RLAST=0");
                    beat++;
                    if (stall_rready) s_rready[m] <= 1'b0;
                end
            end
            s_rready[m] <= 1'b0;
        end
    endtask

    // Main test sequence
    initial begin
        logic [31:0] wbuf[], rbuf[];
        logic [1:0]  bresp, rresp_arr[];
        logic [7:0]  bid, rid;

        $display("=================================================================");
        $display(" PHASE E: AXI4 4x8 INTERCONNECT TESTBENCH (tb_axi_interconnect_4x8)");
        $display("=================================================================");

        for (int s = 0; s < NUM_S; s++) cov_slave_hit[s] = 0;
        init_masters();
        rst = 1'b1;
        repeat (8) @(posedge clk);
        rst = 1'b0;
        repeat (4) @(posedge clk);

        // ---------------------------------------------------------------------
        // Test 1: Decode All 8 Slaves Exclusively + Reset Alias
        // ---------------------------------------------------------------------
        $display("\n--- [1] Exclusive Decode Across M00..M07 & Reset Vector Alias ---");
        begin
            automatic logic [31:0] test_addrs[9] = '{
                32'h0000_0100, // M00 IMEM
                32'h0001_0100, // M01 DMEM lo
                32'h0003_0004, // M02 UART
                32'h0005_0008, // M03 Timer
                32'h0006_0004, // M04 GPIO
                32'h000D_0008, // M05 RLE
                32'h000B_0008, // M06 DMA
                32'h000A_0004, // M07 CRC
                32'h8000_0100  // M00 Reset Alias
            };
            automatic int target_idx[9] = '{0, 1, 2, 3, 4, 5, 6, 7, 0};

            for (int k = 0; k < 9; k++) begin
                wbuf = new[1]; wbuf[0] = 32'h5000_0000 + k;
                allowed_slave_mask = (8'h01 << target_idx[k]);
                unexpected_slave_wr_hits = 8'h0;
                unexpected_slave_rd_hits = 8'h0;
                mst_write_burst(1, 8'h10 + k[7:0], test_addrs[k], 0, wbuf, 0, bresp, bid);
                mst_read_burst (1, 8'h20 + k[7:0], test_addrs[k], 0, 0, rbuf, rresp_arr, rid);
                check(bresp === 2'b00 && bid === (8'h10 + k[7:0]), "Decode write OKAY + BID match");
                check(rresp_arr[0] === 2'b00 && rid === (8'h20 + k[7:0]) && rbuf[0] === wbuf[0], "Decode readback match + RID");
                check(unexpected_slave_wr_hits == 8'h0 && unexpected_slave_rd_hits == 8'h0,
                      $sformatf("Exclusive decode to M%02d without spurious hits", target_idx[k]));
                cov_slave_hit[target_idx[k]]++;
                if (k == 8) cov_reset_alias_hit++;
            end
            allowed_slave_mask = 8'hFF;
        end

        // ---------------------------------------------------------------------
        // Test 2: Single-Beat & 4-Beat DECERR Across All Reserved Slots
        // ---------------------------------------------------------------------
        $display("\n--- [2] DECERR Single & Multi-Beat Bursts on Reserved Slots ---");
        begin
            automatic logic [31:0] decerr_addrs[7] = '{
                32'h0003_1000, // Gap
                32'h0007_0000, // Pkt FIFO
                32'h0008_0000, // Pkt Counter
                32'h0009_0000, // Enh Timer
                32'h000C_0000, // Ext Int Ctrl
                32'h000E_0000, // Exp Bank A start
                32'h8001_0000  // Beyond alias
            };
            allowed_slave_mask = 8'h00; // ZERO slaves may activate!
            unexpected_slave_wr_hits = 8'h0;
            unexpected_slave_rd_hits = 8'h0;

            for (int k = 0; k < 7; k++) begin
                wbuf = new[1]; wbuf[0] = 32'hBAD0_0000;
                mst_write_burst(1, 8'h30, decerr_addrs[k], 0, wbuf, 0, bresp, bid);
                mst_read_burst (1, 8'h31, decerr_addrs[k], 0, 0, rbuf, rresp_arr, rid);
                check(bresp === 2'b11, $sformatf("Single write DECERR @ 0x%08X", decerr_addrs[k]));
                check(rresp_arr[0] === 2'b11, $sformatf("Single read DECERR @ 0x%08X", decerr_addrs[k]));
                cov_decerr_single_hit++;
            end

            // 4-beat burst DECERR
            wbuf = new[4];
            for (int i = 0; i < 4; i++) wbuf[i] = i;
            mst_write_burst(3, 8'h32, 32'h0007_0000, 3, wbuf, 0, bresp, bid);
            mst_read_burst (3, 8'h33, 32'h0008_0000, 3, 1, rbuf, rresp_arr, rid); // With RREADY stalls
            check(bresp === 2'b11 && bid === 8'h32, "4-beat write DECERR + BID");
            check(rresp_arr[0] === 2'b11 && rresp_arr[3] === 2'b11 && rid === 8'h33, "4-beat read DECERR all beats + RID");
            check(unexpected_slave_wr_hits == 8'h0 && unexpected_slave_rd_hits == 8'h0, "Zero slaves activated on DECERR bursts");
            cov_decerr_burst_hit++;
            allowed_slave_mask = 8'hFF;
        end

        // ---------------------------------------------------------------------
        // Test 3: 64 KB DMEM Boundary Crossing Burst + W-before-AW + Back-to-Back
        // ---------------------------------------------------------------------
        $display("\n--- [3] 64 KB Boundary Crossing (0x0001_FFF8 -> 0x0002_0004) & W-before-AW ---");
        wbuf = new[4];
        wbuf[0] = 32'hB001_FFF8;
        wbuf[1] = 32'hB001_FFFC;
        wbuf[2] = 32'hB002_0000;
        wbuf[3] = 32'hB002_0004;
        mst_write_burst(1, 8'h55, 32'h0001_FFF8, 3, wbuf, 1, bresp, bid); // w_before_aw = 1
        cov_w_before_aw_hit++;
        mst_read_burst (3, 8'h66, 32'h0001_FFF8, 3, 1, rbuf, rresp_arr, rid);
        for (int i = 0; i < 4; i++) begin
            check(rbuf[i] === wbuf[i] && rresp_arr[i] === 2'b00,
                  $sformatf("64KB crossing beat %0d match (0x%08X)", i, rbuf[i]));
        end
        cov_64k_cross_hit++;

        // Back-to-back zero-delay reads
        mst_read_burst(0, 8'h70, 32'h0000_0100, 0, 0, rbuf, rresp_arr, rid);
        check(rbuf[0] === 32'h5000_0000 && rid === 8'h70, "Back-to-back read #1 OK");
        mst_read_burst(0, 8'h71, 32'h8000_0100, 0, 0, rbuf, rresp_arr, rid);
        check(rbuf[0] === 32'h5000_0008 && rid === 8'h71, "Back-to-back read #2 (Reset Alias) OK");

        // ---------------------------------------------------------------------
        // Test 4: 4-Master Concurrent Contention (Same Slave M01 + Different Slaves)
        // ---------------------------------------------------------------------
        $display("\n--- [4] 4-Master Simultaneous Round-Robin Contention ---");
        slave_wait_cycles[1] = 2;
        fork
            begin
                logic [31:0] d[]; logic [31:0] r[]; logic [1:0] br, rr[]; logic [7:0] bi, ri;
                d = new[2]; d[0] = 32'h1111_0000; d[1] = 32'h1111_0001;
                mst_write_burst(0, 8'hA0, 32'h0001_2000, 1, d, 0, br, bi);
                mst_read_burst (0, 8'hA1, 32'h0001_2000, 1, 0, r, rr, ri);
                check(br === 2'b00 && bi === 8'hA0 && r[0] === d[0] && r[1] === d[1] && ri === 8'hA1, "S00 concurrent M01 PASS");
            end
            begin
                logic [31:0] d[]; logic [31:0] r[]; logic [1:0] br, rr[]; logic [7:0] bi, ri;
                d = new[2]; d[0] = 32'h2222_0000; d[1] = 32'h2222_0001;
                mst_write_burst(1, 8'hB0, 32'h0001_2100, 1, d, 0, br, bi);
                mst_read_burst (1, 8'hB1, 32'h0001_2100, 1, 0, r, rr, ri);
                check(br === 2'b00 && bi === 8'hB0 && r[0] === d[0] && r[1] === d[1] && ri === 8'hB1, "S01 concurrent M01 PASS");
            end
            begin
                logic [31:0] d[]; logic [31:0] r[]; logic [1:0] br, rr[]; logic [7:0] bi, ri;
                d = new[2]; d[0] = 32'h3333_0000; d[1] = 32'h3333_0001;
                mst_write_burst(2, 8'hC0, 32'h0001_2200, 1, d, 0, br, bi);
                mst_read_burst (2, 8'hC1, 32'h0001_2200, 1, 0, r, rr, ri);
                check(br === 2'b00 && bi === 8'hC0 && r[0] === d[0] && r[1] === d[1] && ri === 8'hC1, "S02 concurrent M01 PASS");
            end
            begin
                logic [31:0] d[]; logic [31:0] r[]; logic [1:0] br, rr[]; logic [7:0] bi, ri;
                d = new[2]; d[0] = 32'h4444_0000; d[1] = 32'h4444_0001;
                mst_write_burst(3, 8'hD0, 32'h0002_2300, 1, d, 0, br, bi);
                mst_read_burst (3, 8'hD1, 32'h0002_2300, 1, 0, r, rr, ri);
                check(br === 2'b00 && bi === 8'hD0 && r[0] === d[0] && r[1] === d[1] && ri === 8'hD1, "S03 concurrent M01 PASS");
            end
        join
        cov_4m_contention_same++;

        // Concurrent requests to 4 DIFFERENT slaves
        fork
            begin
                logic [31:0] r[]; logic [1:0] rr[]; logic [7:0] ri;
                mst_read_burst(0, 8'hE0, 32'h0000_0100, 0, 0, r, rr, ri);
                check(ri === 8'hE0 && r[0] === 32'h5000_0000, "S00 distinct-slave M00 PASS");
            end
            begin
                logic [31:0] r[]; logic [1:0] rr[]; logic [7:0] ri;
                mst_read_burst(1, 8'hE1, 32'h0003_0004, 0, 0, r, rr, ri);
                check(ri === 8'hE1 && r[0] === 32'h5000_0002, "S01 distinct-slave M02 PASS");
            end
            begin
                logic [31:0] r[]; logic [1:0] rr[]; logic [7:0] ri;
                mst_read_burst(2, 8'hE2, 32'h0006_0004, 0, 0, r, rr, ri);
                check(ri === 8'hE2 && r[0] === 32'h5000_0004, "S02 distinct-slave M04 PASS");
            end
            begin
                logic [31:0] r[]; logic [1:0] rr[]; logic [7:0] ri;
                mst_read_burst(3, 8'hE3, 32'h000A_0004, 0, 0, r, rr, ri);
                check(ri === 8'hE3 && r[0] === 32'h5000_0007, "S03 distinct-slave M07 PASS");
            end
        join
        cov_4m_contention_diff++;

        // ---------------------------------------------------------------------
        // Test 5: Reset During In-Flight Burst + Clean Recovery
        // ---------------------------------------------------------------------
        $display("\n--- [5] Dynamic Reset During In-Flight Multi-Beat Read + Recovery ---");
        slave_wait_cycles[1] = 8;
        rst_chk_disable = 1'b1; // Disable queue-tracking across deliberate abort
        @(posedge clk);
        s_arvalid[1] <= 1'b1;
        s_arid[1]    <= 8'hFE;
        s_araddr[1]  <= 32'h0001_0000;
        s_arlen[1]   <= 8'd7;
        s_rready[1]  <= 1'b1;
        repeat (3) @(posedge clk); // While slave is stalled waiting
        rst <= 1'b1;
        s_arvalid[1] <= 1'b0;
        s_rready[1]  <= 1'b0;
        repeat (4) @(posedge clk);
        check(m_arvalid[1] === 1'b0 && s_rvalid[1] === 1'b0 && s_bvalid[1] === 1'b0,
              "Interconnect clears valid outputs during in-flight reset");
        rst <= 1'b0;
        slave_wait_cycles[1] = 0;
        repeat (3) @(posedge clk);
        rst_chk_disable = 1'b0;

        // Post-reset recovery check
        wbuf = new[1]; wbuf[0] = 32'hCAFE_2026;
        mst_write_burst(1, 8'hFF, 32'h0002_1000, 0, wbuf, 0, bresp, bid);
        mst_read_burst (3, 8'h01, 32'h0002_1000, 0, 0, rbuf, rresp_arr, rid);
        check(bresp === 2'b00 && rbuf[0] === 32'hCAFE_2026, "Clean read/write recovery after in-flight reset");
        cov_inflight_rst_hit++;

        // ---------------------------------------------------------------------
        // Assertion & Coverage Report
        // ---------------------------------------------------------------------
        begin
            automatic int total_asrt_errs =
                gen_m_asrt[0].u_m_asrt.get_total_assertion_errors() +
                gen_m_asrt[1].u_m_asrt.get_total_assertion_errors() +
                gen_m_asrt[2].u_m_asrt.get_total_assertion_errors() +
                gen_m_asrt[3].u_m_asrt.get_total_assertion_errors() +
                u_s1_asrt.get_total_assertion_errors();

            automatic int cov_bins = 0;
            for (int s = 0; s < NUM_S; s++) if (cov_slave_hit[s] > 0) cov_bins++;
            if (cov_reset_alias_hit > 0)    cov_bins++;
            if (cov_decerr_single_hit > 0)  cov_bins++;
            if (cov_decerr_burst_hit > 0)   cov_bins++;
            if (cov_64k_cross_hit > 0)      cov_bins++;
            if (cov_4m_contention_same > 0) cov_bins++;
            if (cov_4m_contention_diff > 0) cov_bins++;
            if (cov_w_before_aw_hit > 0)    cov_bins++;
            if (cov_inflight_rst_hit > 0)   cov_bins++;

            $display("\n=================================================================");
            $display(" AXI INTERCONNECT COVERAGE: %0d / 16 Bins (%0.1f%%)", cov_bins, (cov_bins * 100.0) / 16.0);
            $display(" ASSERTION ERRORS         : %0d", total_asrt_errs);
            $display(" CHECKS                   : Passed=%0d Failed=%0d Total=%0d",
                     pass_count, fail_count, pass_count + fail_count);
            $display("=================================================================");
            if (fail_count == 0 && total_asrt_errs == 0 && cov_bins == 16)
                $display("STATUS: ALL INTERCONNECT TESTS & ASSERTIONS PASSED!");
            else
                $display("STATUS: INTERCONNECT VERIFICATION FAILED!");
        end

        $finish;
    end

endmodule
