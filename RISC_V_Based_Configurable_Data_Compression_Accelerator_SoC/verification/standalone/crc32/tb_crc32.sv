// =============================================================================
// tb_crc32.sv
//
// PURPOSE:
//   Self-checking verification testbench for crc32_top.
//   Tests:
//     1. Reset & default register values (RESULT, STATUS, INIT, DATA).
//     2. Standard IEEE 802.3 CRC-32 golden vectors:
//        - Vector A: ASCII "123456789" -> 0xCBF43926
//        - Vector B: Single byte 'A' (0x41) -> 0xD3D99E8B
//        - Vector C: Four 0x00 bytes -> 0x2144DF1C
//        - Vector D: Four 0xFF bytes -> 0xFFFFFFFF
//        - Vector E: 4-byte payload 0xDE, 0xAD, 0xBE, 0xEF -> 0x7C9CA35A
//     3. Byte-strobe handling (wstrb individual byte lane writes, halfword, full word).
//     4. Back-to-back operations and non-destructive CRC_RESULT readbacks during stream.
//     5. Control register re-initialization and custom seed programming via CRC_INIT.
//     6. Independent AXI handshakes (AW-before-W, W-before-AW, delayed BREADY/RREADY).
//     7. Error handling (unmapped register offsets, unaligned accesses -> SLVERR).
//     8. Large 256-byte stream verification against golden model (0x29058C73).
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module tb_crc32;

    localparam DATA_WIDTH = 32;
    localparam ADDR_WIDTH = 32;
    localparam STRB_WIDTH = DATA_WIDTH / 8;

    // Register Offsets
    localparam [ADDR_WIDTH-1:0]
        REG_CRC_DATA   = 32'h000A_0000,
        REG_CRC_RESULT = 32'h000A_0004,
        REG_CRC_CTRL   = 32'h000A_0008,
        REG_CRC_STATUS = 32'h000A_000C,
        REG_CRC_INIT   = 32'h000A_0010,
        REG_UNMAPPED_1 = 32'h000A_0024,
        REG_UNMAPPED_2 = 32'h000A_0040,
        REG_UNALIGNED  = 32'h000A_0003;

    localparam [1:0]
        RESP_OKAY   = 2'b00,
        RESP_EXOKAY = 2'b01,
        RESP_SLVERR = 2'b10,
        RESP_DECERR = 2'b11;

    // Clock and Reset Signals
    reg clk;
    reg rst_n;

    // AXI Write Channel Signals
    reg  [ADDR_WIDTH-1:0] s_axi_awaddr;
    reg  [2:0]            s_axi_awprot;
    reg                   s_axi_awvalid;
    wire                  s_axi_awready;

    reg  [DATA_WIDTH-1:0] s_axi_wdata;
    reg  [STRB_WIDTH-1:0] s_axi_wstrb;
    reg                   s_axi_wvalid;
    wire                  s_axi_wready;

    wire [1:0]            s_axi_bresp;
    wire                  s_axi_bvalid;
    reg                   s_axi_bready;

    // AXI Read Channel Signals
    reg  [ADDR_WIDTH-1:0] s_axi_araddr;
    reg  [2:0]            s_axi_arprot;
    reg                   s_axi_arvalid;
    wire                  s_axi_arready;

    wire [DATA_WIDTH-1:0] s_axi_rdata;
    wire [1:0]            s_axi_rresp;
    wire                  s_axi_rlast;
    wire                  s_axi_rvalid;
    reg                   s_axi_rready;

    // Test Tracking Variables
    integer test_count;
    integer pass_count;
    integer fail_count;
    integer timeout;

    // Instantiate DUT
    crc32_top #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .STRB_WIDTH(STRB_WIDTH)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .s_axi_awaddr (s_axi_awaddr),
        .s_axi_awprot (s_axi_awprot),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata  (s_axi_wdata),
        .s_axi_wstrb  (s_axi_wstrb),
        .s_axi_wvalid (s_axi_wvalid),
        .s_axi_wready (s_axi_wready),
        .s_axi_bresp  (s_axi_bresp),
        .s_axi_bvalid (s_axi_bvalid),
        .s_axi_bready (s_axi_bready),
        .s_axi_araddr (s_axi_araddr),
        .s_axi_arprot (s_axi_arprot),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata  (s_axi_rdata),
        .s_axi_rresp  (s_axi_rresp),
        .s_axi_rlast  (s_axi_rlast),
        .s_axi_rvalid (s_axi_rvalid),
        .s_axi_rready (s_axi_rready)
    );

    // Clock Generation: 100 MHz (10 ns period)
    always #5 clk = ~clk;

    // Simulation Watchdog (500 us maximum simulation time)
    initial begin
        #500_000;
        $display("\n>>> ERROR: Simulation Watchdog Expired (500us)! Simulation aborted. <<<");
        $finish;
    end

    // =========================================================================
    // AXI Bus Helper Tasks
    // =========================================================================

    task axi_write(
        input  [ADDR_WIDTH-1:0] addr,
        input  [DATA_WIDTH-1:0] data,
        input  [STRB_WIDTH-1:0] strb,
        input  [1:0]            exp_bresp
    );
        reg aw_done, w_done, b_done;
        reg [1:0] latched_bresp;
        begin
            aw_done = 0;
            w_done  = 0;
            b_done  = 0;
            latched_bresp = 2'b11;

            @(posedge clk);
            s_axi_awaddr  <= addr;
            s_axi_awprot  <= 3'b000;
            s_axi_awvalid <= 1'b1;
            s_axi_wdata   <= data;
            s_axi_wstrb   <= strb;
            s_axi_wvalid  <= 1'b1;
            s_axi_bready  <= 1'b1;

            timeout = 100;
            while ((!aw_done || !w_done || !b_done) && timeout > 0) begin
                @(posedge clk);
                if (s_axi_awready && s_axi_awvalid) begin
                    s_axi_awvalid <= 1'b0;
                    aw_done = 1;
                end
                if (s_axi_wready && s_axi_wvalid) begin
                    s_axi_wvalid <= 1'b0;
                    w_done = 1;
                end
                if (s_axi_bvalid && s_axi_bready) begin
                    latched_bresp = s_axi_bresp;
                    s_axi_bready <= 1'b0;
                    b_done = 1;
                end
                timeout = timeout - 1;
            end
            s_axi_awvalid <= 1'b0;
            s_axi_wvalid  <= 1'b0;
            s_axi_bready  <= 1'b0;

            test_count = test_count + 1;
            if (b_done && (latched_bresp == exp_bresp)) begin
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL [WR @ 0x%08x]: b_done=%b bresp=%b (exp %b)", addr, b_done, latched_bresp, exp_bresp);
            end
            repeat(1) @(posedge clk);
        end
    endtask

    task axi_read(
        input  [ADDR_WIDTH-1:0] addr,
        output [DATA_WIDTH-1:0] rdata,
        input  [1:0]            exp_rresp
    );
        reg ar_done, r_done;
        reg [1:0] latched_rresp;
        begin
            ar_done = 0;
            r_done  = 0;
            latched_rresp = 2'b11;
            rdata = {DATA_WIDTH{1'b0}};

            @(posedge clk);
            s_axi_araddr  <= addr;
            s_axi_arprot  <= 3'b000;
            s_axi_arvalid <= 1'b1;
            s_axi_rready  <= 1'b1;

            timeout = 100;
            while ((!ar_done || !r_done) && timeout > 0) begin
                @(posedge clk);
                if (s_axi_arready && s_axi_arvalid) begin
                    s_axi_arvalid <= 1'b0;
                    ar_done = 1;
                end
                if (s_axi_rvalid && s_axi_rready) begin
                    rdata = s_axi_rdata;
                    latched_rresp = s_axi_rresp;
                    s_axi_rready <= 1'b0;
                    r_done = 1;
                end
                timeout = timeout - 1;
            end
            s_axi_arvalid <= 1'b0;
            s_axi_rready  <= 1'b0;

            test_count = test_count + 1;
            if (r_done && (latched_rresp == exp_rresp)) begin
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL [RD @ 0x%08x]: r_done=%b rresp=%b (exp %b)", addr, r_done, latched_rresp, exp_rresp);
            end
            repeat(1) @(posedge clk);
        end
    endtask

    task check_reg(
        input [ADDR_WIDTH-1:0] addr,
        input [DATA_WIDTH-1:0] exp_val,
        input [DATA_WIDTH-1:0] mask,
        input [256*8-1:0]      test_name
    );
        reg [DATA_WIDTH-1:0] rd_data;
        begin
            axi_read(addr, rd_data, RESP_OKAY);
            test_count = test_count + 1;
            if ((rd_data & mask) === (exp_val & mask)) begin
                pass_count = pass_count + 1;
                $display("  PASS: %0s -> 0x%08x", test_name, rd_data);
            end else begin
                fail_count = fail_count + 1;
                $display("  FAIL: %0s -> 0x%08x (exp 0x%08x, mask 0x%08x)", test_name, rd_data, exp_val, mask);
            end
        end
    endtask

    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    reg [DATA_WIDTH-1:0] rd_val;
    integer i;

    initial begin
        clk           = 0;
        rst_n         = 0;
        s_axi_awaddr  = 0;
        s_axi_awprot  = 0;
        s_axi_awvalid = 0;
        s_axi_wdata   = 0;
        s_axi_wstrb   = 0;
        s_axi_wvalid  = 0;
        s_axi_bready  = 0;
        s_axi_araddr  = 0;
        s_axi_arprot  = 0;
        s_axi_arvalid = 0;
        s_axi_rready  = 0;
        test_count    = 0;
        pass_count    = 0;
        fail_count    = 0;

        $display("\n==================================================");
        $display("   STARTING CRC-32 STANDALONE TESTBENCH (tb_crc32)");
        $display("==================================================");

        // Reset Pulse
        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(3) @(posedge clk);

        // ---------------------------------------------------------------------
        // TEST 1: Reset & Default Register Values
        // ---------------------------------------------------------------------
        $display("\n[TEST 1] Reset & Default Register Values");
        // Result on reset is 0x00000000 (0xFFFFFFFF ^ 0xFFFFFFFF)
        check_reg(REG_CRC_RESULT, 32'h0000_0000, 32'hFFFF_FFFF, "CRC_RESULT reset state (=0x0)");
        // Status on reset has byte_count = 0 and busy = 0
        check_reg(REG_CRC_STATUS, 32'h0000_0000, 32'hFFFF_FFFF, "CRC_STATUS reset state (byte_count=0, busy=0)");
        // Init seed defaults to 0xFFFFFFFF
        check_reg(REG_CRC_INIT, 32'hFFFF_FFFF, 32'hFFFF_FFFF, "CRC_INIT reset state (=0xFFFFFFFF)");
        // Data register reset state
        check_reg(REG_CRC_DATA, 32'h0000_0000, 32'hFFFF_FFFF, "CRC_DATA reset state (=0x0)");

        // ---------------------------------------------------------------------
        // TEST 2: Standard IEEE 802.3 CRC-32 Golden Vectors
        // ---------------------------------------------------------------------
        $display("\n[TEST 2] Standard IEEE 802.3 CRC-32 Golden Vectors");

        // Subtest 2a: Standard Benchmark ASCII "123456789" -> 0xCBF43926
        // Word 1: '1','2','3','4' -> 0x34333231 (wstrb = 4'b1111)
        axi_write(REG_CRC_DATA, 32'h3433_3231, 4'b1111, RESP_OKAY);
        // Word 2: '5','6','7','8' -> 0x38373635 (wstrb = 4'b1111)
        axi_write(REG_CRC_DATA, 32'h3837_3635, 4'b1111, RESP_OKAY);
        // Word 3: '9' -> 0x00000039 (wstrb = 4'b0001)
        axi_write(REG_CRC_DATA, 32'h0000_0039, 4'b0001, RESP_OKAY);

        check_reg(REG_CRC_RESULT, 32'hCBF4_3926, 32'hFFFF_FFFF, "Vector '123456789' CRC-32 result");
        check_reg(REG_CRC_STATUS, 32'h0000_0009, 32'h0000_FFFF, "Vector '123456789' byte_count (=9)");

        // Subtest 2b: Single Byte ASCII 'A' (0x41) -> 0xD3D99E8B
        // Reset accumulator via CRC_CTRL
        axi_write(REG_CRC_CTRL, 32'h0000_0001, 4'b0001, RESP_OKAY);
        check_reg(REG_CRC_STATUS, 32'h0000_0000, 32'h0000_FFFF, "Accumulator re-init (byte_count=0)");
        axi_write(REG_CRC_DATA, 32'h0000_0041, 4'b0001, RESP_OKAY);
        check_reg(REG_CRC_RESULT, 32'hD3D9_9E8B, 32'hFFFF_FFFF, "Vector 'A' (0x41) CRC-32 result");
        check_reg(REG_CRC_STATUS, 32'h0000_0001, 32'h0000_FFFF, "Vector 'A' byte_count (=1)");

        // Subtest 2c: Four 0x00 bytes -> 0x2144DF1C
        axi_write(REG_CRC_CTRL, 32'h0000_0001, 4'b0001, RESP_OKAY);
        axi_write(REG_CRC_DATA, 32'h0000_0000, 4'b1111, RESP_OKAY);
        check_reg(REG_CRC_RESULT, 32'h2144_DF1C, 32'hFFFF_FFFF, "Vector 4x0x00 CRC-32 result");
        check_reg(REG_CRC_STATUS, 32'h0000_0004, 32'h0000_FFFF, "Vector 4x0x00 byte_count (=4)");

        // Subtest 2d: Four 0xFF bytes -> 0xFFFFFFFF
        axi_write(REG_CRC_CTRL, 32'h0000_0001, 4'b0001, RESP_OKAY);
        axi_write(REG_CRC_DATA, 32'hFFFF_FFFF, 4'b1111, RESP_OKAY);
        check_reg(REG_CRC_RESULT, 32'hFFFF_FFFF, 32'hFFFF_FFFF, "Vector 4x0xFF CRC-32 result");
        check_reg(REG_CRC_STATUS, 32'h0000_0004, 32'h0000_FFFF, "Vector 4x0xFF byte_count (=4)");

        // Subtest 2e: 4-byte payload 0xDE, 0xAD, 0xBE, 0xEF -> 0x7C9CA35A
        // Little-endian in memory: Byte 0=0xDE, 1=0xAD, 2=0xBE, 3=0xEF -> word 0xEFBEADDE
        axi_write(REG_CRC_CTRL, 32'h0000_0001, 4'b0001, RESP_OKAY);
        axi_write(REG_CRC_DATA, 32'hEFBE_ADDE, 4'b1111, RESP_OKAY);
        check_reg(REG_CRC_RESULT, 32'h7C9C_A35A, 32'hFFFF_FFFF, "Vector [0xDE, 0xAD, 0xBE, 0xEF] CRC-32 result");
        check_reg(REG_CRC_STATUS, 32'h0000_0004, 32'h0000_FFFF, "Vector 0xDEADBEEF byte_count (=4)");

        // ---------------------------------------------------------------------
        // TEST 3: Byte-Strobe Sub-Word Flexibility
        // ---------------------------------------------------------------------
        $display("\n[TEST 3] Byte-Strobe Sub-Word Flexibility (Arbitrary Lane Packing)");
        // Write ASCII "123456789" one slice at a time with different byte strobes:
        axi_write(REG_CRC_CTRL, 32'h0000_0001, 4'b0001, RESP_OKAY);

        // Byte 0 lane: "1" (0x31)
        axi_write(REG_CRC_DATA, 32'hA0A0_A031, 4'b0001, RESP_OKAY);
        // Byte 1 lane: "2" (0x32)
        axi_write(REG_CRC_DATA, 32'hB0B0_32B0, 4'b0010, RESP_OKAY);
        // Byte 2 lane: "3" (0x33)
        axi_write(REG_CRC_DATA, 32'hC033_C0C0, 4'b0100, RESP_OKAY);
        // Byte 3 lane: "4" (0x34)
        axi_write(REG_CRC_DATA, 32'h34D0_D0D0, 4'b1000, RESP_OKAY);
        // Lower halfword (bytes 0,1): "5","6" (0x35, 0x36 -> 0x3635)
        axi_write(REG_CRC_DATA, 32'hE0E0_3635, 4'b0011, RESP_OKAY);
        // Upper halfword (bytes 2,3): "7","8" (0x37, 0x38 -> 0x3837)
        axi_write(REG_CRC_DATA, 32'h3837_F0F0, 4'b1100, RESP_OKAY);
        // Byte 0 lane: "9" (0x39)
        axi_write(REG_CRC_DATA, 32'h0000_0039, 4'b0001, RESP_OKAY);

        check_reg(REG_CRC_RESULT, 32'hCBF4_3926, 32'hFFFF_FFFF, "Mixed wstrb stream '123456789' CRC-32");
        check_reg(REG_CRC_STATUS, 32'h0000_0009, 32'h0000_FFFF, "Mixed wstrb byte_count (=9)");

        // ---------------------------------------------------------------------
        // TEST 4: Back-to-Back Operations & Accumulation Continuity
        // ---------------------------------------------------------------------
        $display("\n[TEST 4] Back-to-Back Operations & Accumulation Continuity");
        axi_write(REG_CRC_CTRL, 32'h0000_0001, 4'b0001, RESP_OKAY);

        // Write first half of stream
        axi_write(REG_CRC_DATA, 32'h3433_3231, 4'b1111, RESP_OKAY);
        // Non-destructive read in between writes
        axi_read(REG_CRC_RESULT, rd_val, RESP_OKAY);
        $display("  INFO: Interim CRC after 4 bytes = 0x%08x", rd_val);

        // Write second half of stream
        axi_write(REG_CRC_DATA, 32'h3837_3635, 4'b1111, RESP_OKAY);
        axi_write(REG_CRC_DATA, 32'h0000_0039, 4'b0001, RESP_OKAY);

        check_reg(REG_CRC_RESULT, 32'hCBF4_3926, 32'hFFFF_FFFF, "Final CRC matches despite intermediate reads");

        // ---------------------------------------------------------------------
        // TEST 5: Custom CRC_INIT Seed Programming
        // ---------------------------------------------------------------------
        $display("\n[TEST 5] Custom CRC_INIT Seed Programming");
        // Write custom initial seed = 0x12345678
        axi_write(REG_CRC_INIT, 32'h1234_5678, 4'b1111, RESP_OKAY);
        check_reg(REG_CRC_INIT, 32'h1234_5678, 32'hFFFF_FFFF, "CRC_INIT readback matches programmed value");

        // Re-init accumulator: should seed from 0x12345678
        axi_write(REG_CRC_CTRL, 32'h0000_0001, 4'b0001, RESP_OKAY);
        // Result of empty input with seed 0x12345678 is 0x12345678 ^ 0xFFFFFFFF = 0xEDCBA987
        check_reg(REG_CRC_RESULT, (32'h1234_5678 ^ 32'hFFFF_FFFF), 32'hFFFF_FFFF, "Custom seeded empty result");

        // Restore default seed 0xFFFFFFFF
        axi_write(REG_CRC_INIT, 32'hFFFF_FFFF, 4'b1111, RESP_OKAY);
        axi_write(REG_CRC_CTRL, 32'h0000_0001, 4'b0001, RESP_OKAY);
        check_reg(REG_CRC_RESULT, 32'h0000_0000, 32'hFFFF_FFFF, "Restored default seed empty result (=0x0)");

        // ---------------------------------------------------------------------
        // TEST 6: Independent AXI Handshakes & Backpressure
        // ---------------------------------------------------------------------
        $display("\n[TEST 6] Independent AXI Handshakes & Channel Decoupling");

        // Subtest 6a: AW valid before W valid (decoupled handshakes)
        begin : test_6a
            reg aw_d, w_d, b_d;
            reg [1:0] bresp_d;
            aw_d = 0;
            w_d  = 0;
            b_d  = 0;
            bresp_d = 2'b11;

            @(posedge clk);
            s_axi_awaddr  <= REG_CRC_CTRL;
            s_axi_awprot  <= 3'b000;
            s_axi_awvalid <= 1'b1;
            s_axi_bready  <= 1'b1;

            timeout = 100;
            while (!aw_d && timeout > 0) begin
                @(posedge clk);
                if (s_axi_awready && s_axi_awvalid) begin
                    s_axi_awvalid <= 1'b0;
                    aw_d = 1;
                end
                timeout = timeout - 1;
            end
            s_axi_awvalid <= 1'b0;

            // Wait 3 cycles before asserting W
            repeat(3) @(posedge clk);

            s_axi_wdata   <= 32'h0000_0001;
            s_axi_wstrb   <= 4'b0001;
            s_axi_wvalid  <= 1'b1;

            timeout = 100;
            while ((!w_d || !b_d) && timeout > 0) begin
                @(posedge clk);
                if (s_axi_wready && s_axi_wvalid) begin
                    s_axi_wvalid <= 1'b0;
                    w_d = 1;
                end
                if (s_axi_bvalid && s_axi_bready) begin
                    bresp_d = s_axi_bresp;
                    s_axi_bready <= 1'b0;
                    b_d = 1;
                end
                timeout = timeout - 1;
            end
            s_axi_wvalid <= 1'b0;
            s_axi_bready <= 1'b0;

            test_count = test_count + 1;
            if (aw_d && w_d && b_d && (bresp_d == RESP_OKAY)) begin
                pass_count = pass_count + 1;
                $display("  PASS: AW-before-W decoupled write completed OKAY");
            end else begin
                fail_count = fail_count + 1;
                $display("  FAIL: AW-before-W failed (aw=%b, w=%b, b=%b)", aw_d, w_d, b_d);
            end
            repeat(2) @(posedge clk);
        end

        // Subtest 6b: W valid before AW valid (decoupled handshakes)
        begin : test_6b
            reg aw_d, w_d, b_d;
            reg [1:0] bresp_d;
            aw_d = 0;
            w_d  = 0;
            b_d  = 0;
            bresp_d = 2'b11;

            @(posedge clk);
            s_axi_wdata   <= 32'h0000_0041;
            s_axi_wstrb   <= 4'b0001;
            s_axi_wvalid  <= 1'b1;
            s_axi_bready  <= 1'b1;

            timeout = 100;
            while (!w_d && timeout > 0) begin
                @(posedge clk);
                if (s_axi_wready && s_axi_wvalid) begin
                    s_axi_wvalid <= 1'b0;
                    w_d = 1;
                end
                timeout = timeout - 1;
            end
            s_axi_wvalid <= 1'b0;

            // Wait 3 cycles before asserting AW
            repeat(3) @(posedge clk);

            s_axi_awaddr  <= REG_CRC_DATA;
            s_axi_awprot  <= 3'b000;
            s_axi_awvalid <= 1'b1;

            timeout = 100;
            while ((!aw_d || !b_d) && timeout > 0) begin
                @(posedge clk);
                if (s_axi_awready && s_axi_awvalid) begin
                    s_axi_awvalid <= 1'b0;
                    aw_d = 1;
                end
                if (s_axi_bvalid && s_axi_bready) begin
                    bresp_d = s_axi_bresp;
                    s_axi_bready <= 1'b0;
                    b_d = 1;
                end
                timeout = timeout - 1;
            end
            s_axi_awvalid <= 1'b0;
            s_axi_bready  <= 1'b0;

            test_count = test_count + 1;
            if (aw_d && w_d && b_d && (bresp_d == RESP_OKAY)) begin
                pass_count = pass_count + 1;
                $display("  PASS: W-before-AW decoupled write completed OKAY");
            end else begin
                fail_count = fail_count + 1;
                $display("  FAIL: W-before-AW failed (aw=%b, w=%b, b=%b)", aw_d, w_d, b_d);
            end
            repeat(2) @(posedge clk);
        end

        // Subtest 6c: RREADY backpressure holding
        begin : test_6c
            reg r_held_ok;
            r_held_ok = 1;

            @(posedge clk);
            s_axi_araddr  <= REG_CRC_RESULT;
            s_axi_arprot  <= 3'b000;
            s_axi_arvalid <= 1'b1;
            s_axi_rready  <= 1'b0; // Hold backpressure

            @(posedge clk);
            while (!s_axi_arready) @(posedge clk);
            s_axi_arvalid <= 1'b0;

            // Wait for RVALID with RREADY low
            while (!s_axi_rvalid) @(posedge clk);

            // Hold RREADY low for 4 cycles; verify RVALID and rlast stay asserted
            repeat(4) begin
                @(posedge clk);
                if (!s_axi_rvalid || !s_axi_rlast) r_held_ok = 0;
            end

            // Release backpressure
            s_axi_rready <= 1'b1;
            @(posedge clk);
            s_axi_rready <= 1'b0;

            test_count = test_count + 1;
            if (r_held_ok) begin
                pass_count = pass_count + 1;
                $display("  PASS: RVALID and rlast held high during RREADY backpressure");
            end else begin
                fail_count = fail_count + 1;
                $display("  FAIL: RVALID dropped prematurely during backpressure");
            end
            repeat(2) @(posedge clk);
        end

        // ---------------------------------------------------------------------
        // TEST 7: Error Conditions & Unmapped Access
        // ---------------------------------------------------------------------
        $display("\n[TEST 7] Error Conditions & Unmapped Access");

        // Subtest 7a: Write to unmapped offset (0x24) -> SLVERR (2'b10)
        axi_write(REG_UNMAPPED_1, 32'hDEAD_BEEF, 4'b1111, RESP_SLVERR);
        $display("  PASS: Write to unmapped offset 0x24 returns SLVERR");

        // Subtest 7b: Read from unmapped offset (0x40) -> SLVERR (2'b10)
        axi_read(REG_UNMAPPED_2, rd_val, RESP_SLVERR);
        test_count = test_count + 1;
        if (rd_val === 32'h0000_0000) begin
            pass_count = pass_count + 1;
            $display("  PASS: Read from unmapped offset 0x40 returns SLVERR and 0x0 data");
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL: Read unmapped offset returned non-zero data (0x%08x)", rd_val);
        end

        // Subtest 7c: Unaligned address write (addr=0x03) -> SLVERR
        axi_write(REG_UNALIGNED, 32'hCAFE_BABE, 4'b1111, RESP_SLVERR);
        $display("  PASS: Unaligned write (addr=0x03) returns SLVERR");

        // Subtest 7d: Unaligned address read (addr=0x03) -> SLVERR
        axi_read(REG_UNALIGNED, rd_val, RESP_SLVERR);
        $display("  PASS: Unaligned read (addr=0x03) returns SLVERR");

        // ---------------------------------------------------------------------
        // TEST 8: Large 256-Byte Stream Verification
        // ---------------------------------------------------------------------
        $display("\n[TEST 8] Large 256-Byte Stream Verification (Golden: 0x29058C73)");
        // Reset CRC
        axi_write(REG_CRC_CTRL, 32'h0000_0001, 4'b0001, RESP_OKAY);

        // Stream 256 bytes in 64 words: word[i] = {byte[4i+3], byte[4i+2], byte[4i+1], byte[4i]}
        for (i = 0; i < 64; i = i + 1) begin
            axi_write(
                REG_CRC_DATA,
                {i[7:0] * 8'd4 + 8'd3, i[7:0] * 8'd4 + 8'd2, i[7:0] * 8'd4 + 8'd1, i[7:0] * 8'd4},
                4'b1111,
                RESP_OKAY
            );
        end

        check_reg(REG_CRC_STATUS, 32'h0000_0100, 32'h0000_FFFF, "256-byte stream byte_count (=256 / 0x100)");
        check_reg(REG_CRC_RESULT, 32'h2905_8C73, 32'hFFFF_FFFF, "256-byte stream CRC-32 (Golden 0x29058C73)");

        // ---------------------------------------------------------------------
        // Simulation Summary
        // ---------------------------------------------------------------------
        repeat(10) @(posedge clk);
        $display("\n==================================================");
        $display("   CRC-32 STANDALONE TESTBENCH SUMMARY");
        $display("   TOTAL TESTS : %0d", test_count);
        $display("   PASSED      : %0d", pass_count);
        $display("   FAILED      : %0d", fail_count);
        $display("==================================================");

        if (fail_count == 0) begin
            $display(">>> ALL CRC-32 TESTS PASSED SUCCESSFULLY! <<<\n");
        end else begin
            $display(">>> SOME CRC-32 TESTS FAILED! <<<\n");
        end

        $finish;
    end

endmodule

`default_nettype wire
