// =============================================================================
// tb_soc_address_map_audit.sv
//
// Post-Migration Exhaustive Functional Address Map Audit for soc_top.
// Verifies EVERY entry of Full_Soc_Address_Map.xlsx against the live RTL:
//   1. IMEM (0x0000_0000 .. 0x0000_FFFF, 64 KB) & Reset Alias (0x8000_0000 .. 0x8000_FFFF)
//   2. DMEM (0x0001_0000 .. 0x0002_FFFF, 128 KB): first/last words, 64KB boundary, bursts
//   3. All active peripherals: UART (0x0003_0000), Timer (0x0005_0000), GPIO (0x0006_0000),
//      CRC-32 (0x000A_0000), DMA (0x000B_0000..0x000B_FFFF), RLE (0x000D_0000)
//   4. First/last valid aperture checks (+0x000 and +0xFFC / +0xFFFC) & non-overlap sentinels
//   5. Reserved / Future Expansion slots return DECERR (2'b11) cleanly on Read & Write:
//      0x0003_1000, 0x0004_0000, 0x0007_0000 (Pkt FIFO), 0x0008_0000 (Pkt Cnt),
//      0x0009_0000 (Enh Timer), 0x000C_0000 (Ext Int Ctrl), 0x000E_0000..0x001F_FFFF (Exp A),
//      0x8001_0000 (beyond reset alias)
//   6. Live DMA->RLE->DMEM 256-byte full-buffer transfer & DMEM bounds rejection (ERR_BAD_SRC)
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

