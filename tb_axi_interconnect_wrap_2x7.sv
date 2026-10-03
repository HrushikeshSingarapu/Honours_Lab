// =============================================================================
// tb_axi_interconnect_wrap_2x7.sv
//
// TARGET DUT  : axi_interconnect_wrap_2x7.v  (Alex Forencich AXI4 interconnect
//               wrapper — 2 slave ports, 7 master ports)
// SIMULATOR   : Synopsys VCS U-2023.03  (-full64 -sverilog)
//
// REAL RTL UNDER TEST
//   rtl/axi_interconnect_wrap_2x7.v   — DUT (wrapper)
//   rtl/axi_interconnect.v            — instantiated by the wrapper
//   rtl/arbiter.v                     — used by axi_interconnect.v
//   rtl/priority_encoder.v            — used by axi_interconnect.v
//
// TEST-ONLY STUB MODELS (not the real peripherals)
//   tb/axi_slave_stub.sv — memory-backed AXI4 slave stub (one per master port)
//
// =============================================================================
// *** DISCREPANCIES vs. the architecture document — see README_tb.md ***
//
//   [DISC-1] File named axi_interconnect_wrap_ax7.v in the task prompt;
//            actual file is axi_interconnect_wrap_2x7.v.  Targeting the
//            file that exists.
//
//   [DISC-2] Spec §3.4 says DATA_WIDTH=64 (LSU); wrapper default is 32.
//            ASSUMPTION [A-1]: Using DATA_WIDTH=32.  Change TB_DATA_WIDTH
//            to 64 (and awsize to 3'b011) when the wrapper is updated.
//
//   [DISC-3] Spec Table 1 has 8 regions; DUT has 7 master ports.
//            ASSUMPTION [A-2]: CRC (0x1001_2000) is unmapped → DECERR.
//            Port assignment:
//              m00 InstrMem  0x0000_0000  256KiB (addr_width=18)
//              m01 DataMem   0x0004_0000  256KiB (addr_width=18)
//              m02 UART      0x1000_0000    4KiB (addr_width=12)
//              m03 Timer     0x1000_1000    4KiB (addr_width=12)
//              m04 GPIO      0x1000_2000    4KiB (addr_width=12)
//              m05 RLE       0x1001_0000    4KiB (addr_width=12)
//              m06 DMA       0x1001_1000    4KiB (addr_width=12)
//
//   [DISC-4] LSU_BUS_TAG width not given numerically.
//            ASSUMPTION [A-3]: ID_WIDTH=8 (wrapper default).
//
//   [DISC-5] Undefined-address response not stated in spec.
//            RTL returns bresp/rresp=2'b11 (DECERR). Test 3 checks this.
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

module tb_axi_interconnect_wrap_2x7;

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------
localparam TB_DATA_WIDTH = 32;          // [A-1] change to 64 for 64-bit path
localparam TB_ADDR_WIDTH = 32;
localparam TB_STRB_WIDTH = TB_DATA_WIDTH / 8;
localparam TB_ID_WIDTH   = 8;           // [A-3]

localparam RESP_OKAY   = 2'b00;
localparam RESP_DECERR = 2'b11;

// ---------------------------------------------------------------------------
// Address map (spec §2.2 Table 1 + [A-2])
// ---------------------------------------------------------------------------
localparam [31:0] M00_BASE = 32'h0000_0000; localparam integer M00_ABITS = 18;
localparam [31:0] M01_BASE = 32'h0004_0000; localparam integer M01_ABITS = 18;
localparam [31:0] M02_BASE = 32'h1000_0000; localparam integer M02_ABITS = 12;
localparam [31:0] M03_BASE = 32'h1000_1000; localparam integer M03_ABITS = 12;
localparam [31:0] M04_BASE = 32'h1000_2000; localparam integer M04_ABITS = 12;
localparam [31:0] M05_BASE = 32'h1001_0000; localparam integer M05_ABITS = 12;
localparam [31:0] M06_BASE = 32'h1001_1000; localparam integer M06_ABITS = 12;
localparam [31:0] UNMAPPED = 32'hDEAD_0000; // guaranteed gap for test 3

// ---------------------------------------------------------------------------
// Clock / reset
// ---------------------------------------------------------------------------
reg clk = 1'b0;
reg rst = 1'b1;
always #5 clk = ~clk;   // 100 MHz

// ---------------------------------------------------------------------------
// Scoreboard — module-level so tasks can access them
// ---------------------------------------------------------------------------
integer tests_run  = 0;
integer tests_pass = 0;
integer tests_fail = 0;

// ---------------------------------------------------------------------------
// Shared variables used by test body and tasks
// (ALL local variables hoisted here; no declarations inside begin..end blocks)
// ---------------------------------------------------------------------------
reg  [1:0]               t_bresp, t_rresp;
reg  [TB_ID_WIDTH-1:0]   t_bid,   t_rid;
reg  [TB_DATA_WIDTH-1:0] t_rdata;
reg  [TB_DATA_WIDTH-1:0] t_rd0, t_rd1, t_rd2;
reg  [1:0]               t_b1, t_b2, t_iresp;
reg  [TB_ID_WIDTH-1:0]   t_id1, t_id2;
reg  [TB_DATA_WIDTH-1:0] t_idata;
reg  [31:0]              t_wdata_val;
integer                  t_i, t_j, t_b;

// Region table (flat parallel arrays — no struct/typedef needed)
reg [31:0]  rgn_base  [0:6];
integer     rgn_slave [0:6];
// Region names printed via $display index

// Snapshot buffers for slave counter checks
integer wr_before [0:6];
integer rd_before [0:6];

// ---------------------------------------------------------------------------
// DUT slave-side signals  (s00 = LSU master, s01 = IFU master)
// ---------------------------------------------------------------------------
reg  [TB_ID_WIDTH-1:0]   s00_awid;
reg  [TB_ADDR_WIDTH-1:0] s00_awaddr;
reg  [7:0]               s00_awlen;
reg  [2:0]               s00_awsize;
reg  [1:0]               s00_awburst;
reg                      s00_awlock;
reg  [3:0]               s00_awcache;
reg  [2:0]               s00_awprot;
reg  [3:0]               s00_awqos;
reg                      s00_awvalid;
wire                     s00_awready;

reg  [TB_DATA_WIDTH-1:0] s00_wdata;
reg  [TB_STRB_WIDTH-1:0] s00_wstrb;
reg                      s00_wlast;
reg                      s00_wvalid;
wire                     s00_wready;

wire [TB_ID_WIDTH-1:0]   s00_bid;
wire [1:0]               s00_bresp;
wire                     s00_bvalid;
reg                      s00_bready;

reg  [TB_ID_WIDTH-1:0]   s00_arid;
reg  [TB_ADDR_WIDTH-1:0] s00_araddr;
reg  [7:0]               s00_arlen;
reg  [2:0]               s00_arsize;
reg  [1:0]               s00_arburst;
reg                      s00_arlock;
reg  [3:0]               s00_arcache;
reg  [2:0]               s00_arprot;
reg  [3:0]               s00_arqos;
reg                      s00_arvalid;
wire                     s00_arready;

wire [TB_ID_WIDTH-1:0]   s00_rid;
wire [TB_DATA_WIDTH-1:0] s00_rdata;
wire [1:0]               s00_rresp;
wire                     s00_rlast;
wire                     s00_rvalid;
reg                      s00_rready;

