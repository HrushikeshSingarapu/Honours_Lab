// =============================================================================
// soc_core_top.sv — RISC-V SoC Top-Level with Integrated VeeR EL2 Core
//
// Hierarchy:
//   soc_core_top
//   ├── el2_veer_wrapper  (VeeR EL2 32-bit RISC-V Core, 64-bit AXI4 interfaces)
//   │   ├── DCCM SRAMs    (4 banks: ram_4096x39)
//   │   ├── ICCM SRAMs    (4 banks: ram_4096x39)
//   │   └── ICache SRAMs  (2 banks: ram_be_512x142, Tag: ram_be_128x52)
//   └── soc_top           (32-bit AXI SoC Infrastructure)
//       ├── axi64_to_32_bridge [3x] (IFU, LSU, SB)
//       ├── axi_interconnect_wrap_3x8
//       ├── IMEM (256 kB, aliased at 0x0000_0000 and 0x8000_0000)
//       ├── DMEM (256 kB, at 0x0004_0000)
//       ├── UART, Timer, GPIO, RLE, CRC-32
//
// Reset & Boot Convention:
//   Core resets at 0x8000_0000 (rst_vec = 31'h4000_0000).
//   IFU issues 64-bit AXI fetch requests at 0x8000_0000.
//   u_soc's IFU bridge converts to 32-bit bursts, routed to IMEM.
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

module soc_core_top
    import el2_pkg::*;
