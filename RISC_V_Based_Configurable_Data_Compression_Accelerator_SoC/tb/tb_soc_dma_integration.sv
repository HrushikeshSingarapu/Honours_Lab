// =============================================================================
// tb_soc_dma_integration.sv
//
// SoC-Level Direct Memory Access (DMA) Integration Testbench.
// RISC-V Based Configurable Data Compression Accelerator SoC.
//
// Verification Scope:
//   1. Full SoC Integration with real AXI4 Interconnect (4x8 Crossbar),
//      real Data Memory (DMEM), real RLE Accelerator, and DMA Controller IP.
//   2. CPU MMIO register configuration of DMA via LSU (64-to-32 bridge).
//   3. Autonomous DMA memory-to-peripheral (DMEM -> RLE) transfer.
//   4. Autonomous DMA peripheral-to-memory (RLE -> DMEM) transfer.
//   5. DMA interrupt generation, status reflection, and W1C clearing.
//   6. End-to-end hardware Compression (DMEM -> DMA -> RLE -> DMA -> DMEM).
//   7. End-to-end hardware Decompression (DMEM -> DMA -> RLE -> DMA -> DMEM).
//   8. Partial word writes and correct byte strobes (WSTRB).
//   9. Error trapping and status reporting.
//  10. Verdi FSDB waveform dump generation.
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

