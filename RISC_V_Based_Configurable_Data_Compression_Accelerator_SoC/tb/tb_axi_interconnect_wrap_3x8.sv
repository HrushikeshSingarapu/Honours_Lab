`timescale 1ns / 1ps
`default_nettype none

module tb_axi_interconnect_wrap_3x8;

    localparam DATA_WIDTH = 32;
    localparam ADDR_WIDTH = 32;
    localparam STRB_WIDTH = DATA_WIDTH/8;
    localparam ID_WIDTH = 8;

    localparam FORWARD_ID = 0;
    localparam M_REGIONS = 1;

    /*
     * Address map
     */
    localparam [31:0] M00_BASE = 32'h0000_0000; // InstrMem
    localparam [31:0] M01_BASE = 32'h0004_0000; // DataMem
    localparam [31:0] M02_BASE = 32'h1000_0000; // UART
    localparam [31:0] M03_BASE = 32'h1000_1000; // Timer
    localparam [31:0] M04_BASE = 32'h1000_2000; // GPIO
    localparam [31:0] M05_BASE = 32'h1001_0000; // RLE
    localparam [31:0] M06_BASE = 32'h1001_1000; // DMA
    localparam [31:0] M07_BASE = 32'h1001_2000; // CRC

    localparam [31:0] UNMAPPED_ADDR = 32'hDEAD_0000;

    localparam integer M00_ABITS = 18;
    localparam integer M01_ABITS = 18;
    localparam integer M02_ABITS = 12;
    localparam integer M03_ABITS = 12;
    localparam integer M04_ABITS = 12;
    localparam integer M05_ABITS = 12;
    localparam integer M06_ABITS = 12;
    localparam integer M07_ABITS = 12;

    localparam [1:0] RESP_OKAY   = 2'b00;
    localparam [1:0] RESP_EXOKAY = 2'b01;
    localparam [1:0] RESP_SLVERR = 2'b10;
    localparam [1:0] RESP_DECERR = 2'b11;

    reg clk;
    reg rst;

    integer errors;
    integer tests;

    /*
     * ================================================================
     * S00 : LSU
     * ================================================================
     */
    reg [ID_WIDTH-1:0]   s00_axi_awid;
    reg [ADDR_WIDTH-1:0] s00_axi_awaddr;
    reg [7:0]            s00_axi_awlen;
    reg [2:0]            s00_axi_awsize;
    reg [1:0]            s00_axi_awburst;
    reg                  s00_axi_awlock;
    reg [3:0]            s00_axi_awcache;
    reg [2:0]            s00_axi_awprot;
    reg [3:0]            s00_axi_awqos;
    reg                  s00_axi_awuser;
    reg                  s00_axi_awvalid;
    wire                 s00_axi_awready;

    reg [DATA_WIDTH-1:0] s00_axi_wdata;
    reg [STRB_WIDTH-1:0] s00_axi_wstrb;
    reg                  s00_axi_wlast;
    reg                  s00_axi_wuser;
    reg                  s00_axi_wvalid;
    wire                 s00_axi_wready;

    wire [ID_WIDTH-1:0]   s00_axi_bid;
    wire [1:0]            s00_axi_bresp;
    wire                  s00_axi_buser;
    wire                  s00_axi_bvalid;
    reg                   s00_axi_bready;

    reg [ID_WIDTH-1:0]   s00_axi_arid;
    reg [ADDR_WIDTH-1:0] s00_axi_araddr;
    reg [7:0]            s00_axi_arlen;
    reg [2:0]            s00_axi_arsize;
    reg [1:0]            s00_axi_arburst;
    reg                  s00_axi_arlock;
    reg [3:0]            s00_axi_arcache;
    reg [2:0]            s00_axi_arprot;
    reg [3:0]            s00_axi_arqos;
    reg                  s00_axi_aruser;
    reg                  s00_axi_arvalid;
    wire                 s00_axi_arready;

    wire [ID_WIDTH-1:0]   s00_axi_rid;
    wire [DATA_WIDTH-1:0] s00_axi_rdata;
    wire [1:0]            s00_axi_rresp;
    wire                  s00_axi_rlast;
    wire                  s00_axi_ruser;
    wire                  s00_axi_rvalid;
    reg                   s00_axi_rready;


    /*
     * ================================================================
     * S01 : IFU
     * ================================================================
     */
    reg [ID_WIDTH-1:0]   s01_axi_awid;
    reg [ADDR_WIDTH-1:0] s01_axi_awaddr;
    reg [7:0]            s01_axi_awlen;
    reg [2:0]            s01_axi_awsize;
    reg [1:0]            s01_axi_awburst;
    reg                  s01_axi_awlock;
    reg [3:0]            s01_axi_awcache;
    reg [2:0]            s01_axi_awprot;
    reg [3:0]            s01_axi_awqos;
    reg                  s01_axi_awuser;
    reg                  s01_axi_awvalid;
    wire                 s01_axi_awready;

    reg [DATA_WIDTH-1:0] s01_axi_wdata;
    reg [STRB_WIDTH-1:0] s01_axi_wstrb;
    reg                  s01_axi_wlast;
    reg                  s01_axi_wuser;
    reg                  s01_axi_wvalid;
    wire                 s01_axi_wready;

    wire [ID_WIDTH-1:0]   s01_axi_bid;
    wire [1:0]            s01_axi_bresp;
    wire                  s01_axi_buser;
    wire                  s01_axi_bvalid;
    reg                   s01_axi_bready;

    reg [ID_WIDTH-1:0]   s01_axi_arid;
    reg [ADDR_WIDTH-1:0] s01_axi_araddr;
    reg [7:0]            s01_axi_arlen;
    reg [2:0]            s01_axi_arsize;
    reg [1:0]            s01_axi_arburst;
    reg                  s01_axi_arlock;
    reg [3:0]            s01_axi_arcache;
    reg [2:0]            s01_axi_arprot;
    reg [3:0]            s01_axi_arqos;
    reg                  s01_axi_aruser;
    reg                  s01_axi_arvalid;
    wire                 s01_axi_arready;

    wire [ID_WIDTH-1:0]   s01_axi_rid;
    wire [DATA_WIDTH-1:0] s01_axi_rdata;
    wire [1:0]            s01_axi_rresp;
    wire                  s01_axi_rlast;
    wire                  s01_axi_ruser;
    wire                  s01_axi_rvalid;
    reg                   s01_axi_rready;


    /*
     * ================================================================
     * S02 : SB / DEBUG
     * ================================================================
     */
    reg [ID_WIDTH-1:0]   s02_axi_awid;
    reg [ADDR_WIDTH-1:0] s02_axi_awaddr;
    reg [7:0]            s02_axi_awlen;
    reg [2:0]            s02_axi_awsize;
    reg [1:0]            s02_axi_awburst;
    reg                  s02_axi_awlock;
    reg [3:0]            s02_axi_awcache;
    reg [2:0]            s02_axi_awprot;
    reg [3:0]            s02_axi_awqos;
    reg                  s02_axi_awuser;
    reg                  s02_axi_awvalid;
    wire                 s02_axi_awready;

    reg [DATA_WIDTH-1:0] s02_axi_wdata;
    reg [STRB_WIDTH-1:0] s02_axi_wstrb;
    reg                  s02_axi_wlast;
    reg                  s02_axi_wuser;
    reg                  s02_axi_wvalid;
    wire                 s02_axi_wready;

    wire [ID_WIDTH-1:0]   s02_axi_bid;
    wire [1:0]            s02_axi_bresp;
    wire                  s02_axi_buser;
    wire                  s02_axi_bvalid;
    reg                   s02_axi_bready;

    reg [ID_WIDTH-1:0]   s02_axi_arid;
    reg [ADDR_WIDTH-1:0] s02_axi_araddr;
    reg [7:0]            s02_axi_arlen;
    reg [2:0]            s02_axi_arsize;
    reg [1:0]            s02_axi_arburst;
    reg                  s02_axi_arlock;
    reg [3:0]            s02_axi_arcache;
    reg [2:0]            s02_axi_arprot;
    reg [3:0]            s02_axi_arqos;
    reg                  s02_axi_aruser;
    reg                  s02_axi_arvalid;
    wire                 s02_axi_arready;

    wire [ID_WIDTH-1:0]   s02_axi_rid;
    wire [DATA_WIDTH-1:0] s02_axi_rdata;
    wire [1:0]            s02_axi_rresp;
    wire                  s02_axi_rlast;
    wire                  s02_axi_ruser;
    wire                  s02_axi_rvalid;
    reg                   s02_axi_rready;


    /*
     * ================================================================
     * Master ports
     * ================================================================
     */

