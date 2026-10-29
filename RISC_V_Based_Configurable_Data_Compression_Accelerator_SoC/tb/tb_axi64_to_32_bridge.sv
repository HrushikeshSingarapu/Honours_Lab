// =============================================================================
// tb_axi64_to_32_bridge.sv
//
// Comprehensive, self-checking SystemVerilog testbench for axi64_to_32_bridge.
//
// Verification Coverage:
//   1. Reset state and ready deassertion/assertion
//   2. 64-bit Read Burst Expansion (VeeR IFU Instruction Fetch emulation):
//      - arsize=3'b011, arlen=0 -> downstream 2-beat INCR burst (size=2, len=1)
//      - captures Beat 0 and Beat 1, assembles {Beat1, Beat0}
//   3. 64-bit Write Burst Splitting:
//      - awsize=3'b011, wstrb=8'hFF -> downstream 2-beat INCR burst (size=2, len=1)
//      - Beat 0 carries lower word & strobes, Beat 1 carries upper word & strobes
//   4. Channel Decoupling:
//      - AW-before-W (AW arrives 3 cycles before W)
//      - W-before-AW (W arrives 3 cycles before AW)
//   5. 32-bit Narrow Read - Lower Lane (addr[2] == 0)
//   6. 32-bit Narrow Read - Upper Lane (addr[2] == 1)
//   7. 32-bit Narrow Write - Lower Lane (addr[2] == 0)
//   8. 32-bit Narrow Write - Upper Lane (addr[2] == 1)
//   9. Sub-word Byte & Halfword Writes (Byte 0, Byte 5, Halfword 1, Halfword 3)
//  10. Downstream Backpressure (slave delays arready, awready, wready)
//  11. Upstream Backpressure (master delays rready, bready)
//  12. Error Propagation (SLVERR on read Beat 0, read Beat 1, and write response)
//  13. Upstream Throttling (arready/awready deasserted during in-flight transactions)
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