module tb_soc_dma_integration;

    // =========================================================================
    // Clock & Reset Generation
    // =========================================================================
    reg clk;
    reg rst_n;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk; // 100 MHz clock (10 ns period)
    end

    // Test tracking counters
    integer pass_count = 0;
    integer fail_count = 0;
    integer test_id    = 0;

    // =========================================================================
    // Master Port Interfaces to soc_top (VeeR-facing 64-bit)
    // =========================================================================

    // IFU master signals (64-bit, tied idle)
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

    // LSU master signals (64-bit, CPU load/store transactions)
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

    // SB master signals (64-bit, tied idle)
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

    // External Peripheral I/O
    reg         uart_rx;
    wire        uart_tx;
    reg  [31:0] gpio_i;
    wire [31:0] gpio_o;
    wire [31:0] gpio_oe;

    // Interrupt Outputs
    wire        gpio_irq;
    wire        timer_irq;
    wire        rle_irq;
    wire        dma_irq;

    // =========================================================================
    // SoC Top Instance (DUT)
    // =========================================================================
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
        .rle_irq         (rle_irq),
        .dma_irq         (dma_irq)
    );

    // =========================================================================
    // Address Map Definitions
    // =========================================================================
    localparam [31:0] DMEM_BASE_ADDR        = 32'h0004_0000;
    localparam [31:0] DMA_BASE_ADDR         = 32'h1001_1000;

    // DMA Register Offsets
    localparam [31:0] REG_DMA_CONTROL       = DMA_BASE_ADDR + 32'h000;
    localparam [31:0] REG_DMA_STATUS        = DMA_BASE_ADDR + 32'h004;
    localparam [31:0] REG_DMA_SRC_ADDR      = DMA_BASE_ADDR + 32'h008;
    localparam [31:0] REG_DMA_DST_ADDR      = DMA_BASE_ADDR + 32'h00C;
    localparam [31:0] REG_DMA_INPUT_LEN     = DMA_BASE_ADDR + 32'h010;
    localparam [31:0] REG_DMA_OUTPUT_LEN    = DMA_BASE_ADDR + 32'h014;
    localparam [31:0] REG_DMA_IRQ_ENABLE    = DMA_BASE_ADDR + 32'h018;
    localparam [31:0] REG_DMA_IRQ_STATUS    = DMA_BASE_ADDR + 32'h01C;
    localparam [31:0] REG_DMA_ERROR_CODE    = DMA_BASE_ADDR + 32'h020;

    // =========================================================================
    // Verification Check Helper Task
    // =========================================================================
    task check(input string desc, input bit condition);
        begin
            test_id = test_id + 1;
            if (condition) begin
                $display("[PASS] #%0d: %s", test_id, desc);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] #%0d: %s", test_id, desc);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // =========================================================================
    // CPU 32-bit MMIO / Memory Access Tasks (via LSU 64-bit Master)
    // =========================================================================
    task automatic cpu_write(
        input  [31:0] addr,
        input  [31:0] data,
        input  [3:0]  byte_en,
        output [1:0]  resp
    );
        bit aw_done, w_done;
        reg [63:0] wdata_64;
        reg [7:0]  wstrb_64;

        aw_done = 0;
        w_done  = 0;

        // Position 32-bit data into correct 64-bit word lane based on addr[2]
        if (addr[2]) begin
            wdata_64 = {data, 32'h0};
            wstrb_64 = {byte_en, 4'h0};
        end else begin
            wdata_64 = {32'h0, data};
            wstrb_64 = {4'h0, byte_en};
        end

        @(posedge clk);
        lsu_axi_awvalid <= 1'b1;
        lsu_axi_awaddr  <= addr;
        lsu_axi_awid    <= 8'h01;
        lsu_axi_awlen   <= 8'd0;
        lsu_axi_awsize  <= 3'b010; // 32-bit beat
        lsu_axi_awburst <= 2'b01;

        lsu_axi_wvalid  <= 1'b1;
        lsu_axi_wdata   <= wdata_64;
        lsu_axi_wstrb   <= wstrb_64;
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
        @(posedge clk);
        lsu_axi_bready <= 1'b0;
    endtask

    task automatic cpu_read(
        input  [31:0] addr,
        output [31:0] data,
        output [1:0]  resp
    );
        reg [63:0] rdata_64;

        @(posedge clk);
        lsu_axi_arvalid <= 1'b1;
        lsu_axi_araddr  <= addr;
        lsu_axi_arid    <= 8'h01;
        lsu_axi_arlen   <= 8'd0;
        lsu_axi_arsize  <= 3'b010; // 32-bit beat
        lsu_axi_arburst <= 2'b01;
        lsu_axi_rready  <= 1'b1;

        @(posedge clk);
        while (!lsu_axi_arready) @(posedge clk);
        lsu_axi_arvalid <= 1'b0;

        while (!(lsu_axi_rvalid && lsu_axi_rready)) @(posedge clk);
        rdata_64 = lsu_axi_rdata;
        resp     = lsu_axi_rresp;

        if (addr[2]) begin
            data = rdata_64[63:32];
        end else begin
            data = rdata_64[31:0];
        end

        @(posedge clk);
        lsu_axi_rready <= 1'b0;
    endtask

    // =========================================================================
    // Main Verification Flow
    // =========================================================================
    initial begin
        reg [31:0] rdata;
        reg [1:0]  resp;
        integer    i;
        integer    timeout;

        // Waveform dumping setup
        $fsdbDumpfile("soc_dma_integration.fsdb");
        $fsdbDumpvars(0, tb_soc_dma_integration);

        $display("");
        $display("================================================================");
        $display("   SoC DMA INTEGRATION (tb_soc_dma_integration) TESTBENCH       ");
        $display("================================================================");

        // Initialize signals
        rst_n            = 1'b0;
        ifu_axi_awvalid  = 1'b0;
        ifu_axi_awid     = 8'h00;
        ifu_axi_awaddr   = 32'h0;
        ifu_axi_awlen    = 8'h0;
        ifu_axi_awsize   = 3'b011;
        ifu_axi_awburst  = 2'b01;
        ifu_axi_awlock   = 1'b0;
        ifu_axi_awcache  = 4'h0;
        ifu_axi_awprot   = 3'h0;
        ifu_axi_awqos    = 4'h0;
        ifu_axi_awregion = 4'h0;
        ifu_axi_wvalid   = 1'b0;
        ifu_axi_wdata    = 64'h0;
        ifu_axi_wstrb    = 8'h0;
        ifu_axi_wlast    = 1'b0;
        ifu_axi_bready   = 1'b0;
        ifu_axi_arvalid  = 1'b0;
        ifu_axi_arid     = 8'h00;
        ifu_axi_araddr   = 32'h0;
        ifu_axi_arlen    = 8'h0;
        ifu_axi_arsize   = 3'b011;
        ifu_axi_arburst  = 2'b01;
        ifu_axi_arlock   = 1'b0;
        ifu_axi_arcache  = 4'h0;
        ifu_axi_arprot   = 3'h0;
        ifu_axi_arqos    = 4'h0;
        ifu_axi_arregion = 4'h0;
        ifu_axi_rready   = 1'b0;

        lsu_axi_awvalid  = 1'b0;
        lsu_axi_awid     = 8'h00;
        lsu_axi_awaddr   = 32'h0;
        lsu_axi_awlen    = 8'h0;
        lsu_axi_awsize   = 3'b010;
        lsu_axi_awburst  = 2'b01;
        lsu_axi_awlock   = 1'b0;
        lsu_axi_awcache  = 4'h0;
        lsu_axi_awprot   = 3'h0;
        lsu_axi_awqos    = 4'h0;
        lsu_axi_awregion = 4'h0;
        lsu_axi_wvalid   = 1'b0;
        lsu_axi_wdata    = 64'h0;
        lsu_axi_wstrb    = 8'h0;
        lsu_axi_wlast    = 1'b0;
        lsu_axi_bready   = 1'b0;
        lsu_axi_arvalid  = 1'b0;
        lsu_axi_arid     = 8'h00;
        lsu_axi_araddr   = 32'h0;
        lsu_axi_arlen    = 8'h0;
        lsu_axi_arsize   = 3'b010;
        lsu_axi_arburst  = 2'b01;
        lsu_axi_arlock   = 1'b0;
        lsu_axi_arcache  = 4'h0;
        lsu_axi_arprot   = 3'h0;
        lsu_axi_arqos    = 4'h0;
        lsu_axi_arregion = 4'h0;
        lsu_axi_rready   = 1'b0;

        sb_axi_awvalid   = 1'b0;
        sb_axi_awid      = 8'h00;
        sb_axi_awaddr    = 32'h0;
        sb_axi_awlen     = 8'h0;
        sb_axi_awsize    = 3'b010;
        sb_axi_awburst   = 2'b01;
        sb_axi_awlock    = 1'b0;
        sb_axi_awcache   = 4'h0;
        sb_axi_awprot    = 3'h0;
        sb_axi_awqos     = 4'h0;
        sb_axi_awregion  = 4'h0;
        sb_axi_wvalid    = 1'b0;
        sb_axi_wdata     = 64'h0;
        sb_axi_wstrb     = 8'h0;
        sb_axi_wlast     = 1'b0;
        sb_axi_bready    = 1'b0;
        sb_axi_arvalid   = 1'b0;
        sb_axi_arid      = 8'h00;
        sb_axi_araddr    = 32'h0;
        sb_axi_arlen     = 8'h0;
        sb_axi_arsize    = 3'b010;
        sb_axi_arburst   = 2'b01;
        sb_axi_arlock    = 1'b0;
        sb_axi_arcache   = 4'h0;
        sb_axi_arprot    = 3'h0;
        sb_axi_arqos     = 4'h0;
        sb_axi_arregion  = 4'h0;
        sb_axi_rready    = 1'b0;

        uart_rx          = 1'b1;
        gpio_i           = 32'h0;

        // Reset Pulse
        #100;
        @(posedge clk);
        rst_n = 1'b1;
        #100;
        @(posedge clk);

        // =====================================================================
        // TEST 1: CPU MMIO Access to DMA Registers
        // =====================================================================
        $display("");
        $display("--- Test Group 1: CPU MMIO Access to DMA Registers ---");

        cpu_read(REG_DMA_STATUS, rdata, resp);
        check("DMA STATUS reads OKAY (0x00)", resp == 2'b00);
        check("DMA STATUS reset value is 0x0000_0000", rdata == 32'h0000_0000);

        cpu_read(REG_DMA_SRC_ADDR, rdata, resp);
        check("DMA SRC_ADDR reads default 0x0004_0000", rdata == 32'h0004_0000);

        cpu_read(REG_DMA_DST_ADDR, rdata, resp);
        check("DMA DST_ADDR reads default 0x0004_0100", rdata == 32'h0004_0100);

        // Write configuration registers
        cpu_write(REG_DMA_SRC_ADDR, 32'h0004_1000, 4'hF, resp);
        check("Write DMA SRC_ADDR completes OKAY", resp == 2'b00);
        cpu_read(REG_DMA_SRC_ADDR, rdata, resp);
        check("Readback DMA SRC_ADDR is 0x0004_1000", rdata == 32'h0004_1000);

        cpu_write(REG_DMA_DST_ADDR, 32'h0004_2000, 4'hF, resp);
        check("Write DMA DST_ADDR completes OKAY", resp == 2'b00);
        cpu_read(REG_DMA_DST_ADDR, rdata, resp);
        check("Readback DMA DST_ADDR is 0x0004_2000", rdata == 32'h0004_2000);

        cpu_write(REG_DMA_INPUT_LEN, 32'd16, 4'hF, resp);
        check("Write DMA INPUT_LEN (16) completes OKAY", resp == 2'b00);
        cpu_read(REG_DMA_INPUT_LEN, rdata, resp);
        check("Readback DMA INPUT_LEN is 16", rdata == 32'd16);

        cpu_write(REG_DMA_IRQ_ENABLE, 32'h1, 4'hF, resp);
        check("Enable DMA Interrupt (IRQ_ENABLE = 1)", resp == 2'b00);
        cpu_read(REG_DMA_IRQ_ENABLE, rdata, resp);
        check("Readback DMA IRQ_ENABLE is 1", rdata == 32'h1);

        // =====================================================================
        // TEST 2: Autonomous Hardware Compression (16 bytes -> 8 bytes)
        // =====================================================================
        $display("");
        $display("--- Test Group 2: End-to-End Compression Transfer (16 -> 8 bytes) ---");

        // Step 2.1: CPU populates input buffer in SoC DMEM at 0x0004_1000
        // Data: 4x 0x11, 4x 0x22, 4x 0x33, 4x 0x44 (little endian words)
        cpu_write(32'h0004_1000, 32'h1111_1111, 4'hF, resp);
        cpu_write(32'h0004_1004, 32'h2222_2222, 4'hF, resp);
        cpu_write(32'h0004_1008, 32'h3333_3333, 4'hF, resp);
        cpu_write(32'h0004_100C, 32'h4444_4444, 4'hF, resp);

        // Clear destination DMEM at 0x0004_2000
        cpu_write(32'h0004_2000, 32'h0000_0000, 4'hF, resp);
        cpu_write(32'h0004_2004, 32'h0000_0000, 4'hF, resp);

        // Step 2.2: CPU starts DMA compression (MODE = 0, START = 1)
        check("dma_irq initially low", dma_irq === 1'b0);
        cpu_write(REG_DMA_CONTROL, 32'h0000_0001, 4'hF, resp);
        check("CPU issued DMA START command", resp == 2'b00);

        // Step 2.3: Wait for DMA interrupt assertion
        timeout = 2000;
        while (!dma_irq && timeout > 0) begin
            @(posedge clk);
            timeout = timeout - 1;
        end
        check("DMA completed and asserted dma_irq within timeout", dma_irq === 1'b1);

        // Step 2.4: CPU reads status, output length, and error code
        cpu_read(REG_DMA_STATUS, rdata, resp);
        check("DMA STATUS DONE bit is set (bit 1 == 1)", (rdata & 32'h2) != 0);
        check("DMA STATUS BUSY bit is cleared (bit 0 == 0)", (rdata & 32'h1) == 0);

        cpu_read(REG_DMA_OUTPUT_LEN, rdata, resp);
        check("DMA OUTPUT_LEN is 8 bytes (16 compressed to 8)", rdata == 32'd8);

        cpu_read(REG_DMA_ERROR_CODE, rdata, resp);
        check("DMA ERROR_CODE is ERR_NONE (0x00)", rdata == 32'h00);

        // Step 2.5: CPU clears interrupt via W1C
        cpu_write(REG_DMA_IRQ_STATUS, 32'h0000_0001, 4'hF, resp);
        @(posedge clk);
        check("dma_irq successfully deasserted after W1C clear", dma_irq === 1'b0);

        // Step 2.6: Verify compressed records in SoC DMEM at 0x0004_2000
        // Record 0: [4, 0x11] = 16'h1104
        // Record 1: [4, 0x22] = 16'h2204
        // Word 0 (0x0004_2000): 32'h2204_1104
        cpu_read(32'h0004_2000, rdata, resp);
        check("Destination DMEM Word 0 matches [4, 0x11] & [4, 0x22]", rdata == 32'h2204_1104);

        // Record 2: [4, 0x33] = 16'h3304
        // Record 3: [4, 0x44] = 16'h4404
        // Word 1 (0x0004_2004): 32'h4404_3304
        cpu_read(32'h0004_2004, rdata, resp);
        check("Destination DMEM Word 1 matches [4, 0x33] & [4, 0x44]", rdata == 32'h4404_3304);

        // =====================================================================
        // TEST 3: Autonomous Hardware Decompression (8 bytes -> 16 bytes)
        // =====================================================================
        $display("");
        $display("--- Test Group 3: End-to-End Decompression Transfer (8 -> 16 bytes) ---");

        // Clear decompression target in DMEM at 0x0004_3000
        cpu_write(32'h0004_3000, 32'h0000_0000, 4'hF, resp);
        cpu_write(32'h0004_3004, 32'h0000_0000, 4'hF, resp);
        cpu_write(32'h0004_3008, 32'h0000_0000, 4'hF, resp);
        cpu_write(32'h0004_300C, 32'h0000_0000, 4'hF, resp);

        // Configure DMA for decompression:
        // SRC = 0x0004_2000 (compressed output from Test 2)
        // DST = 0x0004_3000 (new decompressed buffer)
        // INPUT_LEN = 8 bytes
        // MODE = 1 (Decompression)
        cpu_write(REG_DMA_SRC_ADDR, 32'h0004_2000, 4'hF, resp);
        cpu_write(REG_DMA_DST_ADDR, 32'h0004_3000, 4'hF, resp);
        cpu_write(REG_DMA_INPUT_LEN, 32'd8, 4'hF, resp);

        // Start decompression (MODE = 1, START = 1 -> CONTROL = 0x3)
        cpu_write(REG_DMA_CONTROL, 32'h0000_0003, 4'hF, resp);

        timeout = 2000;
        while (!dma_irq && timeout > 0) begin
            @(posedge clk);
            timeout = timeout - 1;
        end
        check("Decompression completed and asserted dma_irq", dma_irq === 1'b1);

        cpu_read(REG_DMA_OUTPUT_LEN, rdata, resp);
        check("Decompressed output length is 16 bytes", rdata == 32'd16);

        // Clear IRQ
        cpu_write(REG_DMA_IRQ_STATUS, 32'h1, 4'hF, resp);
        @(posedge clk);
        check("dma_irq cleared", dma_irq === 1'b0);

        // Verify all 16 decompressed bytes match original data byte-for-byte
        cpu_read(32'h0004_3000, rdata, resp);
        check("Decompressed Word 0 matches original 0x1111_1111", rdata == 32'h1111_1111);

        cpu_read(32'h0004_3004, rdata, resp);
        check("Decompressed Word 1 matches original 0x2222_2222", rdata == 32'h2222_2222);

        cpu_read(32'h0004_3008, rdata, resp);
        check("Decompressed Word 2 matches original 0x3333_3333", rdata == 32'h3333_3333);

        cpu_read(32'h0004_300C, rdata, resp);
        check("Decompressed Word 3 matches original 0x4444_4444", rdata == 32'h4444_4444);

        // =====================================================================
        // TEST 4: Odd Length & Partial Word Transfer (5 bytes -> 2 bytes)
        // =====================================================================
        $display("");
        $display("--- Test Group 4: Odd Length Transfer with Partial Final Word ---");

        // 5 bytes of 0x55:
        // Word 0 (0x0004_1040): 4x 0x55 = 32'h5555_5555
        // Word 1 (0x0004_1044): 1x 0x55 = 32'h0000_0055 (byte 0 only)
        cpu_write(32'h0004_1040, 32'h5555_5555, 4'hF, resp);
        cpu_write(32'h0004_1044, 32'h0000_0055, 4'hF, resp);

        // Pre-fill destination with sentinel pattern 32'hDEAD_BEEF
        cpu_write(32'h0004_2040, 32'hDEAD_BEEF, 4'hF, resp);

        cpu_write(REG_DMA_SRC_ADDR, 32'h0004_1040, 4'hF, resp);
        cpu_write(REG_DMA_DST_ADDR, 32'h0004_2040, 4'hF, resp);
        cpu_write(REG_DMA_INPUT_LEN, 32'd5, 4'hF, resp);

        // Start compression (MODE = 0, START = 1)
        cpu_write(REG_DMA_CONTROL, 32'h0000_0001, 4'hF, resp);

        timeout = 2000;
        while (!dma_irq && timeout > 0) begin
            @(posedge clk);
            timeout = timeout - 1;
        end
        check("5-byte transfer completed and asserted dma_irq", dma_irq === 1'b1);

        cpu_read(REG_DMA_OUTPUT_LEN, rdata, resp);
        check("5 bytes of 0x55 compressed to 2 bytes [5, 0x55]", rdata == 32'd2);

        // Clear IRQ
        cpu_write(REG_DMA_IRQ_STATUS, 32'h1, 4'hF, resp);
        @(posedge clk);
        check("dma_irq cleared", dma_irq === 1'b0);

        // Verify partial write: only lower 2 bytes modified (count=5, sym=0x55) = 16'h5505
        // Upper 2 bytes must remain intact (0xDEAD) from pre-fill!
        cpu_read(32'h0004_2040, rdata, resp);
        check("Partial word destination contains [5, 0x55] and preserves upper bytes", rdata == 32'hDEAD_5505);

        // =====================================================================
        // TEST 5: Parameter Error Trapping (Invalid Length 0)
        // =====================================================================
        $display("");
        $display("--- Test Group 5: Parameter Error Trapping ---");

        // Enable both DONE and ERROR interrupts (bit 0 = DONE_IE, bit 1 = ERR_IE)
        cpu_write(REG_DMA_IRQ_ENABLE, 32'h3, 4'hF, resp);
        cpu_write(REG_DMA_INPUT_LEN, 32'd0, 4'hF, resp);
        cpu_write(REG_DMA_CONTROL, 32'h0000_0001, 4'hF, resp);

        @(posedge clk);
        @(posedge clk);

        check("dma_irq asserted on error condition", dma_irq === 1'b1);
        cpu_read(REG_DMA_STATUS, rdata, resp);
        check("DMA STATUS ERROR bit is set (bit 2 == 1)", (rdata & 32'h4) != 0);

        cpu_read(REG_DMA_ERROR_CODE, rdata, resp);
        check("DMA ERROR_CODE is ERR_BAD_LEN (0x03)", rdata == 32'h03);

        // Clear ERROR IRQ via W1C on bit 1
        cpu_write(REG_DMA_IRQ_STATUS, 32'h2, 4'hF, resp);
        @(posedge clk);
        check("dma_irq cleared after error acknowledgement", dma_irq === 1'b0);

        // =====================================================================
        // Test Summary
        // =====================================================================
        #100;
        $display("");
        $display("================================================================");
        $display("   SoC DMA INTEGRATION TESTBENCH SUMMARY                        ");
        $display("================================================================");
        $display("  Total Checks Executed : %0d", test_id);
        $display("  Passed Checks         : %0d", pass_count);
        $display("  Failed Checks         : %0d", fail_count);
        $display("================================================================");

        if (fail_count == 0) begin
            $display(">>> ALL SoC DMA INTEGRATION CHECKS PASSED SUCCESSFULLY! <<<");
        end else begin
            $display(">>> ERROR: %0d CHECKS FAILED! <<<", fail_count);
        end
        $display("================================================================");
        $display("");

        $finish;
    end

endmodule

`default_nettype wire
