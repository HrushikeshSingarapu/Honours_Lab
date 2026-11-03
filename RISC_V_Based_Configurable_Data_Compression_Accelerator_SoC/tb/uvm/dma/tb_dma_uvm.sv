// =============================================================================
// tb_dma_uvm.sv — Top-Level UVM 1.2 Testbench for DMA Controller IP
// =============================================================================
`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"
import dma_uvm_pkg::*;

module tb_dma_uvm;

    logic clk;
    logic rst_n;

    always #5 clk = ~clk;

    // AXI Interface
    dma_axi_if axi_if (clk, rst_n);

    // =========================================================================
    // 1. DMA Controller IP DUT
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

        // Slave CPU Interface
        .s_axi_awid     (axi_if.s_axi_awid),
        .s_axi_awaddr   (axi_if.s_axi_awaddr),
        .s_axi_awprot   (axi_if.s_axi_awprot),
        .s_axi_awvalid  (axi_if.s_axi_awvalid),
        .s_axi_awready  (axi_if.s_axi_awready),

        .s_axi_wdata    (axi_if.s_axi_wdata),
        .s_axi_wstrb    (axi_if.s_axi_wstrb),
        .s_axi_wvalid   (axi_if.s_axi_wvalid),
        .s_axi_wready   (axi_if.s_axi_wready),

        .s_axi_bid      (axi_if.s_axi_bid),
        .s_axi_bresp    (axi_if.s_axi_bresp),
        .s_axi_bvalid   (axi_if.s_axi_bvalid),
        .s_axi_bready   (axi_if.s_axi_bready),

        .s_axi_arid     (axi_if.s_axi_arid),
        .s_axi_araddr   (axi_if.s_axi_araddr),
        .s_axi_arprot   (axi_if.s_axi_arprot),
        .s_axi_arvalid  (axi_if.s_axi_arvalid),
        .s_axi_arready  (axi_if.s_axi_arready),

        .s_axi_rid      (axi_if.s_axi_rid),
        .s_axi_rdata    (axi_if.s_axi_rdata),
        .s_axi_rresp    (axi_if.s_axi_rresp),
        .s_axi_rlast    (axi_if.s_axi_rlast),
        .s_axi_rvalid   (axi_if.s_axi_rvalid),
        .s_axi_rready   (axi_if.s_axi_rready),

        // Master Interconnect Interface
        .m_axi_awvalid  (axi_if.m_axi_awvalid),
        .m_axi_awready  (axi_if.m_axi_awready),
        .m_axi_awid     (axi_if.m_axi_awid),
        .m_axi_awaddr   (axi_if.m_axi_awaddr),
        .m_axi_awlen    (axi_if.m_axi_awlen),
        .m_axi_awsize   (axi_if.m_axi_awsize),
        .m_axi_awburst  (axi_if.m_axi_awburst),
        .m_axi_awlock   (axi_if.m_axi_awlock),
        .m_axi_awcache  (axi_if.m_axi_awcache),
        .m_axi_awprot   (axi_if.m_axi_awprot),
        .m_axi_awqos    (axi_if.m_axi_awqos),
        .m_axi_awregion (axi_if.m_axi_awregion),
        .m_axi_awuser   (axi_if.m_axi_awuser),

        .m_axi_wvalid   (axi_if.m_axi_wvalid),
        .m_axi_wready   (axi_if.m_axi_wready),
        .m_axi_wdata    (axi_if.m_axi_wdata),
        .m_axi_wstrb    (axi_if.m_axi_wstrb),
        .m_axi_wlast    (axi_if.m_axi_wlast),
        .m_axi_wuser    (axi_if.m_axi_wuser),

        .m_axi_bvalid   (axi_if.m_axi_bvalid),
        .m_axi_bready   (axi_if.m_axi_bready),
        .m_axi_bresp    (axi_if.m_axi_bresp),
        .m_axi_bid      (axi_if.m_axi_bid),
        .m_axi_buser    (axi_if.m_axi_buser),

        .m_axi_arvalid  (axi_if.m_axi_arvalid),
        .m_axi_arready  (axi_if.m_axi_arready),
        .m_axi_arid     (axi_if.m_axi_arid),
        .m_axi_araddr   (axi_if.m_axi_araddr),
        .m_axi_arlen    (axi_if.m_axi_arlen),
        .m_axi_arsize   (axi_if.m_axi_arsize),
        .m_axi_arburst  (axi_if.m_axi_arburst),
        .m_axi_arlock   (axi_if.m_axi_arlock),
        .m_axi_arcache  (axi_if.m_axi_arcache),
        .m_axi_arprot   (axi_if.m_axi_arprot),
        .m_axi_arqos    (axi_if.m_axi_arqos),
        .m_axi_arregion (axi_if.m_axi_arregion),
        .m_axi_aruser   (axi_if.m_axi_aruser),

        .m_axi_rvalid   (axi_if.m_axi_rvalid),
        .m_axi_rready   (axi_if.m_axi_rready),
        .m_axi_rid      (axi_if.m_axi_rid),
        .m_axi_rdata    (axi_if.m_axi_rdata),
        .m_axi_rresp    (axi_if.m_axi_rresp),
        .m_axi_rlast    (axi_if.m_axi_rlast),
        .m_axi_ruser    (axi_if.m_axi_ruser),

        .irq_o          (axi_if.irq)
    );

    // =========================================================================
    // Protocol Assertions
    // =========================================================================
    axi_protocol_assertions #(
        .NAME ("DMA_SLAVE_AXI")
    ) u_slave_axi_assert (
        .clk     (clk),
        .rst_n   (rst_n),
        .awvalid (axi_if.s_axi_awvalid),
        .awready (axi_if.s_axi_awready),
        .awaddr  (axi_if.s_axi_awaddr),
        .awprot  (axi_if.s_axi_awprot),
        .wvalid  (axi_if.s_axi_wvalid),
        .wready  (axi_if.s_axi_wready),
        .wdata   (axi_if.s_axi_wdata),
        .wstrb   (axi_if.s_axi_wstrb),
        .bvalid  (axi_if.s_axi_bvalid),
        .bready  (axi_if.s_axi_bready),
        .bresp   (axi_if.s_axi_bresp),
        .arvalid (axi_if.s_axi_arvalid),
        .arready (axi_if.s_axi_arready),
        .araddr  (axi_if.s_axi_araddr),
        .arprot  (axi_if.s_axi_arprot),
        .rvalid  (axi_if.s_axi_rvalid),
        .rready  (axi_if.s_axi_rready),
        .rdata   (axi_if.s_axi_rdata),
        .rresp   (axi_if.s_axi_rresp)
    );

    dma_protocol_assertions #(
        .NAME ("DMA_MASTER_PROTO")
    ) u_dma_proto_assert (
        .clk           (clk),
        .rst_n         (rst_n),
        .m_axi_awvalid (axi_if.m_axi_awvalid),
        .m_axi_awready (axi_if.m_axi_awready),
        .m_axi_awaddr  (axi_if.m_axi_awaddr),
        .m_axi_awlen   (axi_if.m_axi_awlen),
        .m_axi_awsize  (axi_if.m_axi_awsize),
        .m_axi_awburst (axi_if.m_axi_awburst),
        .m_axi_wvalid  (axi_if.m_axi_wvalid),
        .m_axi_wready  (axi_if.m_axi_wready),
        .m_axi_wdata   (axi_if.m_axi_wdata),
        .m_axi_wstrb   (axi_if.m_axi_wstrb),
        .m_axi_wlast   (axi_if.m_axi_wlast),
        .m_axi_bvalid  (axi_if.m_axi_bvalid),
        .m_axi_bready  (axi_if.m_axi_bready),
        .m_axi_bresp   (axi_if.m_axi_bresp),
        .m_axi_arvalid (axi_if.m_axi_arvalid),
        .m_axi_arready (axi_if.m_axi_arready),
        .m_axi_araddr  (axi_if.m_axi_araddr),
        .m_axi_arlen   (axi_if.m_axi_arlen),
        .m_axi_arsize  (axi_if.m_axi_arsize),
        .m_axi_arburst (axi_if.m_axi_arburst),
        .m_axi_rvalid  (axi_if.m_axi_rvalid),
        .m_axi_rready  (axi_if.m_axi_rready),
        .m_axi_rdata   (axi_if.m_axi_rdata),
        .m_axi_rresp   (axi_if.m_axi_rresp),
        .m_axi_rlast   (axi_if.m_axi_rlast),
        .irq_o         (axi_if.irq)
    );

    // =========================================================================
    // 2. Real RLE Accelerator IP Target
    // =========================================================================
    logic [31:0] rle_awaddr;
    logic [2:0]  rle_awprot;
    logic        rle_awvalid;
    logic        rle_awready;
    logic [31:0] rle_wdata;
    logic [3:0]  rle_wstrb;
    logic        rle_wvalid;
    logic        rle_wready;
    logic [1:0]  rle_bresp;
    logic        rle_bvalid;
    logic        rle_bready;
    logic [31:0] rle_araddr;
    logic [2:0]  rle_arprot;
    logic        rle_arvalid;
    logic        rle_arready;
    logic [31:0] rle_rdata;
    logic [1:0]  rle_rresp;
    logic        rle_rvalid;
    logic        rle_rready;
    logic        rle_irq;

    rle_top #(
        .DATA_WIDTH   (32),
        .ADDR_WIDTH   (32),
        .STRB_WIDTH   (4),
        .BUFFER_DEPTH (256)
    ) u_rle (
        .clk          (clk),
        .rst          (!rst_n),
        .s_axi_awaddr (rle_awaddr),
        .s_axi_awprot (rle_awprot),
        .s_axi_awvalid(rle_awvalid),
        .s_axi_awready(rle_awready),
        .s_axi_wdata  (rle_wdata),
        .s_axi_wstrb  (rle_wstrb),
        .s_axi_wvalid (rle_wvalid),
        .s_axi_wready (rle_wready),
        .s_axi_bresp  (rle_bresp),
        .s_axi_bvalid (rle_bvalid),
        .s_axi_bready (rle_bready),
        .s_axi_araddr (rle_araddr),
        .s_axi_arprot (rle_arprot),
        .s_axi_arvalid(rle_arvalid),
        .s_axi_arready(rle_arready),
        .s_axi_rdata  (rle_rdata),
        .s_axi_rresp  (rle_rresp),
        .s_axi_rvalid (rle_rvalid),
        .s_axi_rready (rle_rready),
        .irq          (rle_irq)
    );

    // =========================================================================
    // 3. Simulated DMEM and Crossbar Router
    // =========================================================================
    logic [7:0] dmem [0:262143]; // 256 KB simulated memory (0x0004_0000 - 0x0007_FFFF)

    wire is_rle_wr  = (axi_if.m_axi_awaddr >= 32'h1001_0000 && axi_if.m_axi_awaddr <= 32'h1001_0FFF);
    wire is_dmem_wr = (axi_if.m_axi_awaddr >= 32'h0004_0000 && axi_if.m_axi_awaddr <= 32'h0007_FFFF);
    wire is_rle_rd  = (axi_if.m_axi_araddr >= 32'h1001_0000 && axi_if.m_axi_araddr <= 32'h1001_0FFF);
    wire is_dmem_rd = (axi_if.m_axi_araddr >= 32'h0004_0000 && axi_if.m_axi_araddr <= 32'h0007_FFFF);

    logic dmem_awready, dmem_wready, dmem_bvalid, dmem_arready, dmem_rvalid, dmem_rlast;
    logic [31:0] dmem_rdata;
    logic [7:0]  dmem_bid, dmem_rid;

    // RLE routing
    assign rle_awaddr  = axi_if.m_axi_awaddr;
    assign rle_awprot  = axi_if.m_axi_awprot;
    assign rle_awvalid = is_rle_wr ? axi_if.m_axi_awvalid : 1'b0;
    assign rle_wdata   = axi_if.m_axi_wdata;
    assign rle_wstrb   = axi_if.m_axi_wstrb;
    assign rle_wvalid  = is_rle_wr ? axi_if.m_axi_wvalid : 1'b0;
    assign rle_bready  = is_rle_wr ? axi_if.m_axi_bready : 1'b0;

    assign rle_araddr  = axi_if.m_axi_araddr;
    assign rle_arprot  = axi_if.m_axi_arprot;
    assign rle_arvalid = is_rle_rd ? axi_if.m_axi_arvalid : 1'b0;
    assign rle_rready  = is_rle_rd ? axi_if.m_axi_rready : 1'b0;

    // Master bus multiplexing
    assign axi_if.m_axi_awready = is_rle_wr ? rle_awready : (is_dmem_wr ? dmem_awready : 1'b0);
    assign axi_if.m_axi_wready  = is_rle_wr ? rle_wready  : (is_dmem_wr ? dmem_wready  : 1'b0);
    assign axi_if.m_axi_bvalid  = is_rle_wr ? rle_bvalid  : (is_dmem_wr ? dmem_bvalid  : 1'b0);
    assign axi_if.m_axi_bresp   = is_rle_wr ? rle_bresp   : 2'b00;
    assign axi_if.m_axi_bid     = is_rle_wr ? axi_if.m_axi_awid : dmem_bid;

    assign axi_if.m_axi_arready = is_rle_rd ? rle_arready : (is_dmem_rd ? dmem_arready : 1'b0);
    assign axi_if.m_axi_rvalid  = is_rle_rd ? rle_rvalid  : (is_dmem_rd ? dmem_rvalid  : 1'b0);
    assign axi_if.m_axi_rdata   = is_rle_rd ? rle_rdata   : (is_dmem_rd ? dmem_rdata   : 32'h0);
    assign axi_if.m_axi_rresp   = is_rle_rd ? rle_rresp   : 2'b00;
    assign axi_if.m_axi_rlast   = is_rle_rd ? 1'b1        : (is_dmem_rd ? dmem_rlast   : 1'b1);
    assign axi_if.m_axi_rid     = is_rle_rd ? axi_if.m_axi_arid : dmem_rid;

    // DMEM Write Responder
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dmem_awready <= 1'b0;
            dmem_wready  <= 1'b0;
            dmem_bvalid  <= 1'b0;
            dmem_bid     <= 8'h0;
        end else if (is_dmem_wr) begin
            if (axi_if.m_axi_awvalid && !dmem_awready && !dmem_bvalid) begin
                logic [31:0] waddr;
                logic [31:0] latched_wdata;
                logic [3:0]  latched_wstrb;

                if (axi_if.inject_aw_backpressure) begin
                    // 1. Accept W beat FIRST: assert WREADY while keeping AWREADY = 0
                    dmem_awready <= 1'b0;
                    dmem_wready  <= 1'b1;
                    @(posedge clk);
                    while (!(axi_if.m_axi_wvalid && dmem_wready)) @(posedge clk);
                    latched_wdata = axi_if.m_axi_wdata;
                    latched_wstrb = axi_if.m_axi_wstrb;
                    dmem_wready   <= 1'b0;

                    // 2. Backpressure AW: hold AWREADY low for 3 cycles while AWVALID remains high
                    repeat (3) @(posedge clk);

                    // 3. Now accept write address on AW channel
                    dmem_awready <= 1'b1;
                    @(posedge clk);
                    waddr        = axi_if.m_axi_awaddr - 32'h0004_0000;
                    dmem_bid     <= axi_if.m_axi_awid;
                    dmem_awready <= 1'b0;

                    // Write latched data to memory
                    if (latched_wstrb[0]) dmem[waddr + 0] <= latched_wdata[7:0];
                    if (latched_wstrb[1]) dmem[waddr + 1] <= latched_wdata[15:8];
                    if (latched_wstrb[2]) dmem[waddr + 2] <= latched_wdata[23:16];
                    if (latched_wstrb[3]) dmem[waddr + 3] <= latched_wdata[31:24];

                    // 4. Send B response
                    dmem_bvalid <= 1'b1;
                    @(posedge clk);
                    while (!axi_if.m_axi_bready) @(posedge clk);
                    dmem_bvalid <= 1'b0;
                end else begin
                    dmem_awready <= 1'b1;
                    dmem_wready  <= 1'b1;
                    @(posedge clk);
                    waddr        = axi_if.m_axi_awaddr - 32'h0004_0000;
                    dmem_bid     <= axi_if.m_axi_awid;
                    dmem_awready <= 1'b0;

                    while (!(axi_if.m_axi_wvalid && dmem_wready)) @(posedge clk);

                    if (axi_if.m_axi_wstrb[0]) dmem[waddr + 0] <= axi_if.m_axi_wdata[7:0];
                    if (axi_if.m_axi_wstrb[1]) dmem[waddr + 1] <= axi_if.m_axi_wdata[15:8];
                    if (axi_if.m_axi_wstrb[2]) dmem[waddr + 2] <= axi_if.m_axi_wdata[23:16];
                    if (axi_if.m_axi_wstrb[3]) dmem[waddr + 3] <= axi_if.m_axi_wdata[31:24];

                    dmem_wready <= 1'b0;
                    dmem_bvalid <= 1'b1;
                    @(posedge clk);
                    while (!axi_if.m_axi_bready) @(posedge clk);
                    dmem_bvalid <= 1'b0;
                end
            end
        end
    end

    // DMEM Read Responder
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dmem_arready <= 1'b0;
            dmem_rvalid  <= 1'b0;
            dmem_rlast   <= 1'b0;
            dmem_rid     <= 8'h0;
        end else if (is_dmem_rd) begin
            if (axi_if.m_axi_arvalid && !dmem_arready) begin
                logic [31:0] raddr;
                logic [7:0]  rlen, rid;
                int b;
                dmem_arready <= 1'b1;
                @(posedge clk);
                raddr = axi_if.m_axi_araddr - 32'h0004_0000;
                rlen  = axi_if.m_axi_arlen;
                rid   = axi_if.m_axi_arid;
                dmem_arready <= 1'b0;

                for (b = 0; b <= rlen; b++) begin
                    dmem_rvalid <= 1'b1;
                    dmem_rdata  <= {dmem[raddr + 3], dmem[raddr + 2], dmem[raddr + 1], dmem[raddr + 0]};
                    dmem_rlast  <= (b == rlen);
                    dmem_rid    <= rid;
                    @(posedge clk);
                    while (!axi_if.m_axi_rready) @(posedge clk);
                    raddr = raddr + 4;
                end
                dmem_rvalid <= 1'b0;
                dmem_rlast  <= 1'b0;
            end
        end
    end

    // Initialization & UVM invocation
    initial begin
        rst_n = 1'b0;
        // Populate test patterns into simulated DMEM (256 KB)
        for (int i = 0; i < 262144; i++) begin
            dmem[i] = 8'hAA; // Repeating 0xAA for compression test
        end
        // Decompression tokens at 0x0005_0000: [10, 0x41], [6, 0x42]
        dmem[32'h0005_0000 - 32'h0004_0000 + 0] = 8'd10;
        dmem[32'h0005_0000 - 32'h0004_0000 + 1] = 8'h41;
        dmem[32'h0005_0000 - 32'h0004_0000 + 2] = 8'd6;
        dmem[32'h0005_0000 - 32'h0004_0000 + 3] = 8'h42;

        repeat (15) @(posedge clk);
        #1;
        rst_n = 1'b1;
    end

    initial begin
        clk = 0;
        uvm_config_db#(virtual dma_axi_if)::set(null, "*", "vif", axi_if);
        run_test("dma_test");
    end

    final begin
        $display("-----------------------------------------------------------------");
        $display("[ASSERTION REPORT] DMA Slave AXI Protocol Errors  : %0d", u_slave_axi_assert.get_total_assertion_errors());
        $display("[ASSERTION REPORT] DMA Master Protocol Errors     : %0d", u_dma_proto_assert.get_total_assertion_errors());
        if (u_slave_axi_assert.get_total_assertion_errors() == 0 && u_dma_proto_assert.get_total_assertion_errors() == 0) begin
            $display("[ASSERTION STATUS] ALL PROTOCOL ASSERTIONS PASSED CLEANLY (0 Errors)");
        end else begin
            $display("[ASSERTION STATUS] FAIL: Assertion errors detected!");
        end
        $display("-----------------------------------------------------------------");
    end

endmodule