`define DECL_MPORT(NN) \
    wire [ID_WIDTH-1:0]   m``NN``_axi_awid; \
    wire [ADDR_WIDTH-1:0] m``NN``_axi_awaddr; \
    wire [7:0]            m``NN``_axi_awlen; \
    wire [2:0]            m``NN``_axi_awsize; \
    wire [1:0]            m``NN``_axi_awburst; \
    wire                  m``NN``_axi_awlock; \
    wire [3:0]            m``NN``_axi_awcache; \
    wire [2:0]            m``NN``_axi_awprot; \
    wire [3:0]            m``NN``_axi_awqos; \
    wire [3:0]            m``NN``_axi_awregion; \
    wire                  m``NN``_axi_awuser; \
    wire                  m``NN``_axi_awvalid; \
    reg                   m``NN``_axi_awready; \
    wire [DATA_WIDTH-1:0] m``NN``_axi_wdata; \
    wire [STRB_WIDTH-1:0] m``NN``_axi_wstrb; \
    wire                  m``NN``_axi_wlast; \
    wire                  m``NN``_axi_wuser; \
    wire                  m``NN``_axi_wvalid; \
    reg                   m``NN``_axi_wready; \
    reg [ID_WIDTH-1:0]    m``NN``_axi_bid; \
    reg [1:0]             m``NN``_axi_bresp; \
    reg                   m``NN``_axi_buser; \
    reg                   m``NN``_axi_bvalid; \
    wire                  m``NN``_axi_bready; \
    wire [ID_WIDTH-1:0]   m``NN``_axi_arid; \
    wire [ADDR_WIDTH-1:0] m``NN``_axi_araddr; \
    wire [7:0]            m``NN``_axi_arlen; \
    wire [2:0]            m``NN``_axi_arsize; \
    wire [1:0]            m``NN``_axi_arburst; \
    wire                  m``NN``_axi_arlock; \
    wire [3:0]            m``NN``_axi_arcache; \
    wire [2:0]            m``NN``_axi_arprot; \
    wire [3:0]            m``NN``_axi_arqos; \
    wire [3:0]            m``NN``_axi_arregion; \
    wire                  m``NN``_axi_aruser; \
    wire                  m``NN``_axi_arvalid; \
    reg                   m``NN``_axi_arready; \
    reg [ID_WIDTH-1:0]    m``NN``_axi_rid; \
    reg [DATA_WIDTH-1:0]  m``NN``_axi_rdata; \
    reg [1:0]             m``NN``_axi_rresp; \
    reg                   m``NN``_axi_rlast; \
    reg                   m``NN``_axi_ruser; \
    reg                   m``NN``_axi_rvalid; \
    wire                  m``NN``_axi_rready;

    `DECL_MPORT(00)
    `DECL_MPORT(01)
    `DECL_MPORT(02)
    `DECL_MPORT(03)
    `DECL_MPORT(04)
    `DECL_MPORT(05)
    `DECL_MPORT(06)
    `DECL_MPORT(07)


    /*
     * ================================================================
     * Slave memory/counter stubs
     * ================================================================
     */

    reg [31:0] write_count [0:7];
    reg [31:0] read_count  [0:7];

    /*
     * A simple AXI slave stub is assumed to be available exactly
     * like the one used by the 2x7 testbench.
     */

`define INST_STUB(NN,SID) \
    axi_slave_stub #(.DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH), .ID_WIDTH(ID_WIDTH)) \
    stub_``NN`` ( \
        .clk(clk), .rst(rst), \
        .s_axi_awid(m``NN``_axi_awid), \
        .s_axi_awaddr(m``NN``_axi_awaddr), \
        .s_axi_awlen(m``NN``_axi_awlen), \
        .s_axi_awsize(m``NN``_axi_awsize), \
        .s_axi_awburst(m``NN``_axi_awburst), \
        .s_axi_awlock(m``NN``_axi_awlock), \
        .s_axi_awcache(m``NN``_axi_awcache), \
        .s_axi_awprot(m``NN``_axi_awprot), \
        .s_axi_awqos(m``NN``_axi_awqos), \
        .s_axi_awregion(m``NN``_axi_awregion), \
        .s_axi_awvalid(m``NN``_axi_awvalid), \
        .s_axi_awready(m``NN``_axi_awready), \
        .s_axi_wdata(m``NN``_axi_wdata), \
        .s_axi_wstrb(m``NN``_axi_wstrb), \
        .s_axi_wlast(m``NN``_axi_wlast), \
        .s_axi_wvalid(m``NN``_axi_wvalid), \
        .s_axi_wready(m``NN``_axi_wready), \
        .s_axi_bid(m``NN``_axi_bid), \
        .s_axi_bresp(m``NN``_axi_bresp), \
        .s_axi_bvalid(m``NN``_axi_bvalid), \
        .s_axi_bready(m``NN``_axi_bready), \
        .s_axi_arid(m``NN``_axi_arid), \
        .s_axi_araddr(m``NN``_axi_araddr), \
        .s_axi_arlen(m``NN``_axi_arlen), \
        .s_axi_arsize(m``NN``_axi_arsize), \
        .s_axi_arburst(m``NN``_axi_arburst), \
        .s_axi_arlock(m``NN``_axi_arlock), \
        .s_axi_arcache(m``NN``_axi_arcache), \
        .s_axi_arprot(m``NN``_axi_arprot), \
        .s_axi_arqos(m``NN``_axi_arqos), \
        .s_axi_arregion(m``NN``_axi_arregion), \
        .s_axi_arvalid(m``NN``_axi_arvalid), \
        .s_axi_arready(m``NN``_axi_arready), \
        .s_axi_rid(m``NN``_axi_rid), \
        .s_axi_rdata(m``NN``_axi_rdata), \
        .s_axi_rresp(m``NN``_axi_rresp), \
        .s_axi_rlast(m``NN``_axi_rlast), \
        .s_axi_rvalid(m``NN``_axi_rvalid), \
        .s_axi_rready(m``NN``_axi_rready), \
        .write_count(write_count[SID]), \
        .read_count(read_count[SID]) \
    );

    `INST_STUB(00,0)
    `INST_STUB(01,1)
    `INST_STUB(02,2)
    `INST_STUB(03,3)
    `INST_STUB(04,4)
    `INST_STUB(05,5)
    `INST_STUB(06,6)
    `INST_STUB(07,7)


    /*
     * ================================================================
     * DUT
     * ================================================================
     */

    axi_interconnect_wrap_3x8 #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .STRB_WIDTH(STRB_WIDTH),
        .ID_WIDTH(ID_WIDTH),
        .FORWARD_ID(FORWARD_ID),
        .M_REGIONS(M_REGIONS),

        .M00_BASE_ADDR(M00_BASE),
        .M00_ADDR_WIDTH(M00_ABITS),
        .M00_CONNECT_READ(3'b111),
        .M00_CONNECT_WRITE(3'b101),

        .M01_BASE_ADDR(M01_BASE),
        .M01_ADDR_WIDTH(M01_ABITS),
        .M01_CONNECT_READ(3'b111),
        .M01_CONNECT_WRITE(3'b101),

        .M02_BASE_ADDR(M02_BASE),
        .M02_ADDR_WIDTH(M02_ABITS),
        .M02_CONNECT_READ(3'b111),
        .M02_CONNECT_WRITE(3'b101),

        .M03_BASE_ADDR(M03_BASE),
        .M03_ADDR_WIDTH(M03_ABITS),
        .M03_CONNECT_READ(3'b111),
        .M03_CONNECT_WRITE(3'b101),

        .M04_BASE_ADDR(M04_BASE),
        .M04_ADDR_WIDTH(M04_ABITS),
        .M04_CONNECT_READ(3'b111),
        .M04_CONNECT_WRITE(3'b101),

        .M05_BASE_ADDR(M05_BASE),
        .M05_ADDR_WIDTH(M05_ABITS),
        .M05_CONNECT_READ(3'b111),
        .M05_CONNECT_WRITE(3'b101),

        .M06_BASE_ADDR(M06_BASE),
        .M06_ADDR_WIDTH(M06_ABITS),
        .M06_CONNECT_READ(3'b111),
        .M06_CONNECT_WRITE(3'b101),

        .M07_BASE_ADDR(M07_BASE),
        .M07_ADDR_WIDTH(M07_ABITS),
        .M07_CONNECT_READ(3'b111),
        .M07_CONNECT_WRITE(3'b101)
    )
    dut (
        .clk(clk),
        .rst(rst),

        /*
         * S00 LSU
         */
        .s00_axi_awid(s00_axi_awid),
        .s00_axi_awaddr(s00_axi_awaddr),
        .s00_axi_awlen(s00_axi_awlen),
        .s00_axi_awsize(s00_axi_awsize),
        .s00_axi_awburst(s00_axi_awburst),
        .s00_axi_awlock(s00_axi_awlock),
        .s00_axi_awcache(s00_axi_awcache),
        .s00_axi_awprot(s00_axi_awprot),
        .s00_axi_awqos(s00_axi_awqos),
        .s00_axi_awuser(s00_axi_awuser),
        .s00_axi_awvalid(s00_axi_awvalid),
        .s00_axi_awready(s00_axi_awready),
        .s00_axi_wdata(s00_axi_wdata),
        .s00_axi_wstrb(s00_axi_wstrb),
        .s00_axi_wlast(s00_axi_wlast),
        .s00_axi_wuser(s00_axi_wuser),
        .s00_axi_wvalid(s00_axi_wvalid),
        .s00_axi_wready(s00_axi_wready),
        .s00_axi_bid(s00_axi_bid),
        .s00_axi_bresp(s00_axi_bresp),
        .s00_axi_buser(s00_axi_buser),
        .s00_axi_bvalid(s00_axi_bvalid),
        .s00_axi_bready(s00_axi_bready),
        .s00_axi_arid(s00_axi_arid),
        .s00_axi_araddr(s00_axi_araddr),
        .s00_axi_arlen(s00_axi_arlen),
        .s00_axi_arsize(s00_axi_arsize),
        .s00_axi_arburst(s00_axi_arburst),
        .s00_axi_arlock(s00_axi_arlock),
        .s00_axi_arcache(s00_axi_arcache),
        .s00_axi_arprot(s00_axi_arprot),
        .s00_axi_arqos(s00_axi_arqos),
        .s00_axi_aruser(s00_axi_aruser),
        .s00_axi_arvalid(s00_axi_arvalid),
        .s00_axi_arready(s00_axi_arready),
        .s00_axi_rid(s00_axi_rid),
        .s00_axi_rdata(s00_axi_rdata),
        .s00_axi_rresp(s00_axi_rresp),
        .s00_axi_rlast(s00_axi_rlast),
        .s00_axi_ruser(s00_axi_ruser),
        .s00_axi_rvalid(s00_axi_rvalid),
        .s00_axi_rready(s00_axi_rready),

        /*
         * S01 IFU
         */
        .s01_axi_awid(0),
        .s01_axi_awaddr(0),
        .s01_axi_awlen(0),
        .s01_axi_awsize(0),
        .s01_axi_awburst(0),
        .s01_axi_awlock(0),
        .s01_axi_awcache(0),
        .s01_axi_awprot(0),
        .s01_axi_awqos(0),
        .s01_axi_awuser(0),
        .s01_axi_awvalid(0),
        .s01_axi_wdata(0),
        .s01_axi_wstrb(0),
        .s01_axi_wlast(0),
        .s01_axi_wuser(0),
        .s01_axi_wvalid(0),
        .s01_axi_bready(s01_axi_bready),
        .s01_axi_arid(s01_axi_arid),
        .s01_axi_araddr(s01_axi_araddr),
        .s01_axi_arlen(s01_axi_arlen),
        .s01_axi_arsize(s01_axi_arsize),
        .s01_axi_arburst(s01_axi_arburst),
        .s01_axi_arlock(s01_axi_arlock),
        .s01_axi_arcache(s01_axi_arcache),
        .s01_axi_arprot(s01_axi_arprot),
        .s01_axi_arqos(s01_axi_arqos),
        .s01_axi_aruser(s01_axi_aruser),
        .s01_axi_arvalid(s01_axi_arvalid),
        .s01_axi_arready(s01_axi_arready),
        .s01_axi_rid(s01_axi_rid),
        .s01_axi_rdata(s01_axi_rdata),
        .s01_axi_rresp(s01_axi_rresp),
        .s01_axi_rlast(s01_axi_rlast),
        .s01_axi_ruser(s01_axi_ruser),
        .s01_axi_rvalid(s01_axi_rvalid),
        .s01_axi_rready(s01_axi_rready),

        /*
         * S02 SB / DEBUG
         */
        .s02_axi_awid(s02_axi_awid),
        .s02_axi_awaddr(s02_axi_awaddr),
        .s02_axi_awlen(s02_axi_awlen),
        .s02_axi_awsize(s02_axi_awsize),
        .s02_axi_awburst(s02_axi_awburst),
        .s02_axi_awlock(s02_axi_awlock),
        .s02_axi_awcache(s02_axi_awcache),
        .s02_axi_awprot(s02_axi_awprot),
        .s02_axi_awqos(s02_axi_awqos),
        .s02_axi_awuser(s02_axi_awuser),
        .s02_axi_awvalid(s02_axi_awvalid),
        .s02_axi_awready(s02_axi_awready),
        .s02_axi_wdata(s02_axi_wdata),
        .s02_axi_wstrb(s02_axi_wstrb),
        .s02_axi_wlast(s02_axi_wlast),
        .s02_axi_wuser(s02_axi_wuser),
        .s02_axi_wvalid(s02_axi_wvalid),
        .s02_axi_wready(s02_axi_wready),
        .s02_axi_bid(s02_axi_bid),
        .s02_axi_bresp(s02_axi_bresp),
        .s02_axi_buser(s02_axi_buser),
        .s02_axi_bvalid(s02_axi_bvalid),
        .s02_axi_bready(s02_axi_bready),
        .s02_axi_arid(s02_axi_arid),
        .s02_axi_araddr(s02_axi_araddr),
        .s02_axi_arlen(s02_axi_arlen),
        .s02_axi_arsize(s02_axi_arsize),
        .s02_axi_arburst(s02_axi_arburst),
        .s02_axi_arlock(s02_axi_arlock),
        .s02_axi_arcache(s02_axi_arcache),
        .s02_axi_arprot(s02_axi_arprot),
        .s02_axi_arqos(s02_axi_arqos),
        .s02_axi_aruser(s02_axi_aruser),
        .s02_axi_arvalid(s02_axi_arvalid),
        .s02_axi_arready(s02_axi_arready),
        .s02_axi_rid(s02_axi_rid),
        .s02_axi_rdata(s02_axi_rdata),
        .s02_axi_rresp(s02_axi_rresp),
        .s02_axi_rlast(s02_axi_rlast),
        .s02_axi_ruser(s02_axi_ruser),
        .s02_axi_rvalid(s02_axi_rvalid),
        .s02_axi_rready(s02_axi_rready)

        // M00-M07 connections continue exactly according
        // to the wrapper port list.
    );


    /*
     * ================================================================
     * Clock
     * ================================================================
     */

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end


    /*
     * ================================================================
     * Reset
     * ================================================================
     */

    initial begin
        rst = 1'b1;

        #100;

        @(posedge clk);
        rst <= 1'b0;
    end


    /*
     * ================================================================
     * Initial values
     * ================================================================
     */

    initial begin
        errors = 0;
        tests  = 0;

        s00_axi_awid    = 0;
        s00_axi_awaddr  = 0;
        s00_axi_awlen   = 0;
        s00_axi_awsize  = 3'd2;
        s00_axi_awburst = 2'b01;
        s00_axi_awlock  = 0;
        s00_axi_awcache = 0;
        s00_axi_awprot  = 0;
        s00_axi_awqos   = 0;
        s00_axi_awuser  = 0;
        s00_axi_awvalid = 0;
        s00_axi_wdata   = 0;
        s00_axi_wstrb   = 4'hF;
        s00_axi_wlast   = 1;
        s00_axi_wuser   = 0;
        s00_axi_wvalid  = 0;
        s00_axi_bready  = 0;
        s00_axi_arid    = 0;
        s00_axi_araddr  = 0;
        s00_axi_arlen   = 0;
        s00_axi_arsize  = 3'd2;
        s00_axi_arburst = 2'b01;
        s00_axi_arlock  = 0;
        s00_axi_arcache = 0;
        s00_axi_arprot  = 0;
        s00_axi_arqos   = 0;
        s00_axi_aruser  = 0;
        s00_axi_arvalid = 0;
        s00_axi_rready  = 0;

        s01_axi_awvalid = 0;
        s01_axi_wvalid  = 0;
        s01_axi_bready  = 0;
        s01_axi_arvalid = 0;
        s01_axi_rready  = 0;

        s02_axi_awid    = 0;
        s02_axi_awaddr  = 0;
        s02_axi_awlen   = 0;
        s02_axi_awsize  = 3'd2;
        s02_axi_awburst = 2'b01;
        s02_axi_awlock  = 0;
        s02_axi_awcache = 0;
        s02_axi_awprot  = 0;
        s02_axi_awqos   = 0;
        s02_axi_awuser  = 0;
        s02_axi_awvalid = 0;
        s02_axi_wdata   = 0;
        s02_axi_wstrb   = 4'hF;
        s02_axi_wlast   = 1;
        s02_axi_wuser   = 0;
        s02_axi_wvalid  = 0;
        s02_axi_bready  = 0;
        s02_axi_arid    = 0;
        s02_axi_araddr  = 0;
        s02_axi_arlen   = 0;
        s02_axi_arsize  = 3'd2;
        s02_axi_arburst = 2'b01;
        s02_axi_arlock  = 0;
        s02_axi_arcache = 0;
        s02_axi_arprot  = 0;
        s02_axi_arqos   = 0;
        s02_axi_aruser  = 0;
        s02_axi_arvalid = 0;
        s02_axi_rready  = 0;
    end


    /*
     * ================================================================
     * Simple checks
     * ================================================================
     */

    task check;
        input condition;
        input [1023:0] message;
        begin
            tests = tests + 1;

            if (!condition) begin
                errors = errors + 1;
                $display("FAIL: %s", message);
            end
            else begin
                $display("PASS: %s", message);
            end
        end
    endtask


    task wait_clks;
        input integer n;
        integer k;
        begin
            for (k = 0; k < n; k = k + 1)
                @(posedge clk);
        end
    endtask


    /*
     * ================================================================
     * S00/S01/S02 idle
     * ================================================================
     */

    task idle_s00;
        begin
            s00_axi_awvalid = 0;
            s00_axi_wvalid  = 0;
            s00_axi_bready  = 0;
            s00_axi_arvalid = 0;
            s00_axi_rready  = 0;
        end
    endtask

    task idle_s01;
        begin
            s01_axi_awvalid = 0;
            s01_axi_wvalid  = 0;
            s01_axi_bready  = 0;
            s01_axi_arvalid = 0;
            s01_axi_rready  = 0;
        end
    endtask

    task idle_s02;
        begin
            s02_axi_awvalid = 0;
            s02_axi_wvalid  = 0;
            s02_axi_bready  = 0;
            s02_axi_arvalid = 0;
            s02_axi_rready  = 0;
        end
    endtask


    /*
     * ================================================================
     * AXI WRITE - S00
     * ================================================================
     */

    task axi_write;
        input [31:0] addr;
        input [31:0] data;
        input [7:0]  id;
        input [3:0]  strb;
        output [1:0] resp;

        begin
            s00_axi_awid    = id;
            s00_axi_awaddr  = addr;
            s00_axi_awlen   = 0;
            s00_axi_awsize  = 3'd2;
            s00_axi_awburst = 2'b01;
            s00_axi_awvalid = 1;

            s00_axi_wdata   = data;
            s00_axi_wstrb   = strb;
            s00_axi_wlast   = 1;
            s00_axi_wvalid  = 1;

            s00_axi_bready  = 1;

            while (!s00_axi_awready)
                @(posedge clk);

            @(posedge clk);
            s00_axi_awvalid = 0;

            while (!s00_axi_wready)
                @(posedge clk);

            @(posedge clk);
            s00_axi_wvalid = 0;

            while (!s00_axi_bvalid)
                @(posedge clk);

            resp = s00_axi_bresp;

            @(posedge clk);
            s00_axi_bready = 0;

            idle_s00();
        end
    endtask


    /*
     * ================================================================
     * AXI READ - S00
     * ================================================================
     */

    task axi_read;
        input [31:0] addr;
        input [7:0]  id;
        output [31:0] data;
        output [1:0]  resp;

        begin
            s00_axi_arid    = id;
            s00_axi_araddr  = addr;
            s00_axi_arlen   = 0;
            s00_axi_arsize  = 3'd2;
            s00_axi_arburst = 2'b01;
            s00_axi_arvalid = 1;
            s00_axi_rready  = 1;

            while (!s00_axi_arready)
                @(posedge clk);

            @(posedge clk);
            s00_axi_arvalid = 0;

            while (!s00_axi_rvalid)
                @(posedge clk);

            data = s00_axi_rdata;
            resp = s00_axi_rresp;

            @(posedge clk);
            s00_axi_rready = 0;

            idle_s00();
        end
    endtask


    /*
     * ================================================================
     * IFU READ - S01
     * ================================================================
     */

    task ifu_read;
        input [31:0] addr;
        input [7:0]  id;
        output [31:0] data;
        output [1:0]  resp;

        begin
            s01_axi_arid    = id;
            s01_axi_araddr  = addr;
            s01_axi_arlen   = 0;
            s01_axi_arsize  = 3'd2;
            s01_axi_arburst = 2'b01;
            s01_axi_arvalid = 1;
            s01_axi_rready  = 1;

            while (!s01_axi_arready)
                @(posedge clk);

            @(posedge clk);
            s01_axi_arvalid = 0;

            while (!s01_axi_rvalid)
                @(posedge clk);

            data = s01_axi_rdata;
            resp = s01_axi_rresp;

            @(posedge clk);
            s01_axi_rready = 0;

            idle_s01();
        end
    endtask


    /*
     * ================================================================
     * SB / DEBUG READ - S02
     * ================================================================
     */

    task sb_read;
        input [31:0] addr;
        input [7:0]  id;
        output [31:0] data;
        output [1:0]  resp;

        begin
            s02_axi_arid    = id;
            s02_axi_araddr  = addr;
            s02_axi_arlen   = 0;
            s02_axi_arsize  = 3'd2;
            s02_axi_arburst = 2'b01;
            s02_axi_arvalid = 1;
            s02_axi_rready  = 1;

            while (!s02_axi_arready)
                @(posedge clk);

            @(posedge clk);
            s02_axi_arvalid = 0;

            while (!s02_axi_rvalid)
                @(posedge clk);

            data = s02_axi_rdata;
            resp = s02_axi_rresp;

            @(posedge clk);
            s02_axi_rready = 0;

            idle_s02();
        end
    endtask


    /*
     * ================================================================
     * Main test sequence
     * ================================================================
     */

    reg [31:0] rdata;
    reg [1:0]  rresp;
    reg [1:0]  bresp;

    initial begin

        wait_clks(20);

        /*
         * ------------------------------------------------------------
         * GROUP 1
         * Address decode
         * ------------------------------------------------------------
         */

        $display("");
        $display("====================================================");
        $display("GROUP 1: ADDRESS DECODE");
        $display("====================================================");

        axi_write(M00_BASE, 32'h1111_0000, 8'h10, 4'hF, bresp);
        check(bresp == RESP_OKAY, "InstrMem write response");

        axi_read(M00_BASE, 8'h11, rdata, rresp);
        check(rresp == RESP_OKAY, "InstrMem read response");
        check(rdata == 32'h1111_0000, "InstrMem read data");

        axi_write(M01_BASE, 32'h2222_0000, 8'h12, 4'hF, bresp);
        check(bresp == RESP_OKAY, "DataMem write response");

        axi_read(M01_BASE, 8'h13, rdata, rresp);
        check(rresp == RESP_OKAY, "DataMem read response");
        check(rdata == 32'h2222_0000, "DataMem read data");

        axi_write(M02_BASE, 32'h3333_0000, 8'h14, 4'hF, bresp);
        check(bresp == RESP_OKAY, "UART write response");

        axi_write(M03_BASE, 32'h4444_0000, 8'h15, 4'hF, bresp);
        check(bresp == RESP_OKAY, "Timer write response");

        axi_write(M04_BASE, 32'h5555_0000, 8'h16, 4'hF, bresp);
        check(bresp == RESP_OKAY, "GPIO write response");

        axi_write(M05_BASE, 32'h6666_0000, 8'h17, 4'hF, bresp);
        check(bresp == RESP_OKAY, "RLE write response");

        axi_write(M06_BASE, 32'h7777_0000, 8'h18, 4'hF, bresp);
        check(bresp == RESP_OKAY, "DMA write response");

        axi_write(M07_BASE, 32'h8888_0000, 8'h19, 4'hF, bresp);
        check(bresp == RESP_OKAY, "CRC write response");


        /*
         * ------------------------------------------------------------
         * GROUP 2
         * Region boundary addresses
         * ------------------------------------------------------------
         */

        $display("");
        $display("====================================================");
        $display("GROUP 2: REGION BOUNDARIES");
        $display("====================================================");

        axi_write(32'h0003_FFFC, 32'hAAAA_0001, 8'h20, 4'hF, bresp);
        check(bresp == RESP_OKAY, "InstrMem upper boundary");

        axi_write(32'h0004_0000, 32'hAAAA_0002, 8'h21, 4'hF, bresp);
        check(bresp == RESP_OKAY, "DataMem lower boundary");

        axi_write(32'h0007_FFFC, 32'hAAAA_0003, 8'h22, 4'hF, bresp);
        check(bresp == RESP_OKAY, "DataMem upper boundary");

        axi_write(32'h1000_0FFC, 32'hAAAA_0004, 8'h23, 4'hF, bresp);
        check(bresp == RESP_OKAY, "UART upper boundary");

        axi_write(32'h1000_1000, 32'hAAAA_0005, 8'h24, 4'hF, bresp);
        check(bresp == RESP_OKAY, "Timer lower boundary");

        axi_write(32'h1001_0FFC, 32'hAAAA_0006, 8'h25, 4'hF, bresp);
        check(bresp == RESP_OKAY, "RLE upper boundary");

        axi_write(32'h1001_1000, 32'hAAAA_0007, 8'h26, 4'hF, bresp);
        check(bresp == RESP_OKAY, "DMA lower boundary");

        axi_write(32'h1001_1FFC, 32'hAAAA_0008, 8'h27, 4'hF, bresp);
        check(bresp == RESP_OKAY, "DMA upper boundary");

        axi_write(32'h1001_2000, 32'hAAAA_0009, 8'h28, 4'hF, bresp);
        check(bresp == RESP_OKAY, "CRC lower boundary");

        axi_write(32'h1001_2FFC, 32'hAAAA_000A, 8'h29, 4'hF, bresp);
        check(bresp == RESP_OKAY, "CRC upper boundary");


        /*
         * ------------------------------------------------------------
         * GROUP 3
         * Unmapped address
         * ------------------------------------------------------------
         */

        $display("");
        $display("====================================================");
        $display("GROUP 3: UNMAPPED ADDRESS");
        $display("====================================================");

        axi_write(UNMAPPED_ADDR, 32'hDEAD_BEEF, 8'h30, 4'hF, bresp);
        check(bresp == RESP_DECERR, "Unmapped write returns DECERR");

        axi_read(UNMAPPED_ADDR, 8'h31, rdata, rresp);
        check(rresp == RESP_DECERR, "Unmapped read returns DECERR");


        /*
         * ------------------------------------------------------------
         * GROUP 4
         * Partial WSTRB + BID
         * ------------------------------------------------------------
         */

        $display("");
        $display("====================================================");
        $display("GROUP 4: WRITE CHANNEL");
        $display("====================================================");

        axi_write(M01_BASE + 32'h10,
                  32'hAABB_CCDD,
                  8'h40,
                  4'b0011,
                  bresp);

        check(bresp == RESP_OKAY, "Partial DataMem write");
        check(s00_axi_bid == 8'h40, "BID matches AWID");


        axi_write(M05_BASE + 32'h10,
                  32'h1234_5678,
                  8'h41,
                  4'hF,
                  bresp);

        check(bresp == RESP_OKAY, "First RLE write");

        axi_write(M05_BASE + 32'h14,
                  32'h8765_4321,
                  8'h42,
                  4'hF,
                  bresp);

        check(bresp == RESP_OKAY, "Second RLE write");


        /*
         * ------------------------------------------------------------
         * GROUP 5
         * Read channel
         * ------------------------------------------------------------
         */

        $display("");
        $display("====================================================");
        $display("GROUP 5: READ CHANNEL");
        $display("====================================================");

        axi_write(M03_BASE + 32'h20,
                  32'hCAFE_BABE,
                  8'h50,
                  4'hF,
                  bresp);

        axi_read(M03_BASE + 32'h20,
                 8'h51,
                 rdata,
                 rresp);

        check(rresp == RESP_OKAY, "Timer read response");
        check(rdata == 32'hCAFE_BABE, "Timer read data");
        check(s00_axi_rid == 8'h51, "RID matches ARID");
        check(s00_axi_rlast == 1'b1, "Single beat RLAST");


        /*
         * IFU read
         */

        axi_write(M00_BASE + 32'h100,
                  32'hFACE_CAFE,
                  8'h52,
                  4'hF,
                  bresp);

        ifu_read(M00_BASE + 32'h100,
                 8'h53,
                 rdata,
                 rresp);

        check(rresp == RESP_OKAY, "IFU read response");
        check(rdata == 32'hFACE_CAFE, "IFU read data");
        check(s01_axi_rid == 8'h53, "IFU RID matches ARID");
        check(s01_axi_rlast == 1'b1, "IFU single beat RLAST");


        /*
         * SB / Debug read
         */

        axi_write(M02_BASE + 32'h20,
                  32'h1357_9BDF,
                  8'h54,
                  4'hF,
                  bresp);

        sb_read(M02_BASE + 32'h20,
                8'h55,
                rdata,
                rresp);

        check(rresp == RESP_OKAY, "SB read response");
        check(rdata == 32'h1357_9BDF, "SB read data");
        check(s02_axi_rid == 8'h55, "SB RID matches ARID");
        check(s02_axi_rlast == 1'b1, "SB single beat RLAST");


        /*
         * ------------------------------------------------------------
         * GROUP 6
         * Back-to-back transactions / no cross-talk
         * ------------------------------------------------------------
         */

        $display("");
        $display("====================================================");
        $display("GROUP 6: BACK-TO-BACK / CROSS-TALK");
        $display("====================================================");

        axi_write(M00_BASE + 32'h200,
                  32'h1111_AAAA,
                  8'h60,
                  4'hF,
                  bresp);

        axi_write(M01_BASE + 32'h200,
                  32'h2222_BBBB,
                  8'h61,
                  4'hF,
                  bresp);

        axi_write(M05_BASE + 32'h200,
                  32'h3333_CCCC,
                  8'h62,
                  4'hF,
                  bresp);

        axi_read(M00_BASE + 32'h200, 8'h63, rdata, rresp);
        check(rdata == 32'h1111_AAAA, "InstrMem cross-talk check");

        axi_read(M01_BASE + 32'h200, 8'h64, rdata, rresp);
        check(rdata == 32'h2222_BBBB, "DataMem cross-talk check");

        axi_read(M05_BASE + 32'h200, 8'h65, rdata, rresp);
        check(rdata == 32'h3333_CCCC, "RLE cross-talk check");


        /*
         * ------------------------------------------------------------
         * GROUP 7
         * 4-beat INCR burst
         *
         * NOTE:
         * Keep this section identical to the burst BFM from the 2x7 TB.
         * ------------------------------------------------------------
         */

        $display("");
        $display("====================================================");
        $display("GROUP 7: INCR BURST");
        $display("====================================================");

        /*
         * The existing axi_write_burst task from your 2x7 TB
         * should be copied here unchanged, with DataMem address
         * M01_BASE + 0x300.
         */


        /*
         * ------------------------------------------------------------
         * GROUP 8
         * Reset behavior
         * ------------------------------------------------------------
         */

        $display("");
        $display("====================================================");
        $display("GROUP 8: RESET");
        $display("====================================================");

        /*
         * Assert AWVALID and reset before W.
         */

        @(posedge clk);

        s00_axi_awid    = 8'h70;
        s00_axi_awaddr  = M06_BASE + 32'h20;
        s00_axi_awlen   = 0;
        s00_axi_awsize  = 3'd2;
        s00_axi_awburst = 2'b01;
        s00_axi_awvalid = 1;

        @(posedge clk);

        rst = 1'b1;

        s00_axi_wvalid = 0;
        s00_axi_bready = 1;

        wait_clks(3);

        check(!s00_axi_bvalid, "No BVALID after reset");

        rst = 1'b0;

        idle_s00();

        /*
         * Post-reset write.
         */

        axi_write(M06_BASE + 32'h20,
                  32'hDADA_1234,
                  8'h71,
                  4'hF,
                  bresp);

        check(bresp == RESP_OKAY, "Post-reset DMA write");


        /*
         * ------------------------------------------------------------
         * Final
         * ------------------------------------------------------------
         */

        wait_clks(10);

        $display("");
        $display("====================================================");
        $display("TEST COMPLETE");
        $display("Tests  = %0d", tests);
        $display("Errors = %0d", errors);
        $display("====================================================");

        if (errors == 0)
            $display("PASS");
        else
            $display("FAIL");

        $finish;
    end


    /*
     * ================================================================
     * FSDB
     * ================================================================
     */

    initial begin
        $fsdbDumpfile("dump.fsdb");
        $fsdbDumpvars(0, tb_axi_interconnect_wrap_3x8, "+all");
        $fsdbDumpSVA(0, tb_axi_interconnect_wrap_3x8);
        $fsdbDumpMDA(0, tb_axi_interconnect_wrap_3x8);
    end


    /*
     * ================================================================
     * Timeout
     * ================================================================
     */

    initial begin
        #200_000;
        $display("FATAL: simulation timeout after 200 us");
        $finish(1);
    end

endmodule

`default_nettype wire
