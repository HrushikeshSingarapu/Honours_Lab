// =============================================================================
// tb_soc_mem_access.sv  —  Memory & Reset Vector Integration Testbench for SoC Top
//
// Tests complete cycle-based AXI transactions through the 64->32 AXI bridges,
// the 3x8 AXI interconnect fabric, and the dual-region IMEM and DMEM SRAMs.
//
// Verification Coverage:
//   1. 64-bit IFU instruction fetch at VeeR EL2 reset vector (0x8000_0000)
//   2. 64-bit IFU instruction fetch at aliased base address (0x0000_0000)
//   3. 64-bit IFU instruction fetch at offset (0x8000_0008)
//   4. 64-bit LSU store and readback in DMEM (0x0004_0100)
//   5. Direct memory array inspection in u_soc_top.u_dmem.mem
//   6. 32-bit LSU store and load at DMEM base (0x0004_0000, lower word lane addr[2]=0)
//   7. 32-bit LSU store and load at DMEM word 1 (0x0004_0004, upper word lane addr[2]=1)
//   8. 64-bit LSU readback assembling consecutive 32-bit writes
//   9. Sub-word byte-level stores with individual write strobes
//  10. Handshake backpressure & data stability (RREADY stall on IFU & LSU, BREADY stall on LSU)
//  11. AW and W handshake channel decoupling (AW before W, W before AW)
//  12. SB (System Bus) master port 32-bit store and load in DMEM
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