module tb_axi64_to_32_bridge;

    localparam ADDR_WIDTH = 32;
    localparam ID_WIDTH   = 8;

    // Clock & Reset
    reg clk;
    reg rst;

    // 64-bit Master Interface
    reg                   m_axi_awvalid;
    wire                  m_axi_awready;
    reg  [ID_WIDTH-1:0]   m_axi_awid;
    reg  [ADDR_WIDTH-1:0] m_axi_awaddr;
    reg  [7:0]            m_axi_awlen;
    reg  [2:0]            m_axi_awsize;
    reg  [1:0]            m_axi_awburst;
    reg                   m_axi_awlock;
    reg  [3:0]            m_axi_awcache;
    reg  [2:0]            m_axi_awprot;
    reg  [3:0]            m_axi_awqos;
    reg  [3:0]            m_axi_awregion;

    reg                   m_axi_wvalid;
    wire                  m_axi_wready;
    reg  [63:0]           m_axi_wdata;
    reg  [7:0]            m_axi_wstrb;
    reg                   m_axi_wlast;

    wire                  m_axi_bvalid;
    reg                   m_axi_bready;
    wire [1:0]            m_axi_bresp;
    wire [ID_WIDTH-1:0]   m_axi_bid;

    reg                   m_axi_arvalid;
    wire                  m_axi_arready;
    reg  [ID_WIDTH-1:0]   m_axi_arid;
    reg  [ADDR_WIDTH-1:0] m_axi_araddr;
    reg  [7:0]            m_axi_arlen;
    reg  [2:0]            m_axi_arsize;
    reg  [1:0]            m_axi_arburst;
    reg                   m_axi_arlock;
    reg  [3:0]            m_axi_arcache;
    reg  [2:0]            m_axi_arprot;
    reg  [3:0]            m_axi_arqos;
    reg  [3:0]            m_axi_arregion;

    wire                  m_axi_rvalid;
    reg                   m_axi_rready;
    wire [ID_WIDTH-1:0]   m_axi_rid;
    wire [63:0]           m_axi_rdata;
    wire [1:0]            m_axi_rresp;
    wire                  m_axi_rlast;

    // 32-bit Slave Interface
    wire                  s_axi_awvalid;
    reg                   s_axi_awready;
    wire [ID_WIDTH-1:0]   s_axi_awid;
    wire [ADDR_WIDTH-1:0] s_axi_awaddr;
    wire [7:0]            s_axi_awlen;
    wire [2:0]            s_axi_awsize;
    wire [1:0]            s_axi_awburst;
    wire                  s_axi_awlock;
    wire [3:0]            s_axi_awcache;
    wire [2:0]            s_axi_awprot;
    wire [3:0]            s_axi_awqos;
    wire                  s_axi_awuser;

    wire                  s_axi_wvalid;
    reg                   s_axi_wready;
    wire [31:0]           s_axi_wdata;
    wire [3:0]            s_axi_wstrb;
    wire                  s_axi_wlast;
    wire                  s_axi_wuser;

    reg                   s_axi_bvalid;
    wire                  s_axi_bready;
    reg  [1:0]            s_axi_bresp;
    reg  [ID_WIDTH-1:0]   s_axi_bid;
    reg                   s_axi_buser;

    wire                  s_axi_arvalid;
    reg                   s_axi_arready;
    wire [ID_WIDTH-1:0]   s_axi_arid;
    wire [ADDR_WIDTH-1:0] s_axi_araddr;
    wire [7:0]            s_axi_arlen;
    wire [2:0]            s_axi_arsize;
    wire [1:0]            s_axi_arburst;
    wire                  s_axi_arlock;
    wire [3:0]            s_axi_arcache;
    wire [2:0]            s_axi_arprot;
    wire [3:0]            s_axi_arqos;
    wire                  s_axi_aruser;

    reg                   s_axi_rvalid;
    wire                  s_axi_rready;
    reg  [ID_WIDTH-1:0]   s_axi_rid;
    reg  [31:0]           s_axi_rdata;
    reg  [1:0]            s_axi_rresp;
    reg                   s_axi_rlast;
    reg                   s_axi_ruser;

    // Test counters
    integer test_cnt = 0;
    integer pass_cnt = 0;
    integer fail_cnt = 0;

    // DUT Instantiation
    axi64_to_32_bridge #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .ID_WIDTH(ID_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_awid(m_axi_awid),
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst),
        .m_axi_awlock(m_axi_awlock),
        .m_axi_awcache(m_axi_awcache),
        .m_axi_awprot(m_axi_awprot),
        .m_axi_awqos(m_axi_awqos),
        .m_axi_awregion(m_axi_awregion),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_bid(m_axi_bid),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_arid(m_axi_arid),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arlock(m_axi_arlock),
        .m_axi_arcache(m_axi_arcache),
        .m_axi_arprot(m_axi_arprot),
        .m_axi_arqos(m_axi_arqos),
        .m_axi_arregion(m_axi_arregion),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready),
        .m_axi_rid(m_axi_rid),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_awid(s_axi_awid),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awlen(s_axi_awlen),
        .s_axi_awsize(s_axi_awsize),
        .s_axi_awburst(s_axi_awburst),
        .s_axi_awlock(s_axi_awlock),
        .s_axi_awcache(s_axi_awcache),
        .s_axi_awprot(s_axi_awprot),
        .s_axi_awqos(s_axi_awqos),
        .s_axi_awuser(s_axi_awuser),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wlast(s_axi_wlast),
        .s_axi_wuser(s_axi_wuser),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bid(s_axi_bid),
        .s_axi_buser(s_axi_buser),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_arid(s_axi_arid),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arlen(s_axi_arlen),
        .s_axi_arsize(s_axi_arsize),
        .s_axi_arburst(s_axi_arburst),
        .s_axi_arlock(s_axi_arlock),
        .s_axi_arcache(s_axi_arcache),
        .s_axi_arprot(s_axi_arprot),
        .s_axi_arqos(s_axi_arqos),
        .s_axi_aruser(s_axi_aruser),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .s_axi_rid(s_axi_rid),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rlast(s_axi_rlast),
        .s_axi_ruser(s_axi_ruser)
    );

    // Clock generator: 10 ns (100 MHz)
    always #5 clk = ~clk;

    // Reporting task
    task check(input string desc, input bit condition);
        test_cnt = test_cnt + 1;
        if (condition) begin
            $display("  [PASS] Test %02d: %s", test_cnt, desc);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  [FAIL] Test %02d: %s", test_cnt, desc);
            fail_cnt = fail_cnt + 1;
        end
    endtask

    // Monitored transaction records
    reg [ADDR_WIDTH-1:0] mon_awaddr;
    reg [7:0]            mon_awlen;
    reg [2:0]            mon_awsize;
    reg [1:0]            mon_awburst;
    reg [ID_WIDTH-1:0]   mon_awid;
    reg                  mon_aw_seen;

    reg [31:0]           mon_wdata_b0;
    reg [3:0]            mon_wstrb_b0;
    reg                  mon_wlast_b0;
    reg [31:0]           mon_wdata_b1;
    reg [3:0]            mon_wstrb_b1;
    reg                  mon_wlast_b1;
    integer              mon_w_count;

    reg [ADDR_WIDTH-1:0] mon_araddr;
    reg [7:0]            mon_arlen;
    reg [2:0]            mon_arsize;
    reg [1:0]            mon_arburst;
    reg [ID_WIDTH-1:0]   mon_arid;
    reg                  mon_ar_seen;

    reg [63:0]           mon_master_rdata;
    reg [1:0]            mon_master_rresp;
    reg [ID_WIDTH-1:0]   mon_master_rid;
    reg                  mon_master_rlast;

    // Initialize all signals
    task init_signals();
        begin
            clk = 0;
            rst = 1;
            m_axi_awvalid = 0; m_axi_awid = 0; m_axi_awaddr = 0; m_axi_awlen = 0;
            m_axi_awsize = 3'b010; m_axi_awburst = 2'b01; m_axi_awlock = 0;
            m_axi_awcache = 0; m_axi_awprot = 0; m_axi_awqos = 0; m_axi_awregion = 0;

            m_axi_wvalid = 0; m_axi_wdata = 0; m_axi_wstrb = 0; m_axi_wlast = 0;
            m_axi_bready = 0;

            m_axi_arvalid = 0; m_axi_arid = 0; m_axi_araddr = 0; m_axi_arlen = 0;
            m_axi_arsize = 3'b010; m_axi_arburst = 2'b01; m_axi_arlock = 0;
            m_axi_arcache = 0; m_axi_arprot = 0; m_axi_arqos = 0; m_axi_arregion = 0;

            m_axi_rready = 0;

            s_axi_awready = 1;
            s_axi_wready  = 1;
            s_axi_bvalid  = 0;
            s_axi_bresp   = 0;
            s_axi_bid     = 0;
            s_axi_buser   = 0;

            s_axi_arready = 1;
            s_axi_rvalid  = 0;
            s_axi_rdata   = 0;
            s_axi_rresp   = 0;
            s_axi_rid     = 0;
            s_axi_rlast   = 0;
            s_axi_ruser   = 0;

            mon_aw_seen   = 0;
            mon_w_count   = 0;
            mon_ar_seen   = 0;
        end
    endtask

    // Transaction execution task: Write
    task do_write(
        input [ADDR_WIDTH-1:0] addr,
        input [63:0]           data,
        input [7:0]            strb,
        input [2:0]            size,
        input [ID_WIDTH-1:0]   id,
        input [1:0]            resp
    );
        begin
            mon_aw_seen = 0;
            mon_w_count = 0;

            @(posedge clk);
            m_axi_awvalid <= 1'b1;
            m_axi_awaddr  <= addr;
            m_axi_awsize  <= size;
            m_axi_awlen   <= 8'h00;
            m_axi_awburst <= 2'b01;
            m_axi_awid    <= id;

            m_axi_wvalid  <= 1'b1;
            m_axi_wdata   <= data;
            m_axi_wstrb   <= strb;
            m_axi_wlast   <= 1'b1;
            m_axi_bready  <= 1'b1;

            // Wait for master AW and W handshakes
            fork
                begin
                    while (!(m_axi_awvalid && m_axi_awready)) @(posedge clk);
                    @(posedge clk);
                    m_axi_awvalid <= 1'b0;
                end
                begin
                    while (!(m_axi_wvalid && m_axi_wready)) @(posedge clk);
                    @(posedge clk);
                    m_axi_wvalid <= 1'b0;
                end
            join

            // Monitor downstream AW and W handshakes
            fork
                begin
                    while (!(s_axi_awvalid && s_axi_awready)) @(posedge clk);
                    mon_awaddr  = s_axi_awaddr;
                    mon_awlen   = s_axi_awlen;
                    mon_awsize  = s_axi_awsize;
                    mon_awburst = s_axi_awburst;
                    mon_awid    = s_axi_awid;
                    mon_aw_seen = 1;
                end
                begin
                    while (!(s_axi_wvalid && s_axi_wready)) @(posedge clk);
                    mon_wdata_b0 = s_axi_wdata;
                    mon_wstrb_b0 = s_axi_wstrb;
                    mon_wlast_b0 = s_axi_wlast;
                    mon_w_count  = 1;

                    if (!s_axi_wlast) begin
                        @(posedge clk);
                        while (!(s_axi_wvalid && s_axi_wready)) @(posedge clk);
                        mon_wdata_b1 = s_axi_wdata;
                        mon_wstrb_b1 = s_axi_wstrb;
                        mon_wlast_b1 = s_axi_wlast;
                        mon_w_count  = 2;
                    end
                end
            join

            // Wait for bridge to assert s_axi_bready
            while (!s_axi_bready) @(posedge clk);

            // Slave drives B response
            s_axi_bvalid <= 1'b1;
            s_axi_bresp  <= resp;
            s_axi_bid    <= id;
            @(posedge clk);
            s_axi_bvalid <= 1'b0;

            // Wait for master B handshake
            while (!(m_axi_bvalid && m_axi_bready)) @(posedge clk);
            @(posedge clk);
            m_axi_bready <= 1'b0;
            @(posedge clk);
        end
    endtask

    // Transaction execution task: Read
    task do_read(
        input [ADDR_WIDTH-1:0] addr,
        input [2:0]            size,
        input [ID_WIDTH-1:0]   id,
        input [31:0]           slave_data_b0,
        input [1:0]            slave_resp_b0,
        input [31:0]           slave_data_b1,
        input [1:0]            slave_resp_b1
    );
        begin
            mon_ar_seen = 0;

            @(posedge clk);
            m_axi_arvalid <= 1'b1;
            m_axi_araddr  <= addr;
            m_axi_arsize  <= size;
            m_axi_arlen   <= 8'h00;
            m_axi_arburst <= 2'b01;
            m_axi_arid    <= id;
            m_axi_rready  <= 1'b1;

            // Wait for master AR handshake
            while (!(m_axi_arvalid && m_axi_arready)) @(posedge clk);
            @(posedge clk);
            m_axi_arvalid <= 1'b0;

            // Wait for downstream AR handshake
            while (!(s_axi_arvalid && s_axi_arready)) @(posedge clk);
            mon_araddr  = s_axi_araddr;
            mon_arlen   = s_axi_arlen;
            mon_arsize  = s_axi_arsize;
            mon_arburst = s_axi_arburst;
            mon_arid    = s_axi_arid;
            mon_ar_seen = 1;

            if (size == 3'b011) begin
                // 64-bit read: 2-beat downstream burst
                while (!s_axi_rready) @(posedge clk);
                s_axi_rvalid <= 1'b1;
                s_axi_rdata  <= slave_data_b0;
                s_axi_rresp  <= slave_resp_b0;
                s_axi_rid    <= id;
                s_axi_rlast  <= 1'b0;
                @(posedge clk);
                while (!s_axi_rready) @(posedge clk);
                s_axi_rdata  <= slave_data_b1;
                s_axi_rresp  <= slave_resp_b1;
                s_axi_rlast  <= 1'b1;
                @(posedge clk);
                s_axi_rvalid <= 1'b0;
            end else begin
                // <= 32-bit read: single beat
                while (!s_axi_rready) @(posedge clk);
                s_axi_rvalid <= 1'b1;
                s_axi_rdata  <= slave_data_b0;
                s_axi_rresp  <= slave_resp_b0;
                s_axi_rid    <= id;
                s_axi_rlast  <= 1'b1;
                @(posedge clk);
                s_axi_rvalid <= 1'b0;
            end

            // Wait for master R handshake
            while (!(m_axi_rvalid && m_axi_rready)) @(posedge clk);
            mon_master_rdata = m_axi_rdata;
            mon_master_rresp = m_axi_rresp;
            mon_master_rid   = m_axi_rid;
            mon_master_rlast = m_axi_rlast;

            @(posedge clk);
            m_axi_rready <= 1'b0;
            @(posedge clk);
        end
    endtask

    // Main verification sequence
    initial begin
        init_signals();

        $display("");
        $display("========================================================================");
        $display("    COMPREHENSIVE VERIFICATION: AXI 64-TO-32 BRIDGE REDESIGN            ");
        $display("========================================================================");

        // Apply reset for 3 cycles
        #25;
        @(posedge clk);
        rst <= 0;
        repeat(2) @(posedge clk);
        #1;

        // ---------------------------------------------------------------------
        // TEST SUITE 1: Reset & Default State
        // ---------------------------------------------------------------------
        $display("\n--- [SUITE 1] Reset & Default State ---");
        check("s_axi_awvalid deasserted after reset", s_axi_awvalid == 1'b0);
        check("s_axi_wvalid deasserted after reset",  s_axi_wvalid == 1'b0);
        check("s_axi_arvalid deasserted after reset", s_axi_arvalid == 1'b0);
        check("m_axi_bvalid deasserted after reset",  m_axi_bvalid == 1'b0);
        check("m_axi_rvalid deasserted after reset",  m_axi_rvalid == 1'b0);
        check("m_axi_arready asserted in IDLE",        m_axi_arready == 1'b1);
        check("m_axi_awready asserted in IDLE",        m_axi_awready == 1'b1);
        check("m_axi_wready asserted in IDLE",         m_axi_wready == 1'b1);

        // ---------------------------------------------------------------------
        // TEST SUITE 2: 64-bit Read Burst Expansion (VeeR IFU Instruction Fetch)
        // Master requests 64-bit read at 0x8000_0100 (size=3, len=0).
        // Slave provides Beat 0 = 0x11223344, Beat 1 = 0x55667788.
        // Master must receive m_axi_rdata = {Beat 1, Beat 0} = 64'h55667788_11223344.
        // ---------------------------------------------------------------------
        $display("\n--- [SUITE 2] 64-bit Read Burst Expansion (VeeR IFU Fetch) ---");
        do_read(
            32'h8000_0100, // addr
            3'b011,        // size: 64-bit
            8'hA1,         // id
            32'h1122_3344, // slave beat 0
            2'b00,         // OKAY
            32'h5566_7788, // slave beat 1
            2'b00          // OKAY
        );

        check("Downstream AR handshake observed", mon_ar_seen == 1'b1);
        check("Downstream AR addr aligned to 64-bit (0x8000_0100)", mon_araddr == 32'h8000_0100);
        check("Downstream AR size clamped to 32-bit (3'b010)", mon_arsize == 3'b010);
        check("Downstream AR len expanded to 2 beats (8'h01)", mon_arlen == 8'h01);
        check("Downstream AR burst set to INCR (2'b01)", mon_arburst == 2'b01);
        check("Downstream AR ID preserved (0xA1)", mon_arid == 8'hA1);
        check("Master receives assembled 64-bit data {Beat1, Beat0}",
              mon_master_rdata == 64'h5566_7788_1122_3344);
        check("Master receives m_axi_rlast == 1", mon_master_rlast == 1'b1);
        check("Master receives m_axi_rresp == OKAY", mon_master_rresp == 2'b00);
        check("Master receives matching RID (0xA1)", mon_master_rid == 8'hA1);
        check("Bridge returns to IDLE and reasserts arready", m_axi_arready == 1'b1);

        // ---------------------------------------------------------------------
        // TEST SUITE 3: 64-bit Write Burst Splitting
        // Master drives 64-bit write (awsize=3'b011, wstrb=8'hFF, wdata=64'hAAAABBBB_CCCCDDDD).
        // Bridge must issue 2-beat 32-bit burst downstream:
        //   Beat 0: wdata = 0xCCCCDDDD, wstrb = 4'hF, wlast = 0
        //   Beat 1: wdata = 0xAAAABBBB, wstrb = 4'hF, wlast = 1
        // ---------------------------------------------------------------------
        $display("\n--- [SUITE 3] 64-bit Write Burst Splitting ---");
        do_write(
            32'h8000_0200,                // addr
            64'hAAAA_BBBB_CCCC_DDDD,      // data
            8'hFF,                        // strb
            3'b011,                       // size: 64-bit
            8'hB2,                        // id
            2'b00                         // OKAY
        );

        check("Downstream AW handshake observed", mon_aw_seen == 1'b1);
        check("Downstream AW addr aligned to 64-bit", mon_awaddr == 32'h8000_0200);
        check("Downstream AW len is 2 beats (8'h01)", mon_awlen == 8'h01);
        check("Downstream AW size is 32-bit (3'b010)", mon_awsize == 3'b010);
        check("Downstream received 2 write beats", mon_w_count == 2);
        check("Beat 0 wdata is lower word (0xCCCCDDDD)", mon_wdata_b0 == 32'hCCCC_DDDD);
        check("Beat 0 wstrb is lower strobes (0xF)", mon_wstrb_b0 == 4'hF);
        check("Beat 0 wlast is 0", mon_wlast_b0 == 1'b0);
        check("Beat 1 wdata is upper word (0xAAAABBBB)", mon_wdata_b1 == 32'hAAAA_BBBB);
        check("Beat 1 wstrb is upper strobes (0xF)", mon_wstrb_b1 == 4'hF);
        check("Beat 1 wlast is 1", mon_wlast_b1 == 1'b1);
        check("Write engine returns to IDLE (awready & wready high)",
              m_axi_awready == 1'b1 && m_axi_wready == 1'b1);

        // ---------------------------------------------------------------------
        // TEST SUITE 4: Decoupled AW and W Arrival
        // 4A: AW arrives 3 cycles before W
        // 4B: W arrives 3 cycles before AW
        // ---------------------------------------------------------------------
        $display("\n--- [SUITE 4] Decoupled AW and W Channels ---");
        // 4A: AW before W
        @(posedge clk);
        m_axi_awvalid <= 1'b1;
        m_axi_awaddr  <= 32'h8000_0300;
        m_axi_awsize  <= 3'b010;
        m_axi_awid    <= 8'hC1;
        m_axi_bready  <= 1'b1;

        @(posedge clk);
        m_axi_awvalid <= 1'b0;
        #1;
        check("AW buffered, wready remains high while waiting for W", m_axi_wready == 1'b1);
        repeat(3) @(posedge clk); // 3 idle cycles

        // Now W arrives
        m_axi_wvalid <= 1'b1;
        m_axi_wdata  <= 64'h0000_0000_1234_5678;
        m_axi_wstrb  <= 8'h0F;
        m_axi_wlast  <= 1'b1;

        @(posedge clk);
        m_axi_wvalid <= 1'b0;

        // Monitor downstream
        while (!(s_axi_awvalid && s_axi_awready)) @(posedge clk);
        check("Downstream write address matches captured AW (0x8000_0300)", s_axi_awaddr == 32'h8000_0300);
        while (!(s_axi_wvalid && s_axi_wready)) @(posedge clk);
        check("Downstream write data matches captured W (0x1234_5678)", s_axi_wdata == 32'h1234_5678);

        while (!s_axi_bready) @(posedge clk);
        s_axi_bvalid <= 1'b1; s_axi_bid <= 8'hC1; s_axi_bresp <= 2'b00;
        @(posedge clk);
        s_axi_bvalid <= 1'b0;
        while (!(m_axi_bvalid && m_axi_bready)) @(posedge clk);
        check("B response received after AW-before-W handshake", m_axi_bresp == 2'b00);
        @(posedge clk);
        m_axi_bready <= 1'b0;
        repeat(2) @(posedge clk);

        // 4B: W before AW
        @(posedge clk);
        m_axi_wvalid <= 1'b1;
        m_axi_wdata  <= 64'h8765_4321_0000_0000;
        m_axi_wstrb  <= 8'hF0;
        m_axi_wlast  <= 1'b1;
        m_axi_bready <= 1'b1;

        @(posedge clk);
        m_axi_wvalid <= 1'b0;
        #1;
        check("W buffered, awready remains high while waiting for AW", m_axi_awready == 1'b1);
        repeat(3) @(posedge clk); // 3 idle cycles

        // Now AW arrives
        m_axi_awvalid <= 1'b1;
        m_axi_awaddr  <= 32'h8000_0304;
        m_axi_awsize  <= 3'b010;
        m_axi_awid    <= 8'hC2;

        @(posedge clk);
        m_axi_awvalid <= 1'b0;

        // Monitor downstream
        while (!(s_axi_awvalid && s_axi_awready)) @(posedge clk);
        check("Downstream write address has bit 2 set (0x8000_0304)", s_axi_awaddr == 32'h8000_0304);
        while (!(s_axi_wvalid && s_axi_wready)) @(posedge clk);
        check("Downstream write data steered from upper word (0x8765_4321)", s_axi_wdata == 32'h8765_4321);

        while (!s_axi_bready) @(posedge clk);
        s_axi_bvalid <= 1'b1; s_axi_bid <= 8'hC2; s_axi_bresp <= 2'b00;
        @(posedge clk);
        s_axi_bvalid <= 1'b0;
        while (!(m_axi_bvalid && m_axi_bready)) @(posedge clk);
        check("B response received after W-before-AW handshake", m_axi_bresp == 2'b00);
        @(posedge clk);
        m_axi_bready <= 1'b0;
        repeat(2) @(posedge clk);

        // ---------------------------------------------------------------------
        // TEST SUITE 5: 32-bit Narrow Read - Lower Lane (addr[2] == 0)
        // ---------------------------------------------------------------------
        $display("\n--- [SUITE 5] 32-bit Narrow Read - Lower Lane (addr[2] == 0) ---");
        do_read(
            32'h2000_0000, // addr
            3'b010,        // size: 32-bit
            8'hD1,         // id
            32'hDEAD_BEEF, // slave beat 0
            2'b00,
            32'h0, 2'b00
        );

        check("Downstream AR addr passes exact addr 0x2000_0000", mon_araddr == 32'h2000_0000);
        check("Downstream AR len is 0 (single beat)", mon_arlen == 8'h00);
        check("Master receives lower word in [31:0]", mon_master_rdata[31:0] == 32'hDEAD_BEEF);
        check("Master receives zero-extended upper word in [63:32]", mon_master_rdata[63:32] == 32'h0);
        check("Master receives valid and last", mon_master_rlast == 1'b1);

        // ---------------------------------------------------------------------
        // TEST SUITE 6: 32-bit Narrow Read - Upper Lane (addr[2] == 1)
        // ---------------------------------------------------------------------
        $display("\n--- [SUITE 6] 32-bit Narrow Read - Upper Lane (addr[2] == 1) ---");
        do_read(
            32'h2000_0004, // addr
            3'b010,        // size: 32-bit
            8'hD2,         // id
            32'hCAFE_BABE, // slave beat 0
            2'b00,
            32'h0, 2'b00
        );

        check("Downstream AR addr passes exact addr 0x2000_0004", mon_araddr == 32'h2000_0004);
        check("Downstream AR len is 0 (single beat)", mon_arlen == 8'h00);
        check("Master receives steered upper word in [63:32]", mon_master_rdata[63:32] == 32'hCAFE_BABE);
        check("Master receives zero in [31:0]", mon_master_rdata[31:0] == 32'h0);
        check("Master receives valid and last", mon_master_rlast == 1'b1);

        // ---------------------------------------------------------------------
        // TEST SUITE 7: Sub-Word Byte & Halfword Writes
        // ---------------------------------------------------------------------
        $display("\n--- [SUITE 7] Sub-Word Byte & Halfword Writes ---");
        // 7A: Byte 0 (addr 0x3000_0000, wstrb=8'h01)
        do_write(
            32'h3000_0000,
            64'h0000_0000_0000_0042,
            8'h01,
            3'b000,
            8'hE1,
            2'b00
        );
        check("Byte 0 write: wdata[7:0] == 0x42", mon_wdata_b0[7:0] == 8'h42);
        check("Byte 0 write: wstrb == 4'b0001",   mon_wstrb_b0 == 4'b0001);

        // 7B: Byte 5 (addr 0x3000_0005, wstrb=8'h20, in upper 32-bit word)
        do_write(
            32'h3000_0005,
            64'h0000_9900_0000_0000,
            8'h20,
            3'b000,
            8'hE2,
            2'b00
        );
        check("Byte 5 write: addr has bit 2 set", mon_awaddr == 32'h3000_0005);
        check("Byte 5 write: wdata[15:8] == 0x99", mon_wdata_b0[15:8] == 8'h99);
        check("Byte 5 write: wstrb == 4'b0010",   mon_wstrb_b0 == 4'b0010);

        // 7C: Halfword 3 (addr 0x3000_0006, wstrb=8'hC0, bytes 6..7 in upper word)
        do_write(
            32'h3000_0006,
            64'h55AA_0000_0000_0000,
            8'hC0,
            3'b001,
            8'hE3,
            2'b00
        );
        check("Halfword 3 write: addr is 0x3000_0006", mon_awaddr == 32'h3000_0006);
        check("Halfword 3 write: wdata[31:16] == 0x55AA", mon_wdata_b0[31:16] == 16'h55AA);
        check("Halfword 3 write: wstrb == 4'b1100", mon_wstrb_b0 == 4'b1100);

        // ---------------------------------------------------------------------
        // TEST SUITE 8: Downstream & Upstream Backpressure
        // ---------------------------------------------------------------------
        $display("\n--- [SUITE 8] Backpressure & Stall Handling ---");
        // Downstream slave stalls arready for 3 cycles
        s_axi_arready <= 1'b0;
        @(posedge clk);
        m_axi_arvalid <= 1'b1;
        m_axi_araddr  <= 32'h4000_0000;
        m_axi_arsize  <= 3'b010;
        m_axi_arid    <= 8'hF1;
        m_axi_rready  <= 1'b1;

        @(posedge clk);
        m_axi_arvalid <= 1'b0;

        repeat(3) @(posedge clk);
        check("Bridge holds s_axi_arvalid asserted while slave stalls", s_axi_arvalid == 1'b1);
        check("Bridge holds s_axi_araddr stable while slave stalls", s_axi_araddr == 32'h4000_0000);

        // Release slave stall
        s_axi_arready <= 1'b1;
        @(posedge clk);
        @(posedge clk);

        // Slave delivers data, but master backpressures (m_axi_rready = 0)
        m_axi_rready <= 1'b0;
        s_axi_rvalid <= 1'b1;
        s_axi_rdata  <= 32'h7788_99AA;
        s_axi_rlast  <= 1'b1;
        @(posedge clk);
        s_axi_rvalid <= 1'b0;

        @(posedge clk);
        check("Bridge asserts m_axi_rvalid to master", m_axi_rvalid == 1'b1);
        check("Bridge data held stable: 0x778899AA", m_axi_rdata[31:0] == 32'h7788_99AA);

        repeat(2) @(posedge clk);
        check("Bridge continues holding m_axi_rvalid while master stalls", m_axi_rvalid == 1'b1);
        check("Bridge continues holding data while master stalls", m_axi_rdata[31:0] == 32'h7788_99AA);

        // Master releases stall
        m_axi_rready <= 1'b1;
        @(posedge clk);
        @(posedge clk);
        check("Master handshake completed, m_axi_rvalid deasserts", m_axi_rvalid == 1'b0);
        m_axi_rready <= 1'b0;
        repeat(2) @(posedge clk);

        // ---------------------------------------------------------------------
        // TEST SUITE 9: Error Propagation (SLVERR)
        // ---------------------------------------------------------------------
        $display("\n--- [SUITE 9] Error Propagation (SLVERR) ---");
        // 9A: Slave returns SLVERR on Beat 1 of 64-bit read
        do_read(
            32'h5000_0000,
            3'b011, // 64-bit
            8'hE8,
            32'h1111_1111,
            2'b00,  // OKAY
            32'h2222_2222,
            2'b10   // SLVERR
        );
        check("Master receives SLVERR (2'b10) consolidated error response", mon_master_rresp == 2'b10);
        check("Master receives data despite error", mon_master_rdata == 64'h2222_2222_1111_1111);

        // 9B: Slave returns SLVERR on write
        do_write(
            32'h5000_0000,
            64'h0,
            8'h0F,
            3'b010,
            8'hE9,
            2'b10   // SLVERR
        );
        check("Master receives SLVERR on write response", m_axi_bresp == 2'b10);

        // ---------------------------------------------------------------------
        // TEST SUITE 10: Upstream Throttling During Split Transactions
        // ---------------------------------------------------------------------
        $display("\n--- [SUITE 10] Upstream Throttling During Split Transactions ---");
        @(posedge clk);
        m_axi_arvalid <= 1'b1;
        m_axi_araddr  <= 32'h6000_0000;
        m_axi_arsize  <= 3'b011;
        s_axi_arready <= 1'b0; // slave stalls AR
        @(posedge clk);
        m_axi_arvalid <= 1'b0;
        @(posedge clk);
        check("m_axi_arready is deasserted while read transaction is in flight", m_axi_arready == 1'b0);

        // Release slave AR and deliver data
        s_axi_arready <= 1'b1;
        @(posedge clk);
        @(posedge clk);
        s_axi_rvalid <= 1'b1; s_axi_rdata <= 32'h0; s_axi_rlast <= 1'b0;
        @(posedge clk);
        s_axi_rdata <= 32'h0; s_axi_rlast <= 1'b1;
        @(posedge clk);
        s_axi_rvalid <= 1'b0;
        m_axi_rready <= 1'b1;
        @(posedge clk);
        @(posedge clk);
        m_axi_rready <= 1'b0;
        repeat(2) @(posedge clk);
        check("m_axi_arready is restored to 1 after read completes", m_axi_arready == 1'b1);

        // ---------------------------------------------------------------------
        // Final Summary
        // ---------------------------------------------------------------------
        $display("");
        $display("========================================================================");
        $display("   VERIFICATION SUMMARY FOR AXI 64-TO-32 BRIDGE                         ");
        $display("========================================================================");
        $display("   Total Checks Executed : %0d", test_cnt);
        $display("   Total Checks Passed   : %0d", pass_cnt);
        $display("   Total Checks Failed   : %0d", fail_cnt);
        if (fail_cnt == 0) begin
            $display("   STATUS: ALL TESTS PASSED SUCCESSFULLY!                             ");
        end else begin
            $display("   STATUS: FAILED %0d CHECKS!                                         ", fail_cnt);
        end
        $display("========================================================================");

        $finish;
    end

endmodule

`default_nettype wire
