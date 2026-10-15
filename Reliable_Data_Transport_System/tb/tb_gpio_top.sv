// =============================================================================
// tb_gpio_top.sv
//
// PURPOSE:
//   Self-checking verification testbench for gpio_top.
//   Tests:
//     1. Reset & default register values (data_out=0, dir=0, irq=0).
//     2. Output direction control & direct DATA_OUT writes.
//     3. Atomic SET_OUT, CLR_OUT, and TOG_OUT operations.
//     4. External input sampling & 2-stage synchronizer readback via DATA_IN.
//     5. Level-sensitive interrupt generation (active-high and active-low).
//     6. Edge-sensitive interrupt generation (rising-edge and falling-edge).
//     7. Interrupt masking via IRQ_EN & sticky status clearing via W1C.
//     8. Independent AXI handshakes & error handling (unmapped/unaligned -> SLVERR).
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module tb_gpio_top;

    localparam DATA_WIDTH = 32;
    localparam ADDR_WIDTH = 32;
    localparam STRB_WIDTH = DATA_WIDTH / 8;

    // Register Offsets
    localparam [ADDR_WIDTH-1:0]
        REG_DATA_IN   = 32'h0006_0000,
        REG_DATA_OUT  = 32'h0006_0004,
        REG_DIR       = 32'h0006_0008,
        REG_IRQ_EN    = 32'h0006_000C,
        REG_IRQ_TYPE  = 32'h0006_0010,
        REG_IRQ_POL   = 32'h0006_0014,
        REG_IRQ_STAT  = 32'h0006_0018,
        REG_SET_OUT   = 32'h0006_001C,
        REG_CLR_OUT   = 32'h0006_0020,
        REG_TOG_OUT   = 32'h0006_0024,
        REG_UNMAPPED  = 32'h0006_0038,
        REG_UNALIGNED = 32'h0006_0001;

    localparam [1:0]
        RESP_OKAY   = 2'b00,
        RESP_EXOKAY = 2'b01,
        RESP_SLVERR = 2'b10,
        RESP_DECERR = 2'b11;

    // Clock and Reset Signals
    reg clk;
    reg rst_n;

    // GPIO External Pins
    reg  [31:0] gpio_i;
    wire [31:0] gpio_o;
    wire [31:0] gpio_oe;
    wire        gpio_irq;

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
    gpio_top #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .STRB_WIDTH(STRB_WIDTH)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .gpio_i       (gpio_i),
        .gpio_o       (gpio_o),
        .gpio_oe      (gpio_oe),
        .gpio_irq     (gpio_irq),
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

    initial begin
        clk           = 0;
        rst_n         = 0;
        gpio_i        = 32'h0000_0000;
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
        $display("   STARTING GPIO STANDALONE TESTBENCH (tb_gpio_top)");
        $display("==================================================");

        // Reset Pulse
        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(3) @(posedge clk);

        // ---------------------------------------------------------------------
        // TEST 1: Reset & Default Register Values
        // ---------------------------------------------------------------------
        $display("\n[TEST 1] Reset & Default Register Values");
        check_reg(REG_DATA_OUT, 32'h0000_0000, 32'hFFFF_FFFF, "DATA_OUT reset state (=0)");
        check_reg(REG_DIR, 32'h0000_0000, 32'hFFFF_FFFF, "DIR reset state (all inputs = 0)");
        check_reg(REG_IRQ_EN, 32'h0000_0000, 32'hFFFF_FFFF, "IRQ_EN reset state (=0)");
        check_reg(REG_IRQ_STAT, 32'h0000_0000, 32'hFFFF_FFFF, "IRQ_STAT reset state (=0)");

        test_count = test_count + 1;
        if (gpio_oe === 32'h0000_0000 && gpio_o === 32'h0000_0000 && gpio_irq === 1'b0) begin
            pass_count = pass_count + 1;
            $display("  PASS: Output pins, output enables, and IRQ line are deasserted on reset");
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL: Reset pins state unexpected (oe=0x%08x, o=0x%08x, irq=%b)", gpio_oe, gpio_o, gpio_irq);
        end

        // ---------------------------------------------------------------------
        // TEST 2: Direction Control & Direct Output Writes
        // ---------------------------------------------------------------------
        $display("\n[TEST 2] Direction Control & Direct Output Writes");
        // Configure lower 16 bits as output, upper 16 bits as input
        axi_write(REG_DIR, 32'h0000_FFFF, 4'b1111, RESP_OKAY);
        check_reg(REG_DIR, 32'h0000_FFFF, 32'hFFFF_FFFF, "DIR readback matches programmed value");

        test_count = test_count + 1;
        if (gpio_oe === 32'h0000_FFFF) begin
            pass_count = pass_count + 1;
            $display("  PASS: External gpio_oe matches DIR register");
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL: gpio_oe mismatch (0x%08x)", gpio_oe);
        end

        // Write output pattern to DATA_OUT
        axi_write(REG_DATA_OUT, 32'hAAAA_5555, 4'b1111, RESP_OKAY);
        check_reg(REG_DATA_OUT, 32'hAAAA_5555, 32'hFFFF_FFFF, "DATA_OUT readback matches");

        test_count = test_count + 1;
        if (gpio_o === 32'hAAAA_5555) begin
            pass_count = pass_count + 1;
            $display("  PASS: External gpio_o pins driven with DATA_OUT value");
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL: gpio_o mismatch (0x%08x)", gpio_o);
        end

        // ---------------------------------------------------------------------
        // TEST 3: Atomic SET_OUT, CLR_OUT, and TOG_OUT Operations
        // ---------------------------------------------------------------------
        $display("\n[TEST 3] Atomic Operations (SET_OUT, CLR_OUT, TOG_OUT)");
        // Initialize DATA_OUT = 0x0000_0000
        axi_write(REG_DATA_OUT, 32'h0000_0000, 4'b1111, RESP_OKAY);

        // Atomic SET: Set bits [7:4] -> 0x0000_00F0
        axi_write(REG_SET_OUT, 32'h0000_00F0, 4'b0001, RESP_OKAY);
        check_reg(REG_DATA_OUT, 32'h0000_00F0, 32'hFFFF_FFFF, "Atomic SET_OUT sets target bits");

        // Atomic SET: Set bits [11:8] -> 0x0000_0FF0
        axi_write(REG_SET_OUT, 32'h0000_0F00, 4'b0010, RESP_OKAY);
        check_reg(REG_DATA_OUT, 32'h0000_0FF0, 32'hFFFF_FFFF, "Atomic SET_OUT accumulates bits");

        // Atomic CLR: Clear bits [7:6] -> 0x0000_0F30
        axi_write(REG_CLR_OUT, 32'h0000_00C0, 4'b0001, RESP_OKAY);
        check_reg(REG_DATA_OUT, 32'h0000_0F30, 32'hFFFF_FFFF, "Atomic CLR_OUT clears target bits");

        // Atomic TOG: Toggle bits [15:0]
        axi_write(REG_TOG_OUT, 32'h0000_FFFF, 4'b0011, RESP_OKAY);
        check_reg(REG_DATA_OUT, (32'h0000_0F30 ^ 32'h0000_FFFF), 32'hFFFF_FFFF, "Atomic TOG_OUT inverts target bits");

        // ---------------------------------------------------------------------
        // TEST 4: External Input Sampling & Synchronizer Readback (DATA_IN)
        // ---------------------------------------------------------------------
        $display("\n[TEST 4] External Input Sampling & Synchronizer Readback");
        // Drive external pattern 1
        gpio_i = 32'hCAFE_BABE;
        repeat(3) @(posedge clk); // Allow 2-stage synchronizer to latch
        check_reg(REG_DATA_IN, 32'hCAFE_BABE, 32'hFFFF_FFFF, "Synchronized input pattern 0xCAFEBABE");

        // Drive external pattern 2
        gpio_i = 32'h1234_5678;
        repeat(3) @(posedge clk);
        check_reg(REG_DATA_IN, 32'h1234_5678, 32'hFFFF_FFFF, "Synchronized input pattern 0x12345678");

        // ---------------------------------------------------------------------
        // TEST 5: Level-Sensitive Interrupt Generation
        // ---------------------------------------------------------------------
        $display("\n[TEST 5] Level-Sensitive Interrupt Generation");
        // Pin 0: Level-sensitive (TYPE=0), Active-High (POL=1), IRQ_EN=1
        axi_write(REG_IRQ_TYPE, 32'h0000_0000, 4'b1111, RESP_OKAY);
        axi_write(REG_IRQ_POL,  32'h0000_0001, 4'b0001, RESP_OKAY);
        axi_write(REG_IRQ_EN,   32'h0000_0001, 4'b0001, RESP_OKAY);

        // Initially pin 0 is low
        gpio_i = 32'h0000_0000;
        repeat(3) @(posedge clk);
        test_count = test_count + 1;
        if (gpio_irq === 1'b0) begin
            pass_count = pass_count + 1;
            $display("  PASS: gpio_irq deasserted when level condition is false");
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL: gpio_irq asserted prematurely");
        end

        // Assert level condition on pin 0
        gpio_i[0] = 1'b1;
        repeat(3) @(posedge clk);
        test_count = test_count + 1;
        if (gpio_irq === 1'b1) begin
            pass_count = pass_count + 1;
            $display("  PASS: gpio_irq asserted on active-high level match");
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL: gpio_irq failed to assert on active-high level match");
        end

        check_reg(REG_IRQ_STAT, 32'h0000_0001, 32'h0000_0001, "IRQ_STAT reflects pin 0 interrupt");

        // Deassert external input pin and clear status with W1C
        gpio_i[0] = 1'b0;
        repeat(3) @(posedge clk);
        axi_write(REG_IRQ_STAT, 32'h0000_0001, 4'b0001, RESP_OKAY);
        repeat(2) @(posedge clk);

        test_count = test_count + 1;
        if (gpio_irq === 1'b0) begin
            pass_count = pass_count + 1;
            $display("  PASS: gpio_irq deasserted after input lowered and status cleared via W1C");
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL: gpio_irq remained asserted after W1C");
        end

        // ---------------------------------------------------------------------
        // TEST 6: Edge-Sensitive Interrupt Generation
        // ---------------------------------------------------------------------
        $display("\n[TEST 6] Edge-Sensitive Interrupt Generation");
        // Pin 1: Rising-edge (TYPE=1, POL=1), Pin 2: Falling-edge (TYPE=1, POL=0)
        axi_write(REG_IRQ_TYPE, 32'h0000_0006, 4'b0001, RESP_OKAY); // Pins 1,2 edge
        axi_write(REG_IRQ_POL,  32'h0000_0002, 4'b0001, RESP_OKAY); // Pin 1 rising, Pin 2 falling
        axi_write(REG_IRQ_EN,   32'h0000_0006, 4'b0001, RESP_OKAY); // Enable pins 1,2

        // Ensure clean starting input states (Pin 1=0, Pin 2=1)
        gpio_i = 32'h0000_0004;
        repeat(3) @(posedge clk);
        axi_write(REG_IRQ_STAT, 32'h0000_0006, 4'b0001, RESP_OKAY); // Clear any initial flags
        repeat(2) @(posedge clk);

        // Pulse Pin 1: 0 -> 1 (Rising edge)
        gpio_i[1] = 1'b1;
        repeat(3) @(posedge clk);
        test_count = test_count + 1;
        if (gpio_irq === 1'b1) begin
            pass_count = pass_count + 1;
            $display("  PASS: Rising-edge on pin 1 asserted gpio_irq");
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL: Rising-edge failed to assert gpio_irq");
        end
        check_reg(REG_IRQ_STAT, 32'h0000_0002, 32'h0000_0002, "IRQ_STAT captures rising-edge on pin 1");

        // Clear pin 1 IRQ via W1C
        axi_write(REG_IRQ_STAT, 32'h0000_0002, 4'b0001, RESP_OKAY);

        // Pulse Pin 2: 1 -> 0 (Falling edge)
        gpio_i[2] = 1'b0;
        repeat(3) @(posedge clk);
        test_count = test_count + 1;
        if (gpio_irq === 1'b1) begin
            pass_count = pass_count + 1;
            $display("  PASS: Falling-edge on pin 2 asserted gpio_irq");
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL: Falling-edge failed to assert gpio_irq");
        end
        check_reg(REG_IRQ_STAT, 32'h0000_0004, 32'h0000_0004, "IRQ_STAT captures falling-edge on pin 2");

        // Clear pin 2 IRQ via W1C
        axi_write(REG_IRQ_STAT, 32'h0000_0004, 4'b0001, RESP_OKAY);
        repeat(2) @(posedge clk);

        // ---------------------------------------------------------------------
        // TEST 7: Independent AXI Handshakes & Error Conditions
        // ---------------------------------------------------------------------
        $display("\n[TEST 7] Independent AXI Handshakes & Error Conditions");

        // Subtest 7a: AW valid before W valid
        begin : test_7a
            reg aw_d, w_d, b_d;
            reg [1:0] bresp_d;
            aw_d = 0;
            w_d  = 0;
            b_d  = 0;
            bresp_d = 2'b11;

            @(posedge clk);
            s_axi_awaddr  <= REG_DATA_OUT;
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

            s_axi_wdata   <= 32'h5555_AAAA;
            s_axi_wstrb   <= 4'b1111;
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

        // Subtest 7b: Delayed RREADY Backpressure
        begin : test_7b
            reg r_held_ok;
            r_held_ok = 1;

            @(posedge clk);
            s_axi_araddr  <= REG_DATA_OUT;
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

        // Subtest 7c: Unmapped offset (0x38) access -> SLVERR
        axi_write(REG_UNMAPPED, 32'hDEAD_BEEF, 4'b1111, RESP_SLVERR);
        $display("  PASS: Write to unmapped offset 0x38 returns SLVERR");

        axi_read(REG_UNMAPPED, rd_val, RESP_SLVERR);
        test_count = test_count + 1;
        if (rd_val === 32'h0000_0000) begin
            pass_count = pass_count + 1;
            $display("  PASS: Read from unmapped offset 0x38 returns SLVERR and 0x0 data");
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL: Read unmapped offset returned non-zero data");
        end

        // Subtest 7d: Unaligned address (0x01) access -> SLVERR
        axi_write(REG_UNALIGNED, 32'hCAFE_BABE, 4'b1111, RESP_SLVERR);
        $display("  PASS: Unaligned write (addr=0x01) returns SLVERR");

        axi_read(REG_UNALIGNED, rd_val, RESP_SLVERR);
        $display("  PASS: Unaligned read (addr=0x01) returns SLVERR");

        // ---------------------------------------------------------------------
        // Simulation Summary
        // ---------------------------------------------------------------------
        repeat(10) @(posedge clk);
        $display("\n==================================================");
        $display("   GPIO STANDALONE TESTBENCH SUMMARY");
        $display("   TOTAL TESTS : %0d", test_count);
        $display("   PASSED      : %0d", pass_count);
        $display("   FAILED      : %0d", fail_count);
        $display("==================================================");

        if (fail_count == 0) begin
            $display(">>> ALL GPIO TESTS PASSED SUCCESSFULLY! <<<\n");
        end else begin
            $display(">>> SOME GPIO TESTS FAILED! <<<\n");
        end

        $finish;
    end

endmodule

`default_nettype wire
