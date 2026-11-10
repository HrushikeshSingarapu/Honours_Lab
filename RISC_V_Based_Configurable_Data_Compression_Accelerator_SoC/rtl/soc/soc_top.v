// =============================================================================
// soc_top.v  —  RISC-V Data Compression Accelerator SoC Top Level
//
// Hierarchy:
//   soc_top
//   ├── axi64_to_32_bridge [3x]  (IFU / LSU / SB VeeR interface adapters)
//   ├── axi_interconnect_wrap_4x8  (4-master, 8-slave AXI crossbar)
//   ├── imem_sram              (Instruction Memory  0x0000_0000 – 0x0000_FFFF, aliased @ 0x8000_0000)
//   ├── dmem_sram              (Data Memory         0x0001_0000 – 0x0002_FFFF)
//   ├── axi_uart_top           (UART                0x0003_0000 – 0x0003_0FFF)
//   ├── timer_top              (Timer               0x0005_0000 – 0x0005_0FFF)
//   ├── gpio_top               (GPIO                0x0006_0000 – 0x0006_0FFF)
//   ├── crc32_top              (CRC-32 Engine       0x000A_0000 – 0x000A_0FFF)
//   ├── dma_top                (DMA Controller      0x000B_0000 – 0x000B_FFFF)
//   └── rle_top                (RLE Accelerator     0x000D_0000 – 0x000D_0FFF)
//
// VeeR EL2 Integration Note:
//   VeeR exports AXI4 at 64-bit data width. Each of its three master ports
//   (IFU, LSU, SB) is bridged to 32-bit via axi64_to_32_bridge before
//   connecting to the interconnect. The soc_top exposes the 64-bit VeeR-facing
//   ports directly so that el2_veer_wrapper.sv can be instantiated above.
//   Until VeeR is compiled, the testbench drives these ports as 32-bit masters
//   (upper half of wdata tied to 0, bridge transparent).
//
// Address Map (from axi_interconnect_wrap_4x8 instantiation):
//   Slave 0  (imem):  BASE=0x0000_0000 & 0x8000_0000 (VeeR reset alias)  SIZE=64  kB  (width=16)
//   Slave 1  (dmem):  BASE=0x0001_0000 (2x 64 kB: 0x0001_0000 & 0x0002_0000)  SIZE=128 kB  (width=16+16)
//   Slave 2  (uart):  BASE=0x0003_0000                                    SIZE=4   kB  (width=12)
//   Slave 3  (timer): BASE=0x0005_0000                                    SIZE=4   kB  (width=12)
//   Slave 4  (gpio):  BASE=0x0006_0000                                    SIZE=4   kB  (width=12)
//   Slave 5  (rle):   BASE=0x000D_0000                                    SIZE=4   kB  (width=12)
//   Slave 6  (dma):   BASE=0x000B_0000                                    SIZE=64  kB  (width=16)
//   Slave 7  (crc):   BASE=0x000A_0000                                    SIZE=4   kB  (width=12)
//
// Reset convention:
//   rst_n  — active-low; used by timer_top, gpio_top, crc32_top
//   rst    — active-high; used by rle_top (internal), axi64_to_32_bridge
//   Internally: rst = ~rst_n
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

