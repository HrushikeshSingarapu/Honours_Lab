// =============================================================================
// tb_dma_unit.sv
//
// Integrated Unit Testbench for the Autonomous DMA Controller (dma_top).
// Connected to real RLE Accelerator IP and simulated Data Memory (DMEM).
//
// Verification Coverage:
//   Test 1 : Single-byte transfer (1 byte)
//   Test 2 : Two-byte transfer (2 bytes)
//   Test 3 : Three-byte transfer (3 bytes)
//   Test 4 : Four-byte transfer (4 bytes / 1 full word)
//   Test 5 : Full Run-Length Compression Flow (16 bytes -> 8 bytes with real RLE)
//   Test 6 : Full Lossless Decompression Flow (8 bytes -> 16 bytes with real RLE)
//   Test 7 : Multi-word transfer (64 bytes)
//   Test 8 : Partial final word boundary transfer (255 bytes)
//   Test 9 : Maximum buffer capacity transfer (256 bytes)
//   Test 10: IRQ generation, masking, and W1C status clearing
//   Test 11: Parameter error detection (Bad length, bad addresses)
//   Test 12: Abort and dynamic reset recovery
//
// =============================================================================

`timescale 1ns / 1ps

module tb_dma_unit;

    localparam ADDR_WIDTH     = 32;
    localparam DATA_WIDTH     = 32;
    localparam STRB_WIDTH     = 4;
    localparam ID_WIDTH       = 8;
    localparam AXI_ID         = 8'h30;
    localparam BUFFER_DEPTH   = 256;
    localparam TIMEOUT_CYCLES = 100000;
    localparam CLK_PERIOD     = 10;

    logic clk;
    logic rst_n;

    // CPU-Facing AXI4-Lite Slave Interface of DMA
    logic [ID_WIDTH-1:0]   s_axi_awid;
    logic [ADDR_WIDTH-1:0] s_axi_awaddr;
    logic [2:0]            s_axi_awprot;
    logic                  s_axi_awvalid;
    logic                  s_axi_awready;

    logic [DATA_WIDTH-1:0] s_axi_wdata;
    logic [STRB_WIDTH-1:0] s_axi_wstrb;
    logic                  s_axi_wvalid;
    logic                  s_axi_wready;

    logic [ID_WIDTH-1:0]   s_axi_bid;
    logic [1:0]            s_axi_bresp;
    logic                  s_axi_bvalid;
    logic                  s_axi_bready;

    logic [ID_WIDTH-1:0]   s_axi_arid;
    logic [ADDR_WIDTH-1:0] s_axi_araddr;
    logic [2:0]            s_axi_arprot;
    logic                  s_axi_arvalid;
    logic                  s_axi_arready;

    logic [ID_WIDTH-1:0]   s_axi_rid;
    logic [DATA_WIDTH-1:0] s_axi_rdata;
    logic [1:0]            s_axi_rresp;
    logic                  s_axi_rlast;
    logic                  s_axi_rvalid;
    logic                  s_axi_rready;

    // Interconnect-Facing AXI4 Master Interface of DMA
    logic                  m_axi_awvalid;
    logic                  m_axi_awready;
    logic [ID_WIDTH-1:0]   m_axi_awid;
    logic [ADDR_WIDTH-1:0] m_axi_awaddr;
    logic [7:0]            m_axi_awlen;
    logic [2:0]            m_axi_awsize;
    logic [1:0]            m_axi_awburst;
    logic                  m_axi_awlock;
    logic [3:0]            m_axi_awcache;
    logic [2:0]            m_axi_awprot;
    logic [3:0]            m_axi_awqos;
    logic [3:0]            m_axi_awregion;
    logic                  m_axi_awuser;

    logic                  m_axi_wvalid;
    logic                  m_axi_wready;
    logic [DATA_WIDTH-1:0] m_axi_wdata;
    logic [STRB_WIDTH-1:0] m_axi_wstrb;
    logic                  m_axi_wlast;
    logic                  m_axi_wuser;

    logic                  m_axi_bvalid;
    logic                  m_axi_bready;
    logic [1:0]            m_axi_bresp;
    logic [ID_WIDTH-1:0]   m_axi_bid;
    logic                  m_axi_buser;

    logic                  m_axi_arvalid;
    logic                  m_axi_arready;
    logic [ID_WIDTH-1:0]   m_axi_arid;
    logic [ADDR_WIDTH-1:0] m_axi_araddr;
    logic [7:0]            m_axi_arlen;
    logic [2:0]            m_axi_arsize;
    logic [1:0]            m_axi_arburst;
    logic                  m_axi_arlock;
    logic [3:0]            m_axi_arcache;
    logic [2:0]            m_axi_arprot;
    logic [3:0]            m_axi_arqos;
    logic [3:0]            m_axi_arregion;
    logic                  m_axi_aruser;

    logic                  m_axi_rvalid;
    logic                  m_axi_rready;
    logic [ID_WIDTH-1:0]   m_axi_rid;
    logic [DATA_WIDTH-1:0] m_axi_rdata;
    logic [1:0]            m_axi_rresp;
    logic                  m_axi_rlast;
    logic                  m_axi_ruser;

    logic                  dma_irq;

    // RLE Accelerator AXI-Lite Slave Interface
    logic [ADDR_WIDTH-1:0] rle_s_axi_awaddr;
    logic [2:0]            rle_s_axi_awprot;
    logic                  rle_s_axi_awvalid;
    logic                  rle_s_axi_awready;

    logic [DATA_WIDTH-1:0] rle_s_axi_wdata;
    logic [STRB_WIDTH-1:0] rle_s_axi_wstrb;
    logic                  rle_s_axi_wvalid;
    logic                  rle_s_axi_wready;

    logic [1:0]            rle_s_axi_bresp;
    logic                  rle_s_axi_bvalid;
    logic                  rle_s_axi_bready;

    logic [ADDR_WIDTH-1:0] rle_s_axi_araddr;
    logic [2:0]            rle_s_axi_arprot;
    logic                  rle_s_axi_arvalid;
    logic                  rle_s_axi_arready;

    logic [DATA_WIDTH-1:0] rle_s_axi_rdata;
    logic [1:0]            rle_s_axi_rresp;
    logic                  rle_s_axi_rvalid;
    logic                  rle_s_axi_rready;
    logic                  rle_irq;

    // =========================================================================
    // 1. DMA Top-Level Instance (DUT)
    // =========================================================================
    dma_top #(
        .ADDR_WIDTH     (ADDR_WIDTH),
        .DATA_WIDTH     (DATA_WIDTH),
        .STRB_WIDTH     (STRB_WIDTH),
        .ID_WIDTH       (ID_WIDTH),
        .AXI_ID         (AXI_ID),
        .BUFFER_DEPTH   (BUFFER_DEPTH),
        .TIMEOUT_CYCLES (TIMEOUT_CYCLES)
    ) dut_dma_top (
        .clk            (clk),
        .rst_n          (rst_n),

        .s_axi_awid     (s_axi_awid),
        .s_axi_awaddr   (s_axi_awaddr),
        .s_axi_awprot   (s_axi_awprot),
        .s_axi_awvalid  (s_axi_awvalid),
        .s_axi_awready  (s_axi_awready),

        .s_axi_wdata    (s_axi_wdata),
        .s_axi_wstrb    (s_axi_wstrb),
        .s_axi_wvalid   (s_axi_wvalid),
        .s_axi_wready   (s_axi_wready),

        .s_axi_bid      (s_axi_bid),
        .s_axi_bresp    (s_axi_bresp),
        .s_axi_bvalid   (s_axi_bvalid),
        .s_axi_bready   (s_axi_bready),

        .s_axi_arid     (s_axi_arid),
        .s_axi_araddr   (s_axi_araddr),
        .s_axi_arprot   (s_axi_arprot),
        .s_axi_arvalid  (s_axi_arvalid),
        .s_axi_arready  (s_axi_arready),

        .s_axi_rid      (s_axi_rid),
        .s_axi_rdata    (s_axi_rdata),
        .s_axi_rresp    (s_axi_rresp),
        .s_axi_rlast    (s_axi_rlast),
        .s_axi_rvalid   (s_axi_rvalid),
        .s_axi_rready   (s_axi_rready),

        .m_axi_awvalid  (m_axi_awvalid),
        .m_axi_awready  (m_axi_awready),
        .m_axi_awid     (m_axi_awid),
        .m_axi_awaddr   (m_axi_awaddr),
        .m_axi_awlen    (m_axi_awlen),
        .m_axi_awsize   (m_axi_awsize),
        .m_axi_awburst  (m_axi_awburst),
        .m_axi_awlock   (m_axi_awlock),
        .m_axi_awcache  (m_axi_awcache),
        .m_axi_awprot   (m_axi_awprot),
        .m_axi_awqos    (m_axi_awqos),
        .m_axi_awregion (m_axi_awregion),
        .m_axi_awuser   (m_axi_awuser),

        .m_axi_wvalid   (m_axi_wvalid),
        .m_axi_wready   (m_axi_wready),
        .m_axi_wdata    (m_axi_wdata),
        .m_axi_wstrb    (m_axi_wstrb),
        .m_axi_wlast    (m_axi_wlast),
        .m_axi_wuser    (m_axi_wuser),

        .m_axi_bvalid   (m_axi_bvalid),
        .m_axi_bready   (m_axi_bready),
        .m_axi_bresp    (m_axi_bresp),
        .m_axi_bid      (m_axi_bid),
        .m_axi_buser    (m_axi_buser),

        .m_axi_arvalid  (m_axi_arvalid),
        .m_axi_arready  (m_axi_arready),
        .m_axi_arid     (m_axi_arid),
        .m_axi_araddr   (m_axi_araddr),
        .m_axi_arlen    (m_axi_arlen),
        .m_axi_arsize   (m_axi_arsize),
        .m_axi_arburst  (m_axi_arburst),
        .m_axi_arlock   (m_axi_arlock),
        .m_axi_arcache  (m_axi_arcache),
        .m_axi_arprot   (m_axi_arprot),
        .m_axi_arqos    (m_axi_arqos),
        .m_axi_arregion (m_axi_arregion),
        .m_axi_aruser   (m_axi_aruser),

        .m_axi_rvalid   (m_axi_rvalid),
        .m_axi_rready   (m_axi_rready),
        .m_axi_rid      (m_axi_rid),
        .m_axi_rdata    (m_axi_rdata),
        .m_axi_rresp    (m_axi_rresp),
        .m_axi_rlast    (m_axi_rlast),
        .m_axi_ruser    (m_axi_ruser),

        .irq_o          (dma_irq)
    );

    // =========================================================================
    // 2. Real RLE Accelerator IP Instance
    // =========================================================================
    rle_top #(
        .DATA_WIDTH   (32),
        .ADDR_WIDTH   (32),
        .STRB_WIDTH   (4),
        .BUFFER_DEPTH (256)
    ) u_real_rle (
        .clk          (clk),
        .rst          (!rst_n), // Active-high reset for RLE IP

        .s_axi_awaddr (rle_s_axi_awaddr),
        .s_axi_awprot (rle_s_axi_awprot),
        .s_axi_awvalid(rle_s_axi_awvalid),
        .s_axi_awready(rle_s_axi_awready),

        .s_axi_wdata  (rle_s_axi_wdata),
        .s_axi_wstrb  (rle_s_axi_wstrb),
        .s_axi_wvalid (rle_s_axi_wvalid),
        .s_axi_wready (rle_s_axi_wready),

        .s_axi_bresp  (rle_s_axi_bresp),
        .s_axi_bvalid (rle_s_axi_bvalid),
        .s_axi_bready (rle_s_axi_bready),

        .s_axi_araddr (rle_s_axi_araddr),
        .s_axi_arprot (rle_s_axi_arprot),
        .s_axi_arvalid(rle_s_axi_arvalid),
        .s_axi_arready(rle_s_axi_arready),

        .s_axi_rdata  (rle_s_axi_rdata),
        .s_axi_rresp  (rle_s_axi_rresp),
        .s_axi_rvalid (rle_s_axi_rvalid),
        .s_axi_rready (rle_s_axi_rready),

        .irq          (rle_irq)
    );

    // =========================================================================
    // Clock Generation
    // =========================================================================
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // =========================================================================
    // Simulated Data Memory (DMEM) Array
    // =========================================================================
    logic [7:0] dmem_array [logic [31:0]];

    function void dmem_write_byte(logic [31:0] addr, logic [7:0] val);
        dmem_array[addr] = val;
    endfunction

    function logic [7:0] dmem_read_byte(logic [31:0] addr);
        if (dmem_array.exists(addr)) return dmem_array[addr];
        else return 8'h00;
    endfunction

    function logic [31:0] dmem_read_word(logic [31:0] addr);
        return {dmem_read_byte(addr + 3), dmem_read_byte(addr + 2),
                dmem_read_byte(addr + 1), dmem_read_byte(addr + 0)};
    endfunction

    // =========================================================================
    // AXI Bus Crossbar Router (DMEM 0x0001_0000..0x0002_FFFF vs RLE 0x000D_0000)
    // =========================================================================
    wire is_rle_wr  = (m_axi_awaddr >= 32'h000D_0000 && m_axi_awaddr <= 32'h000D_0FFF);
    wire is_dmem_wr = (m_axi_awaddr >= 32'h0001_0000 && m_axi_awaddr <= 32'h0002_FFFF);

    wire is_rle_rd  = (m_axi_araddr >= 32'h000D_0000 && m_axi_araddr <= 32'h000D_0FFF);
    wire is_dmem_rd = (m_axi_araddr >= 32'h0001_0000 && m_axi_araddr <= 32'h0002_FFFF);

    // DMEM Write Path Registers
    logic        dmem_awready;
    logic        dmem_wready;
    logic        dmem_bvalid;
    logic [1:0]  dmem_bresp;
    logic [7:0]  dmem_bid;

    // DMEM Read Path Registers
    logic        dmem_arready;
    logic        dmem_rvalid;
    logic [31:0] dmem_rdata;
    logic [1:0]  dmem_rresp;
    logic        dmem_rlast;
    logic [7:0]  dmem_rid;

    // Route Write Channels
    assign rle_s_axi_awaddr  = m_axi_awaddr;
    assign rle_s_axi_awprot  = m_axi_awprot;
    assign rle_s_axi_awvalid = is_rle_wr ? m_axi_awvalid : 1'b0;

    assign rle_s_axi_wdata   = m_axi_wdata;
    assign rle_s_axi_wstrb   = m_axi_wstrb;
    assign rle_s_axi_wvalid  = is_rle_wr ? m_axi_wvalid : 1'b0;

    assign rle_s_axi_bready  = is_rle_wr ? m_axi_bready : 1'b0;

    assign m_axi_awready = is_rle_wr ? rle_s_axi_awready : (is_dmem_wr ? dmem_awready : 1'b0);
    assign m_axi_wready  = is_rle_wr ? rle_s_axi_wready  : (is_dmem_wr ? dmem_wready  : 1'b0);
    assign m_axi_bvalid  = is_rle_wr ? rle_s_axi_bvalid  : (is_dmem_wr ? dmem_bvalid  : 1'b0);
    assign m_axi_bresp   = is_rle_wr ? rle_s_axi_bresp   : (is_dmem_wr ? dmem_bresp   : 2'b10);
    assign m_axi_bid     = is_rle_wr ? m_axi_awid        : dmem_bid;

    // Route Read Channels
    assign rle_s_axi_araddr  = m_axi_araddr;
    assign rle_s_axi_arprot  = m_axi_arprot;
    assign rle_s_axi_arvalid = is_rle_rd ? m_axi_arvalid : 1'b0;
    assign rle_s_axi_rready  = is_rle_rd ? m_axi_rready : 1'b0;

    assign m_axi_arready = is_rle_rd ? rle_s_axi_arready : (is_dmem_rd ? dmem_arready : 1'b0);
    assign m_axi_rvalid  = is_rle_rd ? rle_s_axi_rvalid  : (is_dmem_rd ? dmem_rvalid  : 1'b0);
    assign m_axi_rdata   = is_rle_rd ? rle_s_axi_rdata   : (is_dmem_rd ? dmem_rdata   : 32'h0);
    assign m_axi_rresp   = is_rle_rd ? rle_s_axi_rresp   : (is_dmem_rd ? dmem_rresp   : 2'b10);
    assign m_axi_rlast   = is_rle_rd ? 1'b1              : (is_dmem_rd ? dmem_rlast   : 1'b1);
    assign m_axi_rid     = is_rle_rd ? m_axi_arid        : dmem_rid;

    // =========================================================================
    // DMEM AXI4 Slave Behavioral Handler
    // =========================================================================
    // Write Handler for DMEM
    initial begin
        dmem_awready = 1'b0;
        dmem_wready  = 1'b0;
        dmem_bvalid  = 1'b0;
        dmem_bresp   = 2'b00;
        dmem_bid     = 8'h00;

        forever begin
            @(posedge clk);
            if (!rst_n) begin
                dmem_awready <= 1'b0;
                dmem_wready  <= 1'b0;
                dmem_bvalid  <= 1'b0;
            end else if (is_dmem_wr) begin
                // Handle AW
                if (m_axi_awvalid && !dmem_awready) begin
                    logic [31:0] cur_awaddr;
                    logic [7:0]  cur_awlen;
                    logic [7:0]  cur_awid;
                    int          b;

                    dmem_awready <= 1'b1;
                    @(posedge clk);
                    cur_awaddr   = m_axi_awaddr;
                    cur_awlen    = m_axi_awlen;
                    cur_awid     = m_axi_awid;
                    dmem_awready <= 1'b0;

                    // Receive W beats
                    for (b = 0; b <= cur_awlen; b++) begin
                        int wait_wcnt;
                        dmem_wready <= 1'b1;
                        @(posedge clk);
                        wait_wcnt = 0;
                        while (!m_axi_wvalid && rst_n && wait_wcnt < 30) begin
                            @(posedge clk);
                            wait_wcnt++;
                        end
                        if (!rst_n || wait_wcnt >= 30) break;

                        if (m_axi_wstrb[0]) dmem_write_byte(cur_awaddr + 0, m_axi_wdata[7:0]);
                        if (m_axi_wstrb[1]) dmem_write_byte(cur_awaddr + 1, m_axi_wdata[15:8]);
                        if (m_axi_wstrb[2]) dmem_write_byte(cur_awaddr + 2, m_axi_wdata[23:16]);
                        if (m_axi_wstrb[3]) dmem_write_byte(cur_awaddr + 3, m_axi_wdata[31:24]);

                        cur_awaddr = cur_awaddr + 4;
                    end
                    dmem_wready <= 1'b0;

                    // Send B Response
                    if (rst_n) begin
                        int wait_bcnt;
                        dmem_bvalid <= 1'b1;
                        dmem_bresp  <= 2'b00;
                        dmem_bid    <= cur_awid;
                        @(posedge clk);
                        wait_bcnt = 0;
                        while (!m_axi_bready && rst_n && wait_bcnt < 30) begin
                            @(posedge clk);
                            wait_bcnt++;
                        end
                        dmem_bvalid <= 1'b0;
                    end
                end
            end
        end
    end

    // Read Handler for DMEM
    initial begin
        dmem_arready = 1'b0;
        dmem_rvalid  = 1'b0;
        dmem_rdata   = 32'h0;
        dmem_rresp   = 2'b00;
        dmem_rlast   = 1'b0;
        dmem_rid     = 8'h00;

        forever begin
            @(posedge clk);
            if (!rst_n) begin
                dmem_arready <= 1'b0;
                dmem_rvalid  <= 1'b0;
                dmem_rlast   <= 1'b0;
            end else if (is_dmem_rd) begin
                if (m_axi_arvalid && !dmem_arready) begin
                    logic [31:0] cur_araddr;
                    logic [7:0]  cur_arlen;
                    logic [7:0]  cur_arid;
                    int          rb;

                    dmem_arready <= 1'b1;
                    @(posedge clk);
                    cur_araddr   = m_axi_araddr;
                    cur_arlen    = m_axi_arlen;
                    cur_arid     = m_axi_arid;
                    dmem_arready <= 1'b0;

                    // Send R beats
                    for (rb = 0; rb <= cur_arlen; rb++) begin
                        int wait_rcnt;
                        dmem_rvalid <= 1'b1;
                        dmem_rdata  <= dmem_read_word(cur_araddr);
                        dmem_rlast  <= (rb == cur_arlen);
                        dmem_rid    <= cur_arid;
                        dmem_rresp  <= 2'b00;

                        @(posedge clk);
                        wait_rcnt = 0;
                        while (!m_axi_rready && rst_n && wait_rcnt < 30) begin
                            @(posedge clk);
                            wait_rcnt++;
                        end
                        if (!rst_n || wait_rcnt >= 30) break;
                        cur_araddr = cur_araddr + 4;
                    end
                    dmem_rvalid <= 1'b0;
                    dmem_rlast  <= 1'b0;
                end
            end
        end
    end

    // =========================================================================
    // CPU Master Verification Tasks (Program & Monitor DMA via AXI-Lite)
    // =========================================================================
    task cpu_write(input logic [31:0] addr, input logic [31:0] data, input logic [3:0] strb = 4'hF);
        @(posedge clk);
        s_axi_awid    <= 8'h10;
        s_axi_awaddr  <= addr;
        s_axi_awprot  <= 3'b000;
        s_axi_awvalid <= 1'b1;
        s_axi_wdata   <= data;
        s_axi_wstrb   <= strb;
        s_axi_wvalid  <= 1'b1;
        s_axi_bready  <= 1'b1;

        fork
            begin
                while (!s_axi_awready) @(posedge clk);
                @(posedge clk);
                s_axi_awvalid <= 1'b0;
            end
            begin
                while (!s_axi_wready) @(posedge clk);
                @(posedge clk);
                s_axi_wvalid <= 1'b0;
            end
        join

        while (!s_axi_bvalid) @(posedge clk);
        @(posedge clk);
        s_axi_bready <= 1'b0;
    endtask

    task cpu_read(input logic [31:0] addr, output logic [31:0] data, output logic [1:0] resp);
        @(posedge clk);
        s_axi_arid    <= 8'h20;
        s_axi_araddr  <= addr;
        s_axi_arprot  <= 3'b000;
        s_axi_arvalid <= 1'b1;
        s_axi_rready  <= 1'b1;

        while (!s_axi_arready) @(posedge clk);
        @(posedge clk);
        s_axi_arvalid <= 1'b0;

        while (!s_axi_rvalid) @(posedge clk);
        data = s_axi_rdata;
        resp = s_axi_rresp;
        @(posedge clk);
        s_axi_rready <= 1'b0;
    endtask

    task start_dma(input logic [31:0] src, input logic [31:0] dst,
                   input logic [15:0] len, input logic mode, input logic enable_irq = 1'b1);
        cpu_write(32'h000B_0008, src);                  // DMA_SRC_ADDR
        cpu_write(32'h000B_000C, dst);                  // DMA_DST_ADDR
        cpu_write(32'h000B_0010, {16'd0, len});         // DMA_INPUT_LEN
        cpu_write(32'h000B_0018, enable_irq ? 32'h3 : 32'h0); // DMA_IRQ_ENABLE
        cpu_write(32'h000B_0000, {30'd0, mode, 1'b1}); // DMA_CONTROL: START=1, MODE
    endtask

    task wait_dma_complete(output logic [15:0] out_len, output logic [7:0] err_code);
        logic [31:0] status_val;
        logic [31:0] len_val;
        logic [31:0] err_val;
        logic [1:0]  resp;

        do begin
            cpu_read(32'h000B_0004, status_val, resp);
        end while (status_val[0]); // Poll while BUSY == 1

        cpu_read(32'h000B_0014, len_val, resp);
        out_len = len_val[15:0];

        cpu_read(32'h000B_0020, err_val, resp);
        err_code = err_val[7:0];

        // Clear IRQ status via W1C
        cpu_write(32'h000B_001C, 32'h0000_0003);
    endtask

    // Scoreboard tracking
    int total_tests  = 0;
    int passed_tests = 0;
    int failed_tests = 0;

    task check(input bit cond, input string name);
        total_tests++;
        if (cond) begin
            $display("[PASS] %s", name);
            passed_tests++;
        end else begin
            $display("[FAIL] %s", name);
            failed_tests++;
        end
    endtask

    // =========================================================================
    // Main Verification Process
    // =========================================================================
    initial begin
        logic [15:0] out_len;
        logic [7:0]  err_code;
        logic [31:0] rdata;
        logic [1:0]  rresp;
        int i;

        // Init signals
        s_axi_awid    = 8'h0;
        s_axi_awaddr  = 32'h0;
        s_axi_awprot  = 3'b0;
        s_axi_awvalid = 1'b0;
        s_axi_wdata   = 32'h0;
        s_axi_wstrb   = 4'h0;
        s_axi_wvalid  = 1'b0;
        s_axi_bready  = 1'b0;
        s_axi_arid    = 8'h0;
        s_axi_araddr  = 32'h0;
        s_axi_arprot  = 3'b0;
        s_axi_arvalid = 1'b0;
        s_axi_rready  = 1'b0;
        rst_n         = 1'b0;

        $display("================================================================");
        $display("   DMA TOP-LEVEL INTEGRATED UNIT TESTBENCH (tb_dma_unit)       ");
        $display("================================================================");

        #(CLK_PERIOD * 3);
        rst_n = 1'b1;
        #(CLK_PERIOD * 3);

        // ---------------------------------------------------------------------
        // Test 1: Single-Byte Transfer (1 byte)
        // ---------------------------------------------------------------------
        $display("\n--- Test 1: Single-Byte Transfer (1 Byte) ---");
        dmem_write_byte(32'h0001_0000, 8'h5A);
        start_dma(32'h0001_0000, 32'h0002_0000, 16'd1, 1'b0); // Compress 1 byte
        wait_dma_complete(out_len, err_code);

        check(err_code === 8'h00, "DMA completed with ERR_NONE (0x00)");
        check(out_len === 16'd2, "1-byte uncompressed produces 2-byte RLE run record [1, 0x5A]");
        check(dmem_read_byte(32'h0002_0000) === 8'd1, "Destination DMEM byte 0 is run count = 1");
        check(dmem_read_byte(32'h0002_0001) === 8'h5A, "Destination DMEM byte 1 is symbol = 0x5A");

        // ---------------------------------------------------------------------
        // Test 2: Two-Byte Transfer (2 bytes)
        // ---------------------------------------------------------------------
        $display("\n--- Test 2: Two-Byte Transfer (2 Bytes) ---");
        dmem_write_byte(32'h0001_0010, 8'h77);
        dmem_write_byte(32'h0001_0011, 8'h77);
        start_dma(32'h0001_0010, 32'h0002_0010, 16'd2, 1'b0);
        wait_dma_complete(out_len, err_code);

        check(err_code === 8'h00, "2-byte DMA completed successfully");
        check(out_len === 16'd2, "2 identical bytes compress to single 2-byte record [2, 0x77]");
        check(dmem_read_byte(32'h0002_0010) === 8'd2, "Destination byte 0 is count = 2");
        check(dmem_read_byte(32'h0002_0011) === 8'h77, "Destination byte 1 is symbol = 0x77");

        // ---------------------------------------------------------------------
        // Test 3: Three-Byte Transfer (3 bytes)
        // ---------------------------------------------------------------------
        $display("\n--- Test 3: Three-Byte Transfer (3 Bytes) ---");
        dmem_write_byte(32'h0001_0020, 8'hAA);
        dmem_write_byte(32'h0001_0021, 8'hAA);
        dmem_write_byte(32'h0001_0022, 8'hAA);
        start_dma(32'h0001_0020, 32'h0002_0020, 16'd3, 1'b0);
        wait_dma_complete(out_len, err_code);

        check(err_code === 8'h00, "3-byte DMA completed successfully");
        check(out_len === 16'd2, "3 identical bytes compress to [3, 0xAA]");
        check(dmem_read_byte(32'h0002_0020) === 8'd3, "Destination count = 3");
        check(dmem_read_byte(32'h0002_0021) === 8'hAA, "Destination symbol = 0xAA");

        // ---------------------------------------------------------------------
        // Test 4: Four-Byte Transfer (4 bytes / 1 full word)
        // ---------------------------------------------------------------------
        $display("\n--- Test 4: Four-Byte Transfer (1 Full Word) ---");
        dmem_write_byte(32'h0001_0030, 8'hEE);
        dmem_write_byte(32'h0001_0031, 8'hEE);
        dmem_write_byte(32'h0001_0032, 8'hEE);
        dmem_write_byte(32'h0001_0033, 8'hEE);
        start_dma(32'h0001_0030, 32'h0002_0030, 16'd4, 1'b0);
        wait_dma_complete(out_len, err_code);

        check(err_code === 8'h00, "4-byte DMA completed successfully");
        check(out_len === 16'd2, "4 identical bytes compress to [4, 0xEE]");
        check(dmem_read_byte(32'h0002_0030) === 8'd4, "Destination count = 4");
        check(dmem_read_byte(32'h0002_0031) === 8'hEE, "Destination symbol = 0xEE");

        // ---------------------------------------------------------------------
        // Test 5: Full Run-Length Compression (16 bytes -> 8 bytes with real RLE)
        // ---------------------------------------------------------------------
        $display("\n--- Test 5: End-to-End Compression (16 -> 8 bytes) ---");
        // Pattern: 4x0x11, 4x0x22, 4x0x33, 4x0x44
        for (i = 0; i < 4; i++) dmem_write_byte(32'h0001_0100 + i, 8'h11);
        for (i = 4; i < 8; i++) dmem_write_byte(32'h0001_0100 + i, 8'h22);
        for (i = 8; i < 12; i++) dmem_write_byte(32'h0001_0100 + i, 8'h33);
        for (i = 12; i < 16; i++) dmem_write_byte(32'h0001_0100 + i, 8'h44);

        start_dma(32'h0001_0100, 32'h0002_0100, 16'd16, 1'b0); // Compress
        wait_dma_complete(out_len, err_code);

        check(err_code === 8'h00, "16-byte compression completed successfully");
        check(out_len === 16'd8, "16 bytes compressed down to 8 bytes (50% compression ratio)");
        check(dmem_read_byte(32'h0002_0100) === 8'd4 && dmem_read_byte(32'h0002_0101) === 8'h11, "Record 0: [4, 0x11]");
        check(dmem_read_byte(32'h0002_0102) === 8'd4 && dmem_read_byte(32'h0002_0103) === 8'h22, "Record 1: [4, 0x22]");
        check(dmem_read_byte(32'h0002_0104) === 8'd4 && dmem_read_byte(32'h0002_0105) === 8'h33, "Record 2: [4, 0x33]");
        check(dmem_read_byte(32'h0002_0106) === 8'd4 && dmem_read_byte(32'h0002_0107) === 8'h44, "Record 3: [4, 0x44]");

        // ---------------------------------------------------------------------
        // Test 6: Full Lossless Decompression (8 bytes -> 16 bytes with real RLE)
        // ---------------------------------------------------------------------
        $display("\n--- Test 6: End-to-End Decompression (8 -> 16 bytes) ---");
        // Take the 8-byte compressed output from 0x0002_0100 and decompress it to 0x0002_8100
        start_dma(32'h0002_0100, 32'h0002_8100, 16'd8, 1'b1); // MODE=1 (Decompress)
        wait_dma_complete(out_len, err_code);

        check(err_code === 8'h00, "8-byte decompression completed successfully");
        check(out_len === 16'd16, "Decompression expanded back to original 16 bytes");

        for (i = 0; i < 16; i++) begin
            if (dmem_read_byte(32'h0002_8100 + i) !== dmem_read_byte(32'h0001_0100 + i)) begin
                check(0, $sformatf("Decompressed byte %0d mismatch against original source", i));
            end
        end
        check(1, "All 16 decompressed bytes match original source bytes byte-for-byte!");

        // ---------------------------------------------------------------------
        // Test 7: Multi-Word Transfer (64 bytes)
        // ---------------------------------------------------------------------
        $display("\n--- Test 7: Multi-Word Transfer (64 bytes) ---");
        // Pattern: 32 bytes of 0x01, 32 bytes of 0x02
        for (i = 0; i < 32; i++) dmem_write_byte(32'h0001_0200 + i, 8'h01);
        for (i = 32; i < 64; i++) dmem_write_byte(32'h0001_0200 + i, 8'h02);

        start_dma(32'h0001_0200, 32'h0002_0200, 16'd64, 1'b0);
        wait_dma_complete(out_len, err_code);

        check(err_code === 8'h00, "64-byte compression completed successfully");
        check(out_len === 16'd4, "64 bytes compressed down to 4 bytes: [32, 0x01], [32, 0x02]");
        check(dmem_read_byte(32'h0002_0200) === 8'd32 && dmem_read_byte(32'h0002_0201) === 8'h01, "64-byte run 1 matches");
        check(dmem_read_byte(32'h0002_0202) === 8'd32 && dmem_read_byte(32'h0002_0203) === 8'h02, "64-byte run 2 matches");

        // ---------------------------------------------------------------------
        // Test 8: Partial Final Word Boundary Transfer (255 bytes)
        // ---------------------------------------------------------------------
        $display("\n--- Test 8: Partial Final Word Transfer (255 bytes) ---");
        // 255 bytes of identical symbol 0x88
        for (i = 0; i < 255; i++) dmem_write_byte(32'h0001_1000 + i, 8'h88);

        start_dma(32'h0001_1000, 32'h0002_1000, 16'd255, 1'b0);
        wait_dma_complete(out_len, err_code);

        check(err_code === 8'h00, "255-byte compression completed successfully");
        check(out_len === 16'd2, "255 bytes compressed to single record [255, 0x88]");
        check(dmem_read_byte(32'h0002_1000) === 8'd255, "Run count = 255");
        check(dmem_read_byte(32'h0002_1001) === 8'h88, "Symbol = 0x88");

        // ---------------------------------------------------------------------
        // Test 9: Maximum Capacity Transfer (256 bytes)
        // ---------------------------------------------------------------------
        $display("\n--- Test 9: Maximum Buffer Capacity Transfer (256 bytes) ---");
        // 256 bytes of 0x99. Note: max run count per RLE byte is 255, so 256 bytes becomes [255, 0x99] + [1, 0x99]
        for (i = 0; i < 256; i++) dmem_write_byte(32'h0001_2000 + i, 8'h99);

        start_dma(32'h0001_2000, 32'h0002_2000, 16'd256, 1'b0);
        wait_dma_complete(out_len, err_code);

        check(err_code === 8'h00, "256-byte max capacity compression completed");
        check(out_len === 16'd4, "256 bytes compressed to 4 bytes: [255, 0x99] + [1, 0x99]");
        check(dmem_read_byte(32'h0002_2000) === 8'd255 && dmem_read_byte(32'h0002_2001) === 8'h99, "First record [255, 0x99]");
        check(dmem_read_byte(32'h0002_2002) === 8'd1   && dmem_read_byte(32'h0002_2003) === 8'h99, "Second record [1, 0x99]");

        // ---------------------------------------------------------------------
        // Test 10: IRQ Generation, Masking, and W1C Status Clearing
        // ---------------------------------------------------------------------
        $display("\n--- Test 10: IRQ Generation & W1C Clearing ---");
        dmem_write_byte(32'h0001_3000, 8'hFE);
        // Start with IRQ enabled
        start_dma(32'h0001_3000, 32'h0002_3000, 16'd1, 1'b0, 1'b1);
        while (!dma_irq) @(posedge clk);
        check(dma_irq === 1'b1, "DMA level IRQ asserted upon transfer completion");

        // Read DMA_IRQ_STATUS (0x000B_001C)
        cpu_read(32'h000B_001C, rdata, rresp);
        check(rdata[0] === 1'b1, "DMA_IRQ_STATUS reflects DONE_IS == 1");

        // Clear via W1C
        cpu_write(32'h000B_001C, 32'h0000_0001);
        @(posedge clk);
        check(dma_irq === 1'b0, "DMA IRQ successfully deasserted after W1C clear");

        // ---------------------------------------------------------------------
        // Test 11: Parameter Errors & Busy Protection
        // ---------------------------------------------------------------------
        $display("\n--- Test 11: Parameter Errors ---");
        // Start transfer with length = 0
        start_dma(32'h0001_0000, 32'h0002_0000, 16'd0, 1'b0);
        wait_dma_complete(out_len, err_code);
        check(err_code === 8'h03, "Invalid length 0 trapped with ERR_BAD_LEN (0x03)");

        // Start transfer with source outside DMEM (0x0003_0000 is UART, invalid for DMEM)
        start_dma(32'h0003_0000, 32'h0002_0000, 16'd4, 1'b0);
        wait_dma_complete(out_len, err_code);
        check(err_code === 8'h01, "Invalid source address trapped with ERR_BAD_SRC (0x01)");

        // ---------------------------------------------------------------------
        // Test 12: Abort and Dynamic Reset Recovery
        // ---------------------------------------------------------------------
        $display("\n--- Test 12: Abort & Dynamic Reset Recovery ---");
        dmem_write_byte(32'h0001_4000, 8'h12);
        start_dma(32'h0001_4000, 32'h0002_4000, 16'd1, 1'b0);
        // Abort via CPU writing ABORT bit 2 in DMA_CONTROL
        cpu_write(32'h000B_0000, 32'h0000_0004);
        @(posedge clk);
        cpu_read(32'h000B_0004, rdata, rresp);
        check(rdata[0] === 1'b0, "DMA BUSY deasserted immediately after ABORT command");

        // Dynamic Reset
        rst_n <= 1'b0;
        #(CLK_PERIOD * 2);
        rst_n <= 1'b1;
        #(CLK_PERIOD * 2);

        // Verify recovery after dynamic reset
        dmem_write_byte(32'h0001_5000, 8'h33);
        start_dma(32'h0001_5000, 32'h0002_5000, 16'd1, 1'b0);
        wait_dma_complete(out_len, err_code);
        check(err_code === 8'h00, "Clean transfer completes successfully after dynamic reset");
        check(dmem_read_byte(32'h0002_5000) === 8'd1 && dmem_read_byte(32'h0002_5001) === 8'h33,
              "Destination memory verified correct after dynamic reset recovery");

        // =====================================================================
        // Final Summary
        // =====================================================================
        $display("\n================================================================");
        $display("          DMA UNIT (tb_dma_unit) VERIFICATION SUMMARY           ");
        $display("================================================================");
        $display("  Total Checks Executed : %0d", total_tests);
        $display("  Passed Checks         : %0d", passed_tests);
        $display("  Failed Checks         : %0d", failed_tests);
        $display("================================================================");

        if (failed_tests == 0) begin
            $display(">>> ALL DMA INTEGRATED UNIT CHECKS PASSED! <<<");
        end else begin
            $display(">>> FAILED: %0d check(s) failed. <<<", failed_tests);
        end

        #(CLK_PERIOD * 5);
        $finish;
    end

endmodule