#(
    `include "el2_param.vh",
    parameter IMEM_DEPTH = 65536,
    parameter DMEM_DEPTH = 65536
)(
    input  wire        clk,
    input  wire        rst_n,

    // External peripheral I/O
    input  wire        uart_rx,
    output wire        uart_tx,
    input  wire [31:0] gpio_i,
    output wire [31:0] gpio_o,
    output wire [31:0] gpio_oe,

    // Core trace outputs (for debug / testbench verification)
    output wire [31:0] trace_rv_i_insn_ip,
    output wire [31:0] trace_rv_i_address_ip,
    output wire        trace_rv_i_valid_ip,
    output wire        trace_rv_i_exception_ip,
    output wire [ 4:0] trace_rv_i_ecause_ip,
    output wire        trace_rv_i_interrupt_ip,
    output wire [31:0] trace_rv_i_tval_ip,

    // Interrupt status
    output wire        gpio_irq,
    output wire        timer_irq,
    output wire        rle_irq
);

    // =========================================================================
    // Core Memory Export Interface & Internal SRAM Arrays
    // =========================================================================
    el2_mem_if el2_mem_export ();

    // DCCM SRAM Banks (4 banks x 4096 words x 39 bits)
    wire [pt.DCCM_NUM_BANKS-1:0][pt.DCCM_FDATA_WIDTH-1:0] dccm_bank_fdout;
    for (genvar i = 0; i < pt.DCCM_NUM_BANKS; i++) begin : gen_dccm_banks
        assign el2_mem_export.dccm_bank_dout[i] = dccm_bank_fdout[i][31:0];
        assign el2_mem_export.dccm_bank_ecc[i]  = dccm_bank_fdout[i][38:32];

        ram_4096x39 dccm_bank (
            .CLK      (el2_mem_export.clk),
            .ME       (el2_mem_export.dccm_clken[i]),
            .WE       (el2_mem_export.dccm_wren_bank[i]),
            .ADR      (el2_mem_export.dccm_addr_bank[i]),
            .D        ({el2_mem_export.dccm_wr_ecc_bank[i], el2_mem_export.dccm_wr_data_bank[i]}),
            .Q        (dccm_bank_fdout[i]),
            .ROP      (),
            .TEST1    (1'b0),
            .RME      (1'b0),
            .RM       (4'b0000),
            .LS       (1'b0),
            .DS       (1'b0),
            .SD       (1'b0),
            .TEST_RNM (1'b0),
            .BC1      (1'b0),
            .BC2      (1'b0)
        );
    end

    // ICCM SRAM Banks (4 banks x 4096 words x 39 bits)
    wire [pt.ICCM_NUM_BANKS-1:0][pt.ICCM_ECC_WIDTH+32-1:0] iccm_bank_fdout;
    for (genvar i = 0; i < pt.ICCM_NUM_BANKS; i++) begin : gen_iccm_banks
        assign el2_mem_export.iccm_bank_dout[i] = iccm_bank_fdout[i][31:0];
        assign el2_mem_export.iccm_bank_ecc[i]  = iccm_bank_fdout[i][38:32];

        ram_4096x39 iccm_bank (
            .CLK      (el2_mem_export.clk),
            .ME       (el2_mem_export.iccm_clken[i]),
            .WE       (el2_mem_export.iccm_wren_bank[i]),
            .ADR      (el2_mem_export.iccm_addr_bank[i]),
            .D        ({el2_mem_export.iccm_bank_wr_ecc[i], el2_mem_export.iccm_bank_wr_data[i]}),
            .Q        (iccm_bank_fdout[i]),
            .ROP      (),
            .TEST1    (1'b0),
            .RME      (1'b0),
            .RM       (4'b0000),
            .LS       (1'b0),
            .DS       (1'b0),
            .SD       (1'b0),
            .TEST_RNM (1'b0),
            .BC1      (1'b0),
            .BC2      (1'b0)
        );
    end

    // ICache Data and Tag SRAMs
    assign el2_mem_export.ic_tag_data_raw_pre = '0;
    assign el2_mem_export.wb_dout_pre_up      = '0;

    for (genvar k = 0; k < pt.ICACHE_BANKS_WAY; k++) begin : gen_ic_data_banks
        ram_be_512x142 ic_bank_sb_way_data (
            .CLK      (el2_mem_export.clk),
            .ME       (|el2_mem_export.ic_bank_way_clken_final[k]),
            .WE       (|el2_mem_export.ic_b_sb_wren[k]),
            .WEM      (el2_mem_export.ic_b_sb_bit_en_vec[k][141:0]),
            .D        ({pt.ICACHE_NUM_WAYS{el2_mem_export.ic_sb_wr_data[k][70:0]}}),
            .ADR      (el2_mem_export.ic_rw_addr_bank_q[k][pt.ICACHE_INDEX_HI:pt.ICACHE_DATA_INDEX_LO]),
            .Q        (el2_mem_export.wb_packeddout_pre[k]),
            .ROP      (),
            .TEST1    (1'b0),
            .RME      (1'b0),
            .RM       (4'b0000),
            .LS       (1'b0),
            .DS       (1'b0),
            .SD       (1'b0),
            .TEST_RNM (1'b0),
            .BC1      (1'b0),
            .BC2      (1'b0)
        );
    end

    ram_be_128x52 ic_way_tag (
        .CLK      (el2_mem_export.clk),
        .ME       (|el2_mem_export.ic_tag_clken_final),
        .WE       (|el2_mem_export.ic_tag_wren_q[pt.ICACHE_NUM_WAYS-1:0]),
        .WEM      (el2_mem_export.ic_tag_wren_biten_vec[51:0]),
        .D        ({pt.ICACHE_NUM_WAYS{el2_mem_export.ic_tag_wr_data[25:0]}}),
        .ADR      (el2_mem_export.ic_rw_addr_q[pt.ICACHE_INDEX_HI:pt.ICACHE_TAG_INDEX_LO]),
        .Q        (el2_mem_export.ic_tag_data_raw_packed_pre[51:0]),
        .ROP      (),
        .TEST1    (1'b0),
        .RME      (1'b0),
        .RM       (4'b0000),
        .LS       (1'b0),
        .DS       (1'b0),
        .SD       (1'b0),
        .TEST_RNM (1'b0),
        .BC1      (1'b0),
        .BC2      (1'b0)
    );

    // =========================================================================
    // AXI4 Interconnect Signals (between VeeR EL2 Core and soc_top)
    // =========================================================================

    // --- IFU AXI (Instruction Fetch Unit) ---
    wire                      ifu_axi_awvalid, ifu_axi_awready;
    wire [pt.IFU_BUS_TAG-1:0] ifu_axi_awid_core;
    wire [              31:0] ifu_axi_awaddr;
    wire [               7:0] ifu_axi_awlen;
    wire [               2:0] ifu_axi_awsize;
    wire [               1:0] ifu_axi_awburst;
    wire                      ifu_axi_awlock;
    wire [               3:0] ifu_axi_awcache;
    wire [               2:0] ifu_axi_awprot;
    wire [               3:0] ifu_axi_awqos;
    wire [               3:0] ifu_axi_awregion;
    wire                      ifu_axi_wvalid, ifu_axi_wready;
    wire [              63:0] ifu_axi_wdata;
    wire [               7:0] ifu_axi_wstrb;
    wire                      ifu_axi_wlast;
    wire                      ifu_axi_bvalid, ifu_axi_bready;
    wire [               1:0] ifu_axi_bresp;
    wire [               7:0] ifu_axi_bid_soc;
    wire                      ifu_axi_arvalid, ifu_axi_arready;
    wire [pt.IFU_BUS_TAG-1:0] ifu_axi_arid_core;
    wire [              31:0] ifu_axi_araddr;
    wire [               7:0] ifu_axi_arlen;
    wire [               2:0] ifu_axi_arsize;
    wire [               1:0] ifu_axi_arburst;
    wire                      ifu_axi_arlock;
    wire [               3:0] ifu_axi_arcache;
    wire [               2:0] ifu_axi_arprot;
    wire [               3:0] ifu_axi_arqos;
    wire [               3:0] ifu_axi_arregion;
    wire                      ifu_axi_rvalid, ifu_axi_rready;
    wire [               7:0] ifu_axi_rid_soc;
    wire [              63:0] ifu_axi_rdata;
    wire [               1:0] ifu_axi_rresp;
    wire                      ifu_axi_rlast;

    // --- LSU AXI (Load/Store Unit) ---
    wire                      lsu_axi_awvalid, lsu_axi_awready;
    wire [pt.LSU_BUS_TAG-1:0] lsu_axi_awid_core;
    wire [              31:0] lsu_axi_awaddr;
    wire [               7:0] lsu_axi_awlen;
    wire [               2:0] lsu_axi_awsize;
    wire [               1:0] lsu_axi_awburst;
    wire                      lsu_axi_awlock;
    wire [               3:0] lsu_axi_awcache;
    wire [               2:0] lsu_axi_awprot;
    wire [               3:0] lsu_axi_awqos;
    wire [               3:0] lsu_axi_awregion;
    wire                      lsu_axi_wvalid, lsu_axi_wready;
    wire [              63:0] lsu_axi_wdata;
    wire [               7:0] lsu_axi_wstrb;
    wire                      lsu_axi_wlast;
    wire                      lsu_axi_bvalid, lsu_axi_bready;
    wire [               1:0] lsu_axi_bresp;
    wire [               7:0] lsu_axi_bid_soc;
    wire                      lsu_axi_arvalid, lsu_axi_arready;
    wire [pt.LSU_BUS_TAG-1:0] lsu_axi_arid_core;
    wire [              31:0] lsu_axi_araddr;
    wire [               7:0] lsu_axi_arlen;
    wire [               2:0] lsu_axi_arsize;
    wire [               1:0] lsu_axi_arburst;
    wire                      lsu_axi_arlock;
    wire [               3:0] lsu_axi_arcache;
    wire [               2:0] lsu_axi_arprot;
    wire [               3:0] lsu_axi_arqos;
    wire [               3:0] lsu_axi_arregion;
    wire                      lsu_axi_rvalid, lsu_axi_rready;
    wire [               7:0] lsu_axi_rid_soc;
    wire [              63:0] lsu_axi_rdata;
    wire [               1:0] lsu_axi_rresp;
    wire                      lsu_axi_rlast;

    // --- SB AXI (Debug System Bus) ---
    wire                     sb_axi_awvalid, sb_axi_awready;
    wire [pt.SB_BUS_TAG-1:0] sb_axi_awid_core;
    wire [             31:0] sb_axi_awaddr;
    wire [              7:0] sb_axi_awlen;
    wire [              2:0] sb_axi_awsize;
    wire [              1:0] sb_axi_awburst;
    wire                     sb_axi_awlock;
    wire [              3:0] sb_axi_awcache;
    wire [              2:0] sb_axi_awprot;
    wire [              3:0] sb_axi_awqos;
    wire [              3:0] sb_axi_awregion;
    wire                     sb_axi_wvalid, sb_axi_wready;
    wire [             63:0] sb_axi_wdata;
    wire [              7:0] sb_axi_wstrb;
    wire                     sb_axi_wlast;
    wire                     sb_axi_bvalid, sb_axi_bready;
    wire [              1:0] sb_axi_bresp;
    wire [              7:0] sb_axi_bid_soc;
    wire                     sb_axi_arvalid, sb_axi_arready;
    wire [pt.SB_BUS_TAG-1:0] sb_axi_arid_core;
    wire [             31:0] sb_axi_araddr;
    wire [              7:0] sb_axi_arlen;
    wire [              2:0] sb_axi_arsize;
    wire [              1:0] sb_axi_arburst;
    wire                     sb_axi_arlock;
    wire [              3:0] sb_axi_arcache;
    wire [              2:0] sb_axi_arprot;
    wire [              3:0] sb_axi_arqos;
    wire [              3:0] sb_axi_arregion;
    wire                     sb_axi_rvalid, sb_axi_rready;
    wire [              7:0] sb_axi_rid_soc;
    wire [             63:0] sb_axi_rdata;
    wire [              1:0] sb_axi_rresp;
    wire                     sb_axi_rlast;

    // =========================================================================
    // Unchanged VeeR EL2 Processor Instantiation
    // =========================================================================
    el2_veer_wrapper u_core (
        .clk                    (clk),
        .rst_l                  (rst_n),
        .dbg_rst_l              (rst_n),
        .rst_vec                (31'h4000_0000), // Reset vector 0x8000_0000 >> 1
        .nmi_int                (1'b0),
        .nmi_vec                (31'h0888_8000),
        .jtag_id                (31'h0),

        // Trace
        .trace_rv_i_insn_ip     (trace_rv_i_insn_ip),
        .trace_rv_i_address_ip  (trace_rv_i_address_ip),
        .trace_rv_i_valid_ip    (trace_rv_i_valid_ip),
        .trace_rv_i_exception_ip(trace_rv_i_exception_ip),
        .trace_rv_i_ecause_ip   (trace_rv_i_ecause_ip),
        .trace_rv_i_interrupt_ip(trace_rv_i_interrupt_ip),
        .trace_rv_i_tval_ip     (trace_rv_i_tval_ip),

        // LSU AXI
        .lsu_axi_awvalid        (lsu_axi_awvalid),
        .lsu_axi_awready        (lsu_axi_awready),
        .lsu_axi_awid           (lsu_axi_awid_core),
        .lsu_axi_awaddr         (lsu_axi_awaddr),
        .lsu_axi_awregion       (lsu_axi_awregion),
        .lsu_axi_awlen          (lsu_axi_awlen),
        .lsu_axi_awsize         (lsu_axi_awsize),
        .lsu_axi_awburst        (lsu_axi_awburst),
        .lsu_axi_awlock         (lsu_axi_awlock),
        .lsu_axi_awcache        (lsu_axi_awcache),
        .lsu_axi_awprot         (lsu_axi_awprot),
        .lsu_axi_awqos          (lsu_axi_awqos),
        .lsu_axi_wvalid         (lsu_axi_wvalid),
        .lsu_axi_wready         (lsu_axi_wready),
        .lsu_axi_wdata          (lsu_axi_wdata),
        .lsu_axi_wstrb          (lsu_axi_wstrb),
        .lsu_axi_wlast          (lsu_axi_wlast),
        .lsu_axi_bvalid         (lsu_axi_bvalid),
        .lsu_axi_bready         (lsu_axi_bready),
        .lsu_axi_bresp          (lsu_axi_bresp),
        .lsu_axi_bid            (lsu_axi_bid_soc[pt.LSU_BUS_TAG-1:0]),
        .lsu_axi_arvalid        (lsu_axi_arvalid),
        .lsu_axi_arready        (lsu_axi_arready),
        .lsu_axi_arid           (lsu_axi_arid_core),
        .lsu_axi_araddr         (lsu_axi_araddr),
        .lsu_axi_arregion       (lsu_axi_arregion),
        .lsu_axi_arlen          (lsu_axi_arlen),
        .lsu_axi_arsize         (lsu_axi_arsize),
        .lsu_axi_arburst        (lsu_axi_arburst),
        .lsu_axi_arlock         (lsu_axi_arlock),
        .lsu_axi_arcache        (lsu_axi_arcache),
        .lsu_axi_arprot         (lsu_axi_arprot),
        .lsu_axi_arqos          (lsu_axi_arqos),
        .lsu_axi_rvalid         (lsu_axi_rvalid),
        .lsu_axi_rready         (lsu_axi_rready),
        .lsu_axi_rid            (lsu_axi_rid_soc[pt.LSU_BUS_TAG-1:0]),
        .lsu_axi_rdata          (lsu_axi_rdata),
        .lsu_axi_rresp          (lsu_axi_rresp),
        .lsu_axi_rlast          (lsu_axi_rlast),

        // IFU AXI
        .ifu_axi_awvalid        (ifu_axi_awvalid),
        .ifu_axi_awready        (ifu_axi_awready),
        .ifu_axi_awid           (ifu_axi_awid_core),
        .ifu_axi_awaddr         (ifu_axi_awaddr),
        .ifu_axi_awregion       (ifu_axi_awregion),
        .ifu_axi_awlen          (ifu_axi_awlen),
        .ifu_axi_awsize         (ifu_axi_awsize),
        .ifu_axi_awburst        (ifu_axi_awburst),
        .ifu_axi_awlock         (ifu_axi_awlock),
        .ifu_axi_awcache        (ifu_axi_awcache),
        .ifu_axi_awprot         (ifu_axi_awprot),
        .ifu_axi_awqos          (ifu_axi_awqos),
        .ifu_axi_wvalid         (ifu_axi_wvalid),
        .ifu_axi_wready         (ifu_axi_wready),
        .ifu_axi_wdata          (ifu_axi_wdata),
        .ifu_axi_wstrb          (ifu_axi_wstrb),
        .ifu_axi_wlast          (ifu_axi_wlast),
        .ifu_axi_bvalid         (ifu_axi_bvalid),
        .ifu_axi_bready         (ifu_axi_bready),
        .ifu_axi_bresp          (ifu_axi_bresp),
        .ifu_axi_bid            (ifu_axi_bid_soc[pt.IFU_BUS_TAG-1:0]),
        .ifu_axi_arvalid        (ifu_axi_arvalid),
        .ifu_axi_arready        (ifu_axi_arready),
        .ifu_axi_arid           (ifu_axi_arid_core),
        .ifu_axi_araddr         (ifu_axi_araddr),
        .ifu_axi_arregion       (ifu_axi_arregion),
        .ifu_axi_arlen          (ifu_axi_arlen),
        .ifu_axi_arsize         (ifu_axi_arsize),
        .ifu_axi_arburst        (ifu_axi_arburst),
        .ifu_axi_arlock         (ifu_axi_arlock),
        .ifu_axi_arcache        (ifu_axi_arcache),
        .ifu_axi_arprot         (ifu_axi_arprot),
        .ifu_axi_arqos          (ifu_axi_arqos),
        .ifu_axi_rvalid         (ifu_axi_rvalid),
        .ifu_axi_rready         (ifu_axi_rready),
        .ifu_axi_rid            (ifu_axi_rid_soc[pt.IFU_BUS_TAG-1:0]),
        .ifu_axi_rdata          (ifu_axi_rdata),
        .ifu_axi_rresp          (ifu_axi_rresp),
        .ifu_axi_rlast          (ifu_axi_rlast),

        // SB AXI
        .sb_axi_awvalid         (sb_axi_awvalid),
        .sb_axi_awready         (sb_axi_awready),
        .sb_axi_awid            (sb_axi_awid_core),
        .sb_axi_awaddr          (sb_axi_awaddr),
        .sb_axi_awregion        (sb_axi_awregion),
        .sb_axi_awlen           (sb_axi_awlen),
        .sb_axi_awsize          (sb_axi_awsize),
        .sb_axi_awburst         (sb_axi_awburst),
        .sb_axi_awlock          (sb_axi_awlock),
        .sb_axi_awcache         (sb_axi_awcache),
        .sb_axi_awprot          (sb_axi_awprot),
        .sb_axi_awqos           (sb_axi_awqos),
        .sb_axi_wvalid          (sb_axi_wvalid),
        .sb_axi_wready          (sb_axi_wready),
        .sb_axi_wdata           (sb_axi_wdata),
        .sb_axi_wstrb           (sb_axi_wstrb),
        .sb_axi_wlast           (sb_axi_wlast),
        .sb_axi_bvalid          (sb_axi_bvalid),
        .sb_axi_bready          (sb_axi_bready),
        .sb_axi_bresp           (sb_axi_bresp),
        .sb_axi_bid             (sb_axi_bid_soc[pt.SB_BUS_TAG-1:0]),
        .sb_axi_arvalid         (sb_axi_arvalid),
        .sb_axi_arready         (sb_axi_arready),
        .sb_axi_arid            (sb_axi_arid_core),
        .sb_axi_araddr          (sb_axi_araddr),
        .sb_axi_arregion        (sb_axi_arregion),
        .sb_axi_arlen           (sb_axi_arlen),
        .sb_axi_arsize          (sb_axi_arsize),
        .sb_axi_arburst         (sb_axi_arburst),
        .sb_axi_arlock          (sb_axi_arlock),
        .sb_axi_arcache         (sb_axi_arcache),
        .sb_axi_arprot          (sb_axi_arprot),
        .sb_axi_arqos           (sb_axi_arqos),
        .sb_axi_rvalid          (sb_axi_rvalid),
        .sb_axi_rready          (sb_axi_rready),
        .sb_axi_rid             (sb_axi_rid_soc[pt.SB_BUS_TAG-1:0]),
        .sb_axi_rdata           (sb_axi_rdata),
        .sb_axi_rresp           (sb_axi_rresp),
        .sb_axi_rlast           (sb_axi_rlast),

        // DMA AXI Slave Inputs (tied off)
        .dma_axi_awvalid        (1'b0),
        .dma_axi_awready        (),
        .dma_axi_awid           ('0),
        .dma_axi_awaddr         (32'h0),
        .dma_axi_awsize         (3'b0),
        .dma_axi_awprot         (3'b0),
        .dma_axi_awlen          (8'b0),
        .dma_axi_awburst        (2'b0),
        .dma_axi_wvalid         (1'b0),
        .dma_axi_wready         (),
        .dma_axi_wdata          (64'h0),
        .dma_axi_wstrb          (8'h0),
        .dma_axi_wlast          (1'b0),
        .dma_axi_bvalid         (),
        .dma_axi_bready         (1'b0),
        .dma_axi_bresp          (),
        .dma_axi_bid            (),
        .dma_axi_arvalid        (1'b0),
        .dma_axi_arready        (),
        .dma_axi_arid           ('0),
        .dma_axi_araddr         (32'h0),
        .dma_axi_arsize         (3'b0),
        .dma_axi_arprot         (3'b0),
        .dma_axi_arlen          (8'b0),
        .dma_axi_arburst        (2'b0),
        .dma_axi_rvalid         (),
        .dma_axi_rready         (1'b0),
        .dma_axi_rid            (),
        .dma_axi_rdata          (),
        .dma_axi_rresp          (),
        .dma_axi_rlast          (),

        // Synchronous 1:1 Bus Clock Ratio
        .lsu_bus_clk_en         (1'b1),
        .ifu_bus_clk_en         (1'b1),
        .dbg_bus_clk_en         (1'b1),
        .dma_bus_clk_en         (1'b1),

        // Interrupts
        .timer_int              (timer_irq),
        .soft_int               (1'b0),
        .extintsrc_req          ({29'b0, rle_irq, gpio_irq}),

        // Perf counters
        .dec_tlu_perfcnt0       (),
        .dec_tlu_perfcnt1       (),
        .dec_tlu_perfcnt2       (),
        .dec_tlu_perfcnt3       (),

        // JTAG (tied off)
        .jtag_tck               (1'b0),
        .jtag_tms               (1'b0),
        .jtag_tdi               (1'b0),
        .jtag_trst_n            (1'b0),
        .jtag_tdo               (),
        .jtag_tdoEn             (),
        .core_id                (28'h0),

        // Memory Export
        .el2_mem_export         (el2_mem_export.veer_sram_src),
        .el2_icache_export      (el2_mem_export.veer_icache_src),

        // Core ECC error indicators
        .iccm_ecc_single_error     (),
        .iccm_ecc_double_error     (),
        .dccm_ecc_single_error     (),
        .dccm_ecc_double_error     (),
        .dccm_write_readback_error (),

        // MPC / Run Controls
        .mpc_debug_halt_req     (1'b0),
        .mpc_debug_run_req      (1'b0),
        .mpc_reset_run_req      (1'b1),  // Core runs automatically out of reset
        .mpc_debug_halt_ack     (),
        .mpc_debug_run_ack      (),
        .debug_brkpt_status     (),

        .i_cpu_halt_req         (1'b0),
        .o_cpu_halt_ack         (),
        .o_cpu_halt_status      (),
        .o_debug_mode_status    (),
        .i_cpu_run_req          (1'b0),
        .o_cpu_run_ack          (),
        .scan_mode              (1'b0),
        .mbist_mode             (1'b0),

        .dmi_core_enable        (1'b0),
        .dmi_uncore_enable      (1'b0),
        .dmi_uncore_en          (),
        .dmi_uncore_wr_en       (),
        .dmi_uncore_addr        (),
        .dmi_uncore_wdata       (),
        .dmi_uncore_rdata       (32'h0),
        .dmi_active             ()
    );

    // =========================================================================
    // SoC Top Level Instance
    // =========================================================================
    soc_top #(
        .IMEM_DEPTH(IMEM_DEPTH),
        .DMEM_DEPTH(DMEM_DEPTH)
    ) u_soc (
        .clk             (clk),
        .rst_n           (rst_n),

        // IFU Master Interface (64-bit)
        .ifu_axi_awvalid (ifu_axi_awvalid),
        .ifu_axi_awready (ifu_axi_awready),
        .ifu_axi_awid    ({5'b0, ifu_axi_awid_core}),
        .ifu_axi_awaddr  (ifu_axi_awaddr),
        .ifu_axi_awlen   (ifu_axi_awlen),
        .ifu_axi_awsize  (ifu_axi_awsize),
        .ifu_axi_awburst (ifu_axi_awburst),
        .ifu_axi_awlock  (ifu_axi_awlock),
        .ifu_axi_awcache (ifu_axi_awcache),
        .ifu_axi_awprot  (ifu_axi_awprot),
        .ifu_axi_awqos   (ifu_axi_awqos),
        .ifu_axi_awregion(ifu_axi_awregion),
        .ifu_axi_wvalid  (ifu_axi_wvalid),
        .ifu_axi_wready  (ifu_axi_wready),
        .ifu_axi_wdata   (ifu_axi_wdata),
        .ifu_axi_wstrb   (ifu_axi_wstrb),
        .ifu_axi_wlast   (ifu_axi_wlast),
        .ifu_axi_bvalid  (ifu_axi_bvalid),
        .ifu_axi_bready  (ifu_axi_bready),
        .ifu_axi_bresp   (ifu_axi_bresp),
        .ifu_axi_bid     (ifu_axi_bid_soc),
        .ifu_axi_arvalid (ifu_axi_arvalid),
        .ifu_axi_arready (ifu_axi_arready),
        .ifu_axi_arid    ({5'b0, ifu_axi_arid_core}),
        .ifu_axi_araddr  (ifu_axi_araddr),
        .ifu_axi_arlen   (ifu_axi_arlen),
        .ifu_axi_arsize  (ifu_axi_arsize),
        .ifu_axi_arburst (ifu_axi_arburst),
        .ifu_axi_arlock  (ifu_axi_arlock),
        .ifu_axi_arcache (ifu_axi_arcache),
        .ifu_axi_arprot  (ifu_axi_arprot),
        .ifu_axi_arqos   (ifu_axi_arqos),
        .ifu_axi_arregion(ifu_axi_arregion),
        .ifu_axi_rvalid  (ifu_axi_rvalid),
        .ifu_axi_rready  (ifu_axi_rready),
        .ifu_axi_rid     (ifu_axi_rid_soc),
        .ifu_axi_rdata   (ifu_axi_rdata),
        .ifu_axi_rresp   (ifu_axi_rresp),
        .ifu_axi_rlast   (ifu_axi_rlast),

        // LSU Master Interface (64-bit)
        .lsu_axi_awvalid (lsu_axi_awvalid),
        .lsu_axi_awready (lsu_axi_awready),
        .lsu_axi_awid    ({5'b0, lsu_axi_awid_core}),
        .lsu_axi_awaddr  (lsu_axi_awaddr),
        .lsu_axi_awlen   (lsu_axi_awlen),
        .lsu_axi_awsize  (lsu_axi_awsize),
        .lsu_axi_awburst (lsu_axi_awburst),
        .lsu_axi_awlock  (lsu_axi_awlock),
        .lsu_axi_awcache (lsu_axi_awcache),
        .lsu_axi_awprot  (lsu_axi_awprot),
        .lsu_axi_awqos   (lsu_axi_awqos),
        .lsu_axi_awregion(lsu_axi_awregion),
        .lsu_axi_wvalid  (lsu_axi_wvalid),
        .lsu_axi_wready  (lsu_axi_wready),
        .lsu_axi_wdata   (lsu_axi_wdata),
        .lsu_axi_wstrb   (lsu_axi_wstrb),
        .lsu_axi_wlast   (lsu_axi_wlast),
        .lsu_axi_bvalid  (lsu_axi_bvalid),
        .lsu_axi_bready  (lsu_axi_bready),
        .lsu_axi_bresp   (lsu_axi_bresp),
        .lsu_axi_bid     (lsu_axi_bid_soc),
        .lsu_axi_arvalid (lsu_axi_arvalid),
        .lsu_axi_arready (lsu_axi_arready),
        .lsu_axi_arid    ({5'b0, lsu_axi_arid_core}),
        .lsu_axi_araddr  (lsu_axi_araddr),
        .lsu_axi_arlen   (lsu_axi_arlen),
        .lsu_axi_arsize  (lsu_axi_arsize),
        .lsu_axi_arburst (lsu_axi_arburst),
        .lsu_axi_arlock  (lsu_axi_arlock),
        .lsu_axi_arcache (lsu_axi_arcache),
        .lsu_axi_arprot  (lsu_axi_arprot),
        .lsu_axi_arqos   (lsu_axi_arqos),
        .lsu_axi_arregion(lsu_axi_arregion),
        .lsu_axi_rvalid  (lsu_axi_rvalid),
        .lsu_axi_rready  (lsu_axi_rready),
        .lsu_axi_rid     (lsu_axi_rid_soc),
        .lsu_axi_rdata   (lsu_axi_rdata),
        .lsu_axi_rresp   (lsu_axi_rresp),
        .lsu_axi_rlast   (lsu_axi_rlast),

        // SB Master Interface (64-bit)
        .sb_axi_awvalid  (sb_axi_awvalid),
        .sb_axi_awready  (sb_axi_awready),
        .sb_axi_awid     ({7'b0, sb_axi_awid_core}),
        .sb_axi_awaddr   (sb_axi_awaddr),
        .sb_axi_awlen    (sb_axi_awlen),
        .sb_axi_awsize   (sb_axi_awsize),
        .sb_axi_awburst  (sb_axi_awburst),
        .sb_axi_awlock   (sb_axi_awlock),
        .sb_axi_awcache  (sb_axi_awcache),
        .sb_axi_awprot   (sb_axi_awprot),
        .sb_axi_awqos    (sb_axi_awqos),
        .sb_axi_awregion (sb_axi_awregion),
        .sb_axi_wvalid   (sb_axi_wvalid),
        .sb_axi_wready   (sb_axi_wready),
        .sb_axi_wdata    (sb_axi_wdata),
        .sb_axi_wstrb    (sb_axi_wstrb),
        .sb_axi_wlast    (sb_axi_wlast),
        .sb_axi_bvalid   (sb_axi_bvalid),
        .sb_axi_bready   (sb_axi_bready),
        .sb_axi_bresp    (sb_axi_bresp),
        .sb_axi_bid      (sb_axi_bid_soc),
        .sb_axi_arvalid  (sb_axi_arvalid),
        .sb_axi_arready  (sb_axi_arready),
        .sb_axi_arid     ({7'b0, sb_axi_arid_core}),
        .sb_axi_araddr   (sb_axi_araddr),
        .sb_axi_arlen    (sb_axi_arlen),
        .sb_axi_arsize   (sb_axi_arsize),
        .sb_axi_arburst  (sb_axi_arburst),
        .sb_axi_arlock   (sb_axi_arlock),
        .sb_axi_arcache  (sb_axi_arcache),
        .sb_axi_arprot   (sb_axi_arprot),
        .sb_axi_arqos    (sb_axi_arqos),
        .sb_axi_arregion (sb_axi_arregion),
        .sb_axi_rvalid   (sb_axi_rvalid),
        .sb_axi_rready   (sb_axi_rready),
        .sb_axi_rid      (sb_axi_rid_soc),
        .sb_axi_rdata    (sb_axi_rdata),
        .sb_axi_rresp    (sb_axi_rresp),
        .sb_axi_rlast    (sb_axi_rlast),

        // External Peripherals
        .uart_rx         (uart_rx),
        .uart_tx         (uart_tx),
        .gpio_i          (gpio_i),
        .gpio_o          (gpio_o),
        .gpio_oe         (gpio_oe),
        .gpio_irq        (gpio_irq),
        .timer_irq       (timer_irq),
        .rle_irq         (rle_irq)
    );

endmodule

`default_nettype wire