module soc_top #(
    parameter IMEM_DEPTH = 16384,   // 64  kB / 4 B per word
    parameter DMEM_DEPTH = 32768    // 128 kB / 4 B per word
)(
    input  wire        clk,
    input  wire        rst_n,       // Active-low system reset

    // =========================================================================
    // VeeR EL2 AXI4 Master Ports (64-bit data)
    // These are exposed at the top level so el2_veer_wrapper can connect above.
    // Drive from testbench (with wdata[63:32]=0) when VeeR is not present.
    // =========================================================================

    // --- IFU Master (instruction fetch) ---
    input  wire        ifu_axi_awvalid,
    output wire        ifu_axi_awready,
    input  wire [7:0]  ifu_axi_awid,
    input  wire [31:0] ifu_axi_awaddr,
    input  wire [7:0]  ifu_axi_awlen,
    input  wire [2:0]  ifu_axi_awsize,
    input  wire [1:0]  ifu_axi_awburst,
    input  wire        ifu_axi_awlock,
    input  wire [3:0]  ifu_axi_awcache,
    input  wire [2:0]  ifu_axi_awprot,
    input  wire [3:0]  ifu_axi_awqos,
    input  wire [3:0]  ifu_axi_awregion,
    input  wire        ifu_axi_wvalid,
    output wire        ifu_axi_wready,
    input  wire [63:0] ifu_axi_wdata,
    input  wire [7:0]  ifu_axi_wstrb,
    input  wire        ifu_axi_wlast,
    output wire        ifu_axi_bvalid,
    input  wire        ifu_axi_bready,
    output wire [1:0]  ifu_axi_bresp,
    output wire [7:0]  ifu_axi_bid,
    input  wire        ifu_axi_arvalid,
    output wire        ifu_axi_arready,
    input  wire [7:0]  ifu_axi_arid,
    input  wire [31:0] ifu_axi_araddr,
    input  wire [7:0]  ifu_axi_arlen,
    input  wire [2:0]  ifu_axi_arsize,
    input  wire [1:0]  ifu_axi_arburst,
    input  wire        ifu_axi_arlock,
    input  wire [3:0]  ifu_axi_arcache,
    input  wire [2:0]  ifu_axi_arprot,
    input  wire [3:0]  ifu_axi_arqos,
    input  wire [3:0]  ifu_axi_arregion,
    output wire        ifu_axi_rvalid,
    input  wire        ifu_axi_rready,
    output wire [7:0]  ifu_axi_rid,
    output wire [63:0] ifu_axi_rdata,
    output wire [1:0]  ifu_axi_rresp,
    output wire        ifu_axi_rlast,

    // --- LSU Master (load/store unit) ---
    input  wire        lsu_axi_awvalid,
    output wire        lsu_axi_awready,
    input  wire [7:0]  lsu_axi_awid,
    input  wire [31:0] lsu_axi_awaddr,
    input  wire [7:0]  lsu_axi_awlen,
    input  wire [2:0]  lsu_axi_awsize,
    input  wire [1:0]  lsu_axi_awburst,
    input  wire        lsu_axi_awlock,
    input  wire [3:0]  lsu_axi_awcache,
    input  wire [2:0]  lsu_axi_awprot,
    input  wire [3:0]  lsu_axi_awqos,
    input  wire [3:0]  lsu_axi_awregion,
    input  wire        lsu_axi_wvalid,
    output wire        lsu_axi_wready,
    input  wire [63:0] lsu_axi_wdata,
    input  wire [7:0]  lsu_axi_wstrb,
    input  wire        lsu_axi_wlast,
    output wire        lsu_axi_bvalid,
    input  wire        lsu_axi_bready,
    output wire [1:0]  lsu_axi_bresp,
    output wire [7:0]  lsu_axi_bid,
    input  wire        lsu_axi_arvalid,
    output wire        lsu_axi_arready,
    input  wire [7:0]  lsu_axi_arid,
    input  wire [31:0] lsu_axi_araddr,
    input  wire [7:0]  lsu_axi_arlen,
    input  wire [2:0]  lsu_axi_arsize,
    input  wire [1:0]  lsu_axi_arburst,
    input  wire        lsu_axi_arlock,
    input  wire [3:0]  lsu_axi_arcache,
    input  wire [2:0]  lsu_axi_arprot,
    input  wire [3:0]  lsu_axi_arqos,
    input  wire [3:0]  lsu_axi_arregion,
    output wire        lsu_axi_rvalid,
    input  wire        lsu_axi_rready,
    output wire [7:0]  lsu_axi_rid,
    output wire [63:0] lsu_axi_rdata,
    output wire [1:0]  lsu_axi_rresp,
    output wire        lsu_axi_rlast,

    // --- SB Master (debug system bus) ---
    input  wire        sb_axi_awvalid,
    output wire        sb_axi_awready,
    input  wire [7:0]  sb_axi_awid,
    input  wire [31:0] sb_axi_awaddr,
    input  wire [7:0]  sb_axi_awlen,
    input  wire [2:0]  sb_axi_awsize,
    input  wire [1:0]  sb_axi_awburst,
    input  wire        sb_axi_awlock,
    input  wire [3:0]  sb_axi_awcache,
    input  wire [2:0]  sb_axi_awprot,
    input  wire [3:0]  sb_axi_awqos,
    input  wire [3:0]  sb_axi_awregion,
    input  wire        sb_axi_wvalid,
    output wire        sb_axi_wready,
    input  wire [63:0] sb_axi_wdata,
    input  wire [7:0]  sb_axi_wstrb,
    input  wire        sb_axi_wlast,
    output wire        sb_axi_bvalid,
    input  wire        sb_axi_bready,
    output wire [1:0]  sb_axi_bresp,
    output wire [7:0]  sb_axi_bid,
    input  wire        sb_axi_arvalid,
    output wire        sb_axi_arready,
    input  wire [7:0]  sb_axi_arid,
    input  wire [31:0] sb_axi_araddr,
    input  wire [7:0]  sb_axi_arlen,
    input  wire [2:0]  sb_axi_arsize,
    input  wire [1:0]  sb_axi_arburst,
    input  wire        sb_axi_arlock,
    input  wire [3:0]  sb_axi_arcache,
    input  wire [2:0]  sb_axi_arprot,
    input  wire [3:0]  sb_axi_arqos,
    input  wire [3:0]  sb_axi_arregion,
    output wire        sb_axi_rvalid,
    input  wire        sb_axi_rready,
    output wire [7:0]  sb_axi_rid,
    output wire [63:0] sb_axi_rdata,
    output wire [1:0]  sb_axi_rresp,
    output wire        sb_axi_rlast,

    // =========================================================================
    // External peripheral I/O
    // =========================================================================
    input  wire        uart_rx,
    output wire        uart_tx,
    input  wire [31:0] gpio_i,
    output wire [31:0] gpio_o,
    output wire [31:0] gpio_oe,
    output wire        gpio_irq,
    output wire        timer_irq,
    output wire        rle_irq,
    output wire        dma_irq
);

    // -------------------------------------------------------------------------
    // Internal derived signals
    // -------------------------------------------------------------------------
    wire rst = ~rst_n;   // active-high reset for modules that need it

    // =========================================================================
    // 64→32-bit bridges (one per VeeR master)
    // =========================================================================

    // Wires from IFU bridge → interconnect S00
    wire        ifu32_awvalid, ifu32_awready;
    wire [7:0]  ifu32_awid;
    wire [31:0] ifu32_awaddr;
    wire [7:0]  ifu32_awlen;
    wire [2:0]  ifu32_awsize;
    wire [1:0]  ifu32_awburst;
    wire        ifu32_awlock;
    wire [3:0]  ifu32_awcache, ifu32_awqos;
    wire [2:0]  ifu32_awprot;
    wire        ifu32_awuser;
    wire        ifu32_wvalid, ifu32_wready;
    wire [31:0] ifu32_wdata;
    wire [3:0]  ifu32_wstrb;
    wire        ifu32_wlast, ifu32_wuser;
    wire        ifu32_bvalid, ifu32_bready;
    wire [1:0]  ifu32_bresp;
    wire [7:0]  ifu32_bid;
    wire        ifu32_buser;
    wire        ifu32_arvalid, ifu32_arready;
    wire [7:0]  ifu32_arid;
    wire [31:0] ifu32_araddr;
    wire [7:0]  ifu32_arlen;
    wire [2:0]  ifu32_arsize;
    wire [1:0]  ifu32_arburst;
    wire        ifu32_arlock;
    wire [3:0]  ifu32_arcache, ifu32_arqos;
    wire [2:0]  ifu32_arprot;
    wire        ifu32_aruser;
    wire        ifu32_rvalid, ifu32_rready;
    wire [7:0]  ifu32_rid;
    wire [31:0] ifu32_rdata;
    wire [1:0]  ifu32_rresp;
    wire        ifu32_rlast, ifu32_ruser;

    axi64_to_32_bridge #(.ID_WIDTH(8)) u_ifu_bridge (
        .clk            (clk),
        .rst            (rst),
        .m_axi_awvalid  (ifu_axi_awvalid),  .m_axi_awready  (ifu_axi_awready),
        .m_axi_awid     (ifu_axi_awid),     .m_axi_awaddr   (ifu_axi_awaddr),
        .m_axi_awlen    (ifu_axi_awlen),    .m_axi_awsize   (ifu_axi_awsize),
        .m_axi_awburst  (ifu_axi_awburst),  .m_axi_awlock   (ifu_axi_awlock),
        .m_axi_awcache  (ifu_axi_awcache),  .m_axi_awprot   (ifu_axi_awprot),
        .m_axi_awqos    (ifu_axi_awqos),    .m_axi_awregion (ifu_axi_awregion),
        .m_axi_wvalid   (ifu_axi_wvalid),   .m_axi_wready   (ifu_axi_wready),
        .m_axi_wdata    (ifu_axi_wdata),    .m_axi_wstrb    (ifu_axi_wstrb),
        .m_axi_wlast    (ifu_axi_wlast),
        .m_axi_bvalid   (ifu_axi_bvalid),   .m_axi_bready   (ifu_axi_bready),
        .m_axi_bresp    (ifu_axi_bresp),    .m_axi_bid      (ifu_axi_bid),
        .m_axi_arvalid  (ifu_axi_arvalid),  .m_axi_arready  (ifu_axi_arready),
        .m_axi_arid     (ifu_axi_arid),     .m_axi_araddr   (ifu_axi_araddr),
        .m_axi_arlen    (ifu_axi_arlen),    .m_axi_arsize   (ifu_axi_arsize),
        .m_axi_arburst  (ifu_axi_arburst),  .m_axi_arlock   (ifu_axi_arlock),
        .m_axi_arcache  (ifu_axi_arcache),  .m_axi_arprot   (ifu_axi_arprot),
        .m_axi_arqos    (ifu_axi_arqos),    .m_axi_arregion (ifu_axi_arregion),
        .m_axi_rvalid   (ifu_axi_rvalid),   .m_axi_rready   (ifu_axi_rready),
        .m_axi_rid      (ifu_axi_rid),      .m_axi_rdata    (ifu_axi_rdata),
        .m_axi_rresp    (ifu_axi_rresp),    .m_axi_rlast    (ifu_axi_rlast),
        .s_axi_awvalid  (ifu32_awvalid),    .s_axi_awready  (ifu32_awready),
        .s_axi_awid     (ifu32_awid),       .s_axi_awaddr   (ifu32_awaddr),
        .s_axi_awlen    (ifu32_awlen),      .s_axi_awsize   (ifu32_awsize),
        .s_axi_awburst  (ifu32_awburst),    .s_axi_awlock   (ifu32_awlock),
        .s_axi_awcache  (ifu32_awcache),    .s_axi_awprot   (ifu32_awprot),
        .s_axi_awqos    (ifu32_awqos),      .s_axi_awuser   (ifu32_awuser),
        .s_axi_wvalid   (ifu32_wvalid),     .s_axi_wready   (ifu32_wready),
        .s_axi_wdata    (ifu32_wdata),      .s_axi_wstrb    (ifu32_wstrb),
        .s_axi_wlast    (ifu32_wlast),      .s_axi_wuser    (ifu32_wuser),
        .s_axi_bvalid   (ifu32_bvalid),     .s_axi_bready   (ifu32_bready),
        .s_axi_bresp    (ifu32_bresp),      .s_axi_bid      (ifu32_bid),
        .s_axi_buser    (ifu32_buser),
        .s_axi_arvalid  (ifu32_arvalid),    .s_axi_arready  (ifu32_arready),
        .s_axi_arid     (ifu32_arid),       .s_axi_araddr   (ifu32_araddr),
        .s_axi_arlen    (ifu32_arlen),      .s_axi_arsize   (ifu32_arsize),
        .s_axi_arburst  (ifu32_arburst),    .s_axi_arlock   (ifu32_arlock),
        .s_axi_arcache  (ifu32_arcache),    .s_axi_arprot   (ifu32_arprot),
        .s_axi_arqos    (ifu32_arqos),      .s_axi_aruser   (ifu32_aruser),
        .s_axi_rvalid   (ifu32_rvalid),     .s_axi_rready   (ifu32_rready),
        .s_axi_rid      (ifu32_rid),        .s_axi_rdata    (ifu32_rdata),
        .s_axi_rresp    (ifu32_rresp),      .s_axi_rlast    (ifu32_rlast),
        .s_axi_ruser    (ifu32_ruser)
    );

    // Wires from LSU bridge → interconnect S01
    wire        lsu32_awvalid, lsu32_awready;
    wire [7:0]  lsu32_awid;
    wire [31:0] lsu32_awaddr;
    wire [7:0]  lsu32_awlen;
    wire [2:0]  lsu32_awsize;
    wire [1:0]  lsu32_awburst;
    wire        lsu32_awlock;
    wire [3:0]  lsu32_awcache, lsu32_awqos;
    wire [2:0]  lsu32_awprot;
    wire        lsu32_awuser;
    wire        lsu32_wvalid, lsu32_wready;
    wire [31:0] lsu32_wdata;
    wire [3:0]  lsu32_wstrb;
    wire        lsu32_wlast, lsu32_wuser;
    wire        lsu32_bvalid, lsu32_bready;
    wire [1:0]  lsu32_bresp;
    wire [7:0]  lsu32_bid;
    wire        lsu32_buser;
    wire        lsu32_arvalid, lsu32_arready;
    wire [7:0]  lsu32_arid;
    wire [31:0] lsu32_araddr;
    wire [7:0]  lsu32_arlen;
    wire [2:0]  lsu32_arsize;
    wire [1:0]  lsu32_arburst;
    wire        lsu32_arlock;
    wire [3:0]  lsu32_arcache, lsu32_arqos;
    wire [2:0]  lsu32_arprot;
    wire        lsu32_aruser;
    wire        lsu32_rvalid, lsu32_rready;
    wire [7:0]  lsu32_rid;
    wire [31:0] lsu32_rdata;
    wire [1:0]  lsu32_rresp;
    wire        lsu32_rlast, lsu32_ruser;

    axi64_to_32_bridge #(.ID_WIDTH(8)) u_lsu_bridge (
        .clk            (clk),
        .rst            (rst),
        .m_axi_awvalid  (lsu_axi_awvalid),  .m_axi_awready  (lsu_axi_awready),
        .m_axi_awid     (lsu_axi_awid),     .m_axi_awaddr   (lsu_axi_awaddr),
        .m_axi_awlen    (lsu_axi_awlen),    .m_axi_awsize   (lsu_axi_awsize),
        .m_axi_awburst  (lsu_axi_awburst),  .m_axi_awlock   (lsu_axi_awlock),
        .m_axi_awcache  (lsu_axi_awcache),  .m_axi_awprot   (lsu_axi_awprot),
        .m_axi_awqos    (lsu_axi_awqos),    .m_axi_awregion (lsu_axi_awregion),
        .m_axi_wvalid   (lsu_axi_wvalid),   .m_axi_wready   (lsu_axi_wready),
        .m_axi_wdata    (lsu_axi_wdata),    .m_axi_wstrb    (lsu_axi_wstrb),
        .m_axi_wlast    (lsu_axi_wlast),
        .m_axi_bvalid   (lsu_axi_bvalid),   .m_axi_bready   (lsu_axi_bready),
        .m_axi_bresp    (lsu_axi_bresp),    .m_axi_bid      (lsu_axi_bid),
        .m_axi_arvalid  (lsu_axi_arvalid),  .m_axi_arready  (lsu_axi_arready),
        .m_axi_arid     (lsu_axi_arid),     .m_axi_araddr   (lsu_axi_araddr),
        .m_axi_arlen    (lsu_axi_arlen),    .m_axi_arsize   (lsu_axi_arsize),
        .m_axi_arburst  (lsu_axi_arburst),  .m_axi_arlock   (lsu_axi_arlock),
        .m_axi_arcache  (lsu_axi_arcache),  .m_axi_arprot   (lsu_axi_arprot),
        .m_axi_arqos    (lsu_axi_arqos),    .m_axi_arregion (lsu_axi_arregion),
        .m_axi_rvalid   (lsu_axi_rvalid),   .m_axi_rready   (lsu_axi_rready),
        .m_axi_rid      (lsu_axi_rid),      .m_axi_rdata    (lsu_axi_rdata),
        .m_axi_rresp    (lsu_axi_rresp),    .m_axi_rlast    (lsu_axi_rlast),
        .s_axi_awvalid  (lsu32_awvalid),    .s_axi_awready  (lsu32_awready),
        .s_axi_awid     (lsu32_awid),       .s_axi_awaddr   (lsu32_awaddr),
        .s_axi_awlen    (lsu32_awlen),      .s_axi_awsize   (lsu32_awsize),
        .s_axi_awburst  (lsu32_awburst),    .s_axi_awlock   (lsu32_awlock),
        .s_axi_awcache  (lsu32_awcache),    .s_axi_awprot   (lsu32_awprot),
        .s_axi_awqos    (lsu32_awqos),      .s_axi_awuser   (lsu32_awuser),
        .s_axi_wvalid   (lsu32_wvalid),     .s_axi_wready   (lsu32_wready),
        .s_axi_wdata    (lsu32_wdata),      .s_axi_wstrb    (lsu32_wstrb),
        .s_axi_wlast    (lsu32_wlast),      .s_axi_wuser    (lsu32_wuser),
        .s_axi_bvalid   (lsu32_bvalid),     .s_axi_bready   (lsu32_bready),
        .s_axi_bresp    (lsu32_bresp),      .s_axi_bid      (lsu32_bid),
        .s_axi_buser    (lsu32_buser),
        .s_axi_arvalid  (lsu32_arvalid),    .s_axi_arready  (lsu32_arready),
        .s_axi_arid     (lsu32_arid),       .s_axi_araddr   (lsu32_araddr),
        .s_axi_arlen    (lsu32_arlen),      .s_axi_arsize   (lsu32_arsize),
        .s_axi_arburst  (lsu32_arburst),    .s_axi_arlock   (lsu32_arlock),
        .s_axi_arcache  (lsu32_arcache),    .s_axi_arprot   (lsu32_arprot),
        .s_axi_arqos    (lsu32_arqos),      .s_axi_aruser   (lsu32_aruser),
        .s_axi_rvalid   (lsu32_rvalid),     .s_axi_rready   (lsu32_rready),
        .s_axi_rid      (lsu32_rid),        .s_axi_rdata    (lsu32_rdata),
        .s_axi_rresp    (lsu32_rresp),      .s_axi_rlast    (lsu32_rlast),
        .s_axi_ruser    (lsu32_ruser)
    );

    // Wires from SB bridge → interconnect S02
    wire        sb32_awvalid, sb32_awready;
    wire [7:0]  sb32_awid;
    wire [31:0] sb32_awaddr;
    wire [7:0]  sb32_awlen;
    wire [2:0]  sb32_awsize;
    wire [1:0]  sb32_awburst;
    wire        sb32_awlock;
    wire [3:0]  sb32_awcache, sb32_awqos;
    wire [2:0]  sb32_awprot;
    wire        sb32_awuser;
    wire        sb32_wvalid, sb32_wready;
    wire [31:0] sb32_wdata;
    wire [3:0]  sb32_wstrb;
    wire        sb32_wlast, sb32_wuser;
    wire        sb32_bvalid, sb32_bready;
    wire [1:0]  sb32_bresp;
    wire [7:0]  sb32_bid;
    wire        sb32_buser;
    wire        sb32_arvalid, sb32_arready;
    wire [7:0]  sb32_arid;
    wire [31:0] sb32_araddr;
    wire [7:0]  sb32_arlen;
    wire [2:0]  sb32_arsize;
    wire [1:0]  sb32_arburst;
    wire        sb32_arlock;
    wire [3:0]  sb32_arcache, sb32_arqos;
    wire [2:0]  sb32_arprot;
    wire        sb32_aruser;
    wire        sb32_rvalid, sb32_rready;
    wire [7:0]  sb32_rid;
    wire [31:0] sb32_rdata;
    wire [1:0]  sb32_rresp;
    wire        sb32_rlast, sb32_ruser;

    axi64_to_32_bridge #(.ID_WIDTH(8)) u_sb_bridge (
        .clk            (clk),
        .rst            (rst),
        .m_axi_awvalid  (sb_axi_awvalid),   .m_axi_awready  (sb_axi_awready),
        .m_axi_awid     (sb_axi_awid),      .m_axi_awaddr   (sb_axi_awaddr),
        .m_axi_awlen    (sb_axi_awlen),     .m_axi_awsize   (sb_axi_awsize),
        .m_axi_awburst  (sb_axi_awburst),   .m_axi_awlock   (sb_axi_awlock),
        .m_axi_awcache  (sb_axi_awcache),   .m_axi_awprot   (sb_axi_awprot),
        .m_axi_awqos    (sb_axi_awqos),     .m_axi_awregion (sb_axi_awregion),
        .m_axi_wvalid   (sb_axi_wvalid),    .m_axi_wready   (sb_axi_wready),
        .m_axi_wdata    (sb_axi_wdata),     .m_axi_wstrb    (sb_axi_wstrb),
        .m_axi_wlast    (sb_axi_wlast),
        .m_axi_bvalid   (sb_axi_bvalid),    .m_axi_bready   (sb_axi_bready),
        .m_axi_bresp    (sb_axi_bresp),     .m_axi_bid      (sb_axi_bid),
        .m_axi_arvalid  (sb_axi_arvalid),   .m_axi_arready  (sb_axi_arready),
        .m_axi_arid     (sb_axi_arid),      .m_axi_araddr   (sb_axi_araddr),
        .m_axi_arlen    (sb_axi_arlen),     .m_axi_arsize   (sb_axi_arsize),
        .m_axi_arburst  (sb_axi_arburst),   .m_axi_arlock   (sb_axi_arlock),
        .m_axi_arcache  (sb_axi_arcache),   .m_axi_arprot   (sb_axi_arprot),
        .m_axi_arqos    (sb_axi_arqos),     .m_axi_arregion (sb_axi_arregion),
        .m_axi_rvalid   (sb_axi_rvalid),    .m_axi_rready   (sb_axi_rready),
        .m_axi_rid      (sb_axi_rid),       .m_axi_rdata    (sb_axi_rdata),
        .m_axi_rresp    (sb_axi_rresp),     .m_axi_rlast    (sb_axi_rlast),
        .s_axi_awvalid  (sb32_awvalid),     .s_axi_awready  (sb32_awready),
        .s_axi_awid     (sb32_awid),        .s_axi_awaddr   (sb32_awaddr),
        .s_axi_awlen    (sb32_awlen),       .s_axi_awsize   (sb32_awsize),
        .s_axi_awburst  (sb32_awburst),     .s_axi_awlock   (sb32_awlock),
        .s_axi_awcache  (sb32_awcache),     .s_axi_awprot   (sb32_awprot),
        .s_axi_awqos    (sb32_awqos),       .s_axi_awuser   (sb32_awuser),
        .s_axi_wvalid   (sb32_wvalid),      .s_axi_wready   (sb32_wready),
        .s_axi_wdata    (sb32_wdata),       .s_axi_wstrb    (sb32_wstrb),
        .s_axi_wlast    (sb32_wlast),       .s_axi_wuser    (sb32_wuser),
        .s_axi_bvalid   (sb32_bvalid),      .s_axi_bready   (sb32_bready),
        .s_axi_bresp    (sb32_bresp),       .s_axi_bid      (sb32_bid),
        .s_axi_buser    (sb32_buser),
        .s_axi_arvalid  (sb32_arvalid),     .s_axi_arready  (sb32_arready),
        .s_axi_arid     (sb32_arid),        .s_axi_araddr   (sb32_araddr),
        .s_axi_arlen    (sb32_arlen),       .s_axi_arsize   (sb32_arsize),
        .s_axi_arburst  (sb32_arburst),     .s_axi_arlock   (sb32_arlock),
        .s_axi_arcache  (sb32_arcache),     .s_axi_arprot   (sb32_arprot),
        .s_axi_arqos    (sb32_arqos),       .s_axi_aruser   (sb32_aruser),
        .s_axi_rvalid   (sb32_rvalid),      .s_axi_rready   (sb32_rready),
        .s_axi_rid      (sb32_rid),         .s_axi_rdata    (sb32_rdata),
        .s_axi_rresp    (sb32_rresp),       .s_axi_rlast    (sb32_rlast),
        .s_axi_ruser    (sb32_ruser)
    );

    // =========================================================================
    // DMA Master (S03) wires connecting to AXI Interconnect
    // =========================================================================
    wire        dma_awvalid, dma_awready;
    wire [7:0]  dma_awid;
    wire [31:0] dma_awaddr;
    wire [7:0]  dma_awlen;
    wire [2:0]  dma_awsize;
    wire [1:0]  dma_awburst;
    wire        dma_awlock;
    wire [3:0]  dma_awcache;
    wire [2:0]  dma_awprot;
    wire [3:0]  dma_awqos;
    wire [3:0]  dma_awregion;
    wire        dma_awuser;
    wire        dma_wvalid, dma_wready;
    wire [31:0] dma_wdata;
    wire [3:0]  dma_wstrb;
    wire        dma_wlast;
    wire        dma_wuser;
    wire        dma_bvalid, dma_bready;
    wire [1:0]  dma_bresp;
    wire [7:0]  dma_bid;
    wire        dma_buser;
    wire        dma_arvalid, dma_arready;
    wire [7:0]  dma_arid;
    wire [31:0] dma_araddr;
    wire [7:0]  dma_arlen;
    wire [2:0]  dma_arsize;
    wire [1:0]  dma_arburst;
    wire        dma_arlock;
    wire [3:0]  dma_arcache;
    wire [2:0]  dma_arprot;
    wire [3:0]  dma_arqos;
    wire [3:0]  dma_arregion;
    wire        dma_aruser;
    wire        dma_rvalid, dma_rready;
    wire [7:0]  dma_rid;
    wire [31:0] dma_rdata;
    wire [1:0]  dma_rresp;
    wire        dma_rlast;
    wire        dma_ruser;

    // =========================================================================
    // AXI 4×8 Interconnect
    // Slave port wires (m00–m07 = peripheral-facing outputs of interconnect)
    // =========================================================================

    // imem (M00)
    wire        m00_awvalid, m00_awready;
    wire [7:0]  m00_awid;   wire [31:0] m00_awaddr;
    wire [7:0]  m00_awlen;  wire [2:0]  m00_awsize;
    wire [1:0]  m00_awburst; wire       m00_awlock;
    wire [3:0]  m00_awcache; wire [2:0] m00_awprot;
    wire [3:0]  m00_awqos;   wire [3:0] m00_awregion;
    wire        m00_wvalid, m00_wready;
    wire [31:0] m00_wdata;   wire [3:0] m00_wstrb;
    wire        m00_wlast;
    wire        m00_bvalid, m00_bready;
    wire [1:0]  m00_bresp;   wire [7:0] m00_bid;
    wire        m00_arvalid, m00_arready;
    wire [7:0]  m00_arid;   wire [31:0] m00_araddr;
    wire [7:0]  m00_arlen;  wire [2:0]  m00_arsize;
    wire [1:0]  m00_arburst; wire       m00_arlock;
    wire [3:0]  m00_arcache; wire [2:0] m00_arprot;
    wire [3:0]  m00_arqos;   wire [3:0] m00_arregion;
    wire        m00_rvalid, m00_rready;
    wire [7:0]  m00_rid;    wire [31:0] m00_rdata;
    wire [1:0]  m00_rresp;  wire        m00_rlast;

    // dmem (M01)
    wire        m01_awvalid, m01_awready;
    wire [7:0]  m01_awid;   wire [31:0] m01_awaddr;
    wire [7:0]  m01_awlen;  wire [2:0]  m01_awsize;
    wire [1:0]  m01_awburst; wire       m01_awlock;
    wire [3:0]  m01_awcache; wire [2:0] m01_awprot;
    wire [3:0]  m01_awqos;   wire [3:0] m01_awregion;
    wire        m01_wvalid, m01_wready;
    wire [31:0] m01_wdata;   wire [3:0] m01_wstrb;
    wire        m01_wlast;
    wire        m01_bvalid, m01_bready;
    wire [1:0]  m01_bresp;   wire [7:0] m01_bid;
    wire        m01_arvalid, m01_arready;
    wire [7:0]  m01_arid;   wire [31:0] m01_araddr;
    wire [7:0]  m01_arlen;  wire [2:0]  m01_arsize;
    wire [1:0]  m01_arburst; wire       m01_arlock;
    wire [3:0]  m01_arcache; wire [2:0] m01_arprot;
    wire [3:0]  m01_arqos;   wire [3:0] m01_arregion;
    wire        m01_rvalid, m01_rready;
    wire [7:0]  m01_rid;    wire [31:0] m01_rdata;
    wire [1:0]  m01_rresp;  wire        m01_rlast;

    // uart (M02)
    wire        m02_awvalid, m02_awready;
    wire [7:0]  m02_awid;   wire [31:0] m02_awaddr;
    wire [7:0]  m02_awlen;  wire [2:0]  m02_awsize;
    wire [1:0]  m02_awburst; wire       m02_awlock;
    wire [3:0]  m02_awcache; wire [2:0] m02_awprot;
    wire [3:0]  m02_awqos;   wire [3:0] m02_awregion;
    wire        m02_wvalid, m02_wready;
    wire [31:0] m02_wdata;   wire [3:0] m02_wstrb;
    wire        m02_wlast;
    wire        m02_bvalid, m02_bready;
    wire [1:0]  m02_bresp;   wire [7:0] m02_bid;
    wire        m02_arvalid, m02_arready;
    wire [7:0]  m02_arid;   wire [31:0] m02_araddr;
    wire [7:0]  m02_arlen;  wire [2:0]  m02_arsize;
    wire [1:0]  m02_arburst; wire       m02_arlock;
    wire [3:0]  m02_arcache; wire [2:0] m02_arprot;
    wire [3:0]  m02_arqos;   wire [3:0] m02_arregion;
    wire        m02_rvalid, m02_rready;
    wire [7:0]  m02_rid;    wire [31:0] m02_rdata;
    wire [1:0]  m02_rresp;  wire        m02_rlast;

    // timer (M03)
    wire        m03_awvalid, m03_awready;
    wire [7:0]  m03_awid;   wire [31:0] m03_awaddr;
    wire [7:0]  m03_awlen;  wire [2:0]  m03_awsize;
    wire [1:0]  m03_awburst; wire       m03_awlock;
    wire [3:0]  m03_awcache; wire [2:0] m03_awprot;
    wire [3:0]  m03_awqos;   wire [3:0] m03_awregion;
    wire        m03_wvalid, m03_wready;
    wire [31:0] m03_wdata;   wire [3:0] m03_wstrb;
    wire        m03_wlast;
    wire        m03_bvalid, m03_bready;
    wire [1:0]  m03_bresp;   wire [7:0] m03_bid;
    wire        m03_arvalid, m03_arready;
    wire [7:0]  m03_arid;   wire [31:0] m03_araddr;
    wire [7:0]  m03_arlen;  wire [2:0]  m03_arsize;
    wire [1:0]  m03_arburst; wire       m03_arlock;
    wire [3:0]  m03_arcache; wire [2:0] m03_arprot;
    wire [3:0]  m03_arqos;   wire [3:0] m03_arregion;
    wire        m03_rvalid, m03_rready;
    wire [7:0]  m03_rid;    wire [31:0] m03_rdata;
    wire [1:0]  m03_rresp;  wire        m03_rlast;

    // gpio (M04)
    wire        m04_awvalid, m04_awready;
    wire [7:0]  m04_awid;   wire [31:0] m04_awaddr;
    wire [7:0]  m04_awlen;  wire [2:0]  m04_awsize;
    wire [1:0]  m04_awburst; wire       m04_awlock;
    wire [3:0]  m04_awcache; wire [2:0] m04_awprot;
    wire [3:0]  m04_awqos;   wire [3:0] m04_awregion;
    wire        m04_wvalid, m04_wready;
    wire [31:0] m04_wdata;   wire [3:0] m04_wstrb;
    wire        m04_wlast;
    wire        m04_bvalid, m04_bready;
    wire [1:0]  m04_bresp;   wire [7:0] m04_bid;
    wire        m04_arvalid, m04_arready;
    wire [7:0]  m04_arid;   wire [31:0] m04_araddr;
    wire [7:0]  m04_arlen;  wire [2:0]  m04_arsize;
    wire [1:0]  m04_arburst; wire       m04_arlock;
    wire [3:0]  m04_arcache; wire [2:0] m04_arprot;
    wire [3:0]  m04_arqos;   wire [3:0] m04_arregion;
    wire        m04_rvalid, m04_rready;
    wire [7:0]  m04_rid;    wire [31:0] m04_rdata;
    wire [1:0]  m04_rresp;  wire        m04_rlast;

    // rle (M05)
    wire        m05_awvalid, m05_awready;
    wire [7:0]  m05_awid;   wire [31:0] m05_awaddr;
    wire [7:0]  m05_awlen;  wire [2:0]  m05_awsize;
    wire [1:0]  m05_awburst; wire       m05_awlock;
    wire [3:0]  m05_awcache; wire [2:0] m05_awprot;
    wire [3:0]  m05_awqos;   wire [3:0] m05_awregion;
    wire        m05_wvalid, m05_wready;
    wire [31:0] m05_wdata;   wire [3:0] m05_wstrb;
    wire        m05_wlast;
    wire        m05_bvalid, m05_bready;
    wire [1:0]  m05_bresp;   wire [7:0] m05_bid;
    wire        m05_arvalid, m05_arready;
    wire [7:0]  m05_arid;   wire [31:0] m05_araddr;
    wire [7:0]  m05_arlen;  wire [2:0]  m05_arsize;
    wire [1:0]  m05_arburst; wire       m05_arlock;
    wire [3:0]  m05_arcache; wire [2:0] m05_arprot;
    wire [3:0]  m05_arqos;   wire [3:0] m05_arregion;
    wire        m05_rvalid, m05_rready;
    wire [7:0]  m05_rid;    wire [31:0] m05_rdata;
    wire [1:0]  m05_rresp;  wire        m05_rlast;

    // dma stub (M06) — not implemented; interconnect slave stub
    wire        m06_awvalid, m06_awready;
    wire [7:0]  m06_awid;   wire [31:0] m06_awaddr;
    wire [7:0]  m06_awlen;  wire [2:0]  m06_awsize;
    wire [1:0]  m06_awburst; wire       m06_awlock;
    wire [3:0]  m06_awcache; wire [2:0] m06_awprot;
    wire [3:0]  m06_awqos;   wire [3:0] m06_awregion;
    wire        m06_wvalid, m06_wready;
    wire [31:0] m06_wdata;   wire [3:0] m06_wstrb;
    wire        m06_wlast;
    wire        m06_bvalid, m06_bready;
    wire [1:0]  m06_bresp;   wire [7:0] m06_bid;
    wire        m06_arvalid, m06_arready;
    wire [7:0]  m06_arid;   wire [31:0] m06_araddr;
    wire [7:0]  m06_arlen;  wire [2:0]  m06_arsize;
    wire [1:0]  m06_arburst; wire       m06_arlock;
    wire [3:0]  m06_arcache; wire [2:0] m06_arprot;
    wire [3:0]  m06_arqos;   wire [3:0] m06_arregion;
    wire        m06_rvalid, m06_rready;
    wire [7:0]  m06_rid;    wire [31:0] m06_rdata;
    wire [1:0]  m06_rresp;  wire        m06_rlast;

    // crc (M07)
    wire        m07_awvalid, m07_awready;
    wire [7:0]  m07_awid;   wire [31:0] m07_awaddr;
    wire [7:0]  m07_awlen;  wire [2:0]  m07_awsize;
    wire [1:0]  m07_awburst; wire       m07_awlock;
    wire [3:0]  m07_awcache; wire [2:0] m07_awprot;
    wire [3:0]  m07_awqos;   wire [3:0] m07_awregion;
    wire        m07_wvalid, m07_wready;
    wire [31:0] m07_wdata;   wire [3:0] m07_wstrb;
    wire        m07_wlast;
    wire        m07_bvalid, m07_bready;
    wire [1:0]  m07_bresp;   wire [7:0] m07_bid;
    wire        m07_arvalid, m07_arready;
    wire [7:0]  m07_arid;   wire [31:0] m07_araddr;
    wire [7:0]  m07_arlen;  wire [2:0]  m07_arsize;
    wire [1:0]  m07_arburst; wire       m07_arlock;
    wire [3:0]  m07_arcache; wire [2:0] m07_arprot;
    wire [3:0]  m07_arqos;   wire [3:0] m07_arregion;
    wire        m07_rvalid, m07_rready;
    wire [7:0]  m07_rid;    wire [31:0] m07_rdata;
    wire [1:0]  m07_rresp;  wire        m07_rlast;

    // =========================================================================
    // AXI Interconnect 4×8
    // =========================================================================
    axi_interconnect_wrap_4x8 #(
        .DATA_WIDTH        (32),
        .ADDR_WIDTH        (32),
        .ID_WIDTH          (8),
        .AWUSER_ENABLE     (1),   // must match bridge output
        .WUSER_ENABLE      (1),
        .BUSER_ENABLE      (1),
        .ARUSER_ENABLE     (1),
        .RUSER_ENABLE      (1),
        .M_REGIONS         (2),
        // Slave 0: IMEM  0x0000_0000 & 0x8000_0000 (VeeR reset vector alias) /16 (64 kB)
        .M00_BASE_ADDR     ({32'h8000_0000, 32'h0000_0000}),
        .M00_ADDR_WIDTH    ({32'd16,        32'd16}),
        .M00_CONNECT_READ  (4'b1111),
        .M00_CONNECT_WRITE (4'b1111),
        // Slave 1: DMEM  0x0001_0000 – 0x0002_FFFF (128 kB as two aligned 64 kB regions)
        .M01_BASE_ADDR     ({32'h0002_0000, 32'h0001_0000}),
        .M01_ADDR_WIDTH    ({32'd16,        32'd16}),
        .M01_CONNECT_READ  (4'b1111),
        .M01_CONNECT_WRITE (4'b1111),
        // Slave 2: UART  0x0003_0000  /12  (4 kB)
        .M02_BASE_ADDR     ({32'h0000_0000, 32'h0003_0000}),
        .M02_ADDR_WIDTH    ({32'd0,         32'd12}),
        .M02_CONNECT_READ  (4'b1111),
        .M02_CONNECT_WRITE (4'b1111),
        // Slave 3: Timer 0x0005_0000  /12  (4 kB)
        .M03_BASE_ADDR     ({32'h0000_0000, 32'h0005_0000}),
        .M03_ADDR_WIDTH    ({32'd0,         32'd12}),
        .M03_CONNECT_READ  (4'b1111),
        .M03_CONNECT_WRITE (4'b1111),
        // Slave 4: GPIO  0x0006_0000  /12  (4 kB)
        .M04_BASE_ADDR     ({32'h0000_0000, 32'h0006_0000}),
        .M04_ADDR_WIDTH    ({32'd0,         32'd12}),
        .M04_CONNECT_READ  (4'b1111),
        .M04_CONNECT_WRITE (4'b1111),
        // Slave 5: RLE   0x000D_0000  /12  (4 kB)
        .M05_BASE_ADDR     ({32'h0000_0000, 32'h000D_0000}),
        .M05_ADDR_WIDTH    ({32'd0,         32'd12}),
        .M05_CONNECT_READ  (4'b1111),
        .M05_CONNECT_WRITE (4'b1111),
        // Slave 6: DMA   0x000B_0000  /16  (64 kB)
        .M06_BASE_ADDR     ({32'h0000_0000, 32'h000B_0000}),
        .M06_ADDR_WIDTH    ({32'd0,         32'd16}),
        .M06_CONNECT_READ  (4'b1111),
        .M06_CONNECT_WRITE (4'b1111),
        // Slave 7: CRC   0x000A_0000  /12  (4 kB)
        .M07_BASE_ADDR     ({32'h0000_0000, 32'h000A_0000}),
        .M07_ADDR_WIDTH    ({32'd0,         32'd12}),
        .M07_CONNECT_READ  (4'b1111),
        .M07_CONNECT_WRITE (4'b1111)
    ) u_interconnect (
        .clk               (clk),
        .rst               (rst),
        // S00 = IFU bridge
        .s00_axi_awvalid   (ifu32_awvalid), .s00_axi_awready (ifu32_awready),
        .s00_axi_awid      (ifu32_awid),    .s00_axi_awaddr  (ifu32_awaddr),
        .s00_axi_awlen     (ifu32_awlen),   .s00_axi_awsize  (ifu32_awsize),
        .s00_axi_awburst   (ifu32_awburst), .s00_axi_awlock  (ifu32_awlock),
        .s00_axi_awcache   (ifu32_awcache), .s00_axi_awprot  (ifu32_awprot),
        .s00_axi_awqos     (ifu32_awqos),   .s00_axi_awuser  (ifu32_awuser),
        .s00_axi_wvalid    (ifu32_wvalid),  .s00_axi_wready  (ifu32_wready),
        .s00_axi_wdata     (ifu32_wdata),   .s00_axi_wstrb   (ifu32_wstrb),
        .s00_axi_wlast     (ifu32_wlast),   .s00_axi_wuser   (ifu32_wuser),
        .s00_axi_bvalid    (ifu32_bvalid),  .s00_axi_bready  (ifu32_bready),
        .s00_axi_bresp     (ifu32_bresp),   .s00_axi_bid     (ifu32_bid),
        .s00_axi_buser     (ifu32_buser),
        .s00_axi_arvalid   (ifu32_arvalid), .s00_axi_arready (ifu32_arready),
        .s00_axi_arid      (ifu32_arid),    .s00_axi_araddr  (ifu32_araddr),
        .s00_axi_arlen     (ifu32_arlen),   .s00_axi_arsize  (ifu32_arsize),
        .s00_axi_arburst   (ifu32_arburst), .s00_axi_arlock  (ifu32_arlock),
        .s00_axi_arcache   (ifu32_arcache), .s00_axi_arprot  (ifu32_arprot),
        .s00_axi_arqos     (ifu32_arqos),   .s00_axi_aruser  (ifu32_aruser),
        .s00_axi_rvalid    (ifu32_rvalid),  .s00_axi_rready  (ifu32_rready),
        .s00_axi_rid       (ifu32_rid),     .s00_axi_rdata   (ifu32_rdata),
        .s00_axi_rresp     (ifu32_rresp),   .s00_axi_rlast   (ifu32_rlast),
        .s00_axi_ruser     (ifu32_ruser),
        // S01 = LSU bridge
        .s01_axi_awvalid   (lsu32_awvalid), .s01_axi_awready (lsu32_awready),
        .s01_axi_awid      (lsu32_awid),    .s01_axi_awaddr  (lsu32_awaddr),
        .s01_axi_awlen     (lsu32_awlen),   .s01_axi_awsize  (lsu32_awsize),
        .s01_axi_awburst   (lsu32_awburst), .s01_axi_awlock  (lsu32_awlock),
        .s01_axi_awcache   (lsu32_awcache), .s01_axi_awprot  (lsu32_awprot),
        .s01_axi_awqos     (lsu32_awqos),   .s01_axi_awuser  (lsu32_awuser),
        .s01_axi_wvalid    (lsu32_wvalid),  .s01_axi_wready  (lsu32_wready),
        .s01_axi_wdata     (lsu32_wdata),   .s01_axi_wstrb   (lsu32_wstrb),
        .s01_axi_wlast     (lsu32_wlast),   .s01_axi_wuser   (lsu32_wuser),
        .s01_axi_bvalid    (lsu32_bvalid),  .s01_axi_bready  (lsu32_bready),
        .s01_axi_bresp     (lsu32_bresp),   .s01_axi_bid     (lsu32_bid),
        .s01_axi_buser     (lsu32_buser),
        .s01_axi_arvalid   (lsu32_arvalid), .s01_axi_arready (lsu32_arready),
        .s01_axi_arid      (lsu32_arid),    .s01_axi_araddr  (lsu32_araddr),
        .s01_axi_arlen     (lsu32_arlen),   .s01_axi_arsize  (lsu32_arsize),
        .s01_axi_arburst   (lsu32_arburst), .s01_axi_arlock  (lsu32_arlock),
        .s01_axi_arcache   (lsu32_arcache), .s01_axi_arprot  (lsu32_arprot),
        .s01_axi_arqos     (lsu32_arqos),   .s01_axi_aruser  (lsu32_aruser),
        .s01_axi_rvalid    (lsu32_rvalid),  .s01_axi_rready  (lsu32_rready),
        .s01_axi_rid       (lsu32_rid),     .s01_axi_rdata   (lsu32_rdata),
        .s01_axi_rresp     (lsu32_rresp),   .s01_axi_rlast   (lsu32_rlast),
        .s01_axi_ruser     (lsu32_ruser),
        // S02 = SB (debug bus) bridge
        .s02_axi_awvalid   (sb32_awvalid),  .s02_axi_awready (sb32_awready),
        .s02_axi_awid      (sb32_awid),     .s02_axi_awaddr  (sb32_awaddr),
        .s02_axi_awlen     (sb32_awlen),    .s02_axi_awsize  (sb32_awsize),
        .s02_axi_awburst   (sb32_awburst),  .s02_axi_awlock  (sb32_awlock),
        .s02_axi_awcache   (sb32_awcache),  .s02_axi_awprot  (sb32_awprot),
        .s02_axi_awqos     (sb32_awqos),    .s02_axi_awuser  (sb32_awuser),
        .s02_axi_wvalid    (sb32_wvalid),   .s02_axi_wready  (sb32_wready),
        .s02_axi_wdata     (sb32_wdata),    .s02_axi_wstrb   (sb32_wstrb),
        .s02_axi_wlast     (sb32_wlast),    .s02_axi_wuser   (sb32_wuser),
        .s02_axi_bvalid    (sb32_bvalid),   .s02_axi_bready  (sb32_bready),
        .s02_axi_bresp     (sb32_bresp),    .s02_axi_bid     (sb32_bid),
        .s02_axi_buser     (sb32_buser),
        .s02_axi_arvalid   (sb32_arvalid),  .s02_axi_arready (sb32_arready),
        .s02_axi_arid      (sb32_arid),     .s02_axi_araddr  (sb32_araddr),
        .s02_axi_arlen     (sb32_arlen),    .s02_axi_arsize  (sb32_arsize),
        .s02_axi_arburst   (sb32_arburst),  .s02_axi_arlock  (sb32_arlock),
        .s02_axi_arcache   (sb32_arcache),  .s02_axi_arprot  (sb32_arprot),
        .s02_axi_arqos     (sb32_arqos),    .s02_axi_aruser  (sb32_aruser),
        .s02_axi_rvalid    (sb32_rvalid),   .s02_axi_rready  (sb32_rready),
        .s02_axi_rid       (sb32_rid),      .s02_axi_rdata   (sb32_rdata),
        .s02_axi_rresp     (sb32_rresp),    .s02_axi_rlast   (sb32_rlast),
        .s02_axi_ruser     (sb32_ruser),
        // S03 = DMA Master Engine
        .s03_axi_awvalid   (dma_awvalid),   .s03_axi_awready (dma_awready),
        .s03_axi_awid      (dma_awid),      .s03_axi_awaddr  (dma_awaddr),
        .s03_axi_awlen     (dma_awlen),     .s03_axi_awsize  (dma_awsize),
        .s03_axi_awburst   (dma_awburst),   .s03_axi_awlock  (dma_awlock),
        .s03_axi_awcache   (dma_awcache),   .s03_axi_awprot  (dma_awprot),
        .s03_axi_awqos     (dma_awqos),     .s03_axi_awuser  (dma_awuser),
        .s03_axi_wvalid    (dma_wvalid),    .s03_axi_wready  (dma_wready),
        .s03_axi_wdata     (dma_wdata),     .s03_axi_wstrb   (dma_wstrb),
        .s03_axi_wlast     (dma_wlast),     .s03_axi_wuser   (dma_wuser),
        .s03_axi_bvalid    (dma_bvalid),    .s03_axi_bready  (dma_bready),
        .s03_axi_bresp     (dma_bresp),     .s03_axi_bid     (dma_bid),
        .s03_axi_buser     (dma_buser),
        .s03_axi_arvalid   (dma_arvalid),   .s03_axi_arready (dma_arready),
        .s03_axi_arid      (dma_arid),      .s03_axi_araddr  (dma_araddr),
        .s03_axi_arlen     (dma_arlen),     .s03_axi_arsize  (dma_arsize),
        .s03_axi_arburst   (dma_arburst),   .s03_axi_arlock  (dma_arlock),
        .s03_axi_arcache   (dma_arcache),   .s03_axi_arprot  (dma_arprot),
        .s03_axi_arqos     (dma_arqos),     .s03_axi_aruser  (dma_aruser),
        .s03_axi_rvalid    (dma_rvalid),    .s03_axi_rready  (dma_rready),
        .s03_axi_rid       (dma_rid),       .s03_axi_rdata   (dma_rdata),
        .s03_axi_rresp     (dma_rresp),     .s03_axi_rlast   (dma_rlast),
        .s03_axi_ruser     (dma_ruser),
        // M00 = IMEM
        .m00_axi_awvalid   (m00_awvalid),   .m00_axi_awready (m00_awready),
        .m00_axi_awid      (m00_awid),      .m00_axi_awaddr  (m00_awaddr),
        .m00_axi_awlen     (m00_awlen),     .m00_axi_awsize  (m00_awsize),
        .m00_axi_awburst   (m00_awburst),   .m00_axi_awlock  (m00_awlock),
        .m00_axi_awcache   (m00_awcache),   .m00_axi_awprot  (m00_awprot),
        .m00_axi_awqos     (m00_awqos),     .m00_axi_awregion(m00_awregion),
        .m00_axi_wvalid    (m00_wvalid),    .m00_axi_wready  (m00_wready),
        .m00_axi_wdata     (m00_wdata),     .m00_axi_wstrb   (m00_wstrb),
        .m00_axi_wlast     (m00_wlast),
        .m00_axi_bvalid    (m00_bvalid),    .m00_axi_bready  (m00_bready),
        .m00_axi_bresp     (m00_bresp),     .m00_axi_bid     (m00_bid),
        .m00_axi_arvalid   (m00_arvalid),   .m00_axi_arready (m00_arready),
        .m00_axi_arid      (m00_arid),      .m00_axi_araddr  (m00_araddr),
        .m00_axi_arlen     (m00_arlen),     .m00_axi_arsize  (m00_arsize),
        .m00_axi_arburst   (m00_arburst),   .m00_axi_arlock  (m00_arlock),
        .m00_axi_arcache   (m00_arcache),   .m00_axi_arprot  (m00_arprot),
        .m00_axi_arqos     (m00_arqos),     .m00_axi_arregion(m00_arregion),
        .m00_axi_rvalid    (m00_rvalid),    .m00_axi_rready  (m00_rready),
        .m00_axi_rid       (m00_rid),       .m00_axi_rdata   (m00_rdata),
        .m00_axi_rresp     (m00_rresp),     .m00_axi_rlast   (m00_rlast),
        // M01 = DMEM
        .m01_axi_awvalid   (m01_awvalid),   .m01_axi_awready (m01_awready),
        .m01_axi_awid      (m01_awid),      .m01_axi_awaddr  (m01_awaddr),
        .m01_axi_awlen     (m01_awlen),     .m01_axi_awsize  (m01_awsize),
        .m01_axi_awburst   (m01_awburst),   .m01_axi_awlock  (m01_awlock),
        .m01_axi_awcache   (m01_awcache),   .m01_axi_awprot  (m01_awprot),
        .m01_axi_awqos     (m01_awqos),     .m01_axi_awregion(m01_awregion),
        .m01_axi_wvalid    (m01_wvalid),    .m01_axi_wready  (m01_wready),
        .m01_axi_wdata     (m01_wdata),     .m01_axi_wstrb   (m01_wstrb),
        .m01_axi_wlast     (m01_wlast),
        .m01_axi_bvalid    (m01_bvalid),    .m01_axi_bready  (m01_bready),
        .m01_axi_bresp     (m01_bresp),     .m01_axi_bid     (m01_bid),
        .m01_axi_arvalid   (m01_arvalid),   .m01_axi_arready (m01_arready),
        .m01_axi_arid      (m01_arid),      .m01_axi_araddr  (m01_araddr),
        .m01_axi_arlen     (m01_arlen),     .m01_axi_arsize  (m01_arsize),
        .m01_axi_arburst   (m01_arburst),   .m01_axi_arlock  (m01_arlock),
        .m01_axi_arcache   (m01_arcache),   .m01_axi_arprot  (m01_arprot),
        .m01_axi_arqos     (m01_arqos),     .m01_axi_arregion(m01_arregion),
        .m01_axi_rvalid    (m01_rvalid),    .m01_axi_rready  (m01_rready),
        .m01_axi_rid       (m01_rid),       .m01_axi_rdata   (m01_rdata),
        .m01_axi_rresp     (m01_rresp),     .m01_axi_rlast   (m01_rlast),
        // M02 = UART
        .m02_axi_awvalid   (m02_awvalid),   .m02_axi_awready (m02_awready),
        .m02_axi_awid      (m02_awid),      .m02_axi_awaddr  (m02_awaddr),
        .m02_axi_awlen     (m02_awlen),     .m02_axi_awsize  (m02_awsize),
        .m02_axi_awburst   (m02_awburst),   .m02_axi_awlock  (m02_awlock),
        .m02_axi_awcache   (m02_awcache),   .m02_axi_awprot  (m02_awprot),
        .m02_axi_awqos     (m02_awqos),     .m02_axi_awregion(m02_awregion),
        .m02_axi_wvalid    (m02_wvalid),    .m02_axi_wready  (m02_wready),
        .m02_axi_wdata     (m02_wdata),     .m02_axi_wstrb   (m02_wstrb),
        .m02_axi_wlast     (m02_wlast),
        .m02_axi_bvalid    (m02_bvalid),    .m02_axi_bready  (m02_bready),
        .m02_axi_bresp     (m02_bresp),     .m02_axi_bid     (m02_bid),
        .m02_axi_arvalid   (m02_arvalid),   .m02_axi_arready (m02_arready),
        .m02_axi_arid      (m02_arid),      .m02_axi_araddr  (m02_araddr),
        .m02_axi_arlen     (m02_arlen),     .m02_axi_arsize  (m02_arsize),
        .m02_axi_arburst   (m02_arburst),   .m02_axi_arlock  (m02_arlock),
        .m02_axi_arcache   (m02_arcache),   .m02_axi_arprot  (m02_arprot),
        .m02_axi_arqos     (m02_arqos),     .m02_axi_arregion(m02_arregion),
        .m02_axi_rvalid    (m02_rvalid),    .m02_axi_rready  (m02_rready),
        .m02_axi_rid       (m02_rid),       .m02_axi_rdata   (m02_rdata),
        .m02_axi_rresp     (m02_rresp),     .m02_axi_rlast   (m02_rlast),
        // M03 = Timer
        .m03_axi_awvalid   (m03_awvalid),   .m03_axi_awready (m03_awready),
        .m03_axi_awid      (m03_awid),      .m03_axi_awaddr  (m03_awaddr),
        .m03_axi_awlen     (m03_awlen),     .m03_axi_awsize  (m03_awsize),
        .m03_axi_awburst   (m03_awburst),   .m03_axi_awlock  (m03_awlock),
        .m03_axi_awcache   (m03_awcache),   .m03_axi_awprot  (m03_awprot),
        .m03_axi_awqos     (m03_awqos),     .m03_axi_awregion(m03_awregion),
        .m03_axi_wvalid    (m03_wvalid),    .m03_axi_wready  (m03_wready),
        .m03_axi_wdata     (m03_wdata),     .m03_axi_wstrb   (m03_wstrb),
        .m03_axi_wlast     (m03_wlast),
        .m03_axi_bvalid    (m03_bvalid),    .m03_axi_bready  (m03_bready),
        .m03_axi_bresp     (m03_bresp),     .m03_axi_bid     (m03_bid),
        .m03_axi_arvalid   (m03_arvalid),   .m03_axi_arready (m03_arready),
        .m03_axi_arid      (m03_arid),      .m03_axi_araddr  (m03_araddr),
        .m03_axi_arlen     (m03_arlen),     .m03_axi_arsize  (m03_arsize),
        .m03_axi_arburst   (m03_arburst),   .m03_axi_arlock  (m03_arlock),
        .m03_axi_arcache   (m03_arcache),   .m03_axi_arprot  (m03_arprot),
        .m03_axi_arqos     (m03_arqos),     .m03_axi_arregion(m03_arregion),
        .m03_axi_rvalid    (m03_rvalid),    .m03_axi_rready  (m03_rready),
        .m03_axi_rid       (m03_rid),       .m03_axi_rdata   (m03_rdata),
        .m03_axi_rresp     (m03_rresp),     .m03_axi_rlast   (m03_rlast),
        // M04 = GPIO
        .m04_axi_awvalid   (m04_awvalid),   .m04_axi_awready (m04_awready),
        .m04_axi_awid      (m04_awid),      .m04_axi_awaddr  (m04_awaddr),
        .m04_axi_awlen     (m04_awlen),     .m04_axi_awsize  (m04_awsize),
        .m04_axi_awburst   (m04_awburst),   .m04_axi_awlock  (m04_awlock),
        .m04_axi_awcache   (m04_awcache),   .m04_axi_awprot  (m04_awprot),
        .m04_axi_awqos     (m04_awqos),     .m04_axi_awregion(m04_awregion),
        .m04_axi_wvalid    (m04_wvalid),    .m04_axi_wready  (m04_wready),
        .m04_axi_wdata     (m04_wdata),     .m04_axi_wstrb   (m04_wstrb),
        .m04_axi_wlast     (m04_wlast),
        .m04_axi_bvalid    (m04_bvalid),    .m04_axi_bready  (m04_bready),
        .m04_axi_bresp     (m04_bresp),     .m04_axi_bid     (m04_bid),
        .m04_axi_arvalid   (m04_arvalid),   .m04_axi_arready (m04_arready),
        .m04_axi_arid      (m04_arid),      .m04_axi_araddr  (m04_araddr),
        .m04_axi_arlen     (m04_arlen),     .m04_axi_arsize  (m04_arsize),
        .m04_axi_arburst   (m04_arburst),   .m04_axi_arlock  (m04_arlock),
        .m04_axi_arcache   (m04_arcache),   .m04_axi_arprot  (m04_arprot),
        .m04_axi_arqos     (m04_arqos),     .m04_axi_arregion(m04_arregion),
        .m04_axi_rvalid    (m04_rvalid),    .m04_axi_rready  (m04_rready),
        .m04_axi_rid       (m04_rid),       .m04_axi_rdata   (m04_rdata),
        .m04_axi_rresp     (m04_rresp),     .m04_axi_rlast   (m04_rlast),
        // M05 = RLE
        .m05_axi_awvalid   (m05_awvalid),   .m05_axi_awready (m05_awready),
        .m05_axi_awid      (m05_awid),      .m05_axi_awaddr  (m05_awaddr),
        .m05_axi_awlen     (m05_awlen),     .m05_axi_awsize  (m05_awsize),
        .m05_axi_awburst   (m05_awburst),   .m05_axi_awlock  (m05_awlock),
        .m05_axi_awcache   (m05_awcache),   .m05_axi_awprot  (m05_awprot),
        .m05_axi_awqos     (m05_awqos),     .m05_axi_awregion(m05_awregion),
        .m05_axi_wvalid    (m05_wvalid),    .m05_axi_wready  (m05_wready),
        .m05_axi_wdata     (m05_wdata),     .m05_axi_wstrb   (m05_wstrb),
        .m05_axi_wlast     (m05_wlast),
        .m05_axi_bvalid    (m05_bvalid),    .m05_axi_bready  (m05_bready),
        .m05_axi_bresp     (m05_bresp),     .m05_axi_bid     (m05_bid),
        .m05_axi_arvalid   (m05_arvalid),   .m05_axi_arready (m05_arready),
        .m05_axi_arid      (m05_arid),      .m05_axi_araddr  (m05_araddr),
        .m05_axi_arlen     (m05_arlen),     .m05_axi_arsize  (m05_arsize),
        .m05_axi_arburst   (m05_arburst),   .m05_axi_arlock  (m05_arlock),
        .m05_axi_arcache   (m05_arcache),   .m05_axi_arprot  (m05_arprot),
        .m05_axi_arqos     (m05_arqos),     .m05_axi_arregion(m05_arregion),
        .m05_axi_rvalid    (m05_rvalid),    .m05_axi_rready  (m05_rready),
        .m05_axi_rid       (m05_rid),       .m05_axi_rdata   (m05_rdata),
        .m05_axi_rresp     (m05_rresp),     .m05_axi_rlast   (m05_rlast),
        // M06 = DMA stub
        .m06_axi_awvalid   (m06_awvalid),   .m06_axi_awready (m06_awready),
        .m06_axi_awid      (m06_awid),      .m06_axi_awaddr  (m06_awaddr),
        .m06_axi_awlen     (m06_awlen),     .m06_axi_awsize  (m06_awsize),
        .m06_axi_awburst   (m06_awburst),   .m06_axi_awlock  (m06_awlock),
        .m06_axi_awcache   (m06_awcache),   .m06_axi_awprot  (m06_awprot),
        .m06_axi_awqos     (m06_awqos),     .m06_axi_awregion(m06_awregion),
        .m06_axi_wvalid    (m06_wvalid),    .m06_axi_wready  (m06_wready),
        .m06_axi_wdata     (m06_wdata),     .m06_axi_wstrb   (m06_wstrb),
        .m06_axi_wlast     (m06_wlast),
        .m06_axi_bvalid    (m06_bvalid),    .m06_axi_bready  (m06_bready),
        .m06_axi_bresp     (m06_bresp),     .m06_axi_bid     (m06_bid),
        .m06_axi_arvalid   (m06_arvalid),   .m06_axi_arready (m06_arready),
        .m06_axi_arid      (m06_arid),      .m06_axi_araddr  (m06_araddr),
        .m06_axi_arlen     (m06_arlen),     .m06_axi_arsize  (m06_arsize),
        .m06_axi_arburst   (m06_arburst),   .m06_axi_arlock  (m06_arlock),
        .m06_axi_arcache   (m06_arcache),   .m06_axi_arprot  (m06_arprot),
        .m06_axi_arqos     (m06_arqos),     .m06_axi_arregion(m06_arregion),
        .m06_axi_rvalid    (m06_rvalid),    .m06_axi_rready  (m06_rready),
        .m06_axi_rid       (m06_rid),       .m06_axi_rdata   (m06_rdata),
        .m06_axi_rresp     (m06_rresp),     .m06_axi_rlast   (m06_rlast),
        // M07 = CRC
        .m07_axi_awvalid   (m07_awvalid),   .m07_axi_awready (m07_awready),
        .m07_axi_awid      (m07_awid),      .m07_axi_awaddr  (m07_awaddr),
        .m07_axi_awlen     (m07_awlen),     .m07_axi_awsize  (m07_awsize),
        .m07_axi_awburst   (m07_awburst),   .m07_axi_awlock  (m07_awlock),
        .m07_axi_awcache   (m07_awcache),   .m07_axi_awprot  (m07_awprot),
        .m07_axi_awqos     (m07_awqos),     .m07_axi_awregion(m07_awregion),
        .m07_axi_wvalid    (m07_wvalid),    .m07_axi_wready  (m07_wready),
        .m07_axi_wdata     (m07_wdata),     .m07_axi_wstrb   (m07_wstrb),
        .m07_axi_wlast     (m07_wlast),
        .m07_axi_bvalid    (m07_bvalid),    .m07_axi_bready  (m07_bready),
        .m07_axi_bresp     (m07_bresp),     .m07_axi_bid     (m07_bid),
        .m07_axi_arvalid   (m07_arvalid),   .m07_axi_arready (m07_arready),
        .m07_axi_arid      (m07_arid),      .m07_axi_araddr  (m07_araddr),
        .m07_axi_arlen     (m07_arlen),     .m07_axi_arsize  (m07_arsize),
        .m07_axi_arburst   (m07_arburst),   .m07_axi_arlock  (m07_arlock),
        .m07_axi_arcache   (m07_arcache),   .m07_axi_arprot  (m07_arprot),
        .m07_axi_arqos     (m07_arqos),     .m07_axi_arregion(m07_arregion),
        .m07_axi_rvalid    (m07_rvalid),    .m07_axi_rready  (m07_rready),
        .m07_axi_rid       (m07_rid),       .m07_axi_rdata   (m07_rdata),
        .m07_axi_rresp     (m07_rresp),     .m07_axi_rlast   (m07_rlast)
    );

    // =========================================================================
    // Instruction Memory (IMEM) — Simple AXI4-Lite SRAM (0x0000_0000 & 0x8000_0000)
    // =========================================================================
    soc_sram #(
        .DEPTH     (IMEM_DEPTH),
        .BASE_ADDR (32'h0000_0000)
    ) u_imem (
        .clk      (clk),     .rst_n    (rst_n),
        .awvalid  (m00_awvalid), .awready (m00_awready),
        .awaddr   (m00_awaddr),  .awlen   (m00_awlen),
        .wvalid   (m00_wvalid),  .wready  (m00_wready),
        .wdata    (m00_wdata),   .wstrb   (m00_wstrb),  .wlast(m00_wlast),
        .bvalid   (m00_bvalid),  .bready  (m00_bready),
        .bresp    (m00_bresp),   .bid     (m00_bid),     .bawid(m00_awid),
        .arvalid  (m00_arvalid), .arready (m00_arready),
        .araddr   (m00_araddr),  .arlen   (m00_arlen),   .arid (m00_arid),
        .rvalid   (m00_rvalid),  .rready  (m00_rready),
        .rdata    (m00_rdata),   .rresp   (m00_rresp),
        .rid      (m00_rid),     .rlast   (m00_rlast)
    );

    // =========================================================================
    // Data Memory (DMEM) — 0x0001_0000 – 0x0002_FFFF (128 KB)
    // =========================================================================
    soc_sram #(
        .DEPTH     (DMEM_DEPTH),
        .BASE_ADDR (32'h0001_0000)
    ) u_dmem (
        .clk      (clk),     .rst_n    (rst_n),
        .awvalid  (m01_awvalid), .awready (m01_awready),
        .awaddr   (m01_awaddr),  .awlen   (m01_awlen),
        .wvalid   (m01_wvalid),  .wready  (m01_wready),
        .wdata    (m01_wdata),   .wstrb   (m01_wstrb),  .wlast(m01_wlast),
        .bvalid   (m01_bvalid),  .bready  (m01_bready),
        .bresp    (m01_bresp),   .bid     (m01_bid),     .bawid(m01_awid),
        .arvalid  (m01_arvalid), .arready (m01_arready),
        .araddr   (m01_araddr),  .arlen   (m01_arlen),   .arid (m01_arid),
        .rvalid   (m01_rvalid),  .rready  (m01_rready),
        .rdata    (m01_rdata),   .rresp   (m01_rresp),
        .rid      (m01_rid),     .rlast   (m01_rlast)
    );

    // =========================================================================
    // UART (M02) — axi_uart_top uses different port naming (axi_*_i / *_o)
    // =========================================================================
    axi_uart_top #(
        .AXI_DATA_WIDTH (32),
        .AXI_ADDR_WIDTH (32),
        .AXI_ID_WIDTH   (8)
    ) u_uart (
        .fixed_clk_i    (clk),
        .axi_aclk_i     (clk),
        .axi_aresetn_i  (rst_n),
        .axi_arid_i     (m02_arid),     .axi_araddr_i   (m02_araddr),
        .axi_arvalid_i  (m02_arvalid),  .axi_arready_o  (m02_arready),
        .axi_rid_o      (m02_rid),      .axi_rdata_o    (m02_rdata),
        .axi_rresp_o    (m02_rresp),    .axi_rlast_o    (m02_rlast),
        .axi_rvalid_o   (m02_rvalid),   .axi_rready_i   (m02_rready),
        .axi_awid_i     (m02_awid),     .axi_awaddr_i   (m02_awaddr),
        .axi_awvalid_i  (m02_awvalid),  .axi_awready_o  (m02_awready),
        .axi_wdata_i    (m02_wdata),    .axi_wstrb_i    (m02_wstrb),
        .axi_wvalid_i   (m02_wvalid),   .axi_wready_o   (m02_wready),
        .axi_bid_o      (m02_bid),      .axi_bresp_o    (m02_bresp),
        .axi_bvalid_o   (m02_bvalid),   .axi_bready_i   (m02_bready),
        .uart_rx_i      (uart_rx),
        .uart_tx_o      (uart_tx)
    );

    // =========================================================================
    // Timer (M03)
    // =========================================================================
    timer_top u_timer (
        .clk          (clk),
        .rst_n        (rst_n),
        .timer_irq    (timer_irq),
        .s_axi_awaddr (m03_awaddr),  .s_axi_awprot  (m03_awprot),
        .s_axi_awvalid(m03_awvalid), .s_axi_awready (m03_awready),
        .s_axi_wdata  (m03_wdata),   .s_axi_wstrb   (m03_wstrb),
        .s_axi_wvalid (m03_wvalid),  .s_axi_wready  (m03_wready),
        .s_axi_bresp  (m03_bresp),   .s_axi_bvalid  (m03_bvalid),
        .s_axi_bready (m03_bready),
        .s_axi_araddr (m03_araddr),  .s_axi_arprot  (m03_arprot),
        .s_axi_arvalid(m03_arvalid), .s_axi_arready (m03_arready),
        .s_axi_rdata  (m03_rdata),   .s_axi_rresp   (m03_rresp),
        .s_axi_rvalid (m03_rvalid),  .s_axi_rready  (m03_rready)
    );
    // Timer/GPIO/CRC do not use ID or RLAST from the AXI4-Lite perspective;
    // tie off unused inputs from interconnect
    assign m03_bid   = m03_awid;
    assign m03_rid   = m03_arid;
    assign m03_rlast = 1'b1;

    // =========================================================================
    // GPIO (M04)
    // =========================================================================
    gpio_top u_gpio (
        .clk          (clk),
        .rst_n        (rst_n),
        .gpio_i       (gpio_i),
        .gpio_o       (gpio_o),
        .gpio_oe      (gpio_oe),
        .gpio_irq     (gpio_irq),
        .s_axi_awaddr (m04_awaddr),  .s_axi_awprot  (m04_awprot),
        .s_axi_awvalid(m04_awvalid), .s_axi_awready (m04_awready),
        .s_axi_wdata  (m04_wdata),   .s_axi_wstrb   (m04_wstrb),
        .s_axi_wvalid (m04_wvalid),  .s_axi_wready  (m04_wready),
        .s_axi_bresp  (m04_bresp),   .s_axi_bvalid  (m04_bvalid),
        .s_axi_bready (m04_bready),
        .s_axi_araddr (m04_araddr),  .s_axi_arprot  (m04_arprot),
        .s_axi_arvalid(m04_arvalid), .s_axi_arready (m04_arready),
        .s_axi_rdata  (m04_rdata),   .s_axi_rresp   (m04_rresp),
        .s_axi_rvalid (m04_rvalid),  .s_axi_rready  (m04_rready)
    );
    assign m04_bid   = m04_awid;
    assign m04_rid   = m04_arid;
    assign m04_rlast = 1'b1;

    // =========================================================================
    // RLE Accelerator (M05)
    // =========================================================================
    rle_top u_rle (
        .clk          (clk),
        .rst          (rst),
        .s_axi_awaddr (m05_awaddr),  .s_axi_awprot  (m05_awprot),
        .s_axi_awvalid(m05_awvalid), .s_axi_awready (m05_awready),
        .s_axi_wdata  (m05_wdata),   .s_axi_wstrb   (m05_wstrb),
        .s_axi_wvalid (m05_wvalid),  .s_axi_wready  (m05_wready),
        .s_axi_bresp  (m05_bresp),   .s_axi_bvalid  (m05_bvalid),
        .s_axi_bready (m05_bready),
        .s_axi_araddr (m05_araddr),  .s_axi_arprot  (m05_arprot),
        .s_axi_arvalid(m05_arvalid), .s_axi_arready (m05_arready),
        .s_axi_rdata  (m05_rdata),   .s_axi_rresp   (m05_rresp),
        .s_axi_rvalid (m05_rvalid),  .s_axi_rready  (m05_rready),
        .irq          (rle_irq)
    );
    assign m05_bid   = m05_awid;
    assign m05_rid   = m05_arid;
    assign m05_rlast = 1'b1;

    // =========================================================================
    // DMA Controller IP (M06) & Master (S03)
    // =========================================================================
    dma_top #(
        .ADDR_WIDTH     (32),
        .DATA_WIDTH     (32),
        .STRB_WIDTH     (4),
        .ID_WIDTH       (8),
        .AXI_ID         (8'h30),
        .BUFFER_DEPTH   (256),
        .TIMEOUT_CYCLES (100000)
    ) u_dma (
        .clk            (clk),
        .rst_n          (rst_n),

        // AXI4-Lite Slave Register Interface (from M06 of crossbar)
        .s_axi_awid     (m06_awid),
        .s_axi_awaddr   (m06_awaddr),
        .s_axi_awprot   (m06_awprot),
        .s_axi_awvalid  (m06_awvalid),
        .s_axi_awready  (m06_awready),

        .s_axi_wdata    (m06_wdata),
        .s_axi_wstrb    (m06_wstrb),
        .s_axi_wvalid   (m06_wvalid),
        .s_axi_wready   (m06_wready),

        .s_axi_bid      (m06_bid),
        .s_axi_bresp    (m06_bresp),
        .s_axi_bvalid   (m06_bvalid),
        .s_axi_bready   (m06_bready),

        .s_axi_arid     (m06_arid),
        .s_axi_araddr   (m06_araddr),
        .s_axi_arprot   (m06_arprot),
        .s_axi_arvalid  (m06_arvalid),
        .s_axi_arready  (m06_arready),

        .s_axi_rid      (m06_rid),
        .s_axi_rdata    (m06_rdata),
        .s_axi_rresp    (m06_rresp),
        .s_axi_rlast    (m06_rlast),
        .s_axi_rvalid   (m06_rvalid),
        .s_axi_rready   (m06_rready),

        // AXI4 Master Engine Interface (to S03 of crossbar)
        .m_axi_awvalid  (dma_awvalid),
        .m_axi_awready  (dma_awready),
        .m_axi_awid     (dma_awid),
        .m_axi_awaddr   (dma_awaddr),
        .m_axi_awlen    (dma_awlen),
        .m_axi_awsize   (dma_awsize),
        .m_axi_awburst  (dma_awburst),
        .m_axi_awlock   (dma_awlock),
        .m_axi_awcache  (dma_awcache),
        .m_axi_awprot   (dma_awprot),
        .m_axi_awqos    (dma_awqos),
        .m_axi_awregion (dma_awregion),
        .m_axi_awuser   (dma_awuser),

        .m_axi_wvalid   (dma_wvalid),
        .m_axi_wready   (dma_wready),
        .m_axi_wdata    (dma_wdata),
        .m_axi_wstrb    (dma_wstrb),
        .m_axi_wlast    (dma_wlast),
        .m_axi_wuser    (dma_wuser),

        .m_axi_bvalid   (dma_bvalid),
        .m_axi_bready   (dma_bready),
        .m_axi_bresp    (dma_bresp),
        .m_axi_bid      (dma_bid),
        .m_axi_buser    (dma_buser),

        .m_axi_arvalid  (dma_arvalid),
        .m_axi_arready  (dma_arready),
        .m_axi_arid     (dma_arid),
        .m_axi_araddr   (dma_araddr),
        .m_axi_arlen    (dma_arlen),
        .m_axi_arsize   (dma_arsize),
        .m_axi_arburst  (dma_arburst),
        .m_axi_arlock   (dma_arlock),
        .m_axi_arcache  (dma_arcache),
        .m_axi_arprot   (dma_arprot),
        .m_axi_arqos    (dma_arqos),
        .m_axi_arregion (dma_arregion),
        .m_axi_aruser   (dma_aruser),

        .m_axi_rvalid   (dma_rvalid),
        .m_axi_rready   (dma_rready),
        .m_axi_rid      (dma_rid),
        .m_axi_rdata    (dma_rdata),
        .m_axi_rresp    (dma_rresp),
        .m_axi_rlast    (dma_rlast),
        .m_axi_ruser    (dma_ruser),

        // Interrupt Output
        .irq_o          (dma_irq)
    );

    // =========================================================================
    // CRC-32 Engine (M07)
    // =========================================================================
    crc32_top u_crc (
        .clk          (clk),
        .rst_n        (rst_n),
        .s_axi_awaddr (m07_awaddr),  .s_axi_awprot  (m07_awprot),
        .s_axi_awvalid(m07_awvalid), .s_axi_awready (m07_awready),
        .s_axi_wdata  (m07_wdata),   .s_axi_wstrb   (m07_wstrb),
        .s_axi_wvalid (m07_wvalid),  .s_axi_wready  (m07_wready),
        .s_axi_bresp  (m07_bresp),   .s_axi_bvalid  (m07_bvalid),
        .s_axi_bready (m07_bready),
        .s_axi_araddr (m07_araddr),  .s_axi_arprot  (m07_arprot),
        .s_axi_arvalid(m07_arvalid), .s_axi_arready (m07_arready),
        .s_axi_rdata  (m07_rdata),   .s_axi_rresp   (m07_rresp),
        .s_axi_rvalid (m07_rvalid),  .s_axi_rready  (m07_rready)
    );
    assign m07_bid   = m07_awid;
    assign m07_rid   = m07_arid;
    assign m07_rlast = 1'b1;

endmodule


// =============================================================================
// soc_sram — simple AXI4 SRAM slave model for IMEM / DMEM
// Supports single-beat and burst (INCR) transactions with byte strobes.
// =============================================================================
module soc_sram #(
    parameter DEPTH            = 16384,        // Number of 32-bit words
    parameter [31:0] BASE_ADDR = 32'h0000_0000 // Base address subtracted before indexing
)(
    input  wire        clk,
    input  wire        rst_n,
    // Write address
    input  wire        awvalid,
    output reg         awready,
    input  wire [31:0] awaddr,
    input  wire [7:0]  awlen,
    // Write data
    input  wire        wvalid,
    output reg         wready,
    input  wire [31:0] wdata,
    input  wire [3:0]  wstrb,
    input  wire        wlast,
    // Write response
    output reg         bvalid,
    input  wire        bready,
    output wire [1:0]  bresp,
    output wire [7:0]  bid,
    input  wire [7:0]  bawid,
    // Read address
    input  wire        arvalid,
    output reg         arready,
    input  wire [31:0] araddr,
    input  wire [7:0]  arlen,
    input  wire [7:0]  arid,
    // Read data
    output reg         rvalid,
    input  wire        rready,
    output reg  [31:0] rdata,
    output wire [1:0]  rresp,
    output wire [7:0]  rid,
    output reg         rlast
);
    // Memory array
    reg [31:0] mem [0:DEPTH-1];

    // Local word indexing masked to memory depth
    localparam ADDR_BITS = (DEPTH > 1) ? $clog2(DEPTH) : 1;

    // Internal state
    reg [31:0] wr_addr;
    reg [7:0]  wr_beats_left;
    reg        wr_addr_accepted;
    reg [7:0]  wr_id_reg;

    reg [31:0] rd_addr;
    reg [7:0]  rd_beats_left;
    reg        rd_addr_accepted;
    reg [7:0]  rd_id_reg;

    wire [31:0]          aw_off       = awaddr - BASE_ADDR;
    wire [31:0]          wr_off       = wr_addr - BASE_ADDR;
    wire [31:0]          rd_off       = rd_addr - BASE_ADDR;
    wire [31:0]          next_rd_addr = rd_addr + 32'd4;
    wire [31:0]          next_rd_off  = next_rd_addr - BASE_ADDR;

    wire [ADDR_BITS-1:0] aw_idx       = aw_off[ADDR_BITS+1 : 2];
    wire [ADDR_BITS-1:0] wr_idx       = wr_off[ADDR_BITS+1 : 2];
    wire [ADDR_BITS-1:0] rd_idx       = rd_off[ADDR_BITS+1 : 2];
    wire [ADDR_BITS-1:0] next_rd_idx  = next_rd_off[ADDR_BITS+1 : 2];

    assign bresp = 2'b00;   // OKAY
    assign bid   = wr_id_reg;
    assign rresp = 2'b00;
    assign rid   = rd_id_reg;

    // ---- Write path ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            awready          <= 1'b1;
            wready           <= 1'b1;
            bvalid           <= 1'b0;
            wr_addr_accepted <= 1'b0;
            wr_beats_left    <= 8'h0;
            wr_id_reg        <= 8'h0;
            wr_addr          <= 32'h0;
        end else begin
            // Write response handshake
            if (bvalid && bready) begin
                bvalid  <= 1'b0;
                awready <= 1'b1;
                wready  <= 1'b1;
            end

            // Write address & data handling
            if (awvalid && awready && wvalid && wready) begin
                // Simultaneous AW and W handshake
                if (wstrb[0]) mem[aw_idx][7:0]   <= wdata[7:0];
                if (wstrb[1]) mem[aw_idx][15:8]  <= wdata[15:8];
                if (wstrb[2]) mem[aw_idx][23:16] <= wdata[23:16];
                if (wstrb[3]) mem[aw_idx][31:24] <= wdata[31:24];

                if (awlen == 8'd0 || wlast) begin
                    wr_addr_accepted <= 1'b0;
                    awready          <= 1'b0;
                    wready           <= 1'b0;
                    bvalid           <= 1'b1;
                    wr_id_reg        <= bawid;
                end else begin
                    wr_addr          <= awaddr + 32'd4;
                    wr_beats_left    <= awlen - 8'd1;
                    wr_addr_accepted <= 1'b1;
                    wr_id_reg        <= bawid;
                    awready          <= 1'b0;
                    wready           <= 1'b1;
                end
            end else if (awvalid && awready) begin
                // AW arrived before W
                wr_addr          <= awaddr;
                wr_beats_left    <= awlen;
                wr_addr_accepted <= 1'b1;
                wr_id_reg        <= bawid;
                awready          <= 1'b0;
                wready           <= 1'b1;
            end else if (wvalid && wready && wr_addr_accepted) begin
                // W arrived after AW (or burst beat 1..N)
                if (wstrb[0]) mem[wr_idx][7:0]   <= wdata[7:0];
                if (wstrb[1]) mem[wr_idx][15:8]  <= wdata[15:8];
                if (wstrb[2]) mem[wr_idx][23:16] <= wdata[23:16];
                if (wstrb[3]) mem[wr_idx][31:24] <= wdata[31:24];

                wr_addr <= wr_addr + 32'd4;
                if (wr_beats_left == 8'd0 || wlast) begin
                    wr_addr_accepted <= 1'b0;
                    wready           <= 1'b0;
                    bvalid           <= 1'b1;
                end else begin
                    wr_beats_left <= wr_beats_left - 8'd1;
                end
            end
        end
    end

    // ---- Read path ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            arready          <= 1'b1;
            rvalid           <= 1'b0;
            rlast            <= 1'b0;
            rd_addr_accepted <= 1'b0;
            rd_beats_left    <= 8'h0;
            rd_id_reg        <= 8'h0;
            rdata            <= 32'h0;
        end else begin
            if (arvalid && arready) begin
                rd_addr          <= araddr;
                rd_beats_left    <= arlen;
                rd_id_reg        <= arid;
                rd_addr_accepted <= 1'b1;
                arready          <= 1'b0;
            end
            if (rd_addr_accepted && !rvalid) begin
                rdata  <= mem[rd_idx];
                rlast  <= (rd_beats_left == 0);
                rvalid <= 1'b1;
            end
            if (rvalid && rready) begin
                if (rd_beats_left == 0) begin
                    rvalid           <= 1'b0;
                    rlast            <= 1'b0;
                    rd_addr_accepted <= 1'b0;
                    arready          <= 1'b1;
                end else begin
                    rd_addr       <= next_rd_addr;
                    rd_beats_left <= rd_beats_left - 1;
                    rdata         <= mem[next_rd_idx];
                    rlast         <= (rd_beats_left == 1);
                end
            end
        end
    end

endmodule

`default_nettype wire