// s01 — IFU (read-only; write ports tied off in DUT instantiation)
reg  [TB_ID_WIDTH-1:0]   s01_arid;
reg  [TB_ADDR_WIDTH-1:0] s01_araddr;
reg  [7:0]               s01_arlen;
reg  [2:0]               s01_arsize;
reg  [1:0]               s01_arburst;
reg                      s01_arlock;
reg  [3:0]               s01_arcache;
reg  [2:0]               s01_arprot;
reg  [3:0]               s01_arqos;
reg                      s01_arvalid;
wire                     s01_arready;
wire [TB_ID_WIDTH-1:0]   s01_rid;
wire [TB_DATA_WIDTH-1:0] s01_rdata;
wire [1:0]               s01_rresp;
wire                     s01_rlast;
wire                     s01_rvalid;
reg                      s01_rready;

// ---------------------------------------------------------------------------
// DUT master-side signals  (interconnect → slave stubs)
// ---------------------------------------------------------------------------
`define DECL_MPORT(NN) \
wire [TB_ID_WIDTH-1:0]   m``NN``_awid;    \
wire [TB_ADDR_WIDTH-1:0] m``NN``_awaddr;  \
wire [7:0]               m``NN``_awlen;   \
wire [2:0]               m``NN``_awsize;  \
wire [1:0]               m``NN``_awburst; \
wire                     m``NN``_awlock;  \
wire [3:0]               m``NN``_awcache; \
wire [2:0]               m``NN``_awprot;  \
wire [3:0]               m``NN``_awqos;   \
wire [3:0]               m``NN``_awregion;\
wire                     m``NN``_awvalid; \
wire                     m``NN``_awready; \
wire [TB_DATA_WIDTH-1:0] m``NN``_wdata;   \
wire [TB_STRB_WIDTH-1:0] m``NN``_wstrb;   \
wire                     m``NN``_wlast;   \
wire                     m``NN``_wvalid;  \
wire                     m``NN``_wready;  \
wire [TB_ID_WIDTH-1:0]   m``NN``_bid;     \
wire [1:0]               m``NN``_bresp;   \
wire                     m``NN``_bvalid;  \
wire                     m``NN``_bready;  \
wire [TB_ID_WIDTH-1:0]   m``NN``_arid;    \
wire [TB_ADDR_WIDTH-1:0] m``NN``_araddr;  \
wire [7:0]               m``NN``_arlen;   \
wire [2:0]               m``NN``_arsize;  \
wire [1:0]               m``NN``_arburst; \
wire                     m``NN``_arlock;  \
wire [3:0]               m``NN``_arcache; \
wire [2:0]               m``NN``_arprot;  \
wire [3:0]               m``NN``_arqos;   \
wire [3:0]               m``NN``_arregion;\
wire                     m``NN``_arvalid; \
wire                     m``NN``_arready; \
wire [TB_ID_WIDTH-1:0]   m``NN``_rid;     \
wire [TB_DATA_WIDTH-1:0] m``NN``_rdata;   \
wire [1:0]               m``NN``_rresp;   \
wire                     m``NN``_rlast;   \
wire                     m``NN``_rvalid;  \
wire                     m``NN``_rready

`DECL_MPORT(00);
`DECL_MPORT(01);
`DECL_MPORT(02);
`DECL_MPORT(03);
`DECL_MPORT(04);
`DECL_MPORT(05);
`DECL_MPORT(06);

// ---------------------------------------------------------------------------
// Slave stub observability counters
// ---------------------------------------------------------------------------
wire [31:0] slave_wr_cnt [0:6];
wire [31:0] slave_rd_cnt [0:6];