module tb_soc_mem_access;

    // Clock and Reset
    reg clk;
    reg rst_n;

    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100 MHz clock (10 ns period)
    end

    // Test tracking counters
    integer pass_count = 0;
    integer fail_count = 0;

    // -------------------------------------------------------------------------
    // IFU master signals (64-bit)
    // -------------------------------------------------------------------------
    reg         ifu_axi_awvalid;
    wire        ifu_axi_awready;
    reg  [7:0]  ifu_axi_awid;
    reg  [31:0] ifu_axi_awaddr;
    reg  [7:0]  ifu_axi_awlen;
    reg  [2:0]  ifu_axi_awsize;
    reg  [1:0]  ifu_axi_awburst;
    reg         ifu_axi_awlock;
    reg  [3:0]  ifu_axi_awcache;
    reg  [2:0]  ifu_axi_awprot;
    reg  [3:0]  ifu_axi_awqos;
    reg  [3:0]  ifu_axi_awregion;
    reg         ifu_axi_wvalid;
    wire        ifu_axi_wready;
    reg  [63:0] ifu_axi_wdata;
    reg  [7:0]  ifu_axi_wstrb;
    reg         ifu_axi_wlast;
    wire        ifu_axi_bvalid;
    reg         ifu_axi_bready;
    wire [1:0]  ifu_axi_bresp;
    wire [7:0]  ifu_axi_bid;
    reg         ifu_axi_arvalid;
    wire        ifu_axi_arready;
    reg  [7:0]  ifu_axi_arid;
    reg  [31:0] ifu_axi_araddr;
    reg  [7:0]  ifu_axi_arlen;
    reg  [2:0]  ifu_axi_arsize;
    reg  [1:0]  ifu_axi_arburst;
    reg         ifu_axi_arlock;
    reg  [3:0]  ifu_axi_arcache;
    reg  [2:0]  ifu_axi_arprot;
    reg  [3:0]  ifu_axi_arqos;
    reg  [3:0]  ifu_axi_arregion;
    wire        ifu_axi_rvalid;
    reg         ifu_axi_rready;
    wire [7:0]  ifu_axi_rid;
    wire [63:0] ifu_axi_rdata;
    wire [1:0]  ifu_axi_rresp;
    wire        ifu_axi_rlast;

    // -------------------------------------------------------------------------
    // LSU master signals (64-bit)
    // -------------------------------------------------------------------------
    reg         lsu_axi_awvalid;
    wire        lsu_axi_awready;
    reg  [7:0]  lsu_axi_awid;
    reg  [31:0] lsu_axi_awaddr;
    reg  [7:0]  lsu_axi_awlen;
    reg  [2:0]  lsu_axi_awsize;
    reg  [1:0]  lsu_axi_awburst;
    reg         lsu_axi_awlock;
    reg  [3:0]  lsu_axi_awcache;
    reg  [2:0]  lsu_axi_awprot;
    reg  [3:0]  lsu_axi_awqos;
    reg  [3:0]  lsu_axi_awregion;
    reg         lsu_axi_wvalid;
    wire        lsu_axi_wready;
    reg  [63:0] lsu_axi_wdata;
    reg  [7:0]  lsu_axi_wstrb;
    reg         lsu_axi_wlast;
    wire        lsu_axi_bvalid;
    reg         lsu_axi_bready;
    wire [1:0]  lsu_axi_bresp;
    wire [7:0]  lsu_axi_bid;
    reg         lsu_axi_arvalid;
    wire        lsu_axi_arready;
    reg  [7:0]  lsu_axi_arid;
    reg  [31:0] lsu_axi_araddr;
    reg  [7:0]  lsu_axi_arlen;
    reg  [2:0]  lsu_axi_arsize;
    reg  [1:0]  lsu_axi_arburst;
    reg         lsu_axi_arlock;
    reg  [3:0]  lsu_axi_arcache;
    reg  [2:0]  lsu_axi_arprot;
    reg  [3:0]  lsu_axi_arqos;
    reg  [3:0]  lsu_axi_arregion;
    wire        lsu_axi_rvalid;
    reg         lsu_axi_rready;
    wire [7:0]  lsu_axi_rid;
    wire [63:0] lsu_axi_rdata;
    wire [1:0]  lsu_axi_rresp;
    wire        lsu_axi_rlast;

    // -------------------------------------------------------------------------
    // SB master signals (64-bit)
    // -------------------------------------------------------------------------
    reg         sb_axi_awvalid;
    wire        sb_axi_awready;
    reg  [7:0]  sb_axi_awid;
    reg  [31:0] sb_axi_awaddr;
    reg  [7:0]  sb_axi_awlen;
    reg  [2:0]  sb_axi_awsize;
    reg  [1:0]  sb_axi_awburst;
    reg         sb_axi_awlock;
    reg  [3:0]  sb_axi_awcache;
    reg  [2:0]  sb_axi_awprot;
    reg  [3:0]  sb_axi_awqos;
    reg  [3:0]  sb_axi_awregion;
    reg         sb_axi_wvalid;
    wire        sb_axi_wready;
    reg  [63:0] sb_axi_wdata;
    reg  [7:0]  sb_axi_wstrb;
    reg         sb_axi_wlast;
    wire        sb_axi_bvalid;
    reg         sb_axi_bready;
    wire [1:0]  sb_axi_bresp;
    wire [7:0]  sb_axi_bid;
    reg         sb_axi_arvalid;
    wire        sb_axi_arready;
    reg  [7:0]  sb_axi_arid;
    reg  [31:0] sb_axi_araddr;
    reg  [7:0]  sb_axi_arlen;
    reg  [2:0]  sb_axi_arsize;
    reg  [1:0]  sb_axi_arburst;
    reg         sb_axi_arlock;
    reg  [3:0]  sb_axi_arcache;
    reg  [2:0]  sb_axi_arprot;
    reg  [3:0]  sb_axi_arqos;
    reg  [3:0]  sb_axi_arregion;
    wire        sb_axi_rvalid;
    reg         sb_axi_rready;
    wire [7:0]  sb_axi_rid;
    wire [63:0] sb_axi_rdata;
    wire [1:0]  sb_axi_rresp;
    wire        sb_axi_rlast;

    // External peripheral I/O
    reg         uart_rx;
    wire        uart_tx;
    reg  [31:0] gpio_i;
    wire [31:0] gpio_o;
    wire [31:0] gpio_oe;
    wire        gpio_irq;
    wire        timer_irq;
    wire        rle_irq;

    // -------------------------------------------------------------------------
    // SoC Top Instantiation
    // -------------------------------------------------------------------------
    soc_top #(
        .IMEM_DEPTH(65536),
        .DMEM_DEPTH(65536)
    ) u_soc_top (
        .clk             (clk),
        .rst_n           (rst_n),

        // IFU
        .ifu_axi_awvalid (ifu_axi_awvalid),
        .ifu_axi_awready (ifu_axi_awready),
        .ifu_axi_awid    (ifu_axi_awid),
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
        .ifu_axi_bid     (ifu_axi_bid),
        .ifu_axi_arvalid (ifu_axi_arvalid),
        .ifu_axi_arready (ifu_axi_arready),
        .ifu_axi_arid    (ifu_axi_arid),
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
        .ifu_axi_rid     (ifu_axi_rid),
        .ifu_axi_rdata   (ifu_axi_rdata),
        .ifu_axi_rresp   (ifu_axi_rresp),
        .ifu_axi_rlast   (ifu_axi_rlast),

        // LSU
        .lsu_axi_awvalid (lsu_axi_awvalid),
        .lsu_axi_awready (lsu_axi_awready),
        .lsu_axi_awid    (lsu_axi_awid),
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
        .lsu_axi_bid     (lsu_axi_bid),
        .lsu_axi_arvalid (lsu_axi_arvalid),
        .lsu_axi_arready (lsu_axi_arready),
        .lsu_axi_arid    (lsu_axi_arid),
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
        .lsu_axi_rid     (lsu_axi_rid),
        .lsu_axi_rdata   (lsu_axi_rdata),
        .lsu_axi_rresp   (lsu_axi_rresp),
        .lsu_axi_rlast   (lsu_axi_rlast),

        // SB
        .sb_axi_awvalid  (sb_axi_awvalid),
        .sb_axi_awready  (sb_axi_awready),
        .sb_axi_awid     (sb_axi_awid),
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
        .sb_axi_bid      (sb_axi_bid),
        .sb_axi_arvalid  (sb_axi_arvalid),
        .sb_axi_arready  (sb_axi_arready),
        .sb_axi_arid     (sb_axi_arid),
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
        .sb_axi_rid      (sb_axi_rid),
        .sb_axi_rdata    (sb_axi_rdata),
        .sb_axi_rresp    (sb_axi_rresp),
        .sb_axi_rlast    (sb_axi_rlast),

        // Peripherals
        .uart_rx         (uart_rx),
        .uart_tx         (uart_tx),
        .gpio_i          (gpio_i),
        .gpio_o          (gpio_o),
        .gpio_oe         (gpio_oe),
        .gpio_irq        (gpio_irq),
        .timer_irq       (timer_irq),
        .rle_irq         (rle_irq)
    );

    // -------------------------------------------------------------------------
    // Verification Check Tasks
    // -------------------------------------------------------------------------
    task automatic check(input string desc, input bit cond);
        if (cond) begin
            pass_count = pass_count + 1;
            $display("  [PASS] %s", desc);
        end else begin
            fail_count = fail_count + 1;
            $display("  [FAIL] %s", desc);
        end
    endtask

    task automatic check_eq_64(input string desc, input [63:0] actual, input [63:0] expected);
        if (actual === expected) begin
            pass_count = pass_count + 1;
            $display("  [PASS] %s: actual=0x%016h", desc, actual);
        end else begin
            fail_count = fail_count + 1;
            $display("  [FAIL] %s: actual=0x%016h, expected=0x%016h", desc, actual, expected);
        end
    endtask

    task automatic check_eq_32(input string desc, input [31:0] actual, input [31:0] expected);
        if (actual === expected) begin
            pass_count = pass_count + 1;
            $display("  [PASS] %s: actual=0x%08h", desc, actual);
        end else begin
            fail_count = fail_count + 1;
            $display("  [FAIL] %s: actual=0x%08h, expected=0x%08h", desc, actual, expected);
        end
    endtask

    // -------------------------------------------------------------------------
    // AXI Bus Driver Tasks
    // -------------------------------------------------------------------------

    // 64-bit IFU Instruction Read
    task automatic ifu_read_64(
        input  [31:0] addr,
        input  [7:0]  id,
        output [63:0] data,
        output [1:0]  resp,
        output        last,
        output [7:0]  rid
    );
        @(posedge clk);
        ifu_axi_arvalid  <= 1'b1;
        ifu_axi_araddr   <= addr;
        ifu_axi_arid     <= id;
        ifu_axi_arlen    <= 8'd0;
        ifu_axi_arsize   <= 3'b011; // 64-bit
        ifu_axi_arburst  <= 2'b01;  // INCR
        ifu_axi_rready   <= 1'b1;

        @(posedge clk);
        while (!ifu_axi_arready) @(posedge clk);
        ifu_axi_arvalid  <= 1'b0;

        while (!(ifu_axi_rvalid && ifu_axi_rready)) @(posedge clk);
        data = ifu_axi_rdata;
        resp = ifu_axi_rresp;
        last = ifu_axi_rlast;
        rid  = ifu_axi_rid;
        @(posedge clk);
        ifu_axi_rready   <= 1'b0;
    endtask

    // 64-bit LSU Write (splits into 2 beats downstream)
    task automatic lsu_write_64(
        input  [31:0] addr,
        input  [7:0]  id,
        input  [63:0] data,
        input  [7:0]  strb,
        output [1:0]  resp,
        output [7:0]  bid
    );
        bit aw_done, w_done;
        aw_done = 0;
        w_done  = 0;

        @(posedge clk);
        lsu_axi_awvalid <= 1'b1;
        lsu_axi_awaddr  <= addr;
        lsu_axi_awid    <= id;
        lsu_axi_awlen   <= 8'd0;
        lsu_axi_awsize  <= 3'b011; // 64-bit
        lsu_axi_awburst <= 2'b01;

        lsu_axi_wvalid  <= 1'b1;
        lsu_axi_wdata   <= data;
        lsu_axi_wstrb   <= strb;
        lsu_axi_wlast   <= 1'b1;
        lsu_axi_bready  <= 1'b1;

        while (!aw_done || !w_done) begin
            @(posedge clk);
            if (lsu_axi_awvalid && lsu_axi_awready) begin
                aw_done = 1;
                lsu_axi_awvalid <= 1'b0;
            end
            if (lsu_axi_wvalid && lsu_axi_wready) begin
                w_done = 1;
                lsu_axi_wvalid <= 1'b0;
                lsu_axi_wlast  <= 1'b0;
            end
        end

        while (!(lsu_axi_bvalid && lsu_axi_bready)) @(posedge clk);
        resp = lsu_axi_bresp;
        bid  = lsu_axi_bid;
        @(posedge clk);
        lsu_axi_bready <= 1'b0;
    endtask

    // 64-bit LSU Read (splits into 2 beats downstream, reassembled upstream)
    task automatic lsu_read_64(
        input  [31:0] addr,
        input  [7:0]  id,
        output [63:0] data,
        output [1:0]  resp,
        output        last,
        output [7:0]  rid
    );
        @(posedge clk);
        lsu_axi_arvalid <= 1'b1;
        lsu_axi_araddr  <= addr;
        lsu_axi_arid    <= id;
        lsu_axi_arlen   <= 8'd0;
        lsu_axi_arsize  <= 3'b011; // 64-bit
        lsu_axi_arburst <= 2'b01;
        lsu_axi_rready  <= 1'b1;

        @(posedge clk);
        while (!lsu_axi_arready) @(posedge clk);
        lsu_axi_arvalid <= 1'b0;

        while (!(lsu_axi_rvalid && lsu_axi_rready)) @(posedge clk);
        data = lsu_axi_rdata;
        resp = lsu_axi_rresp;
        last = lsu_axi_rlast;
        rid  = lsu_axi_rid;
        @(posedge clk);
        lsu_axi_rready <= 1'b0;
    endtask

    // 32-bit LSU Write (single beat downstream)
    task automatic lsu_write_32(
        input  [31:0] addr,
        input  [7:0]  id,
        input  [63:0] data,
        input  [7:0]  strb,
        output [1:0]  resp,
        output [7:0]  bid
    );
        bit aw_done, w_done;
        aw_done = 0;
        w_done  = 0;

        @(posedge clk);
        lsu_axi_awvalid <= 1'b1;
        lsu_axi_awaddr  <= addr;
        lsu_axi_awid    <= id;
        lsu_axi_awlen   <= 8'd0;
        lsu_axi_awsize  <= 3'b010; // 32-bit
        lsu_axi_awburst <= 2'b01;

        lsu_axi_wvalid  <= 1'b1;
        lsu_axi_wdata   <= data;
        lsu_axi_wstrb   <= strb;
        lsu_axi_wlast   <= 1'b1;
        lsu_axi_bready  <= 1'b1;

        while (!aw_done || !w_done) begin
            @(posedge clk);
            if (lsu_axi_awvalid && lsu_axi_awready) begin
                aw_done = 1;
                lsu_axi_awvalid <= 1'b0;
            end
            if (lsu_axi_wvalid && lsu_axi_wready) begin
                w_done = 1;
                lsu_axi_wvalid <= 1'b0;
                lsu_axi_wlast  <= 1'b0;
            end
        end

        while (!(lsu_axi_bvalid && lsu_axi_bready)) @(posedge clk);
        resp = lsu_axi_bresp;
        bid  = lsu_axi_bid;
        @(posedge clk);
        lsu_axi_bready <= 1'b0;
    endtask

    // 32-bit LSU Read (single beat downstream, formatted to word lane)
    task automatic lsu_read_32(
        input  [31:0] addr,
        input  [7:0]  id,
        output [63:0] data,
        output [1:0]  resp,
        output        last,
        output [7:0]  rid
    );
        @(posedge clk);
        lsu_axi_arvalid <= 1'b1;
        lsu_axi_araddr  <= addr;
        lsu_axi_arid    <= id;
        lsu_axi_arlen   <= 8'd0;
        lsu_axi_arsize  <= 3'b010; // 32-bit
        lsu_axi_arburst <= 2'b01;
        lsu_axi_rready  <= 1'b1;

        @(posedge clk);
        while (!lsu_axi_arready) @(posedge clk);
        lsu_axi_arvalid <= 1'b0;

        while (!(lsu_axi_rvalid && lsu_axi_rready)) @(posedge clk);
        data = lsu_axi_rdata;
        resp = lsu_axi_rresp;
        last = lsu_axi_rlast;
        rid  = lsu_axi_rid;
        @(posedge clk);
        lsu_axi_rready <= 1'b0;
    endtask

    // 32-bit SB Write
    task automatic sb_write_32(
        input  [31:0] addr,
        input  [7:0]  id,
        input  [63:0] data,
        input  [7:0]  strb,
        output [1:0]  resp,
        output [7:0]  bid
    );
        bit aw_done, w_done;
        aw_done = 0;
        w_done  = 0;

        @(posedge clk);
        sb_axi_awvalid <= 1'b1;
        sb_axi_awaddr  <= addr;
        sb_axi_awid    <= id;
        sb_axi_awlen   <= 8'd0;
        sb_axi_awsize  <= 3'b010;
        sb_axi_awburst <= 2'b01;

        sb_axi_wvalid  <= 1'b1;
        sb_axi_wdata   <= data;
        sb_axi_wstrb   <= strb;
        sb_axi_wlast   <= 1'b1;
        sb_axi_bready  <= 1'b1;

        while (!aw_done || !w_done) begin
            @(posedge clk);
            if (sb_axi_awvalid && sb_axi_awready) begin
                aw_done = 1;
                sb_axi_awvalid <= 1'b0;
            end
            if (sb_axi_wvalid && sb_axi_wready) begin
                w_done = 1;
                sb_axi_wvalid <= 1'b0;
                sb_axi_wlast  <= 1'b0;
            end
        end

        while (!(sb_axi_bvalid && sb_axi_bready)) @(posedge clk);
        resp = sb_axi_bresp;
        bid  = sb_axi_bid;
        @(posedge clk);
        sb_axi_bready <= 1'b0;
    endtask

    // 32-bit SB Read
    task automatic sb_read_32(
        input  [31:0] addr,
        input  [7:0]  id,
        output [63:0] data,
        output [1:0]  resp,
        output        last,
        output [7:0]  rid
    );
        @(posedge clk);
        sb_axi_arvalid <= 1'b1;
        sb_axi_araddr  <= addr;
        sb_axi_arid    <= id;
        sb_axi_arlen   <= 8'd0;
        sb_axi_arsize  <= 3'b010;
        sb_axi_arburst <= 2'b01;
        sb_axi_rready  <= 1'b1;

        @(posedge clk);
        while (!sb_axi_arready) @(posedge clk);
        sb_axi_arvalid <= 1'b0;

        while (!(sb_axi_rvalid && sb_axi_rready)) @(posedge clk);
        data = sb_axi_rdata;
        resp = sb_axi_rresp;
        last = sb_axi_rlast;
        rid  = sb_axi_rid;
        @(posedge clk);
        sb_axi_rready <= 1'b0;
    endtask

    // Decoupled Write: AW arrives before W
    task automatic lsu_write_aw_before_w(
        input  [31:0]  addr,
        input  [7:0]   id,
        input  [63:0]  data,
        input  [7:0]   strb,
        input  integer delay_cycles,
        output [1:0]   resp,
        output [7:0]   bid
    );
        integer d;
        @(posedge clk);
        lsu_axi_awvalid <= 1'b1;
        lsu_axi_awaddr  <= addr;
        lsu_axi_awid    <= id;
        lsu_axi_awlen   <= 8'd0;
        lsu_axi_awsize  <= 3'b011;
        lsu_axi_awburst <= 2'b01;

        @(posedge clk);
        while (!lsu_axi_awready) @(posedge clk);
        lsu_axi_awvalid <= 1'b0;

        // Bubble delay cycles before W
        for (d = 0; d < delay_cycles; d = d + 1) @(posedge clk);

        lsu_axi_wvalid <= 1'b1;
        lsu_axi_wdata  <= data;
        lsu_axi_wstrb  <= strb;
        lsu_axi_wlast  <= 1'b1;
        lsu_axi_bready <= 1'b1;

        @(posedge clk);
        while (!lsu_axi_wready) @(posedge clk);
        lsu_axi_wvalid <= 1'b0;
        lsu_axi_wlast  <= 1'b0;

        while (!(lsu_axi_bvalid && lsu_axi_bready)) @(posedge clk);
        resp = lsu_axi_bresp;
        bid  = lsu_axi_bid;
        @(posedge clk);
        lsu_axi_bready <= 1'b0;
    endtask

    // Decoupled Write: W arrives before AW
    task automatic lsu_write_w_before_aw(
        input  [31:0]  addr,
        input  [7:0]   id,
        input  [63:0]  data,
        input  [7:0]   strb,
        input  integer delay_cycles,
        output [1:0]   resp,
        output [7:0]   bid
    );
        integer d;
        @(posedge clk);
        lsu_axi_wvalid <= 1'b1;
        lsu_axi_wdata  <= data;
        lsu_axi_wstrb  <= strb;
        lsu_axi_wlast  <= 1'b1;

        @(posedge clk);
        while (!lsu_axi_wready) @(posedge clk);
        lsu_axi_wvalid <= 1'b0;
        lsu_axi_wlast  <= 1'b0;

        // Bubble delay cycles before AW
        for (d = 0; d < delay_cycles; d = d + 1) @(posedge clk);

        lsu_axi_awvalid <= 1'b1;
        lsu_axi_awaddr  <= addr;
        lsu_axi_awid    <= id;
        lsu_axi_awlen   <= 8'd0;
        lsu_axi_awsize  <= 3'b011;
        lsu_axi_awburst <= 2'b01;
        lsu_axi_bready  <= 1'b1;

        @(posedge clk);
        while (!lsu_axi_awready) @(posedge clk);
        lsu_axi_awvalid <= 1'b0;

        while (!(lsu_axi_bvalid && lsu_axi_bready)) @(posedge clk);
        resp = lsu_axi_bresp;
        bid  = lsu_axi_bid;
        @(posedge clk);
        lsu_axi_bready <= 1'b0;
    endtask

    // -------------------------------------------------------------------------
    // Main Test Sequence
    // -------------------------------------------------------------------------
    reg [63:0] rd_data64;
    reg [1:0]  rd_resp;
    reg        rd_last;
    reg [7:0]  rd_id;
    reg [1:0]  wr_resp;
    reg [7:0]  wr_bid;
    integer    stall_i;

    initial begin
        // Simulation Watchdog
        #1_000_000;
        $display("\n[FATAL] Simulation timeout reached!");
        $finish(2);
    end

    initial begin
        $display("=================================================================");
        $display("tb_soc_mem_access: Starting SoC Top Memory Integration Tests");
        $display("=================================================================\n");

        // Initialize master signal lines
        rst_n           = 1'b0;
        ifu_axi_awvalid = 1'b0; ifu_axi_awid    = 8'h0; ifu_axi_awaddr = 32'h0;
        ifu_axi_awlen   = 8'h0; ifu_axi_awsize  = 3'h0; ifu_axi_awburst= 2'h0;
        ifu_axi_awlock  = 1'b0; ifu_axi_awcache = 4'h0; ifu_axi_awprot = 3'h0;
        ifu_axi_awqos   = 4'h0; ifu_axi_awregion= 4'h0;
        ifu_axi_wvalid  = 1'b0; ifu_axi_wdata   = 64'h0;ifu_axi_wstrb  = 8'h0;
        ifu_axi_wlast   = 1'b0; ifu_axi_bready  = 1'b0;
        ifu_axi_arvalid = 1'b0; ifu_axi_arid    = 8'h0; ifu_axi_araddr = 32'h0;
        ifu_axi_arlen   = 8'h0; ifu_axi_arsize  = 3'h0; ifu_axi_arburst= 2'h0;
        ifu_axi_arlock  = 1'b0; ifu_axi_arcache = 4'h0; ifu_axi_arprot = 3'h0;
        ifu_axi_arqos   = 4'h0; ifu_axi_arregion= 4'h0; ifu_axi_rready = 1'b0;

        lsu_axi_awvalid = 1'b0; lsu_axi_awid    = 8'h0; lsu_axi_awaddr = 32'h0;
        lsu_axi_awlen   = 8'h0; lsu_axi_awsize  = 3'h0; lsu_axi_awburst= 2'h0;
        lsu_axi_awlock  = 1'b0; lsu_axi_awcache = 4'h0; lsu_axi_awprot = 3'h0;
        lsu_axi_awqos   = 4'h0; lsu_axi_awregion= 4'h0;
        lsu_axi_wvalid  = 1'b0; lsu_axi_wdata   = 64'h0;lsu_axi_wstrb  = 8'h0;
        lsu_axi_wlast   = 1'b0; lsu_axi_bready  = 1'b0;
        lsu_axi_arvalid = 1'b0; lsu_axi_arid    = 8'h0; lsu_axi_araddr = 32'h0;
        lsu_axi_arlen   = 8'h0; lsu_axi_arsize  = 3'h0; lsu_axi_arburst= 2'h0;
        lsu_axi_arlock  = 1'b0; lsu_axi_arcache = 4'h0; lsu_axi_arprot = 3'h0;
        lsu_axi_arqos   = 4'h0; lsu_axi_arregion= 4'h0; lsu_axi_rready = 1'b0;

        sb_axi_awvalid  = 1'b0; sb_axi_awid     = 8'h0; sb_axi_awaddr  = 32'h0;
        sb_axi_awlen    = 8'h0; sb_axi_awsize   = 3'h0; sb_axi_awburst = 2'h0;
        sb_axi_awlock   = 1'b0; sb_axi_awcache  = 4'h0; sb_axi_awprot  = 3'h0;
        sb_axi_awqos    = 4'h0; sb_axi_awregion = 4'h0;
        sb_axi_wvalid   = 1'b0; sb_axi_wdata    = 64'h0;sb_axi_wstrb   = 8'h0;
        sb_axi_wlast    = 1'b0; sb_axi_bready   = 1'b0;
        sb_axi_arvalid  = 1'b0; sb_axi_arid     = 8'h0; sb_axi_araddr  = 32'h0;
        sb_axi_arlen    = 8'h0; sb_axi_arsize   = 3'h0; sb_axi_arburst = 2'h0;
        sb_axi_arlock   = 1'b0; sb_axi_arcache  = 4'h0; sb_axi_arprot  = 3'h0;
        sb_axi_arqos    = 4'h0; sb_axi_arregion = 4'h0; sb_axi_rready  = 1'b0;

        uart_rx = 1'b1;
        gpio_i  = 32'h0;

        // Apply reset for 5 clock cycles
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        // Preload Instruction Memory contents via hierarchical reference
        // Word 0 (offset 0): 32'h1111_2222
        // Word 1 (offset 4): 32'h3333_4444
        // Word 2 (offset 8): 32'h5555_6666
        // Word 3 (offset C): 32'h7777_8888
        u_soc_top.u_imem.mem[0] = 32'h1111_2222;
        u_soc_top.u_imem.mem[1] = 32'h3333_4444;
        u_soc_top.u_imem.mem[2] = 32'h5555_6666;
        u_soc_top.u_imem.mem[3] = 32'h7777_8888;

        // =====================================================================
        // Test 1: 64-bit IFU Fetch from VeeR Reset Vector (0x8000_0000)
        // =====================================================================
        $display("[TEST 1] 64-bit IFU Fetch from VeeR Reset Vector (0x8000_0000)");
        ifu_read_64(32'h8000_0000, 8'h01, rd_data64, rd_resp, rd_last, rd_id);
        check_eq_64("IFU fetch 0x8000_0000 assembled 64-bit data {word1, word0}",
                    rd_data64, 64'h3333_4444_1111_2222);
        check("IFU fetch response OKAY (2'b00)", rd_resp === 2'b00);
        check("IFU fetch rlast asserted", rd_last === 1'b1);
        check("IFU fetch rid preserved (0x01)", rd_id === 8'h01);

        // =====================================================================
        // Test 2: Dual-Region Symmetry: 64-bit IFU Fetch from Base (0x0000_0000)
        // =====================================================================
        $display("\n[TEST 2] Dual-Region Symmetry: 64-bit IFU Fetch from 0x0000_0000");
        ifu_read_64(32'h0000_0000, 8'h02, rd_data64, rd_resp, rd_last, rd_id);
        check_eq_64("IFU fetch 0x0000_0000 alias returns same {word1, word0}",
                    rd_data64, 64'h3333_4444_1111_2222);
        check("IFU fetch base response OKAY", rd_resp === 2'b00);
        check("IFU fetch base rlast asserted", rd_last === 1'b1);
        check("IFU fetch base rid preserved (0x02)", rd_id === 8'h02);

        // =====================================================================
        // Test 3: 64-bit IFU Fetch from Next Doubleword (0x8000_0008)
        // =====================================================================
        $display("\n[TEST 3] 64-bit IFU Fetch from Offset 0x8000_0008");
        ifu_read_64(32'h8000_0008, 8'h03, rd_data64, rd_resp, rd_last, rd_id);
        check_eq_64("IFU fetch 0x8000_0008 returns {word3, word2}",
                    rd_data64, 64'h7777_8888_5555_6666);
        check("IFU fetch 0x8000_0008 response OKAY", rd_resp === 2'b00);

        // =====================================================================
        // Test 4: 64-bit LSU Write to DMEM (0x0004_0100) & Internal RAM Inspection
        // =====================================================================
        $display("\n[TEST 4] 64-bit LSU Write to DMEM (0x0004_0100)");
        lsu_write_64(32'h0004_0100, 8'h10, 64'hCAFE_BABE_DEAD_BEEF, 8'hFF, wr_resp, wr_bid);
        check("LSU 64-bit write response OKAY", wr_resp === 2'b00);
        check("LSU 64-bit write bid match (0x10)", wr_bid === 8'h10);
        // Inspect internal DMEM word storage (0x100 >> 2 = 64)
        check_eq_32("DMEM internal mem[64] lower word", u_soc_top.u_dmem.mem[64], 32'hDEAD_BEEF);
        check_eq_32("DMEM internal mem[65] upper word", u_soc_top.u_dmem.mem[65], 32'hCAFE_BABE);

        // =====================================================================
        // Test 5: 64-bit LSU Readback from DMEM (0x0004_0100)
        // =====================================================================
        $display("\n[TEST 5] 64-bit LSU Readback from DMEM (0x0004_0100)");
        lsu_read_64(32'h0004_0100, 8'h11, rd_data64, rd_resp, rd_last, rd_id);
        check_eq_64("LSU 64-bit readback matches written value",
                    rd_data64, 64'hCAFE_BABE_DEAD_BEEF);
        check("LSU 64-bit readback response OKAY", rd_resp === 2'b00);
        check("LSU 64-bit readback rlast asserted", rd_last === 1'b1);
        check("LSU 64-bit readback rid match (0x11)", rd_id === 8'h11);

        // =====================================================================
        // Test 6: 32-bit LSU Writes and Readbacks at DMEM Base & Offset
        // =====================================================================
        $display("\n[TEST 6] 32-bit LSU Writes and Word-Lane Readbacks");
        lsu_write_32(32'h0004_0000, 8'h20, 64'h0000_0000_5555_AAAA, 8'h0F, wr_resp, wr_bid);
        check("32-bit write addr[2]=0 response OKAY", wr_resp === 2'b00);
        check_eq_32("DMEM mem[0] contains written 32-bit word", u_soc_top.u_dmem.mem[0], 32'h5555_AAAA);

        lsu_read_32(32'h0004_0000, 8'h21, rd_data64, rd_resp, rd_last, rd_id);
        check_eq_32("32-bit read addr[2]=0 placed on rdata[31:0]", rd_data64[31:0], 32'h5555_AAAA);
        check_eq_32("32-bit read addr[2]=0 upper word zero-extended", rd_data64[63:32], 32'h0000_0000);
        check("32-bit read response OKAY", rd_resp === 2'b00);

        // Upper word lane: addr[2] == 1 (0x0004_0004 -> mem[1])
        lsu_write_32(32'h0004_0004, 8'h22, 64'h1234_5678_0000_0000, 8'hF0, wr_resp, wr_bid);
        check("32-bit write addr[2]=1 response OKAY", wr_resp === 2'b00);
        check_eq_32("DMEM mem[1] contains written 32-bit word", u_soc_top.u_dmem.mem[1], 32'h1234_5678);

        lsu_read_32(32'h0004_0004, 8'h23, rd_data64, rd_resp, rd_last, rd_id);
        check_eq_32("32-bit read addr[2]=1 placed on rdata[63:32]", rd_data64[63:32], 32'h1234_5678);
        check_eq_32("32-bit read addr[2]=1 lower word zero-extended", rd_data64[31:0], 32'h0000_0000);
        check("32-bit read response OKAY", rd_resp === 2'b00);
        check_eq_32("32-bit read addr[2]=1 placed on rdata[63:32]", rd_data64[63:32], 32'h1234_5678);
        check_eq_32("32-bit read addr[2]=1 lower word zero-extended", rd_data64[31:0], 32'h0000_0000);
        check("32-bit read response OKAY", rd_resp === 2'b00);

        // =====================================================================
        // Test 7: 64-bit Readback of Consecutive 32-bit Writes (0x0004_0000)
        // =====================================================================
        $display("\n[TEST 7] 64-bit Readback of Consecutive 32-bit Stores");
        lsu_read_64(32'h0004_0000, 8'h24, rd_data64, rd_resp, rd_last, rd_id);
        check_eq_64("64-bit load correctly assemblies {mem[1], mem[0]}",
                    rd_data64, 64'h1234_5678_5555_AAAA);

        // =====================================================================
        // Test 8: Byte-level Sub-word Writes with Byte Strobes
        // =====================================================================
        $display("\n[TEST 8] Byte-level Sub-word Writes to DMEM Word 8 (0x0004_0020)");
        // Write byte 0 (strb 8'h01)
        lsu_write_32(32'h0004_0020, 8'h30, 64'h0000_0000_0000_00A1, 8'h01, wr_resp, wr_bid);
        // Write byte 1 (strb 8'h02)
        lsu_write_32(32'h0004_0020, 8'h31, 64'h0000_0000_0000_B200, 8'h02, wr_resp, wr_bid);
        // Write byte 2 (strb 8'h04)
        lsu_write_32(32'h0004_0020, 8'h32, 64'h0000_0000_00C3_0000, 8'h04, wr_resp, wr_bid);
        // Write byte 3 (strb 8'h08)
        lsu_write_32(32'h0004_0020, 8'h33, 64'h0000_0000_D400_0000, 8'h08, wr_resp, wr_bid);
        check_eq_32("DMEM mem[8] assembled byte by byte", u_soc_top.u_dmem.mem[8], 32'hD4C3_B2A1);

        // Write upper word lane byte (addr[2]=1, offset 0x0004_0026 -> byte 2 of mem[9])
        lsu_write_32(32'h0004_0024, 8'h34, 64'h00EE_0000_0000_0000, 8'h40, wr_resp, wr_bid);
        check_eq_32("DMEM mem[9] byte 2 written via wstrb[6]",
                    {8'h0, u_soc_top.u_dmem.mem[9][23:16], 16'h0}, 32'h00EE_0000);

        // =====================================================================
        // Test 9: Backpressure Tolerance & Data Stability
        // =====================================================================
        $display("\n[TEST 9] Handshake Backpressure & Data Stability Checks");

        // --- 9A: IFU Read with RREADY stalled ---
        @(posedge clk);
        ifu_axi_arvalid <= 1'b1;
        ifu_axi_araddr  <= 32'h8000_0000;
        ifu_axi_arid    <= 8'h40;
        ifu_axi_arlen   <= 8'd0;
        ifu_axi_arsize  <= 3'b011;
        ifu_axi_arburst <= 2'b01;
        ifu_axi_rready  <= 1'b0; // STALL RREADY

        @(posedge clk);
        while (!ifu_axi_arready) @(posedge clk);
        ifu_axi_arvalid <= 1'b0;

        // Wait until rvalid asserts while rready is stalled
        while (!ifu_axi_rvalid) @(posedge clk);

        // Verify rdata and control signals remain completely stable for 5 cycles
        for (stall_i = 0; stall_i < 5; stall_i = stall_i + 1) begin
            check_eq_64("IFU rdata stability during rready stall",
                        ifu_axi_rdata, 64'h3333_4444_1111_2222);
            check("IFU rvalid held high during stall", ifu_axi_rvalid === 1'b1);
            check("IFU rlast held high during stall", ifu_axi_rlast === 1'b1);
            @(posedge clk);
        end
        // Release stall
        ifu_axi_rready <= 1'b1;
        @(posedge clk);
        ifu_axi_rready <= 1'b0;

        // --- 9B: LSU Write with BREADY stalled ---
        @(posedge clk);
        lsu_axi_awvalid <= 1'b1;
        lsu_axi_awaddr  <= 32'h0004_0200;
        lsu_axi_awid    <= 8'h41;
        lsu_axi_awlen   <= 8'd0;
        lsu_axi_awsize  <= 3'b011;
        lsu_axi_awburst <= 2'b01;

        lsu_axi_wvalid  <= 1'b1;
        lsu_axi_wdata   <= 64'h9999_8888_7777_6666;
        lsu_axi_wstrb   <= 8'hFF;
        lsu_axi_wlast   <= 1'b1;
        lsu_axi_bready  <= 1'b0; // STALL BREADY

        @(posedge clk);
        while (!(lsu_axi_awready && lsu_axi_wready)) @(posedge clk);
        lsu_axi_awvalid <= 1'b0;
        lsu_axi_wvalid  <= 1'b0;
        lsu_axi_wlast   <= 1'b0;

        while (!lsu_axi_bvalid) @(posedge clk);
        for (stall_i = 0; stall_i < 5; stall_i = stall_i + 1) begin
            check("LSU bvalid held high during bready stall", lsu_axi_bvalid === 1'b1);
            check("LSU bresp stays OKAY during stall", lsu_axi_bresp === 2'b00);
            check("LSU bid stays matched during stall", lsu_axi_bid === 8'h41);
            @(posedge clk);
        end
        lsu_axi_bready <= 1'b1;
        @(posedge clk);
        lsu_axi_bready <= 1'b0;

        // Verify written data landed in DMEM (0x200 >> 2 = 128)
        check_eq_32("DMEM mem[128] written under B backpressure",
                    u_soc_top.u_dmem.mem[128], 32'h7777_6666);
        check_eq_32("DMEM mem[129] written under B backpressure",
                    u_soc_top.u_dmem.mem[129], 32'h9999_8888);

        // --- 9C: LSU Read with RREADY stalled ---
        @(posedge clk);
        lsu_axi_arvalid <= 1'b1;
        lsu_axi_araddr  <= 32'h0004_0200;
        lsu_axi_arid    <= 8'h42;
        lsu_axi_arlen   <= 8'd0;
        lsu_axi_arsize  <= 3'b011;
        lsu_axi_arburst <= 2'b01;
        lsu_axi_rready  <= 1'b0; // STALL RREADY

        @(posedge clk);
        while (!lsu_axi_arready) @(posedge clk);
        lsu_axi_arvalid <= 1'b0;

        while (!lsu_axi_rvalid) @(posedge clk);
        for (stall_i = 0; stall_i < 5; stall_i = stall_i + 1) begin
            check_eq_64("LSU rdata stability during rready stall",
                        lsu_axi_rdata, 64'h9999_8888_7777_6666);
            check("LSU rvalid held during stall", lsu_axi_rvalid === 1'b1);
            check("LSU rlast held during stall", lsu_axi_rlast === 1'b1);
            @(posedge clk);
        end
        lsu_axi_rready <= 1'b1;
        @(posedge clk);
        lsu_axi_rready <= 1'b0;

        // =====================================================================
        // Test 10: AW and W Handshake Decoupling
        // =====================================================================
        $display("\n[TEST 10] AW and W Channel Decoupling Tests");

        // 10A: AW presented 5 cycles BEFORE W
        lsu_write_aw_before_w(32'h0004_0210, 8'h50, 64'hAAAA_BBBB_CCCC_DDDD, 8'hFF, 5, wr_resp, wr_bid);
        check("AW-before-W write response OKAY", wr_resp === 2'b00);
        check_eq_32("AW-before-W DMEM mem[132]", u_soc_top.u_dmem.mem[132], 32'hCCCC_DDDD);
        check_eq_32("AW-before-W DMEM mem[133]", u_soc_top.u_dmem.mem[133], 32'hAAAA_BBBB);

        // 10B: W presented 5 cycles BEFORE AW
        lsu_write_w_before_aw(32'h0004_0218, 8'h51, 64'h1122_3344_5566_7788, 8'hFF, 5, wr_resp, wr_bid);
        check("W-before-AW write response OKAY", wr_resp === 2'b00);
        check_eq_32("W-before-AW DMEM mem[134]", u_soc_top.u_dmem.mem[134], 32'h5566_7788);
        check_eq_32("W-before-AW DMEM mem[135]", u_soc_top.u_dmem.mem[135], 32'h1122_3344);

        // =====================================================================
        // Test 11: System Bus (SB) Master Port Transactions
        // =====================================================================
        $display("\n[TEST 11] System Bus (SB) Master Port Transactions");
        sb_write_32(32'h0004_0300, 8'h60, 64'h0000_0000_FEED_FACE, 8'h0F, wr_resp, wr_bid);
        check("SB 32-bit write response OKAY", wr_resp === 2'b00);
        check_eq_32("DMEM mem[192] written via SB master", u_soc_top.u_dmem.mem[192], 32'hFEED_FACE);

        sb_read_32(32'h0004_0300, 8'h61, rd_data64, rd_resp, rd_last, rd_id);
        check_eq_32("SB 32-bit readback data matches", rd_data64[31:0], 32'hFEED_FACE);
        check("SB 32-bit readback response OKAY", rd_resp === 2'b00);
        check("SB 32-bit readback rid matches (0x61)", rd_id === 8'h61);

        // =====================================================================
        // Final Summary
        // =====================================================================
        $display("\n=================================================================");
        $display("tb_soc_mem_access: SIMULATION COMPLETE");
        $display("PASSED checks: %0d", pass_count);
        $display("FAILED checks: %0d", fail_count);
        $display("=================================================================");

        if (fail_count == 0) begin
            $display("[RESULT] ALL TESTS PASSED SUCCESSFULLY!\n");
            $finish(0);
        end else begin
            $display("[RESULT] SOME TESTS FAILED!\n");
            $finish(1);
        end
    end

endmodule

`default_nettype wire