module tb_soc_address_map_audit;

    reg clk;
    reg rst_n;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    integer pass_count = 0;
    integer fail_count = 0;

    // -------------------------------------------------------------------------
    // SoC Ports (IFU 64-bit, LSU 64-bit, SB 64-bit, Peripherals)
    // -------------------------------------------------------------------------
    reg         ifu_axi_awvalid; wire        ifu_axi_awready; reg  [7:0]  ifu_axi_awid;
    reg  [31:0] ifu_axi_awaddr;  reg  [7:0]  ifu_axi_awlen;   reg  [2:0]  ifu_axi_awsize;
    reg  [1:0]  ifu_axi_awburst; reg         ifu_axi_awlock;  reg  [3:0]  ifu_axi_awcache;
    reg  [2:0]  ifu_axi_awprot;  reg  [3:0]  ifu_axi_awqos;   reg  [3:0]  ifu_axi_awregion;
    reg         ifu_axi_wvalid;  wire        ifu_axi_wready;  reg  [63:0] ifu_axi_wdata;
    reg  [7:0]  ifu_axi_wstrb;   reg         ifu_axi_wlast;
    wire        ifu_axi_bvalid;  reg         ifu_axi_bready;  wire [1:0]  ifu_axi_bresp;
    wire [7:0]  ifu_axi_bid;
    reg         ifu_axi_arvalid; wire        ifu_axi_arready; reg  [7:0]  ifu_axi_arid;
    reg  [31:0] ifu_axi_araddr;  reg  [7:0]  ifu_axi_arlen;   reg  [2:0]  ifu_axi_arsize;
    reg  [1:0]  ifu_axi_arburst; reg         ifu_axi_arlock;  reg  [3:0]  ifu_axi_arcache;
    reg  [2:0]  ifu_axi_arprot;  reg  [3:0]  ifu_axi_arqos;   reg  [3:0]  ifu_axi_arregion;
    wire        ifu_axi_rvalid;  reg         ifu_axi_rready;  wire [7:0]  ifu_axi_rid;
    wire [63:0] ifu_axi_rdata;   wire [1:0]  ifu_axi_rresp;   wire        ifu_axi_rlast;

    reg         lsu_axi_awvalid; wire        lsu_axi_awready; reg  [7:0]  lsu_axi_awid;
    reg  [31:0] lsu_axi_awaddr;  reg  [7:0]  lsu_axi_awlen;   reg  [2:0]  lsu_axi_awsize;
    reg  [1:0]  lsu_axi_awburst; reg         lsu_axi_awlock;  reg  [3:0]  lsu_axi_awcache;
    reg  [2:0]  lsu_axi_awprot;  reg  [3:0]  lsu_axi_awqos;   reg  [3:0]  lsu_axi_awregion;
    reg         lsu_axi_wvalid;  wire        lsu_axi_wready;  reg  [63:0] lsu_axi_wdata;
    reg  [7:0]  lsu_axi_wstrb;   reg         lsu_axi_wlast;
    wire        lsu_axi_bvalid;  reg         lsu_axi_bready;  wire [1:0]  lsu_axi_bresp;
    wire [7:0]  lsu_axi_bid;
    reg         lsu_axi_arvalid; wire        lsu_axi_arready; reg  [7:0]  lsu_axi_arid;
    reg  [31:0] lsu_axi_araddr;  reg  [7:0]  lsu_axi_arlen;   reg  [2:0]  lsu_axi_arsize;
    reg  [1:0]  lsu_axi_arburst; reg         lsu_axi_arlock;  reg  [3:0]  lsu_axi_arcache;
    reg  [2:0]  lsu_axi_arprot;  reg  [3:0]  lsu_axi_arqos;   reg  [3:0]  lsu_axi_arregion;
    wire        lsu_axi_rvalid;  reg         lsu_axi_rready;  wire [7:0]  lsu_axi_rid;
    wire [63:0] lsu_axi_rdata;   wire [1:0]  lsu_axi_rresp;   wire        lsu_axi_rlast;

    reg         sb_axi_awvalid;  wire        sb_axi_awready;  reg  [7:0]  sb_axi_awid;
    reg  [31:0] sb_axi_awaddr;   reg  [7:0]  sb_axi_awlen;    reg  [2:0]  sb_axi_awsize;
    reg  [1:0]  sb_axi_awburst;  reg         sb_axi_awlock;   reg  [3:0]  sb_axi_awcache;
    reg  [2:0]  sb_axi_awprot;   reg  [3:0]  sb_axi_awqos;    reg  [3:0]  sb_axi_awregion;
    reg         sb_axi_wvalid;   wire        sb_axi_wready;   reg  [63:0] sb_axi_wdata;
    reg  [7:0]  sb_axi_wstrb;    reg         sb_axi_wlast;
    wire        sb_axi_bvalid;   reg         sb_axi_bready;   wire [1:0]  sb_axi_bresp;
    wire [7:0]  sb_axi_bid;
    reg         sb_axi_arvalid;  wire        sb_axi_arready;  reg  [7:0]  sb_axi_arid;
    reg  [31:0] sb_axi_araddr;   reg  [7:0]  sb_axi_arlen;    reg  [2:0]  sb_axi_arsize;
    reg  [1:0]  sb_axi_arburst;  reg         sb_axi_arlock;   reg  [3:0]  sb_axi_arcache;
    reg  [2:0]  sb_axi_arprot;   reg  [3:0]  sb_axi_arqos;    reg  [3:0]  sb_axi_arregion;
    wire        sb_axi_rvalid;   reg         sb_axi_rready;   wire [7:0]  sb_axi_rid;
    wire [63:0] sb_axi_rdata;    wire [1:0]  sb_axi_rresp;    wire        sb_axi_rlast;

    reg         uart_rx; wire uart_tx;
    reg  [31:0] gpio_i;  wire [31:0] gpio_o, gpio_oe;
    wire        timer_irq, gpio_irq, rle_irq, dma_irq;

    soc_top #(
        .IMEM_DEPTH(16384),
        .DMEM_DEPTH(32768)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .ifu_axi_awvalid(ifu_axi_awvalid), .ifu_axi_awready(ifu_axi_awready), .ifu_axi_awid(ifu_axi_awid),
        .ifu_axi_awaddr(ifu_axi_awaddr), .ifu_axi_awlen(ifu_axi_awlen), .ifu_axi_awsize(ifu_axi_awsize),
        .ifu_axi_awburst(ifu_axi_awburst), .ifu_axi_awlock(ifu_axi_awlock), .ifu_axi_awcache(ifu_axi_awcache),
        .ifu_axi_awprot(ifu_axi_awprot), .ifu_axi_awqos(ifu_axi_awqos), .ifu_axi_awregion(ifu_axi_awregion),
        .ifu_axi_wvalid(ifu_axi_wvalid), .ifu_axi_wready(ifu_axi_wready), .ifu_axi_wdata(ifu_axi_wdata),
        .ifu_axi_wstrb(ifu_axi_wstrb), .ifu_axi_wlast(ifu_axi_wlast),
        .ifu_axi_bvalid(ifu_axi_bvalid), .ifu_axi_bready(ifu_axi_bready), .ifu_axi_bresp(ifu_axi_bresp),
        .ifu_axi_bid(ifu_axi_bid),
        .ifu_axi_arvalid(ifu_axi_arvalid), .ifu_axi_arready(ifu_axi_arready), .ifu_axi_arid(ifu_axi_arid),
        .ifu_axi_araddr(ifu_axi_araddr), .ifu_axi_arlen(ifu_axi_arlen), .ifu_axi_arsize(ifu_axi_arsize),
        .ifu_axi_arburst(ifu_axi_arburst), .ifu_axi_arlock(ifu_axi_arlock), .ifu_axi_arcache(ifu_axi_arcache),
        .ifu_axi_arprot(ifu_axi_arprot), .ifu_axi_arqos(ifu_axi_arqos), .ifu_axi_arregion(ifu_axi_arregion),
        .ifu_axi_rvalid(ifu_axi_rvalid), .ifu_axi_rready(ifu_axi_rready), .ifu_axi_rid(ifu_axi_rid),
        .ifu_axi_rdata(ifu_axi_rdata), .ifu_axi_rresp(ifu_axi_rresp), .ifu_axi_rlast(ifu_axi_rlast),
        .lsu_axi_awvalid(lsu_axi_awvalid), .lsu_axi_awready(lsu_axi_awready), .lsu_axi_awid(lsu_axi_awid),
        .lsu_axi_awaddr(lsu_axi_awaddr), .lsu_axi_awlen(lsu_axi_awlen), .lsu_axi_awsize(lsu_axi_awsize),
        .lsu_axi_awburst(lsu_axi_awburst), .lsu_axi_awlock(lsu_axi_awlock), .lsu_axi_awcache(lsu_axi_awcache),
        .lsu_axi_awprot(lsu_axi_awprot), .lsu_axi_awqos(lsu_axi_awqos), .lsu_axi_awregion(lsu_axi_awregion),
        .lsu_axi_wvalid(lsu_axi_wvalid), .lsu_axi_wready(lsu_axi_wready), .lsu_axi_wdata(lsu_axi_wdata),
        .lsu_axi_wstrb(lsu_axi_wstrb), .lsu_axi_wlast(lsu_axi_wlast),
        .lsu_axi_bvalid(lsu_axi_bvalid), .lsu_axi_bready(lsu_axi_bready), .lsu_axi_bresp(lsu_axi_bresp),
        .lsu_axi_bid(lsu_axi_bid),
        .lsu_axi_arvalid(lsu_axi_arvalid), .lsu_axi_arready(lsu_axi_arready), .lsu_axi_arid(lsu_axi_arid),
        .lsu_axi_araddr(lsu_axi_araddr), .lsu_axi_arlen(lsu_axi_arlen), .lsu_axi_arsize(lsu_axi_arsize),
        .lsu_axi_arburst(lsu_axi_arburst), .lsu_axi_arlock(lsu_axi_arlock), .lsu_axi_arcache(lsu_axi_arcache),
        .lsu_axi_arprot(lsu_axi_arprot), .lsu_axi_arqos(lsu_axi_arqos), .lsu_axi_arregion(lsu_axi_arregion),
        .lsu_axi_rvalid(lsu_axi_rvalid), .lsu_axi_rready(lsu_axi_rready), .lsu_axi_rid(lsu_axi_rid),
        .lsu_axi_rdata(lsu_axi_rdata), .lsu_axi_rresp(lsu_axi_rresp), .lsu_axi_rlast(lsu_axi_rlast),
        .sb_axi_awvalid(sb_axi_awvalid), .sb_axi_awready(sb_axi_awready), .sb_axi_awid(sb_axi_awid),
        .sb_axi_awaddr(sb_axi_awaddr), .sb_axi_awlen(sb_axi_awlen), .sb_axi_awsize(sb_axi_awsize),
        .sb_axi_awburst(sb_axi_awburst), .sb_axi_awlock(sb_axi_awlock), .sb_axi_awcache(sb_axi_awcache),
        .sb_axi_awprot(sb_axi_awprot), .sb_axi_awqos(sb_axi_awqos), .sb_axi_awregion(sb_axi_awregion),
        .sb_axi_wvalid(sb_axi_wvalid), .sb_axi_wready(sb_axi_wready), .sb_axi_wdata(sb_axi_wdata),
        .sb_axi_wstrb(sb_axi_wstrb), .sb_axi_wlast(sb_axi_wlast),
        .sb_axi_bvalid(sb_axi_bvalid), .sb_axi_bready(sb_axi_bready), .sb_axi_bresp(sb_axi_bresp),
        .sb_axi_bid(sb_axi_bid),
        .sb_axi_arvalid(sb_axi_arvalid), .sb_axi_arready(sb_axi_arready), .sb_axi_arid(sb_axi_arid),
        .sb_axi_araddr(sb_axi_araddr), .sb_axi_arlen(sb_axi_arlen), .sb_axi_arsize(sb_axi_arsize),
        .sb_axi_arburst(sb_axi_arburst), .sb_axi_arlock(sb_axi_arlock), .sb_axi_arcache(sb_axi_arcache),
        .sb_axi_arprot(sb_axi_arprot), .sb_axi_arqos(sb_axi_arqos), .sb_axi_arregion(sb_axi_arregion),
        .sb_axi_rvalid(sb_axi_rvalid), .sb_axi_rready(sb_axi_rready), .sb_axi_rid(sb_axi_rid),
        .sb_axi_rdata(sb_axi_rdata), .sb_axi_rresp(sb_axi_rresp), .sb_axi_rlast(sb_axi_rlast),
        .uart_rx(uart_rx), .uart_tx(uart_tx),
        .gpio_i(gpio_i), .gpio_o(gpio_o), .gpio_oe(gpio_oe),
        .timer_irq(timer_irq), .gpio_irq(gpio_irq), .rle_irq(rle_irq), .dma_irq(dma_irq)
    );

    // Watchdog timer
    initial begin
        #5_000_000;
        $display("[FAIL] Watchdog timeout in tb_soc_address_map_audit!");
        $finish;
    end

    task automatic check(input reg cond, input string msg);
        if (cond) begin
            pass_count++;
        end else begin
            $display("[FAIL] @%0t: %s", $time, msg);
            fail_count++;
        end
    endtask

    task automatic init_signals();
        ifu_axi_awvalid = 0; ifu_axi_awid = 0; ifu_axi_awaddr = 0; ifu_axi_awlen = 0;
        ifu_axi_awsize = 3'b011; ifu_axi_awburst = 2'b01; ifu_axi_awlock = 0;
        ifu_axi_awcache = 0; ifu_axi_awprot = 0; ifu_axi_awqos = 0; ifu_axi_awregion = 0;
        ifu_axi_wvalid = 0; ifu_axi_wdata = 0; ifu_axi_wstrb = 0; ifu_axi_wlast = 0;
        ifu_axi_bready = 0;
        ifu_axi_arvalid = 0; ifu_axi_arid = 0; ifu_axi_araddr = 0; ifu_axi_arlen = 0;
        ifu_axi_arsize = 3'b011; ifu_axi_arburst = 2'b01; ifu_axi_arlock = 0;
        ifu_axi_arcache = 0; ifu_axi_arprot = 0; ifu_axi_arqos = 0; ifu_axi_arregion = 0;
        ifu_axi_rready = 0;

        lsu_axi_awvalid = 0; lsu_axi_awid = 0; lsu_axi_awaddr = 0; lsu_axi_awlen = 0;
        lsu_axi_awsize = 3'b010; lsu_axi_awburst = 2'b01; lsu_axi_awlock = 0;
        lsu_axi_awcache = 0; lsu_axi_awprot = 0; lsu_axi_awqos = 0; lsu_axi_awregion = 0;
        lsu_axi_wvalid = 0; lsu_axi_wdata = 0; lsu_axi_wstrb = 0; lsu_axi_wlast = 0;
        lsu_axi_bready = 0;
        lsu_axi_arvalid = 0; lsu_axi_arid = 0; lsu_axi_araddr = 0; lsu_axi_arlen = 0;
        lsu_axi_arsize = 3'b010; lsu_axi_arburst = 2'b01; lsu_axi_arlock = 0;
        lsu_axi_arcache = 0; lsu_axi_arprot = 0; lsu_axi_arqos = 0; lsu_axi_arregion = 0;
        lsu_axi_rready = 0;

        sb_axi_awvalid = 0; sb_axi_awid = 0; sb_axi_awaddr = 0; sb_axi_awlen = 0;
        sb_axi_awsize = 3'b010; sb_axi_awburst = 2'b01; sb_axi_awlock = 0;
        sb_axi_awcache = 0; sb_axi_awprot = 0; sb_axi_awqos = 0; sb_axi_awregion = 0;
        sb_axi_wvalid = 0; sb_axi_wdata = 0; sb_axi_wstrb = 0; sb_axi_wlast = 0;
        sb_axi_bready = 0;
        sb_axi_arvalid = 0; sb_axi_arid = 0; sb_axi_araddr = 0; sb_axi_arlen = 0;
        sb_axi_arsize = 3'b010; sb_axi_arburst = 2'b01; sb_axi_arlock = 0;
        sb_axi_arcache = 0; sb_axi_arprot = 0; sb_axi_arqos = 0; sb_axi_arregion = 0;
        sb_axi_rready = 0;

        uart_rx = 1'b1;
        gpio_i  = 32'h0;
    endtask

    // -------------------------------------------------------------------------
    // LSU 32-bit Read / Write helpers (with byte-strobe & resp capture)
    // -------------------------------------------------------------------------
    task automatic lsu_write32_strb(
        input  logic [31:0] addr,
        input  logic [31:0] data,
        input  logic [3:0]  strb32,
        output logic [1:0]  resp
    );
        logic [63:0] wdata64;
        logic [7:0]  wstrb64;
        begin
            wdata64 = addr[2] ? {data, 32'h0} : {32'h0, data};
            wstrb64 = addr[2] ? {strb32, 4'h0} : {4'h0, strb32};
            @(posedge clk);
            lsu_axi_awvalid <= 1'b1;
            lsu_axi_awaddr  <= addr;
            lsu_axi_awid    <= 8'h21;
            lsu_axi_awsize  <= 3'b010;
            lsu_axi_awlen   <= 8'd0;
            lsu_axi_wvalid  <= 1'b1;
            lsu_axi_wdata   <= wdata64;
            lsu_axi_wstrb   <= wstrb64;
            lsu_axi_wlast   <= 1'b1;
            lsu_axi_bready  <= 1'b1;

            begin
                bit aw_done = 0, w_done = 0;
                while (!(aw_done && w_done)) begin
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
            end

            while (!lsu_axi_bvalid) @(posedge clk);
            resp = lsu_axi_bresp;
            @(posedge clk);
            lsu_axi_bready <= 1'b0;
        end
    endtask

    task automatic lsu_write32(input logic [31:0] addr, input logic [31:0] data, output logic [1:0] resp);
        lsu_write32_strb(addr, data, 4'b1111, resp);
    endtask

    task automatic lsu_read32(
        input  logic [31:0] addr,
        output logic [31:0] data,
        output logic [1:0]  resp
    );
        begin
            @(posedge clk);
            lsu_axi_arvalid <= 1'b1;
            lsu_axi_araddr  <= addr;
            lsu_axi_arid    <= 8'h22;
            lsu_axi_arsize  <= 3'b010;
            lsu_axi_arlen   <= 8'd0;
            lsu_axi_rready  <= 1'b1;

            @(posedge clk);
            while (!lsu_axi_arready) @(posedge clk);
            lsu_axi_arvalid <= 1'b0;

            while (!lsu_axi_rvalid) @(posedge clk);
            resp = lsu_axi_rresp;
            data = addr[2] ? lsu_axi_rdata[63:32] : lsu_axi_rdata[31:0];
            @(posedge clk);
            lsu_axi_rready <= 1'b0;
        end
    endtask

    task automatic ifu_read64(
        input  logic [31:0] addr,
        output logic [63:0] data,
        output logic [1:0]  resp
    );
        begin
            @(posedge clk);
            ifu_axi_arvalid <= 1'b1;
            ifu_axi_araddr  <= addr;
            ifu_axi_arid    <= 8'h11;
            ifu_axi_arsize  <= 3'b011;
            ifu_axi_arlen   <= 8'd0;
            ifu_axi_rready  <= 1'b1;

            @(posedge clk);
            while (!ifu_axi_arready) @(posedge clk);
            ifu_axi_arvalid <= 1'b0;

            while (!ifu_axi_rvalid) @(posedge clk);
            resp = ifu_axi_rresp;
            data = ifu_axi_rdata;
            @(posedge clk);
            ifu_axi_rready <= 1'b0;
        end
    endtask

    // SB 64-bit Write/Read (also verifies SB bridge path)
    task automatic sb_write64(
        input  logic [31:0] addr,
        input  logic [63:0] data,
        input  logic [7:0]  strb8,
        output logic [1:0]  resp
    );
        begin
            @(posedge clk);
            sb_axi_awvalid <= 1'b1;
            sb_axi_awaddr  <= addr;
            sb_axi_awid    <= 8'h41;
            sb_axi_awsize  <= 3'b011;
            sb_axi_awlen   <= 8'd0;
            sb_axi_wvalid  <= 1'b1;
            sb_axi_wdata   <= data;
            sb_axi_wstrb   <= strb8;
            sb_axi_wlast   <= 1'b1;
            sb_axi_bready  <= 1'b1;

            begin
                bit aw_done = 0, w_done = 0;
                while (!(aw_done && w_done)) begin
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
            end

            while (!sb_axi_bvalid) @(posedge clk);
            resp = sb_axi_bresp;
            @(posedge clk);
            sb_axi_bready <= 1'b0;
        end
    endtask

    task automatic sb_read32(
        input  logic [31:0] addr,
        output logic [31:0] data,
        output logic [1:0]  resp
    );
        begin
            @(posedge clk);
            sb_axi_arvalid <= 1'b1;
            sb_axi_araddr  <= addr;
            sb_axi_arid    <= 8'h42;
            sb_axi_arsize  <= 3'b010;
            sb_axi_arlen   <= 8'd0;
            sb_axi_rready  <= 1'b1;

            @(posedge clk);
            while (!sb_axi_arready) @(posedge clk);
            sb_axi_arvalid <= 1'b0;

            while (!sb_axi_rvalid) @(posedge clk);
            resp = sb_axi_rresp;
            data = addr[2] ? sb_axi_rdata[63:32] : sb_axi_rdata[31:0];
            @(posedge clk);
            sb_axi_rready <= 1'b0;
        end
    endtask

    // Check that reserved/unimplemented slot returns DECERR (2'b11) on both Read & Write
    task automatic check_decerr_slot(input logic [31:0] addr, input string label);
        logic [1:0]  r, wr, sr;
        logic [31:0] rd;
        begin
            lsu_write32(addr, 32'hDEAD_BEEF, wr);
            lsu_read32(addr, rd, r);
            sb_read32(addr, rd, sr);
            check(wr === 2'b11, $sformatf("%s Write 0x%08X -> DECERR (got %b)", label, addr, wr));
            check(r  === 2'b11, $sformatf("%s LSU Read 0x%08X -> DECERR (got %b)", label, addr, r));
            check(sr === 2'b11, $sformatf("%s SB Read 0x%08X -> DECERR (got %b)", label, addr, sr));
        end
    endtask

    // Variables
    logic [1:0]  resp;
    logic [31:0] r32;
    logic [63:0] r64;

    initial begin
        $display("=================================================================");
        $display(" POST-MIGRATION EXHAUSTIVE ADDRESS MAP AUDIT (tb_soc_address_map_audit)");
        $display("=================================================================");

        init_signals();
        rst_n = 1'b0;
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        // ---------------------------------------------------------------------
        // 1. IMEM (0x0000_0000..0x0000_FFFF) & Reset Vector Alias (0x8000_0000..0x8000_FFFF)
        // ---------------------------------------------------------------------
        $display("\n--- [1] IMEM & Reset Vector Alias Boundary Audit ---");
        lsu_write32(32'h0000_0000, 32'h1122_3344, resp);
        check(resp === 2'b00, "IMEM first word write (0x0000_0000) OKAY");
        lsu_write32(32'h0000_0004, 32'h5566_7788, resp);
        check(resp === 2'b00, "IMEM word 1 write (0x0000_0004) OKAY");
        lsu_write32(32'h0000_FFF8, 32'hCAFE_0001, resp);
        check(resp === 2'b00, "IMEM 0x0000_FFF8 write OKAY");
        lsu_write32(32'h0000_FFFC, 32'hBEEF_0002, resp);
        check(resp === 2'b00, "IMEM last word write (0x0000_FFFC) OKAY");

        // Last byte write test on 0x0000_FFFF (byte 3 of 0x0000_FFFC)
        lsu_write32_strb(32'h0000_FFFC, 32'hA500_0000, 4'b1000, resp);
        check(resp === 2'b00, "IMEM last byte write (0x0000_FFFF, WSTRB=1000) OKAY");

        // IFU fetch via base 0x0000_0000 & alias 0x8000_0000
        ifu_read64(32'h0000_0000, r64, resp);
        check(resp === 2'b00 && r64 === 64'h5566_7788_1122_3344, "IFU 64b fetch @ 0x0000_0000 matches");
        ifu_read64(32'h8000_0000, r64, resp);
        check(resp === 2'b00 && r64 === 64'h5566_7788_1122_3344, "IFU 64b fetch @ 0x8000_0000 (Reset Alias) matches");
        ifu_read64(32'h8000_FFF8, r64, resp);
        check(resp === 2'b00 && r64 === 64'hA5EF_0002_CAFE_0001, "IFU 64b fetch @ 0x8000_FFF8 (Alias Last QWord) matches");

        // Write via 0x8000_0000 alias, read via 0x0000_0000
        lsu_write32(32'h8000_0008, 32'hDECA_FBAD, resp);
        check(resp === 2'b00, "LSU write via Reset Alias 0x8000_0008 OKAY");
        lsu_read32(32'h0000_0008, r32, resp);
        check(resp === 2'b00 && r32 === 32'hDECA_FBAD, "IMEM read at 0x0000_0008 reflects Reset Alias write");

        // ---------------------------------------------------------------------
        // 2. DMEM (0x0001_0000..0x0002_FFFF, 128 KB) Boundary & Non-Alias Audit
        // ---------------------------------------------------------------------
        $display("\n--- [2] DMEM 128 KB Boundary & Alias-Isolation Audit ---");
        lsu_write32(32'h0001_0000, 32'hD001_0000, resp);
        check(resp === 2'b00, "DMEM base write 0x0001_0000 OKAY");
        lsu_write32(32'h0001_FFFC, 32'hD001_FFFC, resp);
        check(resp === 2'b00, "DMEM lower-64KB last word 0x0001_FFFC OKAY");
        lsu_write32(32'h0002_0000, 32'hD002_0000, resp);
        check(resp === 2'b00, "DMEM upper-64KB first word 0x0002_0000 OKAY");
        sb_write64(32'h0002_FFF8, 64'hE002_FFFC_E002_FFF8, 8'hFF, resp);
        check(resp === 2'b00, "DMEM 64-bit write at last QWord 0x0002_FFF8 OKAY");
        // Byte 0x0002_FFFF write
        lsu_write32_strb(32'h0002_FFFC, 32'h5A00_0000, 4'b1000, resp);
        check(resp === 2'b00, "DMEM last valid byte write (0x0002_FFFF) OKAY");

        lsu_read32(32'h0001_0000, r32, resp);
        check(resp === 2'b00 && r32 === 32'hD001_0000, "DMEM 0x0001_0000 uncorrupted by 0x0002_0000");
        lsu_read32(32'h0001_FFFC, r32, resp);
        check(resp === 2'b00 && r32 === 32'hD001_FFFC, "DMEM 0x0001_FFFC intact");
        lsu_read32(32'h0002_0000, r32, resp);
        check(resp === 2'b00 && r32 === 32'hD002_0000, "DMEM 0x0002_0000 intact (128 KB independent bank)");
        lsu_read32(32'h0002_FFFC, r32, resp);
        check(resp === 2'b00 && r32 === 32'h5A02_FFFC, "DMEM last word 0x0002_FFFC reflects last byte update");
        lsu_read32(32'h0000_0000, r32, resp);
        check(resp === 2'b00 && r32 === 32'h1122_3344, "IMEM 0x0000_0000 uncorrupted by DMEM writes");

        // ---------------------------------------------------------------------
        // 3. Active Peripherals First & Last Word Aperture Audit
        // ---------------------------------------------------------------------
        $display("\n--- [3] Active Peripherals Aperture Audit ---");
        // UART (0x0003_0000 .. 0x0003_0FFF) - LCR=0x0C (DLAB=bit7), BAUD_DIV=0x08, LSR=0x14
        lsu_write32(32'h0003_000C, 32'h0000_0083, resp); // Enable DLAB=1
        check(resp === 2'b00, "UART write LCR DLAB=1 (0x0003_000C) OKAY");
        lsu_write32(32'h0003_0008, 32'd434, resp); // BAUDDIV
        check(resp === 2'b00, "UART write BAUDDIV (0x0003_0008) OKAY");
        lsu_read32(32'h0003_0008, r32, resp);
        check(resp === 2'b00 && r32 === 32'd434, "UART readback BAUDDIV == 434 OKAY");
        lsu_write32(32'h0003_000C, 32'h0000_0003, resp); // Clear DLAB=0 (8N1)
        lsu_read32(32'h0003_0014, r32, resp); // LSR (TX empty)
        check(resp === 2'b00 && r32[6] === 1'b1, "UART LSR (0x0003_0014) reports TX empty");
        lsu_read32(32'h0003_0FFC, r32, resp);
        check(resp === 2'b00, "UART last 4KB aperture word (0x0003_0FFC) hits UART slave (OKAY, not DECERR)");

        // Timer (0x0005_0000 .. 0x0005_0FFF)
        lsu_write32(32'h0005_0008, 32'h0000_1234, resp); // MTIMECMP_LO
        check(resp === 2'b00, "Timer write MTIMECMP_LO (0x0005_0008) OKAY");
        lsu_read32(32'h0005_0008, r32, resp);
        check(resp === 2'b00 && r32 === 32'h0000_1234, "Timer readback MTIMECMP_LO OKAY");
        lsu_read32(32'h0005_0FFC, r32, resp);
        check(resp === 2'b10, "Timer last 4KB aperture word (0x0005_0FFC) hits Timer slave -> SLVERR");

        // GPIO (0x0006_0000 .. 0x0006_0FFF): 0x00=DATA_IN(RO), 0x04=DATA_OUT(RW), 0x08=DIR(RW)
        lsu_write32(32'h0006_0008, 32'h0000_00FF, resp); // GPIO_DIR
        check(resp === 2'b00, "GPIO write DIR (0x0006_0008) OKAY");
        lsu_write32(32'h0006_0004, 32'h0000_00A5, resp); // GPIO_OUT
        check(resp === 2'b00 && gpio_oe === 32'h0000_00FF && gpio_o === 32'h0000_00A5, "GPIO outputs match 0x00A5");
        lsu_read32(32'h0006_0FFC, r32, resp);
        check(resp === 2'b10, "GPIO last 4KB aperture word (0x0006_0FFC) hits GPIO slave -> SLVERR");

        // CRC-32 (0x000A_0000 .. 0x000A_0FFF)
        lsu_write32(32'h000A_0008, 32'h0000_0001, resp); // CTRL INIT
        check(resp === 2'b00, "CRC-32 write CTRL=INIT (0x000A_0008) OKAY");
        lsu_write32(32'h000A_0000, 32'h0000_0031, resp); // "1" -> "123456789" test starts with '1'
        lsu_read32(32'h000A_0004, r32, resp);
        check(resp === 2'b00 && r32 !== 32'h0000_0000, "CRC-32 DATA/RESULT active at 0x000A_0000/04 OKAY");
        lsu_read32(32'h000A_0FFC, r32, resp);
        check(resp === 2'b10, "CRC-32 last 4KB aperture word (0x000A_0FFC) hits CRC slave -> SLVERR");

        // DMA (0x000B_0000 .. 0x000B_FFFF, 64 KB)
        lsu_write32(32'h000B_0008, 32'h0001_2000, resp);
        check(resp === 2'b00, "DMA write SRC_ADDR (0x000B_0008) OKAY");
        lsu_read32(32'h000B_0008, r32, resp);
        check(resp === 2'b00 && r32 === 32'h0001_2000, "DMA readback SRC_ADDR OKAY");
        lsu_read32(32'h000B_FFFC, r32, resp);
        check(resp === 2'b10, "DMA last 64KB aperture word (0x000B_FFFC) hits DMA slave -> SLVERR");

        // RLE (0x000D_0000 .. 0x000D_0FFF, 4 KB)
        lsu_write32(32'h000D_0008, 32'd4, resp);
        check(resp === 2'b00, "RLE write INPUT_LEN (0x000D_0008) OKAY");
        lsu_read32(32'h000D_0008, r32, resp);
        check(resp === 2'b00 && r32 === 32'd4, "RLE readback INPUT_LEN OKAY");
        lsu_read32(32'h000D_0FFC, r32, resp);
        check(resp === 2'b10, "RLE last 4KB aperture word (0x000D_0FFC) hits RLE slave -> SLVERR");

        // ---------------------------------------------------------------------
        // 4. Exhaustive Reserved / Unimplemented Regions DECERR Audit
        // ---------------------------------------------------------------------
        $display("\n--- [4] Reserved / Expansion Regions DECERR Audit ---");
        check_decerr_slot(32'h0003_1000, "Gap-after-UART (0x0003_1000)");
        check_decerr_slot(32'h0004_0000, "Unalloc-0x40000 (0x0004_0000)");
        check_decerr_slot(32'h0004_FFFC, "Gap-before-Timer (0x0004_FFFC)");
        check_decerr_slot(32'h0005_1000, "Gap-after-Timer (0x0005_1000)");
        check_decerr_slot(32'h0006_1000, "Gap-after-GPIO (0x0006_1000)");
        check_decerr_slot(32'h0007_0000, "Reserved-PktFIFO-Base");
        check_decerr_slot(32'h0007_0FFC, "Reserved-PktFIFO-End");
        check_decerr_slot(32'h0008_0000, "Reserved-PktCnt-Base");
        check_decerr_slot(32'h0008_0FFC, "Reserved-PktCnt-End");
        check_decerr_slot(32'h0009_0000, "Reserved-EnhTimer-Base");
        check_decerr_slot(32'h0009_0FFC, "Reserved-EnhTimer-End");
        check_decerr_slot(32'h000A_1000, "Gap-after-CRC");
        check_decerr_slot(32'h000C_0000, "Reserved-ExtIntCtrl-Base");
        check_decerr_slot(32'h000C_0FFC, "Reserved-ExtIntCtrl-End");
        check_decerr_slot(32'h000D_1000, "Gap-after-RLE");
        check_decerr_slot(32'h000E_0000, "ExpansionBankA-Start");
        check_decerr_slot(32'h0010_0000, "ExpansionBankA-Mid");
        check_decerr_slot(32'h001F_FFFC, "ExpansionBankA-End");
        check_decerr_slot(32'h0020_0000, "Post-ExpansionBankA");
        check_decerr_slot(32'h8001_0000, "Beyond-Reset-Alias");

        // ---------------------------------------------------------------------
        // 5. DMA->RLE->DMEM 256-Byte Full Transfer & End-of-DMEM Overflow Check
        // ---------------------------------------------------------------------
        $display("\n--- [5] SoC Live DMA 256-Byte Transfer & End-of-DMEM Bound Check ---");
        // Test 5A: Populate 256 identical bytes (64 words) at DMEM upper half (0x0002_0000..0x0002_00FC)
        for (int w = 0; w < 64; w++) begin
            lsu_write32(32'h0002_0000 + (w * 4), 32'h4141_4141, resp);
        end
        // Also place compressed sentinel at 0x0002_1000
        lsu_write32(32'h0002_1000, 32'hDEAD_BEEF, resp);

        // Configure DMA: SRC=0x0002_0000, DST=0x0002_1000, LEN=256, MODE=0 (Compress)
        lsu_write32(32'h000B_0008, 32'h0002_0000, resp);
        lsu_write32(32'h000B_000C, 32'h0002_1000, resp);
        lsu_write32(32'h000B_0010, 32'd256,       resp);
        lsu_write32(32'h000B_0018, 32'h0000_0003, resp); // IRQ EN
        lsu_write32(32'h000B_0000, 32'h0000_0001, resp); // START

        begin
            automatic int timeout = 0;
            do begin
                repeat (10) @(posedge clk);
                lsu_read32(32'h000B_0004, r32, resp);
                timeout++;
            end while (r32[0] == 1'b1 && timeout < 5000);

            check(r32[0] === 1'b0 && r32[1] === 1'b1 && r32[2] === 1'b0,
                  "DMA 256-byte compress completed with DONE=1, ERROR=0");
            check(dma_irq === 1'b1, "DMA completion asserted dma_irq");
        end

        lsu_read32(32'h000B_0014, r32, resp); // OUTPUT_LEN (256 'A' -> [255,'A', 1,'A'] = 4 bytes)
        check(r32 === 32'd4, $sformatf("DMA 256B compress OUTPUT_LEN == 4 (got %0d)", r32));
        lsu_read32(32'h0002_1000, r32, resp);
        check(r32 === 32'h4101_41FF, $sformatf("DMEM compressed data == 0x4101_41FF (got 0x%08X)", r32));
        // Clear IRQ
        lsu_write32(32'h000B_001C, 32'h0000_0003, resp);
        @(posedge clk);
        check(dma_irq === 1'b0, "DMA W1C cleared dma_irq");

        // Test 5B: Decompress 4 bytes -> 256 bytes into DMEM ending right at 0x0002_FFFF (base = 0x0002_FF00)
        lsu_write32(32'h000B_0008, 32'h0002_1000, resp);
        lsu_write32(32'h000B_000C, 32'h0002_FF00, resp);
        lsu_write32(32'h000B_0010, 32'd4,         resp);
        lsu_write32(32'h000B_0000, 32'h0000_0003, resp); // START | MODE=1 (Decompress)

        begin
            automatic int timeout = 0;
            do begin
                repeat (10) @(posedge clk);
                lsu_read32(32'h000B_0004, r32, resp);
                timeout++;
            end while (r32[0] == 1'b1 && timeout < 10000);
            check(r32[0] === 1'b0 && r32[1] === 1'b1 && r32[2] === 1'b0,
                  "DMA 4B->256B decompress into 0x0002_FF00..0x0002_FFFF DONE=1, ERROR=0");
        end
        lsu_read32(32'h000B_0014, r32, resp);
        check(r32 === 32'd256, $sformatf("DMA decompress OUTPUT_LEN == 256 (got %0d)", r32));
        lsu_read32(32'h0002_FF00, r32, resp);
        check(r32 === 32'h4141_4141, "DMA 256B decompressed first word (0x0002_FF00) matches");
        lsu_read32(32'h0002_FFFC, r32, resp);
        check(r32 === 32'h4141_4141, "DMA 256B decompressed final word at DMEM end (0x0002_FFFC) matches");
        lsu_write32(32'h000B_001C, 32'h0000_0003, resp);

        // Test 5C: Attempt DMA read starting inside DMEM (0x0002_FFFC) with length 8 (spills to 0x0003_0000) -> ERR_BAD_SRC
        lsu_write32(32'h000B_0008, 32'h0002_FFFC, resp);
        lsu_write32(32'h000B_000C, 32'h0001_0000, resp);
        lsu_write32(32'h000B_0010, 32'd8,         resp);
        lsu_write32(32'h000B_0000, 32'h0000_0001, resp);
        repeat (10) @(posedge clk);
        lsu_read32(32'h000B_0004, r32, resp);
        check(r32[2] === 1'b1, "DMA SRC spillover across 0x0002_FFFF sets ERROR=1");
        lsu_read32(32'h000B_0020, r32, resp);
        check(r32 === 32'h0000_0001, $sformatf("DMA SRC spillover trapped with ERR_BAD_SRC (0x01, got 0x%02X)", r32));

        // ---------------------------------------------------------------------
        // Summary
        // ---------------------------------------------------------------------
        $display("\n=================================================================");
        $display(" ADDRESS MAP AUDIT SUMMARY: Passed=%0d Failed=%0d Total=%0d",
                 pass_count, fail_count, pass_count + fail_count);
        $display("=================================================================");
        if (fail_count == 0)
            $display("STATUS: ALL ADDRESS MAP AUDIT CHECKS PASSED!");
        else
            $display("STATUS: ADDRESS MAP AUDIT FAILED!");

        $finish;
    end

endmodule
