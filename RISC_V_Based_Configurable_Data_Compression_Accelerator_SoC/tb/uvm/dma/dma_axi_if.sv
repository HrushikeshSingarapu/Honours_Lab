// =============================================================================
// dma_axi_if.sv — Dual Slave/Master AXI Interface for DMA IP UVM Environment
// =============================================================================
`timescale 1ns/1ps

interface dma_axi_if (
    input wire clk,
    input wire rst_n
);
    // -------------------------------------------------------------------------
    // Slave Programming Interface (CPU-Facing)
    // -------------------------------------------------------------------------
    logic [7:0]  s_axi_awid;
    logic [31:0] s_axi_awaddr;
    logic [2:0]  s_axi_awprot;
    logic        s_axi_awvalid;
    logic        s_axi_awready;

    logic [31:0] s_axi_wdata;
    logic [3:0]  s_axi_wstrb;
    logic        s_axi_wvalid;
    logic        s_axi_wready;

    logic [7:0]  s_axi_bid;
    logic [1:0]  s_axi_bresp;
    logic        s_axi_bvalid;
    logic        s_axi_bready;

    logic [7:0]  s_axi_arid;
    logic [31:0] s_axi_araddr;
    logic [2:0]  s_axi_arprot;
    logic        s_axi_arvalid;
    logic        s_axi_arready;

    logic [7:0]  s_axi_rid;
    logic [31:0] s_axi_rdata;
    logic [1:0]  s_axi_rresp;
    logic        s_axi_rlast;
    logic        s_axi_rvalid;
    logic        s_axi_rready;

    // -------------------------------------------------------------------------
    // Master Interconnect Interface (Memory/Peripheral-Facing)
    // -------------------------------------------------------------------------
    logic        m_axi_awvalid;
    logic        m_axi_awready;
    logic [7:0]  m_axi_awid;
    logic [31:0] m_axi_awaddr;
    logic [7:0]  m_axi_awlen;
    logic [2:0]  m_axi_awsize;
    logic [1:0]  m_axi_awburst;
    logic        m_axi_awlock;
    logic [3:0]  m_axi_awcache;
    logic [2:0]  m_axi_awprot;
    logic [3:0]  m_axi_awqos;
    logic [3:0]  m_axi_awregion;
    logic        m_axi_awuser;

    logic        m_axi_wvalid;
    logic        m_axi_wready;
    logic [31:0] m_axi_wdata;
    logic [3:0]  m_axi_wstrb;
    logic        m_axi_wlast;
    logic        m_axi_wuser;

    logic        m_axi_bvalid;
    logic        m_axi_bready;
    logic [1:0]  m_axi_bresp;
    logic [7:0]  m_axi_bid;
    logic        m_axi_buser;

    logic        m_axi_arvalid;
    logic        m_axi_arready;
    logic [7:0]  m_axi_arid;
    logic [31:0] m_axi_araddr;
    logic [7:0]  m_axi_arlen;
    logic [2:0]  m_axi_arsize;
    logic [1:0]  m_axi_arburst;
    logic        m_axi_arlock;
    logic [3:0]  m_axi_arcache;
    logic [2:0]  m_axi_arprot;
    logic [3:0]  m_axi_arqos;
    logic [3:0]  m_axi_arregion;
    logic        m_axi_aruser;

    logic        m_axi_rvalid;
    logic        m_axi_rready;
    logic [7:0]  m_axi_rid;
    logic [31:0] m_axi_rdata;
    logic [1:0]  m_axi_rresp;
    logic        m_axi_rlast;
    logic        m_axi_ruser;

    // Interrupt line
    logic        irq;

    // Testbench Control: AW backpressure injection (allows W-before-AW acceptance)
    logic        inject_aw_backpressure;

endinterface: dma_axi_if