// ---------------------------------------------------------------------------
// DUT instantiation
// ---------------------------------------------------------------------------
axi_interconnect_wrap_2x7 #(
    .DATA_WIDTH  (TB_DATA_WIDTH),
    .ADDR_WIDTH  (TB_ADDR_WIDTH),
    .STRB_WIDTH  (TB_STRB_WIDTH),
    .ID_WIDTH    (TB_ID_WIDTH),
    .FORWARD_ID  (0),
    .M_REGIONS   (1),
    .M00_BASE_ADDR  (M00_BASE), .M00_ADDR_WIDTH ({1{32'd18}}),
    .M00_CONNECT_READ(2'b11),   .M00_CONNECT_WRITE(2'b11),
    .M01_BASE_ADDR  (M01_BASE), .M01_ADDR_WIDTH ({1{32'd18}}),
    .M01_CONNECT_READ(2'b11),   .M01_CONNECT_WRITE(2'b11),
    .M02_BASE_ADDR  (M02_BASE), .M02_ADDR_WIDTH ({1{32'd12}}),
    .M02_CONNECT_READ(2'b11),   .M02_CONNECT_WRITE(2'b11),
    .M03_BASE_ADDR  (M03_BASE), .M03_ADDR_WIDTH ({1{32'd12}}),
    .M03_CONNECT_READ(2'b11),   .M03_CONNECT_WRITE(2'b11),
    .M04_BASE_ADDR  (M04_BASE), .M04_ADDR_WIDTH ({1{32'd12}}),
    .M04_CONNECT_READ(2'b11),   .M04_CONNECT_WRITE(2'b11),
    .M05_BASE_ADDR  (M05_BASE), .M05_ADDR_WIDTH ({1{32'd12}}),
    .M05_CONNECT_READ(2'b11),   .M05_CONNECT_WRITE(2'b11),
    .M06_BASE_ADDR  (M06_BASE), .M06_ADDR_WIDTH ({1{32'd12}}),
    .M06_CONNECT_READ(2'b11),   .M06_CONNECT_WRITE(2'b11)
) dut (
    .clk(clk), .rst(rst),
    // s00
    .s00_axi_awid(s00_awid),   .s00_axi_awaddr(s00_awaddr),
    .s00_axi_awlen(s00_awlen), .s00_axi_awsize(s00_awsize),
    .s00_axi_awburst(s00_awburst), .s00_axi_awlock(s00_awlock),
    .s00_axi_awcache(s00_awcache), .s00_axi_awprot(s00_awprot),
    .s00_axi_awqos(s00_awqos),  .s00_axi_awuser(1'b0),
    .s00_axi_awvalid(s00_awvalid), .s00_axi_awready(s00_awready),
    .s00_axi_wdata(s00_wdata),  .s00_axi_wstrb(s00_wstrb),
    .s00_axi_wlast(s00_wlast),  .s00_axi_wuser(1'b0),
    .s00_axi_wvalid(s00_wvalid), .s00_axi_wready(s00_wready),
    .s00_axi_bid(s00_bid),      .s00_axi_bresp(s00_bresp),
    .s00_axi_buser(),           .s00_axi_bvalid(s00_bvalid),
    .s00_axi_bready(s00_bready),
    .s00_axi_arid(s00_arid),    .s00_axi_araddr(s00_araddr),
    .s00_axi_arlen(s00_arlen),  .s00_axi_arsize(s00_arsize),
    .s00_axi_arburst(s00_arburst), .s00_axi_arlock(s00_arlock),
    .s00_axi_arcache(s00_arcache), .s00_axi_arprot(s00_arprot),
    .s00_axi_arqos(s00_arqos),  .s00_axi_aruser(1'b0),
    .s00_axi_arvalid(s00_arvalid), .s00_axi_arready(s00_arready),
    .s00_axi_rid(s00_rid),      .s00_axi_rdata(s00_rdata),
    .s00_axi_rresp(s00_rresp),  .s00_axi_rlast(s00_rlast),
    .s00_axi_ruser(),           .s00_axi_rvalid(s00_rvalid),
    .s00_axi_rready(s00_rready),
    // s01 (IFU — write ports tied off)
    .s01_axi_awid({TB_ID_WIDTH{1'b0}}),   .s01_axi_awaddr({TB_ADDR_WIDTH{1'b0}}),
    .s01_axi_awlen(8'h0),                 .s01_axi_awsize(3'h0),
    .s01_axi_awburst(2'h0),               .s01_axi_awlock(1'b0),
    .s01_axi_awcache(4'h0),               .s01_axi_awprot(3'h0),
    .s01_axi_awqos(4'h0),                 .s01_axi_awuser(1'b0),
    .s01_axi_awvalid(1'b0),               .s01_axi_awready(),
    .s01_axi_wdata({TB_DATA_WIDTH{1'b0}}), .s01_axi_wstrb({TB_STRB_WIDTH{1'b0}}),
    .s01_axi_wlast(1'b0),                 .s01_axi_wuser(1'b0),
    .s01_axi_wvalid(1'b0),                .s01_axi_wready(),
    .s01_axi_bid(),   .s01_axi_bresp(),   .s01_axi_buser(),
    .s01_axi_bvalid(), .s01_axi_bready(1'b0),
    .s01_axi_arid(s01_arid),    .s01_axi_araddr(s01_araddr),
    .s01_axi_arlen(s01_arlen),  .s01_axi_arsize(s01_arsize),
    .s01_axi_arburst(s01_arburst), .s01_axi_arlock(s01_arlock),
    .s01_axi_arcache(s01_arcache), .s01_axi_arprot(s01_arprot),
    .s01_axi_arqos(s01_arqos),  .s01_axi_aruser(1'b0),
    .s01_axi_arvalid(s01_arvalid), .s01_axi_arready(s01_arready),
    .s01_axi_rid(s01_rid),      .s01_axi_rdata(s01_rdata),
    .s01_axi_rresp(s01_rresp),  .s01_axi_rlast(s01_rlast),
    .s01_axi_ruser(),           .s01_axi_rvalid(s01_rvalid),
    .s01_axi_rready(s01_rready),
    // m00
    .m00_axi_awid(m00_awid),    .m00_axi_awaddr(m00_awaddr),
    .m00_axi_awlen(m00_awlen),  .m00_axi_awsize(m00_awsize),
    .m00_axi_awburst(m00_awburst), .m00_axi_awlock(m00_awlock),
    .m00_axi_awcache(m00_awcache), .m00_axi_awprot(m00_awprot),
    .m00_axi_awqos(m00_awqos),  .m00_axi_awregion(m00_awregion),
    .m00_axi_awuser(),          .m00_axi_awvalid(m00_awvalid),
    .m00_axi_awready(m00_awready), .m00_axi_wdata(m00_wdata),
    .m00_axi_wstrb(m00_wstrb),  .m00_axi_wlast(m00_wlast),
    .m00_axi_wuser(),           .m00_axi_wvalid(m00_wvalid),
    .m00_axi_wready(m00_wready), .m00_axi_bid(m00_bid),
    .m00_axi_bresp(m00_bresp),  .m00_axi_buser(1'b0),
    .m00_axi_bvalid(m00_bvalid), .m00_axi_bready(m00_bready),
    .m00_axi_arid(m00_arid),    .m00_axi_araddr(m00_araddr),
    .m00_axi_arlen(m00_arlen),  .m00_axi_arsize(m00_arsize),
    .m00_axi_arburst(m00_arburst), .m00_axi_arlock(m00_arlock),
    .m00_axi_arcache(m00_arcache), .m00_axi_arprot(m00_arprot),
    .m00_axi_arqos(m00_arqos),  .m00_axi_arregion(m00_arregion),
    .m00_axi_aruser(),          .m00_axi_arvalid(m00_arvalid),
    .m00_axi_arready(m00_arready), .m00_axi_rid(m00_rid),
    .m00_axi_rdata(m00_rdata),  .m00_axi_rresp(m00_rresp),
    .m00_axi_rlast(m00_rlast),  .m00_axi_ruser(1'b0),
    .m00_axi_rvalid(m00_rvalid), .m00_axi_rready(m00_rready),
    // m01
    .m01_axi_awid(m01_awid),    .m01_axi_awaddr(m01_awaddr),
    .m01_axi_awlen(m01_awlen),  .m01_axi_awsize(m01_awsize),
    .m01_axi_awburst(m01_awburst), .m01_axi_awlock(m01_awlock),
    .m01_axi_awcache(m01_awcache), .m01_axi_awprot(m01_awprot),
    .m01_axi_awqos(m01_awqos),  .m01_axi_awregion(m01_awregion),
    .m01_axi_awuser(),          .m01_axi_awvalid(m01_awvalid),
    .m01_axi_awready(m01_awready), .m01_axi_wdata(m01_wdata),
    .m01_axi_wstrb(m01_wstrb),  .m01_axi_wlast(m01_wlast),
    .m01_axi_wuser(),           .m01_axi_wvalid(m01_wvalid),
    .m01_axi_wready(m01_wready), .m01_axi_bid(m01_bid),
    .m01_axi_bresp(m01_bresp),  .m01_axi_buser(1'b0),
    .m01_axi_bvalid(m01_bvalid), .m01_axi_bready(m01_bready),
    .m01_axi_arid(m01_arid),    .m01_axi_araddr(m01_araddr),
    .m01_axi_arlen(m01_arlen),  .m01_axi_arsize(m01_arsize),
    .m01_axi_arburst(m01_arburst), .m01_axi_arlock(m01_arlock),
    .m01_axi_arcache(m01_arcache), .m01_axi_arprot(m01_arprot),
    .m01_axi_arqos(m01_arqos),  .m01_axi_arregion(m01_arregion),
    .m01_axi_aruser(),          .m01_axi_arvalid(m01_arvalid),
    .m01_axi_arready(m01_arready), .m01_axi_rid(m01_rid),
    .m01_axi_rdata(m01_rdata),  .m01_axi_rresp(m01_rresp),
    .m01_axi_rlast(m01_rlast),  .m01_axi_ruser(1'b0),
    .m01_axi_rvalid(m01_rvalid), .m01_axi_rready(m01_rready),
    // m02
    .m02_axi_awid(m02_awid),    .m02_axi_awaddr(m02_awaddr),
    .m02_axi_awlen(m02_awlen),  .m02_axi_awsize(m02_awsize),
    .m02_axi_awburst(m02_awburst), .m02_axi_awlock(m02_awlock),
    .m02_axi_awcache(m02_awcache), .m02_axi_awprot(m02_awprot),
    .m02_axi_awqos(m02_awqos),  .m02_axi_awregion(m02_awregion),
    .m02_axi_awuser(),          .m02_axi_awvalid(m02_awvalid),
    .m02_axi_awready(m02_awready), .m02_axi_wdata(m02_wdata),
    .m02_axi_wstrb(m02_wstrb),  .m02_axi_wlast(m02_wlast),
    .m02_axi_wuser(),           .m02_axi_wvalid(m02_wvalid),
    .m02_axi_wready(m02_wready), .m02_axi_bid(m02_bid),
    .m02_axi_bresp(m02_bresp),  .m02_axi_buser(1'b0),
    .m02_axi_bvalid(m02_bvalid), .m02_axi_bready(m02_bready),
    .m02_axi_arid(m02_arid),    .m02_axi_araddr(m02_araddr),
    .m02_axi_arlen(m02_arlen),  .m02_axi_arsize(m02_arsize),
    .m02_axi_arburst(m02_arburst), .m02_axi_arlock(m02_arlock),
    .m02_axi_arcache(m02_arcache), .m02_axi_arprot(m02_arprot),
    .m02_axi_arqos(m02_arqos),  .m02_axi_arregion(m02_arregion),
    .m02_axi_aruser(),          .m02_axi_arvalid(m02_arvalid),
    .m02_axi_arready(m02_arready), .m02_axi_rid(m02_rid),
    .m02_axi_rdata(m02_rdata),  .m02_axi_rresp(m02_rresp),
    .m02_axi_rlast(m02_rlast),  .m02_axi_ruser(1'b0),
    .m02_axi_rvalid(m02_rvalid), .m02_axi_rready(m02_rready),
    // m03
    .m03_axi_awid(m03_awid),    .m03_axi_awaddr(m03_awaddr),
    .m03_axi_awlen(m03_awlen),  .m03_axi_awsize(m03_awsize),
    .m03_axi_awburst(m03_awburst), .m03_axi_awlock(m03_awlock),
    .m03_axi_awcache(m03_awcache), .m03_axi_awprot(m03_awprot),
    .m03_axi_awqos(m03_awqos),  .m03_axi_awregion(m03_awregion),
    .m03_axi_awuser(),          .m03_axi_awvalid(m03_awvalid),
    .m03_axi_awready(m03_awready), .m03_axi_wdata(m03_wdata),
    .m03_axi_wstrb(m03_wstrb),  .m03_axi_wlast(m03_wlast),
    .m03_axi_wuser(),           .m03_axi_wvalid(m03_wvalid),
    .m03_axi_wready(m03_wready), .m03_axi_bid(m03_bid),
    .m03_axi_bresp(m03_bresp),  .m03_axi_buser(1'b0),
    .m03_axi_bvalid(m03_bvalid), .m03_axi_bready(m03_bready),
    .m03_axi_arid(m03_arid),    .m03_axi_araddr(m03_araddr),
    .m03_axi_arlen(m03_arlen),  .m03_axi_arsize(m03_arsize),
    .m03_axi_arburst(m03_arburst), .m03_axi_arlock(m03_arlock),
    .m03_axi_arcache(m03_arcache), .m03_axi_arprot(m03_arprot),
    .m03_axi_arqos(m03_arqos),  .m03_axi_arregion(m03_arregion),
    .m03_axi_aruser(),          .m03_axi_arvalid(m03_arvalid),
    .m03_axi_arready(m03_arready), .m03_axi_rid(m03_rid),
    .m03_axi_rdata(m03_rdata),  .m03_axi_rresp(m03_rresp),
    .m03_axi_rlast(m03_rlast),  .m03_axi_ruser(1'b0),
    .m03_axi_rvalid(m03_rvalid), .m03_axi_rready(m03_rready),
    // m04
    .m04_axi_awid(m04_awid),    .m04_axi_awaddr(m04_awaddr),
    .m04_axi_awlen(m04_awlen),  .m04_axi_awsize(m04_awsize),
    .m04_axi_awburst(m04_awburst), .m04_axi_awlock(m04_awlock),
    .m04_axi_awcache(m04_awcache), .m04_axi_awprot(m04_awprot),
    .m04_axi_awqos(m04_awqos),  .m04_axi_awregion(m04_awregion),
    .m04_axi_awuser(),          .m04_axi_awvalid(m04_awvalid),
    .m04_axi_awready(m04_awready), .m04_axi_wdata(m04_wdata),
    .m04_axi_wstrb(m04_wstrb),  .m04_axi_wlast(m04_wlast),
    .m04_axi_wuser(),           .m04_axi_wvalid(m04_wvalid),
    .m04_axi_wready(m04_wready), .m04_axi_bid(m04_bid),
    .m04_axi_bresp(m04_bresp),  .m04_axi_buser(1'b0),
    .m04_axi_bvalid(m04_bvalid), .m04_axi_bready(m04_bready),
    .m04_axi_arid(m04_arid),    .m04_axi_araddr(m04_araddr),
    .m04_axi_arlen(m04_arlen),  .m04_axi_arsize(m04_arsize),
    .m04_axi_arburst(m04_arburst), .m04_axi_arlock(m04_arlock),
    .m04_axi_arcache(m04_arcache), .m04_axi_arprot(m04_arprot),
    .m04_axi_arqos(m04_arqos),  .m04_axi_arregion(m04_arregion),
    .m04_axi_aruser(),          .m04_axi_arvalid(m04_arvalid),
    .m04_axi_arready(m04_arready), .m04_axi_rid(m04_rid),
    .m04_axi_rdata(m04_rdata),  .m04_axi_rresp(m04_rresp),
    .m04_axi_rlast(m04_rlast),  .m04_axi_ruser(1'b0),
    .m04_axi_rvalid(m04_rvalid), .m04_axi_rready(m04_rready),
    // m05
    .m05_axi_awid(m05_awid),    .m05_axi_awaddr(m05_awaddr),
    .m05_axi_awlen(m05_awlen),  .m05_axi_awsize(m05_awsize),
    .m05_axi_awburst(m05_awburst), .m05_axi_awlock(m05_awlock),
    .m05_axi_awcache(m05_awcache), .m05_axi_awprot(m05_awprot),
    .m05_axi_awqos(m05_awqos),  .m05_axi_awregion(m05_awregion),
    .m05_axi_awuser(),          .m05_axi_awvalid(m05_awvalid),
    .m05_axi_awready(m05_awready), .m05_axi_wdata(m05_wdata),
    .m05_axi_wstrb(m05_wstrb),  .m05_axi_wlast(m05_wlast),
    .m05_axi_wuser(),           .m05_axi_wvalid(m05_wvalid),
    .m05_axi_wready(m05_wready), .m05_axi_bid(m05_bid),
    .m05_axi_bresp(m05_bresp),  .m05_axi_buser(1'b0),
    .m05_axi_bvalid(m05_bvalid), .m05_axi_bready(m05_bready),
    .m05_axi_arid(m05_arid),    .m05_axi_araddr(m05_araddr),
    .m05_axi_arlen(m05_arlen),  .m05_axi_arsize(m05_arsize),
    .m05_axi_arburst(m05_arburst), .m05_axi_arlock(m05_arlock),
    .m05_axi_arcache(m05_arcache), .m05_axi_arprot(m05_arprot),
    .m05_axi_arqos(m05_arqos),  .m05_axi_arregion(m05_arregion),
    .m05_axi_aruser(),          .m05_axi_arvalid(m05_arvalid),
    .m05_axi_arready(m05_arready), .m05_axi_rid(m05_rid),
    .m05_axi_rdata(m05_rdata),  .m05_axi_rresp(m05_rresp),
    .m05_axi_rlast(m05_rlast),  .m05_axi_ruser(1'b0),
    .m05_axi_rvalid(m05_rvalid), .m05_axi_rready(m05_rready),
    // m06
    .m06_axi_awid(m06_awid),    .m06_axi_awaddr(m06_awaddr),
    .m06_axi_awlen(m06_awlen),  .m06_axi_awsize(m06_awsize),
    .m06_axi_awburst(m06_awburst), .m06_axi_awlock(m06_awlock),
    .m06_axi_awcache(m06_awcache), .m06_axi_awprot(m06_awprot),
    .m06_axi_awqos(m06_awqos),  .m06_axi_awregion(m06_awregion),
    .m06_axi_awuser(),          .m06_axi_awvalid(m06_awvalid),
    .m06_axi_awready(m06_awready), .m06_axi_wdata(m06_wdata),
    .m06_axi_wstrb(m06_wstrb),  .m06_axi_wlast(m06_wlast),
    .m06_axi_wuser(),           .m06_axi_wvalid(m06_wvalid),
    .m06_axi_wready(m06_wready), .m06_axi_bid(m06_bid),
    .m06_axi_bresp(m06_bresp),  .m06_axi_buser(1'b0),
    .m06_axi_bvalid(m06_bvalid), .m06_axi_bready(m06_bready),
    .m06_axi_arid(m06_arid),    .m06_axi_araddr(m06_araddr),
    .m06_axi_arlen(m06_arlen),  .m06_axi_arsize(m06_arsize),
    .m06_axi_arburst(m06_arburst), .m06_axi_arlock(m06_arlock),
    .m06_axi_arcache(m06_arcache), .m06_axi_arprot(m06_arprot),
    .m06_axi_arqos(m06_arqos),  .m06_axi_arregion(m06_arregion),
    .m06_axi_aruser(),          .m06_axi_arvalid(m06_arvalid),
    .m06_axi_arready(m06_arready), .m06_axi_rid(m06_rid),
    .m06_axi_rdata(m06_rdata),  .m06_axi_rresp(m06_rresp),
    .m06_axi_rlast(m06_rlast),  .m06_axi_ruser(1'b0),
    .m06_axi_rvalid(m06_rvalid), .m06_axi_rready(m06_rready)
);

// ---------------------------------------------------------------------------
// Slave stub instantiation
// ---------------------------------------------------------------------------
`define INST_STUB(NN, SID) \
axi_slave_stub #(.DATA_WIDTH(TB_DATA_WIDTH),.ADDR_WIDTH(TB_ADDR_WIDTH),\
                 .ID_WIDTH(TB_ID_WIDTH),.SLAVE_ID(SID),.MEM_DEPTH(256)) \
stub_``NN (.clk(clk),.rst(rst),\
   .axi_awid(m``NN``_awid),.axi_awaddr(m``NN``_awaddr),\
   .axi_awlen(m``NN``_awlen),.axi_awsize(m``NN``_awsize),\
   .axi_awburst(m``NN``_awburst),.axi_awvalid(m``NN``_awvalid),\
   .axi_awready(m``NN``_awready),\
   .axi_wdata(m``NN``_wdata),.axi_wstrb(m``NN``_wstrb),\
   .axi_wlast(m``NN``_wlast),.axi_wvalid(m``NN``_wvalid),\
   .axi_wready(m``NN``_wready),\
   .axi_bid(m``NN``_bid),.axi_bresp(m``NN``_bresp),\
   .axi_bvalid(m``NN``_bvalid),.axi_bready(m``NN``_bready),\
   .axi_arid(m``NN``_arid),.axi_araddr(m``NN``_araddr),\
   .axi_arlen(m``NN``_arlen),.axi_arsize(m``NN``_arsize),\
   .axi_arburst(m``NN``_arburst),.axi_arvalid(m``NN``_arvalid),\
   .axi_arready(m``NN``_arready),\
   .axi_rid(m``NN``_rid),.axi_rdata(m``NN``_rdata),\
   .axi_rresp(m``NN``_rresp),.axi_rlast(m``NN``_rlast),\
   .axi_rvalid(m``NN``_rvalid),.axi_rready(m``NN``_rready),\
   .wr_txn_count(slave_wr_cnt[SID]),.rd_txn_count(slave_rd_cnt[SID]))

`INST_STUB(00, 0);
`INST_STUB(01, 1);
`INST_STUB(02, 2);
`INST_STUB(03, 3);
`INST_STUB(04, 4);
`INST_STUB(05, 5);
`INST_STUB(06, 6);

// ---------------------------------------------------------------------------
// Check task
// ---------------------------------------------------------------------------
task check;
    input [127:0] test_name;   // fixed-width reg — no 'string' type needed
    input         condition;
    begin
        tests_run = tests_run + 1;
        if (condition) begin
            tests_pass = tests_pass + 1;
            $display("  PASS  [%0t] %0s", $time, test_name);
        end else begin
            tests_fail = tests_fail + 1;
            $display("  FAIL  [%0t] %0s  *** FAILURE ***", $time, test_name);
        end
    end
endtask

// ---------------------------------------------------------------------------
// Idle task — safe default state for s00 / s01
// ---------------------------------------------------------------------------
task idle_s00;
    begin
        s00_awvalid = 0; s00_awid = 0; s00_awaddr = 0;
        s00_awlen   = 0; s00_awsize = 3'b010; s00_awburst = 2'b01;
        s00_awlock  = 0; s00_awcache = 0; s00_awprot = 0; s00_awqos = 0;
        s00_wvalid  = 0; s00_wdata = 0; s00_wstrb = {TB_STRB_WIDTH{1'b1}};
        s00_wlast   = 0; s00_bready = 0;
        s00_arvalid = 0; s00_arid = 0; s00_araddr = 0;
        s00_arlen   = 0; s00_arsize = 3'b010; s00_arburst = 2'b01;
        s00_arlock  = 0; s00_arcache = 0; s00_arprot = 0; s00_arqos = 0;
        s00_rready  = 0;
    end
endtask

task idle_s01;
    begin
        s01_arvalid = 0; s01_arid = 0; s01_araddr = 0;
        s01_arlen   = 0; s01_arsize = 3'b010; s01_arburst = 2'b01;
        s01_arlock  = 0; s01_arcache = 0; s01_arprot = 0; s01_arqos = 0;
        s01_rready  = 0;
    end
endtask

// ---------------------------------------------------------------------------
// AXI write BFM — single beat via s00
// ---------------------------------------------------------------------------
task axi_write;
    input  [TB_ADDR_WIDTH-1:0] addr;
    input  [TB_DATA_WIDTH-1:0] data;
    input  [TB_STRB_WIDTH-1:0] strb;
    input  [TB_ID_WIDTH-1:0]   id;
    output [1:0]               bresp_out;
    output [TB_ID_WIDTH-1:0]   bid_out;
    begin
        @(posedge clk);
        s00_awvalid <= 1'b1; s00_awid    <= id;    s00_awaddr  <= addr;
        s00_awlen   <= 8'h0; s00_awsize  <= 3'b010; s00_awburst <= 2'b01;
        s00_awlock  <= 1'b0; s00_awcache <= 4'h0;  s00_awprot  <= 3'h0;
        s00_awqos   <= 4'h0;
        s00_wvalid  <= 1'b1; s00_wdata   <= data;  s00_wstrb   <= strb;
        s00_wlast   <= 1'b1;
        // wait AW handshake
        while (!s00_awready) @(posedge clk);
        @(posedge clk); s00_awvalid <= 1'b0;
        // wait W handshake
        while (!s00_wready) @(posedge clk);
        @(posedge clk); s00_wvalid <= 1'b0; s00_wlast <= 1'b0;
        // wait B
        s00_bready <= 1'b1;
        while (!s00_bvalid) @(posedge clk);
        bresp_out = s00_bresp;
        bid_out   = s00_bid;
        @(posedge clk); s00_bready <= 1'b0;
    end
endtask

// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// AXI read BFM — single beat via s00
//
// Timing: the slave stub drives rvalid, rdata, rresp, rid with non-blocking
// (<=) assignments in one always_ff.  All four resolve at the END of the
// same rising edge.  When 'while (!rvalid) @(posedge clk)' exits, we are
// at the posedge where rvalid just went high but rdata has not settled yet.
//
// Strategy: keep rready=1 and take ONE more posedge.  At that second edge
// the stub sees (rvalid && rready) → true, so it de-asserts rvalid in the
// NEXT always_ff evaluation (which also updates rdata for the NEXT read if
// any).  We sample rdata/rresp/rid BEFORE that second edge resolves — i.e.
// we sample the wire values that were driven by the FIRST edge's NBA.
// Using @(posedge clk) and then immediate blocking reads gives us the value
// after the first edge's NBA has resolved, which is correct.
// ---------------------------------------------------------------------------
task axi_read;
    input  [TB_ADDR_WIDTH-1:0] addr;
    input  [TB_ID_WIDTH-1:0]   id;
    output [TB_DATA_WIDTH-1:0] rdata_out;
    output [1:0]               rresp_out;
    output [TB_ID_WIDTH-1:0]   rid_out;
    begin
        @(posedge clk);
        s00_arvalid <= 1'b1; s00_arid    <= id;    s00_araddr  <= addr;
        s00_arlen   <= 8'h0; s00_arsize  <= 3'b010; s00_arburst <= 2'b01;
        s00_arlock  <= 1'b0; s00_arcache <= 4'h0;  s00_arprot  <= 3'h0;
        s00_arqos   <= 4'h0;
        while (!s00_arready) @(posedge clk);
        @(posedge clk); s00_arvalid <= 1'b0;
        s00_rready <= 1'b1;
        // Wait for rvalid. At this posedge rdata/rresp are being driven by
        // the stub's always_ff but have not resolved yet (NBA region).
        while (!s00_rvalid) @(posedge clk);
        // Advance one more clock.  NOW the NBA from the previous edge has
        // resolved, so rdata/rresp/rid hold their correct stable values.
        @(posedge clk);
        rdata_out = s00_rdata;
        rresp_out = s00_rresp;
        rid_out   = s00_rid;
        s00_rready <= 1'b0;
        @(posedge clk);  // let rready de-assertion propagate
    end
endtask

// ---------------------------------------------------------------------------
// IFU read BFM — single beat via s01  (same timing as axi_read above)
// ---------------------------------------------------------------------------
task ifu_read;
    input  [TB_ADDR_WIDTH-1:0] addr;
    input  [TB_ID_WIDTH-1:0]   id;
    output [TB_DATA_WIDTH-1:0] rdata_out;
    output [1:0]               rresp_out;
    begin
        @(posedge clk);
        s01_arvalid <= 1'b1; s01_arid    <= id;    s01_araddr  <= addr;
        s01_arlen   <= 8'h0; s01_arsize  <= 3'b010; s01_arburst <= 2'b01;
        s01_arlock  <= 1'b0; s01_arcache <= 4'h0;  s01_arprot  <= 3'h0;
        s01_arqos   <= 4'h0;
        while (!s01_arready) @(posedge clk);
        @(posedge clk); s01_arvalid <= 1'b0;
        s01_rready <= 1'b1;
        while (!s01_rvalid) @(posedge clk);
        @(posedge clk);
        rdata_out = s01_rdata;
        rresp_out = s01_rresp;
        s01_rready <= 1'b0;
        @(posedge clk);
    end
endtask

// ---------------------------------------------------------------------------
// INCR burst write BFM via s00
//
// Timing: stimulus signals (wdata, wstrb, wlast, wvalid) are driven with
// blocking assignments (=) so they take effect immediately in simulation
// time — the slave stub samples them at the SAME posedge without the
// one-cycle NBA lag that non-blocking (<<=) would introduce.
// ---------------------------------------------------------------------------
task axi_write_burst;
    input  [TB_ADDR_WIDTH-1:0] addr;
    input  [7:0]               blen;
    input  [TB_DATA_WIDTH-1:0] base_data;
    input  [TB_STRB_WIDTH-1:0] strb;
    input  [TB_ID_WIDTH-1:0]   id;
    output [1:0]               bresp_out;
    integer b;
    begin
        // Drive AW with non-blocking (registered interface, one clock cycle)
        @(posedge clk);
        s00_awvalid <= 1'b1; s00_awid    <= id;    s00_awaddr  <= addr;
        s00_awlen   <= blen; s00_awsize  <= 3'b010; s00_awburst <= 2'b01;
        s00_awlock  <= 1'b0; s00_awcache <= 4'h0;  s00_awprot  <= 3'h0;
        s00_awqos   <= 4'h0;
        while (!s00_awready) @(posedge clk);
        @(posedge clk); s00_awvalid <= 1'b0;
        // Drive W beats: use blocking = so each beat's data is visible to
        // the DUT/stub at the posedge where wready is asserted.
        for (b = 0; b <= blen; b = b + 1) begin
            @(posedge clk);
            s00_wvalid = 1'b1;
            s00_wdata  = base_data + b;
            s00_wstrb  = strb;
            s00_wlast  = (b == blen);
            // Hold until wready is seen (already at posedge, poll next ones)
            while (!s00_wready) @(posedge clk);
        end
        s00_wvalid = 1'b0; s00_wlast = 1'b0;
        // B channel — non-blocking is fine (just checking bresp)
        s00_bready <= 1'b1;
        while (!s00_bvalid) @(posedge clk);
        @(posedge clk);   // let bresp settle (same NBA consideration)
        bresp_out = s00_bresp;
        s00_bready <= 1'b0;
    end
endtask

// ---------------------------------------------------------------------------
// Wait N clocks
// ---------------------------------------------------------------------------
task wait_clks;
    input integer n;
    integer k;
    begin
        for (k = 0; k < n; k = k + 1) @(posedge clk);
    end
endtask

// ---------------------------------------------------------------------------
// Snapshot slave counters
// ---------------------------------------------------------------------------
task snap_counters;
    integer s;
    begin
        for (s = 0; s < 7; s = s + 1) begin
            wr_before[s] = slave_wr_cnt[s];
            rd_before[s] = slave_rd_cnt[s];
        end
    end
endtask

// ============================================================================
// TEST BODY
// ============================================================================
initial begin
    // --- Initialise region table ---
    rgn_base[0] = M00_BASE; rgn_slave[0] = 0;
    rgn_base[1] = M01_BASE; rgn_slave[1] = 1;
    rgn_base[2] = M02_BASE; rgn_slave[2] = 2;
    rgn_base[3] = M03_BASE; rgn_slave[3] = 3;
    rgn_base[4] = M04_BASE; rgn_slave[4] = 4;
    rgn_base[5] = M05_BASE; rgn_slave[5] = 5;
    rgn_base[6] = M06_BASE; rgn_slave[6] = 6;

    idle_s00();
    idle_s01();

    // ---- RESET ----
    rst = 1'b1;
    wait_clks(10);
    @(posedge clk); rst = 1'b0;
    wait_clks(5);

    $display("===================================================================");
    $display(" tb_axi_interconnect_wrap_2x7  — self-checking testbench");
    $display("===================================================================");

    // ================================================================
    // TEST GROUP 1 — Address decode at base address of each region
    // ================================================================
    $display("\n--- Test Group 1: Address decode at base address ---");
    for (t_i = 0; t_i < 7; t_i = t_i + 1) begin
        t_wdata_val = 32'hA000_0000 | (t_i << 8) | 8'hBB;
        snap_counters();

        axi_write(rgn_base[t_i], t_wdata_val, {TB_STRB_WIDTH{1'b1}},
                  t_i[TB_ID_WIDTH-1:0], t_bresp, t_bid);

        check("T1: write bresp=OKAY",            t_bresp == RESP_OKAY);
        check("T1: write bid matches awid",       t_bid == t_i[TB_ID_WIDTH-1:0]);
        check("T1: write routed to correct slave",
              slave_wr_cnt[rgn_slave[t_i]] == wr_before[rgn_slave[t_i]] + 1);

        for (t_j = 0; t_j < 7; t_j = t_j + 1) begin
            if (t_j != rgn_slave[t_i])
                check("T1: no spurious write to other slave",
                      slave_wr_cnt[t_j] == wr_before[t_j]);
        end

        wait_clks(2);
        snap_counters();

        axi_read(rgn_base[t_i], (t_i | 8'h10), t_rdata, t_rresp, t_rid);
        check("T1: read rresp=OKAY",              t_rresp == RESP_OKAY);
        check("T1: read data matches written",     t_rdata == t_wdata_val);
        check("T1: read routed to correct slave",
              slave_rd_cnt[rgn_slave[t_i]] == rd_before[rgn_slave[t_i]] + 1);

        $display("  [T1.%0d] addr=%08h slave=%0d data=%08h",
                 t_i, rgn_base[t_i], rgn_slave[t_i], t_wdata_val);
        wait_clks(4);
    end

    // ================================================================
    // TEST GROUP 2 — Region boundary addresses
    // ================================================================
    $display("\n--- Test Group 2: Region boundary addresses ---");

    // 2a — InstrMem upper boundary (0x0003_FFFC)
    snap_counters();
    axi_write(32'h0003_FFFC, 32'hBEEF_0001, {TB_STRB_WIDTH{1'b1}}, 8'h20, t_bresp, t_bid);
    check("T2.1 InstrMem upper boundary: OKAY",    t_bresp == RESP_OKAY);
    check("T2.1 InstrMem upper boundary: slave0",  slave_wr_cnt[0] == wr_before[0]+1);
    check("T2.1 InstrMem upper boundary: no slave1", slave_wr_cnt[1] == wr_before[1]);
    wait_clks(2);

    // 2b — DataMem base (0x0004_0000) — must NOT go to InstrMem
    snap_counters();
    axi_write(32'h0004_0000, 32'hBEEF_0002, {TB_STRB_WIDTH{1'b1}}, 8'h21, t_bresp, t_bid);
    check("T2.2 DataMem base: OKAY",               t_bresp == RESP_OKAY);
    check("T2.2 DataMem base: slave1",             slave_wr_cnt[1] == wr_before[1]+1);
    check("T2.2 DataMem base: not slave0",         slave_wr_cnt[0] == wr_before[0]);
    wait_clks(2);

    // 2c — DataMem upper boundary (0x0007_FFFC)
    snap_counters();
    axi_write(32'h0007_FFFC, 32'hBEEF_0003, {TB_STRB_WIDTH{1'b1}}, 8'h22, t_bresp, t_bid);
    check("T2.3 DataMem upper boundary: OKAY",     t_bresp == RESP_OKAY);
    check("T2.3 DataMem upper boundary: slave1",   slave_wr_cnt[1] == wr_before[1]+1);
    wait_clks(2);

    // 2d — UART upper boundary (0x1000_0FFC)
    snap_counters();
    axi_write(32'h1000_0FFC, 32'hBEEF_0004, {TB_STRB_WIDTH{1'b1}}, 8'h23, t_bresp, t_bid);
    check("T2.4 UART upper boundary: OKAY",        t_bresp == RESP_OKAY);
    check("T2.4 UART upper boundary: slave2",      slave_wr_cnt[2] == wr_before[2]+1);
    wait_clks(2);

    // 2e — Timer base (0x1000_1000) — must NOT go to UART
    snap_counters();
    axi_write(32'h1000_1000, 32'hBEEF_0005, {TB_STRB_WIDTH{1'b1}}, 8'h24, t_bresp, t_bid);
    check("T2.5 Timer base: OKAY",                 t_bresp == RESP_OKAY);
    check("T2.5 Timer base: slave3",               slave_wr_cnt[3] == wr_before[3]+1);
    check("T2.5 Timer base: not slave2",           slave_wr_cnt[2] == wr_before[2]);
    wait_clks(2);

    // 2f — RLE upper boundary (0x1001_0FFC)
    snap_counters();
    axi_write(32'h1001_0FFC, 32'hBEEF_0006, {TB_STRB_WIDTH{1'b1}}, 8'h25, t_bresp, t_bid);
    check("T2.6 RLE upper boundary: OKAY",         t_bresp == RESP_OKAY);
    check("T2.6 RLE upper boundary: slave5",       slave_wr_cnt[5] == wr_before[5]+1);
    wait_clks(2);

    // ================================================================
    // TEST GROUP 3 — Unmapped address → DECERR
    // ================================================================
    $display("\n--- Test Group 3: Unmapped address (DECERR) ---");
    // NOTE: Spec §2.2 does not specify the response for unmapped addresses.
    // axi_interconnect.v lines 636-643 return bresp/rresp=2'b11 (DECERR).
    // Test 3 verifies this RTL behaviour, not a spec requirement.

    // 3a — Write to gap address
    snap_counters();
    axi_write(UNMAPPED, 32'hDEAD_BEEF, {TB_STRB_WIDTH{1'b1}}, 8'h30, t_bresp, t_bid);
    check("T3.1 Unmapped write: DECERR",           t_bresp == RESP_DECERR);
    for (t_j = 0; t_j < 7; t_j = t_j + 1)
        check("T3.1 Unmapped write: no slave hit", slave_wr_cnt[t_j] == wr_before[t_j]);
    wait_clks(2);

    // 3b — Read from gap address
    snap_counters();
    axi_read(UNMAPPED, 8'h31, t_rdata, t_rresp, t_rid);
    check("T3.2 Unmapped read: DECERR",            t_rresp == RESP_DECERR);
    for (t_j = 0; t_j < 7; t_j = t_j + 1)
        check("T3.2 Unmapped read: no slave hit",  slave_rd_cnt[t_j] == rd_before[t_j]);
    wait_clks(2);

    // 3c — CRC address (0x1001_2000) — unmapped per [A-2] / OPEN-ITEM-1
    snap_counters();
    axi_write(32'h1001_2000, 32'hCCC0_0001, {TB_STRB_WIDTH{1'b1}}, 8'h32, t_bresp, t_bid);
    check("T3.3 CRC 0x10012000 write: DECERR (OPEN-ITEM-1)", t_bresp == RESP_DECERR);
    wait_clks(2);

    // ================================================================
    // TEST GROUP 4 — Write channel correctness
    // ================================================================
    $display("\n--- Test Group 4: Write channel correctness ---");

    // 4a — partial wstrb: fill word, then overwrite only byte 0
    axi_write(M01_BASE + 32'h10, 32'hFFFF_FFFF, {TB_STRB_WIDTH{1'b1}}, 8'h40, t_bresp, t_bid);
    check("T4.1 pre-fill DataMem+0x10: OKAY",      t_bresp == RESP_OKAY);
    wait_clks(2);

    axi_write(M01_BASE + 32'h10, 32'h0000_00AB, 4'b0001, 8'h41, t_bresp, t_bid);
    check("T4.2 partial wstrb[0] write: OKAY",     t_bresp == RESP_OKAY);
    wait_clks(2);

    axi_read(M01_BASE + 32'h10, 8'h42, t_rdata, t_rresp, t_rid);
    check("T4.3 partial wstrb: byte0=0xAB",        t_rdata[7:0]  == 8'hAB);
    check("T4.4 partial wstrb: bytes1-3 unchanged", t_rdata[31:8] == 24'hFFFFFF);
    wait_clks(2);

    // 4b — BID must equal AWID
    axi_write(M02_BASE, 32'hCAFE_0001, {TB_STRB_WIDTH{1'b1}}, 8'h50, t_bresp, t_bid);
    check("T4.5 bid=awid for UART write",          t_bid == 8'h50);
    wait_clks(2);

    // 4c — two sequential writes to same slave, each completes cleanly
    axi_write(M05_BASE + 32'h00, 32'h1111_0000, {TB_STRB_WIDTH{1'b1}}, 8'h60, t_b1, t_id1);
    axi_write(M05_BASE + 32'h04, 32'h2222_0000, {TB_STRB_WIDTH{1'b1}}, 8'h61, t_b2, t_id2);
    check("T4.6 sequential write 1: OKAY",         t_b1 == RESP_OKAY);
    check("T4.7 sequential write 2: OKAY",         t_b2 == RESP_OKAY);
    wait_clks(4);

    // ================================================================
    // TEST GROUP 5 — Read channel correctness
    // ================================================================
    $display("\n--- Test Group 5: Read channel correctness ---");

    // 5a — write-then-read, RID must match ARID, data must match
    axi_write(M03_BASE + 32'h00, 32'hDEAD_0001, {TB_STRB_WIDTH{1'b1}}, 8'h70, t_bresp, t_bid);
    wait_clks(2);
    axi_read(M03_BASE + 32'h00, 8'h71, t_rdata, t_rresp, t_rid);
    check("T5.1 Timer read: rresp=OKAY",           t_rresp == RESP_OKAY);
    check("T5.2 Timer read: rid matches arid",     t_rid == 8'h71);
    check("T5.3 Timer read: data correct",         t_rdata == 32'hDEAD_0001);
    wait_clks(2);

    // 5b — RLAST=1 for single-beat (len=0) read observed on s00_rlast
    @(posedge clk);
    s00_arvalid <= 1'b1; s00_arid <= 8'h72; s00_araddr <= M04_BASE;
    s00_arlen <= 8'h00; s00_arsize <= 3'b010; s00_arburst <= 2'b01;
    s00_arlock <= 1'b0; s00_arcache <= 4'h0; s00_arprot <= 3'h0; s00_arqos <= 4'h0;
    while (!s00_arready) @(posedge clk);
    @(posedge clk); s00_arvalid <= 1'b0;
    s00_rready <= 1'b1;
    while (!s00_rvalid) @(posedge clk);
    check("T5.4 single-beat read: rlast=1",        s00_rlast == 1'b1);
    @(posedge clk); s00_rready <= 1'b0;
    wait_clks(2);

    // 5c — IFU path (s01) read to InstrMem
    axi_write(M00_BASE, 32'hFEED_FACE, {TB_STRB_WIDTH{1'b1}}, 8'h80, t_bresp, t_bid);
    wait_clks(2);
    ifu_read(M00_BASE, 8'h81, t_idata, t_iresp);
    check("T5.5 IFU read via s01: rresp=OKAY",     t_iresp == RESP_OKAY);
    check("T5.6 IFU read: data matches LSU write",  t_idata == 32'hFEED_FACE);
    wait_clks(2);

    // ================================================================
    // TEST GROUP 6 — Back-to-back transactions, no cross-talk
    // ================================================================
    $display("\n--- Test Group 6: Back-to-back, no cross-talk ---");

    axi_write(M00_BASE + 32'h04, 32'hAAAA_0001, {TB_STRB_WIDTH{1'b1}}, 8'h90, t_bresp, t_bid);
    check("T6.1 Seq write InstrMem: OKAY",         t_bresp == RESP_OKAY);
    axi_write(M01_BASE + 32'h04, 32'hBBBB_0001, {TB_STRB_WIDTH{1'b1}}, 8'h91, t_bresp, t_bid);
    check("T6.2 Seq write DataMem: OKAY",          t_bresp == RESP_OKAY);
    axi_write(M05_BASE + 32'h04, 32'hCCCC_0001, {TB_STRB_WIDTH{1'b1}}, 8'h92, t_bresp, t_bid);
    check("T6.3 Seq write RLE: OKAY",              t_bresp == RESP_OKAY);

    axi_read(M00_BASE + 32'h04, 8'h93, t_rd0, t_rresp, t_rid);
    check("T6.4 Seq read InstrMem: correct",       t_rd0 == 32'hAAAA_0001);
    axi_read(M01_BASE + 32'h04, 8'h94, t_rd1, t_rresp, t_rid);
    check("T6.5 Seq read DataMem: correct",        t_rd1 == 32'hBBBB_0001);
    axi_read(M05_BASE + 32'h04, 8'h95, t_rd2, t_rresp, t_rid);
    check("T6.6 Seq read RLE: correct",            t_rd2 == 32'hCCCC_0001);
    check("T6.7 No cross-talk: InstrMem != DataMem", t_rd0 != t_rd1);
    wait_clks(4);

    // ================================================================
    // TEST GROUP 7 — INCR burst (4 beats)
    // ================================================================
    $display("\n--- Test Group 7: INCR burst ---");

    axi_write_burst(M01_BASE + 32'h20, 8'h03,
                    32'h5500_0000, {TB_STRB_WIDTH{1'b1}}, 8'hA0, t_bresp);
    check("T7.1 4-beat burst write: OKAY",         t_bresp == RESP_OKAY);
    wait_clks(2);

    for (t_b = 0; t_b < 4; t_b = t_b + 1) begin
        axi_read(M01_BASE + 32'h20 + (4*t_b), 8'hA1 + t_b[TB_ID_WIDTH-1:0],
                 t_rdata, t_rresp, t_rid);
        check("T7.2 burst readback beat: correct",
              t_rdata == (32'h5500_0000 + t_b));
    end
    wait_clks(2);

    // ================================================================
    // TEST GROUP 8 — Reset behavior
    // ================================================================
    $display("\n--- Test Group 8: Reset behavior ---");

    // Assert AW, then inject reset before W completes
    @(posedge clk);
    s00_awvalid <= 1'b1; s00_awaddr <= M05_BASE; s00_awid <= 8'hB0;
    s00_awlen   <= 8'h0; s00_awsize <= 3'b010;   s00_awburst <= 2'b01;
    wait_clks(2);
    rst <= 1'b1;
    wait_clks(5);
    rst <= 1'b0;
    s00_awvalid <= 1'b0;
    idle_s00();
    wait_clks(5);

    check("T8.1 After reset: s00_bvalid=0",        s00_bvalid == 1'b0);
    check("T8.2 After reset: s00_rvalid=0",        s00_rvalid == 1'b0);

    axi_write(M06_BASE, 32'hB0B0_0001, {TB_STRB_WIDTH{1'b1}}, 8'hB1, t_bresp, t_bid);
    check("T8.3 Post-reset write to DMA: OKAY",    t_bresp == RESP_OKAY);
    wait_clks(4);

    // ================================================================
    // SUMMARY
    // ================================================================
    $display("\n===================================================================");
    $display(" RESULTS: %0d tests run,  %0d PASS,  %0d FAIL",
             tests_run, tests_pass, tests_fail);
    $display("===================================================================");
    if (tests_fail == 0)
        $display(" ALL TESTS PASSED");
    else
        $display(" *** %0d TEST(S) FAILED — see FAIL lines above ***", tests_fail);

    $finish;
end

// ---------------------------------------------------------------------------
// FSDB waveform dump
// Requires:  -P <novas.tab> <pli.a>  on the vcs compile line (see Makefile).
// ---------------------------------------------------------------------------
initial begin
    $fsdbDumpfile("dump.fsdb");
    $fsdbDumpvars(0, tb_axi_interconnect_wrap_2x7, "+all");
    $fsdbDumpSVA(0, tb_axi_interconnect_wrap_2x7);
    $fsdbDumpMDA(0, tb_axi_interconnect_wrap_2x7);
end

// ---------------------------------------------------------------------------
// Timeout watchdog
// ---------------------------------------------------------------------------
initial begin
    #200_000;
    $display("FATAL: simulation timeout after 200 us");
    $finish(1);
end

endmodule

`default_nettype wire
