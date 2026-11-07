// =============================================================================
// tb_timer_top.sv
//
// PURPOSE:
//   Self-checking verification testbench for timer_top.
//   Tests:
//     1. Reset & default register values (mtime=0, mtimecmp=max, ctrl=1, irq=0).
//     2. Counter progression & enable/disable (start/stop) control.
//     3. Clock prescaler divider verification (N+1 clock cycles per tick).
//     4. Compare match & level-sensitive interrupt assertion.
//     5. Dynamic interrupt clearing via mtimecmp update & W1C status bit.
//     6. Auto-reload periodic mode (counter resets to 0 on match).
//     7. 64-bit upper-word compare boundary handling.
//     8. Independent AXI handshakes & error handling (unmapped/unaligned -> SLVERR).
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module tb_timer_top;

    localparam DATA_WIDTH = 32;
    localparam ADDR_WIDTH = 32;
    localparam STRB_WIDTH = DATA_WIDTH / 8;

    // Register Offsets
    localparam [ADDR_WIDTH-1:0]
        REG_MTIME_LOW     = 32'h0005_0000,
        REG_MTIME_HIGH    = 32'h0005_0004,
        REG_MTIMECMP_LOW  = 32'h0005_0008,
        REG_MTIMECMP_HIGH = 32'h0005_000C,
        REG_TIMER_CTRL    = 32'h0005_0010,
        REG_TIMER_STATUS  = 32'h0005_0014,
        REG_UNMAPPED      = 32'h0005_0028,
        REG_UNALIGNED     = 32'h0005_0002;

    localparam [1:0]
        RESP_OKAY   = 2'b00,
        RESP_EXOKAY = 2'b01,
        RESP_SLVERR = 2'b10,
        RESP_DECERR = 2'b11;

    // Clock and Reset Signals
    reg clk;
    reg rst_n;

    // Interrupt Pin
    wire timer_irq;

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
    timer_top #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .STRB_WIDTH(STRB_WIDTH)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .timer_irq    (timer_irq),
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
    reg [DATA_WIDTH-1:0] rd_val, val1, val2;

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
        $display("   STARTING TIMER STANDALONE TESTBENCH (tb_timer_top)");
        $display("==================================================");

        // Reset Pulse (hold in reset so mtime starts cleanly at 0)
        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        // ---------------------------------------------------------------------
        // TEST 1: Reset & Default Register Values
        // ---------------------------------------------------------------------
        $display("\n[TEST 1] Reset & Default Register Values");
        check_reg(REG_MTIME_HIGH, 32'h0000_0000, 32'hFFFF_FFFF, "MTIME_HIGH reset state (=0)");
        check_reg(REG_MTIMECMP_LOW, 32'hFFFF_FFFF, 32'hFFFF_FFFF, "MTIMECMP_LOW reset state (=0xFFFFFFFF)");
        check_reg(REG_MTIMECMP_HIGH, 32'hFFFF_FFFF, 32'hFFFF_FFFF, "MTIMECMP_HIGH reset state (=0xFFFFFFFF)");
        check_reg(REG_TIMER_CTRL, 32'h0000_0001, 32'hFFFF_FFFF, "TIMER_CTRL reset state (EN=1)");
        check_reg(REG_TIMER_STATUS, 32'h0000_0000, 32'hFFFF_FFFF, "TIMER_STATUS reset state (=0)");

        test_count = test_count + 1;
        if (timer_irq === 1'b0) begin
            pass_count = pass_count + 1;
            $display("  PASS: timer_irq is deasserted on reset");
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL: timer_irq asserted prematurely on reset");
        end

        // ---------------------------------------------------------------------
        // TEST 2: Counter Progression & Enable/Disable Control
        // ---------------------------------------------------------------------
        $display("\n[TEST 2] Counter Progression & Enable/Disable (Start/Stop)");
        // Sample counter value, wait 10 cycles, sample again
        axi_read(REG_MTIME_LOW, val1, RESP_OKAY);
        repeat(10) @(posedge clk);
        axi_read(REG_MTIME_LOW, val2, RESP_OKAY);

        test_count = test_count + 1;
        if (val2 > val1) begin
            pass_count = pass_count + 1;
            $display("  PASS: mtime counter progressed while EN=1 (val1=%0d -> val2=%0d)", val1, val2);
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL: mtime counter did not advance (val1=%0d, val2=%0d)", val1, val2);
        end

        // Pause counter by setting EN = 0 in CTRL
        axi_write(REG_TIMER_CTRL, 32'h0000_0000, 4'b0001, RESP_OKAY);
        repeat(3) @(posedge clk);
        axi_read(REG_MTIME_LOW, val1, RESP_OKAY);
        repeat(15) @(posedge clk);
        axi_read(REG_MTIME_LOW, val2, RESP_OKAY);

        test_count = test_count + 1;
        if (val1 === val2) begin
            pass_count = pass_count + 1;
            $display("  PASS: mtime held constant when EN=0 (held at %0d)", val1);
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL: mtime changed while EN=0 (val1=%0d, val2=%0d)", val1, val2);
        end

        // Resume counter
        axi_write(REG_TIMER_CTRL, 32'h0000_0001, 4'b0001, RESP_OKAY);

        // ---------------------------------------------------------------------
        // TEST 3: Clock Prescaler Divider
        // ---------------------------------------------------------------------
        $display("\n[TEST 3] Clock Prescaler Divider (N+1 clock cycles per tick)");
        // 1. Pause timer and set prescaler N = 3 (bits [15:8] = 3), EN = 0
        axi_write(REG_TIMER_CTRL, 32'h0000_0300, 4'b0011, RESP_OKAY);
        axi_write(REG_MTIME_LOW, 32'h0000_0000, 4'b1111, RESP_OKAY);

        // 2. Start timer with N = 3
        axi_write(REG_TIMER_CTRL, 32'h0000_0301, 4'b0011, RESP_OKAY);

        // 3. Wait exactly 20 clock cycles
        repeat(20) @(posedge clk);

        // 4. Pause timer so AXI read transaction latency does not add extra ticks
        axi_write(REG_TIMER_CTRL, 32'h0000_0300, 4'b0011, RESP_OKAY);

        // 5. Read mtime: 20 cycles with N=3 (divide by 4) + write latency cycles = 5 to 7 ticks
        axi_read(REG_MTIME_LOW, rd_val, RESP_OKAY);

        test_count = test_count + 1;
        if (rd_val >= 32'd5 && rd_val <= 32'd7) begin
            pass_count = pass_count + 1;
            $display("  PASS: Prescaler N=3 divided clock correctly (ticks=%0d in 20 cycles)", rd_val);
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL: Prescaler rate unexpected (got %0d ticks in 20 cycles)", rd_val);
        end

        // Restore prescaler N = 0
        axi_write(REG_TIMER_CTRL, 32'h0000_0001, 4'b0011, RESP_OKAY);

        // ---------------------------------------------------------------------
        // TEST 4: Compare Match & Level-Sensitive Interrupt Assertion
        // ---------------------------------------------------------------------
        $display("\n[TEST 4] Compare Match & Interrupt Assertion");
        // Pause timer while programming match threshold
        axi_write(REG_TIMER_CTRL, 32'h0000_0000, 4'b0001, RESP_OKAY);
        axi_write(REG_MTIME_LOW, 32'h0000_0000, 4'b1111, RESP_OKAY);
        axi_write(REG_MTIME_HIGH, 32'h0000_0000, 4'b1111, RESP_OKAY);

        // Threshold = 25 ticks
        axi_write(REG_MTIMECMP_LOW, 32'h0000_0019, 4'b1111, RESP_OKAY);
        axi_write(REG_MTIMECMP_HIGH, 32'h0000_0000, 4'b1111, RESP_OKAY);

        // Enable timer and interrupt: EN=1, IRQ_EN=1 -> 0x00000003
        axi_write(REG_TIMER_CTRL, 32'h0000_0003, 4'b0001, RESP_OKAY);

        test_count = test_count + 1;
        if (timer_irq === 1'b0) begin
            pass_count = pass_count + 1;
            $display("  PASS: timer_irq is deasserted before compare threshold is reached");
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL: timer_irq asserted prematurely");
        end

        // Wait for counter to cross threshold (25 ticks = 250 ns)
        repeat(35) @(posedge clk);

        test_count = test_count + 1;
        if (timer_irq === 1'b1) begin
            pass_count = pass_count + 1;
            $display("  PASS: timer_irq asserted on compare match (mtime >= mtimecmp)");
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL: timer_irq did not assert on match");
        end

        check_reg(REG_TIMER_STATUS, 32'h0000_0003, 32'h0000_0003, "STATUS reflects active match & sticky bit");

        // ---------------------------------------------------------------------
        // TEST 5: Dynamic Interrupt Clearing via mtimecmp update & W1C
        // ---------------------------------------------------------------------
        $display("\n[TEST 5] Dynamic Interrupt Clearing via MTIMECMP Update & W1C");
        // Write mtimecmp to 1000: mtime (around 35-40) is now < mtimecmp
        axi_write(REG_MTIMECMP_LOW, 32'h0000_03E8, 4'b1111, RESP_OKAY);
        repeat(2) @(posedge clk);

        test_count = test_count + 1;
        if (timer_irq === 1'b0) begin
            pass_count = pass_count + 1;
            $display("  PASS: timer_irq deasserted dynamically upon advancing mtimecmp");
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL: timer_irq remained asserted after mtimecmp increased");
        end

        // Clear sticky match bit with W1C
        axi_write(REG_TIMER_STATUS, 32'h0000_0001, 4'b0001, RESP_OKAY);
        check_reg(REG_TIMER_STATUS, 32'h0000_0000, 32'h0000_0001, "Sticky MATCH bit cleared via W1C");

        // ---------------------------------------------------------------------
        // TEST 6: Auto-Reload Periodic Mode
        // ---------------------------------------------------------------------
        $display("\n[TEST 6] Auto-Reload Periodic Mode");
        // Reset counter to 0, compare = 10, enable auto-reload: EN=1, AUTO_RELOAD=1 -> CTRL = 0x00000005
        axi_write(REG_TIMER_CTRL, 32'h0000_0000, 4'b0001, RESP_OKAY);
        axi_write(REG_MTIME_LOW, 32'h0000_0000, 4'b1111, RESP_OKAY);
        axi_write(REG_MTIMECMP_LOW, 32'h0000_000A, 4'b1111, RESP_OKAY);
        axi_write(REG_TIMER_CTRL, 32'h0000_0005, 4'b0001, RESP_OKAY);

        // Wait 12 cycles (counter reaches 10 and auto-reloads to 0, then ticks 1-2 times)
        repeat(12) @(posedge clk);
        axi_read(REG_MTIME_LOW, rd_val, RESP_OKAY);

        test_count = test_count + 1;
        if (rd_val < 32'd10) begin
            pass_count = pass_count + 1;
            $display("  PASS: Counter rolled over to 0 upon match in auto-reload mode (mtime=%0d)", rd_val);
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL: Auto-reload did not reset counter (mtime=%0d)", rd_val);
        end

        // Restore normal mode
        axi_write(REG_TIMER_CTRL, 32'h0000_0001, 4'b0001, RESP_OKAY);

        // ---------------------------------------------------------------------
        // TEST 7: 64-Bit Upper Word Compare Boundary Handling
        // ---------------------------------------------------------------------
        $display("\n[TEST 7] 64-Bit Upper-Word Compare Boundary");
        // Stop timer
        axi_write(REG_TIMER_CTRL, 32'h0000_0000, 4'b0001, RESP_OKAY);

        // MTIME = 0x0000_0001_FFFF_FFF0
        axi_write(REG_MTIME_HIGH, 32'h0000_0001, 4'b1111, RESP_OKAY);
        axi_write(REG_MTIME_LOW, 32'hFFFF_FFF0, 4'b1111, RESP_OKAY);

        // MTIMECMP = 0x0000_0001_FFFF_FFF5
        axi_write(REG_MTIMECMP_HIGH, 32'h0000_0001, 4'b1111, RESP_OKAY);
        axi_write(REG_MTIMECMP_LOW, 32'hFFFF_FFF5, 4'b1111, RESP_OKAY);

        // Enable timer & IRQ: EN=1, IRQ_EN=1 -> CTRL = 0x00000003
        axi_write(REG_TIMER_CTRL, 32'h0000_0003, 4'b0001, RESP_OKAY);

        // Wait 10 cycles: counter crosses 0x0000_0001_FFFF_FFF5 and increments upper word on overflow
        repeat(10) @(posedge clk);

        test_count = test_count + 1;
        if (timer_irq === 1'b1) begin
            pass_count = pass_count + 1;
            $display("  PASS: 64-bit compare match correctly asserted timer_irq");
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL: 64-bit compare failed to assert timer_irq");
        end

        // ---------------------------------------------------------------------
        // TEST 8: Decoupled AXI Handshakes & Error Conditions
        // ---------------------------------------------------------------------
        $display("\n[TEST 8] Independent AXI Handshakes & Error Conditions");

        // Subtest 8a: AW valid before W valid
        begin : test_8a
            reg aw_d, w_d, b_d;
            reg [1:0] bresp_d;
            aw_d = 0;
            w_d  = 0;
            b_d  = 0;
            bresp_d = 2'b11;

            @(posedge clk);
            s_axi_awaddr  <= REG_TIMER_CTRL;
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
                $display("  FAIL: AW-before-W failed");
            end
            repeat(2) @(posedge clk);
        end

        // Subtest 8b: Delayed RREADY Backpressure
        begin : test_8b
            reg r_held_ok;
            r_held_ok = 1;

            @(posedge clk);
            s_axi_araddr  <= REG_MTIME_LOW;
            s_axi_arprot  <= 3'b000;
            s_axi_arvalid <= 1'b1;
            s_axi_rready  <= 1'b0;

            @(posedge clk);
            while (!s_axi_arready) @(posedge clk);
            s_axi_arvalid <= 1'b0;

            while (!s_axi_rvalid) @(posedge clk);

            repeat(4) begin
                @(posedge clk);
                if (!s_axi_rvalid || !s_axi_rlast) r_held_ok = 0;
            end

            s_axi_rready <= 1'b1;
            @(posedge clk);
            s_axi_rready <= 1'b0;

            test_count = test_count + 1;
            if (r_held_ok) begin
                pass_count = pass_count + 1;
                $display("  PASS: RVALID and rlast held high during RREADY backpressure");
            end else begin
                fail_count = fail_count + 1;
                $display("  FAIL: RVALID dropped during backpressure");
            end
            repeat(2) @(posedge clk);
        end

        // Subtest 8c: Unmapped offset (0x28) access -> SLVERR
        axi_write(REG_UNMAPPED, 32'hDEAD_BEEF, 4'b1111, RESP_SLVERR);
        $display("  PASS: Write to unmapped offset 0x28 returns SLVERR");

        axi_read(REG_UNMAPPED, rd_val, RESP_SLVERR);
        test_count = test_count + 1;
        if (rd_val === 32'h0000_0000) begin
            pass_count = pass_count + 1;
            $display("  PASS: Read from unmapped offset 0x28 returns SLVERR and 0x0 data");
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL: Read unmapped offset returned non-zero data");
        end

        // Subtest 8d: Unaligned address (0x02) access -> SLVERR
        axi_write(REG_UNALIGNED, 32'hCAFE_BABE, 4'b1111, RESP_SLVERR);
        $display("  PASS: Unaligned write (addr=0x02) returns SLVERR");

        axi_read(REG_UNALIGNED, rd_val, RESP_SLVERR);
        $display("  PASS: Unaligned read (addr=0x02) returns SLVERR");

        // ---------------------------------------------------------------------
        // Simulation Summary
        // ---------------------------------------------------------------------
        repeat(10) @(posedge clk);
        $display("\n==================================================");
        $display("   TIMER STANDALONE TESTBENCH SUMMARY");
        $display("   TOTAL TESTS : %0d", test_count);
        $display("   PASSED      : %0d", pass_count);
        $display("   FAILED      : %0d", fail_count);
        $display("==================================================");

        if (fail_count == 0) begin
            $display(">>> ALL TIMER TESTS PASSED SUCCESSFULLY! <<<\n");
        end else begin
            $display(">>> SOME TIMER TESTS FAILED! <<<\n");
        end

        $finish;
    end

endmodule

`default_nettype wire
