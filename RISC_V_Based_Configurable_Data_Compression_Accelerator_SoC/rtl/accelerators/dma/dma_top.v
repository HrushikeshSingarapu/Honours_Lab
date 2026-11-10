// =============================================================================
// dma_top.v
//
// Top-Level Module for the Autonomous DMA Controller IP.
// RISC-V Based Configurable Data Compression Accelerator SoC.
//
// Hierarchy:
//   dma_top
//   ├── dma_reg_file      (CPU-facing AXI4-Lite slave register interface)
//   ├── dma_sequencer     (Hardware transfer sequencer & byte-packing FSM)
//   └── dma_master_engine (Interconnect-facing AXI4 master interface)
//
// Authors: SoC Development Team
// Date: October 2026
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module dma_top #(
    parameter ADDR_WIDTH     = 32,
    parameter DATA_WIDTH     = 32,
    parameter STRB_WIDTH     = (DATA_WIDTH / 8),
    parameter ID_WIDTH       = 8,
    parameter AXI_ID         = 8'h30,
    parameter BUFFER_DEPTH   = 256,
    parameter TIMEOUT_CYCLES = 100000
)(
    input  wire                    clk,
    input  wire                    rst_n,      // System active-low reset

    // =========================================================================
    // CPU-Facing AXI4-Lite Slave Interface (Base: 0x000B_0000)
    // =========================================================================
    input  wire [ID_WIDTH-1:0]     s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]   s_axi_awaddr,
    input  wire [2:0]              s_axi_awprot,
    input  wire                    s_axi_awvalid,
    output wire                    s_axi_awready,

    input  wire [DATA_WIDTH-1:0]   s_axi_wdata,
    input  wire [STRB_WIDTH-1:0]   s_axi_wstrb,
    input  wire                    s_axi_wvalid,
    output wire                    s_axi_wready,

    output wire [ID_WIDTH-1:0]     s_axi_bid,
    output wire [1:0]              s_axi_bresp,
    output wire                    s_axi_bvalid,
    input  wire                    s_axi_bready,

    input  wire [ID_WIDTH-1:0]     s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]   s_axi_araddr,
    input  wire [2:0]              s_axi_arprot,
    input  wire                    s_axi_arvalid,
    output wire                    s_axi_arready,

    output wire [ID_WIDTH-1:0]     s_axi_rid,
    output wire [DATA_WIDTH-1:0]   s_axi_rdata,
    output wire [1:0]              s_axi_rresp,
    output wire                    s_axi_rlast,
    output wire                    s_axi_rvalid,
    input  wire                    s_axi_rready,

    // =========================================================================
    // Interconnect-Facing AXI4 Master Interface (S03 on Crossbar)
    // =========================================================================
    output wire                    m_axi_awvalid,
    input  wire                    m_axi_awready,
    output wire [ID_WIDTH-1:0]     m_axi_awid,
    output wire [ADDR_WIDTH-1:0]   m_axi_awaddr,
    output wire [7:0]              m_axi_awlen,
    output wire [2:0]              m_axi_awsize,
    output wire [1:0]              m_axi_awburst,
    output wire                    m_axi_awlock,
    output wire [3:0]              m_axi_awcache,
    output wire [2:0]              m_axi_awprot,
    output wire [3:0]              m_axi_awqos,
    output wire [3:0]              m_axi_awregion,
    output wire                    m_axi_awuser,

    output wire                    m_axi_wvalid,
    input  wire                    m_axi_wready,
    output wire [DATA_WIDTH-1:0]   m_axi_wdata,
    output wire [STRB_WIDTH-1:0]   m_axi_wstrb,
    output wire                    m_axi_wlast,
    output wire                    m_axi_wuser,

    input  wire                    m_axi_bvalid,
    output wire                    m_axi_bready,
    input  wire [1:0]              m_axi_bresp,
    input  wire [ID_WIDTH-1:0]     m_axi_bid,
    input  wire                    m_axi_buser,

    output wire                    m_axi_arvalid,
    input  wire                    m_axi_arready,
    output wire [ID_WIDTH-1:0]     m_axi_arid,
    output wire [ADDR_WIDTH-1:0]   m_axi_araddr,
    output wire [7:0]              m_axi_arlen,
    output wire [2:0]              m_axi_arsize,
    output wire [1:0]              m_axi_arburst,
    output wire                    m_axi_arlock,
    output wire [3:0]              m_axi_arcache,
    output wire [2:0]              m_axi_arprot,
    output wire [3:0]              m_axi_arqos,
    output wire [3:0]              m_axi_arregion,
    output wire                    m_axi_aruser,

    input  wire                    m_axi_rvalid,
    output wire                    m_axi_rready,
    input  wire [ID_WIDTH-1:0]     m_axi_rid,
    input  wire [DATA_WIDTH-1:0]   m_axi_rdata,
    input  wire [1:0]              m_axi_rresp,
    input  wire                    m_axi_rlast,
    input  wire                    m_axi_ruser,

    // =========================================================================
    // Interrupt Output (to SoC PIC / Top-Level)
    // =========================================================================
    output wire                    irq_o
);

    // =========================================================================
    // Internal Interconnect Wires
    // =========================================================================

    // Register File <-> Sequencer
    wire        ctrl_start_pulse;
    wire        ctrl_mode;
    wire        ctrl_abort_pulse;
    wire [31:0] cfg_src_addr;
    wire [31:0] cfg_dst_addr;
    wire [15:0] cfg_input_len;

    wire        status_busy;
    wire        status_done_pulse;
    wire        status_error_pulse;
    wire [15:0] status_output_len;
    wire [7:0]  status_error_code;

    // Sequencer <-> Master Engine
    wire        seq_req_rd_start;
    wire [31:0] seq_req_rd_addr;
    wire [7:0]  seq_req_rd_len;
    wire [31:0] eng_rd_data;
    wire        eng_rd_valid;
    wire        seq_rd_ready;
    wire        eng_rd_last;
    wire        eng_rd_done;
    wire        eng_rd_error;
    wire [1:0]  eng_rd_resp;

    wire        seq_req_wr_start;
    wire [31:0] seq_req_wr_addr;
    wire [7:0]  seq_req_wr_len;
    wire [31:0] seq_wr_data;
    wire [3:0]  seq_wr_strb;
    wire        seq_wr_valid;
    wire        eng_wr_ready;
    wire        eng_wr_done;
    wire        eng_wr_error;
    wire [1:0]  eng_wr_resp;

    wire        seq_master_abort;
    wire        eng_rd_busy;
    wire        eng_wr_busy;
    wire        eng_busy;

    // Combined abort signal for master engine
    wire        master_abort_combined = ctrl_abort_pulse | seq_master_abort;

    // =========================================================================
    // 1. DMA Register File Instance
    // =========================================================================
    dma_reg_file #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH),
        .ID_WIDTH   (ID_WIDTH),
        .STRB_WIDTH (STRB_WIDTH)
    ) u_reg_file (
        .clk                  (clk),
        .rst_n                (rst_n),

        // AXI4-Lite Slave Ports
        .s_axi_awid           (s_axi_awid),
        .s_axi_awaddr         (s_axi_awaddr),
        .s_axi_awprot         (s_axi_awprot),
        .s_axi_awvalid        (s_axi_awvalid),
        .s_axi_awready        (s_axi_awready),

        .s_axi_wdata          (s_axi_wdata),
        .s_axi_wstrb          (s_axi_wstrb),
        .s_axi_wvalid         (s_axi_wvalid),
        .s_axi_wready         (s_axi_wready),

        .s_axi_bid            (s_axi_bid),
        .s_axi_bresp          (s_axi_bresp),
        .s_axi_bvalid         (s_axi_bvalid),
        .s_axi_bready         (s_axi_bready),

        .s_axi_arid           (s_axi_arid),
        .s_axi_araddr         (s_axi_araddr),
        .s_axi_arprot         (s_axi_arprot),
        .s_axi_arvalid        (s_axi_arvalid),
        .s_axi_arready        (s_axi_arready),

        .s_axi_rid            (s_axi_rid),
        .s_axi_rdata          (s_axi_rdata),
        .s_axi_rresp          (s_axi_rresp),
        .s_axi_rlast          (s_axi_rlast),
        .s_axi_rvalid         (s_axi_rvalid),
        .s_axi_rready         (s_axi_rready),

        // Control & Configuration to Sequencer
        .ctrl_start_pulse_o   (ctrl_start_pulse),
        .ctrl_mode_o          (ctrl_mode),
        .ctrl_abort_pulse_o   (ctrl_abort_pulse),
        .cfg_src_addr_o       (cfg_src_addr),
        .cfg_dst_addr_o       (cfg_dst_addr),
        .cfg_input_len_o      (cfg_input_len),

        // Status from Sequencer / Engine
        .status_busy_i        (status_busy | eng_busy),
        .status_done_pulse_i  (status_done_pulse),
        .status_error_pulse_i (status_error_pulse),
        .status_output_len_i  (status_output_len),
        .status_error_code_i  (status_error_code),

        // Interrupt Output
        .irq_o                (irq_o)
    );

    // =========================================================================
    // 2. DMA Sequencer Instance
    // =========================================================================
    dma_sequencer #(
        .ADDR_WIDTH     (ADDR_WIDTH),
        .DATA_WIDTH     (DATA_WIDTH),
        .STRB_WIDTH     (STRB_WIDTH),
        .BUFFER_DEPTH   (BUFFER_DEPTH),
        .TIMEOUT_CYCLES (TIMEOUT_CYCLES)
    ) u_sequencer (
        .clk                  (clk),
        .rst_n                (rst_n),

        // Interface with Register File
        .ctrl_start_i         (ctrl_start_pulse),
        .ctrl_abort_i         (ctrl_abort_pulse),
        .ctrl_mode_i          (ctrl_mode),
        .cfg_src_addr_i       (cfg_src_addr),
        .cfg_dst_addr_i       (cfg_dst_addr),
        .cfg_input_len_i      (cfg_input_len),

        .status_busy_o        (status_busy),
        .status_done_pulse_o  (status_done_pulse),
        .status_error_pulse_o (status_error_pulse),
        .status_output_len_o  (status_output_len),
        .status_error_code_o  (status_error_code),

        // Interface with Master Engine
        .req_rd_start_o       (seq_req_rd_start),
        .req_rd_addr_o        (seq_req_rd_addr),
        .req_rd_len_o         (seq_req_rd_len),
        .rd_data_i            (eng_rd_data),
        .rd_valid_i           (eng_rd_valid),
        .rd_ready_o           (seq_rd_ready),
        .rd_last_i            (eng_rd_last),
        .rd_done_i            (eng_rd_done),
        .rd_error_i           (eng_rd_error),
        .rd_resp_i            (eng_rd_resp),

        .req_wr_start_o       (seq_req_wr_start),
        .req_wr_addr_o        (seq_req_wr_addr),
        .req_wr_len_o         (seq_req_wr_len),
        .wr_data_o            (seq_wr_data),
        .wr_strb_o            (seq_wr_strb),
        .wr_valid_o           (seq_wr_valid),
        .wr_ready_i           (eng_wr_ready),
        .wr_done_i            (eng_wr_done),
        .wr_error_i           (eng_wr_error),
        .wr_resp_i            (eng_wr_resp),

        .master_abort_o       (seq_master_abort)
    );

    // =========================================================================
    // 3. DMA AXI4 Master Engine Instance
    // =========================================================================
    dma_master_engine #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .STRB_WIDTH (STRB_WIDTH),
        .ID_WIDTH   (ID_WIDTH),
        .AXI_ID     (AXI_ID)
    ) u_master_engine (
        .clk             (clk),
        .rst_n           (rst_n),

        // Sequencer Control Interface
        .req_rd_start_i  (seq_req_rd_start),
        .req_rd_addr_i   (seq_req_rd_addr),
        .req_rd_len_i    (seq_req_rd_len),
        .rd_data_o       (eng_rd_data),
        .rd_valid_o      (eng_rd_valid),
        .rd_ready_i      (seq_rd_ready),
        .rd_last_o       (eng_rd_last),
        .rd_done_o       (eng_rd_done),
        .rd_error_o      (eng_rd_error),
        .rd_resp_o       (eng_rd_resp),

        .req_wr_start_i  (seq_req_wr_start),
        .req_wr_addr_i   (seq_req_wr_addr),
        .req_wr_len_i    (seq_req_wr_len),
        .wr_data_i       (seq_wr_data),
        .wr_strb_i       (seq_wr_strb),
        .wr_valid_i      (seq_wr_valid),
        .wr_ready_o      (eng_wr_ready),
        .wr_done_o       (eng_wr_done),
        .wr_error_o      (eng_wr_error),
        .wr_resp_o       (eng_wr_resp),

        .rd_busy_o       (eng_rd_busy),
        .wr_busy_o       (eng_wr_busy),
        .busy_o          (eng_busy),
        .abort_i         (master_abort_combined),

        // AXI4 Master External Interface
        .m_axi_arvalid   (m_axi_arvalid),
        .m_axi_arready   (m_axi_arready),
        .m_axi_arid      (m_axi_arid),
        .m_axi_araddr    (m_axi_araddr),
        .m_axi_arlen     (m_axi_arlen),
        .m_axi_arsize    (m_axi_arsize),
        .m_axi_arburst   (m_axi_arburst),
        .m_axi_arlock    (m_axi_arlock),
        .m_axi_arcache   (m_axi_arcache),
        .m_axi_arprot    (m_axi_arprot),
        .m_axi_arqos     (m_axi_arqos),
        .m_axi_arregion  (m_axi_arregion),
        .m_axi_aruser    (m_axi_aruser),

        .m_axi_rvalid    (m_axi_rvalid),
        .m_axi_rready    (m_axi_rready),
        .m_axi_rid       (m_axi_rid),
        .m_axi_rdata     (m_axi_rdata),
        .m_axi_rresp     (m_axi_rresp),
        .m_axi_rlast     (m_axi_rlast),
        .m_axi_ruser     (m_axi_ruser),

        .m_axi_awvalid   (m_axi_awvalid),
        .m_axi_awready   (m_axi_awready),
        .m_axi_awid      (m_axi_awid),
        .m_axi_awaddr    (m_axi_awaddr),
        .m_axi_awlen     (m_axi_awlen),
        .m_axi_awsize    (m_axi_awsize),
        .m_axi_awburst   (m_axi_awburst),
        .m_axi_awlock    (m_axi_awlock),
        .m_axi_awcache   (m_axi_awcache),
        .m_axi_awprot    (m_axi_awprot),
        .m_axi_awqos     (m_axi_awqos),
        .m_axi_awregion  (m_axi_awregion),
        .m_axi_awuser    (m_axi_awuser),

        .m_axi_wvalid    (m_axi_wvalid),
        .m_axi_wready    (m_axi_wready),
        .m_axi_wdata     (m_axi_wdata),
        .m_axi_wstrb     (m_axi_wstrb),
        .m_axi_wlast     (m_axi_wlast),
        .m_axi_wuser     (m_axi_wuser),

        .m_axi_bvalid    (m_axi_bvalid),
        .m_axi_bready    (m_axi_bready),
        .m_axi_bresp     (m_axi_bresp),
        .m_axi_bid       (m_axi_bid),
        .m_axi_buser     (m_axi_buser)
    );

endmodule

`default_nettype wire
