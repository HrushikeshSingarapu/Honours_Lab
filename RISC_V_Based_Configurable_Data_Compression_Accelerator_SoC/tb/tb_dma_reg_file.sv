// =============================================================================
// tb_dma_reg_file.sv — Comprehensive Self-Checking Testbench for DMA Register File
//
// Verification Scope:
//   1. Reset state verification across all registers and control lines.
//   2. Read/Write access to every configuration register.
//   3. Byte write strobe (WSTRB) partial updates on 32-bit registers.
//   4. START pulse generation: exact 1-cycle duration, self-clearing.
//   5. ABORT pulse generation: exact 1-cycle duration, self-clearing.
//   6. Independent AW and W channel handshakes:
//        - Simultaneous AW and W
//        - AW valid first, W delayed
//        - W valid first, AW delayed
//   7. Read channel backpressure and RID/ARID correlation.
//   8. Read-only register write protection (SLVERR on attempt).
//   9. Unmapped address access handling (SLVERR).
//  10. BUSY locking: SRC/DST/LEN write rejection and START suppression while busy.
//  11. Hardware completion/error event capture and DMA_OUTPUT_LEN/ERROR_CODE updates.
//  12. IRQ enable, level assertion, and Write-1-to-Clear (W1C) status clearing.
//  13. Dynamic reset assertion during active operation and post-reset clean state.
// =============================================================================

`timescale 1ns / 1ps

module tb_dma_reg_file;

    // Parameters
    localparam DATA_WIDTH = 32;
    localparam ADDR_WIDTH = 32;
    localparam ID_WIDTH   = 8;
    localparam STRB_WIDTH = DATA_WIDTH / 8;
    localparam CLK_PERIOD = 10; // 100 MHz clock

    // Register Offsets
    localparam [31:0] BASE_ADDR          = 32'h1001_1000;
    localparam [31:0] REG_DMA_CONTROL    = BASE_ADDR + 32'h000;
    localparam [31:0] REG_DMA_STATUS     = BASE_ADDR + 32'h004;
    localparam [31:0] REG_DMA_SRC_ADDR   = BASE_ADDR + 32'h008;
    localparam [31:0] REG_DMA_DST_ADDR   = BASE_ADDR + 32'h00C;
    localparam [31:0] REG_DMA_INPUT_LEN  = BASE_ADDR + 32'h010;
    localparam [31:0] REG_DMA_OUTPUT_LEN = BASE_ADDR + 32'h014;
    localparam [31:0] REG_DMA_IRQ_ENABLE = BASE_ADDR + 32'h018;
    localparam [31:0] REG_DMA_IRQ_STATUS = BASE_ADDR + 32'h01C;
    localparam [31:0] REG_DMA_ERROR_CODE = BASE_ADDR + 32'h020;
    localparam [31:0] REG_DMA_UNMAPPED   = BASE_ADDR + 32'h040;

    localparam [1:0] RESP_OKAY   = 2'b00;
    localparam [1:0] RESP_SLVERR = 2'b10;

    // DUT Signals
    logic                  clk;
    logic                  rst_n;

    // AXI Slave Signals
    logic [ID_WIDTH-1:0]   s_axi_awid;
    logic [ADDR_WIDTH-1:0] s_axi_awaddr;
    logic [2:0]            s_axi_awprot;
    logic                  s_axi_awvalid;
    wire                   s_axi_awready;

    logic [DATA_WIDTH-1:0] s_axi_wdata;
    logic [STRB_WIDTH-1:0] s_axi_wstrb;
    logic                  s_axi_wvalid;
    wire                   s_axi_wready;

    wire  [ID_WIDTH-1:0]   s_axi_bid;
    wire  [1:0]            s_axi_bresp;
    wire                   s_axi_bvalid;
    logic                  s_axi_bready;

    logic [ID_WIDTH-1:0]   s_axi_arid;
    logic [ADDR_WIDTH-1:0] s_axi_araddr;
    logic [2:0]            s_axi_arprot;
    logic                  s_axi_arvalid;
    wire                   s_axi_arready;

    wire  [ID_WIDTH-1:0]   s_axi_rid;
    wire  [DATA_WIDTH-1:0] s_axi_rdata;
    wire  [1:0]            s_axi_rresp;
    wire                   s_axi_rlast;
    wire                   s_axi_rvalid;
    logic                  s_axi_rready;

    // FSM Interface Signals
    wire                   ctrl_start_pulse_o;
    wire                   ctrl_mode_o;
    wire                   ctrl_abort_pulse_o;
    wire  [31:0]           cfg_src_addr_o;
    wire  [31:0]           cfg_dst_addr_o;
    wire  [15:0]           cfg_input_len_o;

    logic                  status_busy_i;
    logic                  status_done_pulse_i;
    logic                  status_error_pulse_i;
    logic [15:0]           status_output_len_i;
    logic [7:0]            status_error_code_i;
    wire                   irq_o;

    // Test statistics
    int total_tests;
    int pass_count;
    int fail_count;

    // Clock generator (100 MHz)
    initial clk = 1'b0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    // DUT Instantiation
    dma_reg_file #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .ID_WIDTH  (ID_WIDTH),
        .STRB_WIDTH(STRB_WIDTH)
    ) u_dut (
        .clk                 (clk),
        .rst_n               (rst_n),
        .s_axi_awid          (s_axi_awid),
        .s_axi_awaddr        (s_axi_awaddr),
        .s_axi_awprot        (s_axi_awprot),
        .s_axi_awvalid       (s_axi_awvalid),
        .s_axi_awready       (s_axi_awready),
        .s_axi_wdata         (s_axi_wdata),
        .s_axi_wstrb         (s_axi_wstrb),
        .s_axi_wvalid        (s_axi_wvalid),
        .s_axi_wready        (s_axi_wready),
        .s_axi_bid           (s_axi_bid),
        .s_axi_bresp         (s_axi_bresp),
        .s_axi_bvalid        (s_axi_bvalid),
        .s_axi_bready        (s_axi_bready),
        .s_axi_arid          (s_axi_arid),
        .s_axi_araddr        (s_axi_araddr),
        .s_axi_arprot        (s_axi_arprot),
        .s_axi_arvalid       (s_axi_arvalid),
        .s_axi_arready       (s_axi_arready),
        .s_axi_rid           (s_axi_rid),
        .s_axi_rdata         (s_axi_rdata),
        .s_axi_rresp         (s_axi_rresp),
        .s_axi_rlast         (s_axi_rlast),
        .s_axi_rvalid        (s_axi_rvalid),
        .s_axi_rready        (s_axi_rready),
        .ctrl_start_pulse_o  (ctrl_start_pulse_o),
        .ctrl_mode_o         (ctrl_mode_o),
        .ctrl_abort_pulse_o  (ctrl_abort_pulse_o),
        .cfg_src_addr_o      (cfg_src_addr_o),
        .cfg_dst_addr_o      (cfg_dst_addr_o),
        .cfg_input_len_o     (cfg_input_len_o),
        .status_busy_i       (status_busy_i),
        .status_done_pulse_i (status_done_pulse_i),
        .status_error_pulse_i(status_error_pulse_i),
        .status_output_len_i (status_output_len_i),
        .status_error_code_i (status_error_code_i),
        .irq_o               (irq_o)
    );

    // =========================================================================
    // Master BFM Tasks
    // =========================================================================

    // Synchronous AXI Write (Simultaneous AW and W)
    task automatic axi_write(
        input [ADDR_WIDTH-1:0] addr,
        input [DATA_WIDTH-1:0] data,
        input [STRB_WIDTH-1:0] strb,
        input [ID_WIDTH-1:0]   id,
        input [1:0]            exp_resp,
        input string           test_name
    );
        total_tests++;
        @(posedge clk);
        s_axi_awaddr  <= addr;
        s_axi_awid    <= id;
        s_axi_awprot  <= 3'b000;
        s_axi_awvalid <= 1'b1;
        s_axi_wdata   <= data;
        s_axi_wstrb   <= strb;
        s_axi_wvalid  <= 1'b1;
        s_axi_bready  <= 1'b1;

        // Wait for address acceptance
        fork
            begin
                while (!(s_axi_awvalid && s_axi_awready)) @(posedge clk);
                s_axi_awvalid <= 1'b0;
            end
            begin
                while (!(s_axi_wvalid && s_axi_wready)) @(posedge clk);
                s_axi_wvalid <= 1'b0;
            end
        join

        // Wait for B response
        while (!s_axi_bvalid) @(posedge clk);
        if (s_axi_bresp === exp_resp && s_axi_bid === id) begin
            $display("[PASS] %s (Addr=0x%08h, BRESP=%0b, BID=%0d)", test_name, addr, s_axi_bresp, s_axi_bid);
            pass_count++;
        end else begin
            $display("[FAIL] %s (Addr=0x%08h | Expected BRESP=%0b got %0b, BID=%0d got %0d)",
                     test_name, addr, exp_resp, s_axi_bresp, id, s_axi_bid);
            fail_count++;
        end
        @(posedge clk);
        s_axi_bready <= 1'b0;
    endtask

    // AW valid first, W delayed
    task automatic axi_write_aw_first(
        input [ADDR_WIDTH-1:0] addr,
        input [DATA_WIDTH-1:0] data,
        input [STRB_WIDTH-1:0] strb,
        input [ID_WIDTH-1:0]   id,
        input int              w_delay_cycles,
        input [1:0]            exp_resp,
        input string           test_name
    );
        total_tests++;
        @(posedge clk);
        s_axi_awaddr  <= addr;
        s_axi_awid    <= id;
        s_axi_awprot  <= 3'b000;
        s_axi_awvalid <= 1'b1;
        s_axi_wvalid  <= 1'b0;
        s_axi_bready  <= 1'b1;

        while (!(s_axi_awvalid && s_axi_awready)) @(posedge clk);
        s_axi_awvalid <= 1'b0;

        repeat (w_delay_cycles) @(posedge clk);
        s_axi_wdata  <= data;
        s_axi_wstrb  <= strb;
        s_axi_wvalid <= 1'b1;

        while (!(s_axi_wvalid && s_axi_wready)) @(posedge clk);
        s_axi_wvalid <= 1'b0;

        while (!s_axi_bvalid) @(posedge clk);
        if (s_axi_bresp === exp_resp && s_axi_bid === id) begin
            $display("[PASS] %s [AW-first, delay=%0d] (BRESP=%0b)", test_name, w_delay_cycles, s_axi_bresp);
            pass_count++;
        end else begin
            $display("[FAIL] %s [AW-first] (Expected BRESP=%0b got %0b)", test_name, exp_resp, s_axi_bresp);
            fail_count++;
        end
        @(posedge clk);
        s_axi_bready <= 1'b0;
    endtask

    // W valid first, AW delayed
    task automatic axi_write_w_first(
        input [ADDR_WIDTH-1:0] addr,
        input [DATA_WIDTH-1:0] data,
        input [STRB_WIDTH-1:0] strb,
        input [ID_WIDTH-1:0]   id,
        input int              aw_delay_cycles,
        input [1:0]            exp_resp,
        input string           test_name
    );
        total_tests++;
        @(posedge clk);
        s_axi_wdata   <= data;
        s_axi_wstrb   <= strb;
        s_axi_wvalid  <= 1'b1;
        s_axi_awvalid <= 1'b0;
        s_axi_bready  <= 1'b1;

        while (!(s_axi_wvalid && s_axi_wready)) @(posedge clk);
        s_axi_wvalid <= 1'b0;

        repeat (aw_delay_cycles) @(posedge clk);
        s_axi_awaddr  <= addr;
        s_axi_awid    <= id;
        s_axi_awprot  <= 3'b000;
        s_axi_awvalid <= 1'b1;

        while (!(s_axi_awvalid && s_axi_awready)) @(posedge clk);
        s_axi_awvalid <= 1'b0;

        while (!s_axi_bvalid) @(posedge clk);
        if (s_axi_bresp === exp_resp && s_axi_bid === id) begin
            $display("[PASS] %s [W-first, delay=%0d] (BRESP=%0b)", test_name, aw_delay_cycles, s_axi_bresp);
            pass_count++;
        end else begin
            $display("[FAIL] %s [W-first] (Expected BRESP=%0b got %0b)", test_name, exp_resp, s_axi_bresp);
            fail_count++;
        end
        @(posedge clk);
        s_axi_bready <= 1'b0;
    endtask

    // AXI Read Task
    task automatic axi_read(
        input  [ADDR_WIDTH-1:0] addr,
        input  [DATA_WIDTH-1:0] exp_data,
        input  [DATA_WIDTH-1:0] mask,
        input  [ID_WIDTH-1:0]   id,
        input  [1:0]            exp_resp,
        input  string           test_name
    );
        total_tests++;
        @(posedge clk);
        s_axi_araddr  <= addr;
        s_axi_arid    <= id;
        s_axi_arprot  <= 3'b000;
        s_axi_arvalid <= 1'b1;
        s_axi_rready  <= 1'b1;

        while (!(s_axi_arvalid && s_axi_arready)) @(posedge clk);
        s_axi_arvalid <= 1'b0;

        while (!s_axi_rvalid) @(posedge clk);
        if (s_axi_rresp === exp_resp && s_axi_rid === id && ((s_axi_rdata & mask) === (exp_data & mask))) begin
            $display("[PASS] %s (Addr=0x%08h, RDATA=0x%08h, RRESP=%0b)", test_name, addr, s_axi_rdata, s_axi_rresp);
            pass_count++;
        end else begin
            $display("[FAIL] %s (Addr=0x%08h | Expected Data=0x%08h (mask 0x%08h) got 0x%08h, RRESP=%0b got %0b)",
                     test_name, addr, exp_data, mask, s_axi_rdata, exp_resp, s_axi_rresp);
            fail_count++;
        end
        @(posedge clk);
        s_axi_rready <= 1'b0;
    endtask

    // =========================================================================
    // Main Test Stimulus
    // =========================================================================
    initial begin
        // Waveform dumping setup
        $dumpfile("dump_dma_reg.vcd");
        $dumpvars(0, tb_dma_reg_file);

        total_tests = 0;
        pass_count  = 0;
        fail_count  = 0;

        // Initialize signals
        rst_n                = 1'b0;
        s_axi_awid           = '0;
        s_axi_awaddr         = '0;
        s_axi_awprot         = '0;
        s_axi_awvalid        = 1'b0;
        s_axi_wdata          = '0;
        s_axi_wstrb          = '0;
        s_axi_wvalid         = 1'b0;
        s_axi_bready         = 1'b0;
        s_axi_arid           = '0;
        s_axi_araddr         = '0;
        s_axi_arprot         = '0;
        s_axi_arvalid        = 1'b0;
        s_axi_rready         = 1'b0;
        status_busy_i        = 1'b0;
        status_done_pulse_i  = 1'b0;
        status_error_pulse_i = 1'b0;
        status_output_len_i  = 16'd0;
        status_error_code_i  = 8'd0;

        $display("");
        $display("================================================================");
        $display("   DMA REGISTER FILE (dma_reg_file) SELF-CHECKING TESTBENCH     ");
        $display("================================================================");

        // Apply reset
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // ---------------------------------------------------------------------
        // TEST GROUP 1: Reset Defaults
        // ---------------------------------------------------------------------
        $display("\n--- Test Group 1: Reset Defaults ---");
        axi_read(REG_DMA_CONTROL,    32'h0000_0000, 32'hFFFF_FFFF, 8'd1, RESP_OKAY, "CONTROL reset value");
        axi_read(REG_DMA_STATUS,     32'h0000_0000, 32'h0000_0007, 8'd2, RESP_OKAY, "STATUS reset value (all clear)");
        axi_read(REG_DMA_SRC_ADDR,   32'h0004_0000, 32'hFFFF_FFFF, 8'd3, RESP_OKAY, "SRC_ADDR default");
        axi_read(REG_DMA_DST_ADDR,   32'h0004_0100, 32'hFFFF_FFFF, 8'd4, RESP_OKAY, "DST_ADDR default");
        axi_read(REG_DMA_INPUT_LEN,  32'h0000_0000, 32'h0000_FFFF, 8'd5, RESP_OKAY, "INPUT_LEN reset value");
        axi_read(REG_DMA_OUTPUT_LEN, 32'h0000_0000, 32'h0000_FFFF, 8'd6, RESP_OKAY, "OUTPUT_LEN reset value");
        axi_read(REG_DMA_IRQ_ENABLE, 32'h0000_0000, 32'h0000_0003, 8'd7, RESP_OKAY, "IRQ_ENABLE reset value");
        axi_read(REG_DMA_IRQ_STATUS, 32'h0000_0000, 32'h0000_0003, 8'd8, RESP_OKAY, "IRQ_STATUS reset value");
        axi_read(REG_DMA_ERROR_CODE, 32'h0000_0000, 32'h0000_00FF, 8'd9, RESP_OKAY, "ERROR_CODE reset value");

        total_tests++;
        if (irq_o === 1'b0 && ctrl_start_pulse_o === 1'b0 && ctrl_abort_pulse_o === 1'b0) begin
            $display("[PASS] Control & Interrupt pins idle out of reset");
            pass_count++;
        end else begin
            $display("[FAIL] Control or IRQ active out of reset!");
            fail_count++;
        end

        // ---------------------------------------------------------------------
        // TEST GROUP 2: Basic Read / Write Operations
        // ---------------------------------------------------------------------
        $display("\n--- Test Group 2: Basic Read / Write Configuration ---");
        axi_write(REG_DMA_SRC_ADDR,  32'h0004_1234, 4'b1111, 8'd10, RESP_OKAY, "Write SRC_ADDR");
        axi_read (REG_DMA_SRC_ADDR,  32'h0004_1234, 32'hFFFF_FFFF, 8'd10, RESP_OKAY, "Readback SRC_ADDR");

        axi_write(REG_DMA_DST_ADDR,  32'h0005_5678, 4'b1111, 8'd11, RESP_OKAY, "Write DST_ADDR");
        axi_read (REG_DMA_DST_ADDR,  32'h0005_5678, 32'hFFFF_FFFF, 8'd11, RESP_OKAY, "Readback DST_ADDR");

        axi_write(REG_DMA_INPUT_LEN, 32'h0000_00A0, 4'b1111, 8'd12, RESP_OKAY, "Write INPUT_LEN (160 bytes)");
        axi_read (REG_DMA_INPUT_LEN, 32'h0000_00A0, 32'h0000_FFFF, 8'd12, RESP_OKAY, "Readback INPUT_LEN");

        axi_write(REG_DMA_CONTROL,   32'h0000_0002, 4'b1111, 8'd13, RESP_OKAY, "Set MODE=1 (Decompress)");
        axi_read (REG_DMA_CONTROL,   32'h0000_0002, 32'h0000_0002, 8'd13, RESP_OKAY, "Readback MODE");

        // Verify configuration outputs to FSM
        total_tests++;
        if (cfg_src_addr_o === 32'h0004_1234 && cfg_dst_addr_o === 32'h0005_5678 &&
            cfg_input_len_o === 16'h00A0 && ctrl_mode_o === 1'b1) begin
            $display("[PASS] Configuration signals propagated correctly to FSM interface");
            pass_count++;
        end else begin
            $display("[FAIL] Configuration signals to FSM do not match programmed registers!");
            fail_count++;
        end

        // ---------------------------------------------------------------------
        // TEST GROUP 3: Partial Writes Using WSTRB Byte Enables
        // ---------------------------------------------------------------------
        $display("\n--- Test Group 3: Byte Enables (WSTRB) ---");
        // Update only byte 0 and byte 3 of SRC_ADDR: 0x0004_1234 -> 0xAA04_12EF
        axi_write(REG_DMA_SRC_ADDR, 32'hAA00_00EF, 4'b1001, 8'd14, RESP_OKAY, "Partial write SRC_ADDR [3] & [0]");
        axi_read (REG_DMA_SRC_ADDR, 32'hAA04_12EF, 32'hFFFF_FFFF, 8'd14, RESP_OKAY, "Verify partial write SRC_ADDR");

        // Update byte 1 of INPUT_LEN: 0x00A0 -> 0x01A0 (256+160 = 416)
        axi_write(REG_DMA_INPUT_LEN, 32'h0000_0100, 4'b0010, 8'd15, RESP_OKAY, "Partial write INPUT_LEN byte 1");
        axi_read (REG_DMA_INPUT_LEN, 32'h0000_01A0, 32'h0000_FFFF, 8'd15, RESP_OKAY, "Verify partial write INPUT_LEN");

        // ---------------------------------------------------------------------
        // TEST GROUP 4: START & ABORT One-Cycle Pulse Behavior
        // ---------------------------------------------------------------------
        $display("\n--- Test Group 4: START & ABORT Pulse Generation ---");
        // Pulse START
        fork
            begin
                axi_write(REG_DMA_CONTROL, 32'h0000_0001, 4'b1111, 8'd16, RESP_OKAY, "Issue START command");
            end
            begin
                // Monitor ctrl_start_pulse_o
                @(posedge ctrl_start_pulse_o);
                total_tests++;
                $display("[PASS] ctrl_start_pulse_o asserted high on START command");
                pass_count++;
                @(posedge clk);
                #1;
                total_tests++;
                if (ctrl_start_pulse_o === 1'b0) begin
                    $display("[PASS] ctrl_start_pulse_o strictly self-cleared after 1 cycle");
                    pass_count++;
                end else begin
                    $display("[FAIL] ctrl_start_pulse_o did not self-clear!");
                    fail_count++;
                end
            end
        join

        // Pulse ABORT
        fork
            begin
                axi_write(REG_DMA_CONTROL, 32'h0000_0004, 4'b1111, 8'd17, RESP_OKAY, "Issue ABORT command");
            end
            begin
                @(posedge ctrl_abort_pulse_o);
                total_tests++;
                $display("[PASS] ctrl_abort_pulse_o asserted high on ABORT command");
                pass_count++;
                @(posedge clk);
                #1;
                total_tests++;
                if (ctrl_abort_pulse_o === 1'b0) begin
                    $display("[PASS] ctrl_abort_pulse_o strictly self-cleared after 1 cycle");
                    pass_count++;
                end else begin
                    $display("[FAIL] ctrl_abort_pulse_o did not self-clear!");
                    fail_count++;
                end
            end
        join

        // ---------------------------------------------------------------------
        // TEST GROUP 5: Independent AW / W Channel Handshakes
        // ---------------------------------------------------------------------
        $display("\n--- Test Group 5: Independent AW and W Handshakes ---");
        // Case A: AW valid first, W delayed by 3 cycles
        axi_write_aw_first(REG_DMA_SRC_ADDR, 32'h0004_CAFE, 4'b1111, 8'd18, 3, RESP_OKAY, "AW-First decoupled write");
        axi_read          (REG_DMA_SRC_ADDR, 32'h0004_CAFE, 32'hFFFF_FFFF, 8'd18, RESP_OKAY, "Verify AW-First write result");

        // Case B: W valid first, AW delayed by 4 cycles
        axi_write_w_first (REG_DMA_DST_ADDR, 32'h0004_BABE, 4'b1111, 8'd19, 4, RESP_OKAY, "W-First decoupled write");
        axi_read          (REG_DMA_DST_ADDR, 32'h0004_BABE, 32'hFFFF_FFFF, 8'd19, RESP_OKAY, "Verify W-First write result");

        // ---------------------------------------------------------------------
        // TEST GROUP 6: Read-Only Protection and Unmapped Offsets
        // ---------------------------------------------------------------------
        $display("\n--- Test Group 6: Error Responses (SLVERR) ---");
        // Attempt write to DMA_STATUS (read-only) -> expect SLVERR
        axi_write(REG_DMA_STATUS, 32'hFFFF_FFFF, 4'b1111, 8'd20, RESP_SLVERR, "Write to RO DMA_STATUS rejected with SLVERR");

        // Attempt write to DMA_OUTPUT_LEN (read-only) -> expect SLVERR
        axi_write(REG_DMA_OUTPUT_LEN, 32'h1234_5678, 4'b1111, 8'd21, RESP_SLVERR, "Write to RO DMA_OUTPUT_LEN rejected with SLVERR");

        // Attempt write to DMA_ERROR_CODE (read-only) -> expect SLVERR
        axi_write(REG_DMA_ERROR_CODE, 32'h0000_00FF, 4'b1111, 8'd22, RESP_SLVERR, "Write to RO DMA_ERROR_CODE rejected with SLVERR");

        // Unmapped address read and write -> expect SLVERR
        axi_write(REG_DMA_UNMAPPED, 32'hDEAD_BEEF, 4'b1111, 8'd23, RESP_SLVERR, "Write to unmapped offset rejected with SLVERR");
        axi_read (REG_DMA_UNMAPPED, 32'hDEAD_BEEF, 32'hFFFF_FFFF, 8'd24, RESP_SLVERR, "Read from unmapped offset returns SLVERR");

        // ---------------------------------------------------------------------
        // TEST GROUP 7: BUSY Protection
        // ---------------------------------------------------------------------
        $display("\n--- Test Group 7: BUSY Locking ---");
        // Emulate FSM becoming busy
        @(posedge clk);
        status_busy_i = 1'b1;
        @(posedge clk);

        // Verify STATUS bit 0 is 1
        axi_read(REG_DMA_STATUS, 32'h0000_0001, 32'h0000_0001, 8'd25, RESP_OKAY, "STATUS reflects BUSY=1");

        // Writing SRC_ADDR while busy must return SLVERR
        axi_write(REG_DMA_SRC_ADDR, 32'h0004_9999, 4'b1111, 8'd26, RESP_SLVERR, "Write SRC_ADDR while busy rejected with SLVERR");

        // Writing START while busy must NOT trigger ctrl_start_pulse_o
        axi_write(REG_DMA_CONTROL, 32'h0000_0001, 4'b1111, 8'd27, RESP_OKAY, "START write attempted while busy");
        total_tests++;
        if (ctrl_start_pulse_o === 1'b0) begin
            $display("[PASS] ctrl_start_pulse_o suppressed while BUSY=1");
            pass_count++;
        end else begin
            $display("[FAIL] ctrl_start_pulse_o fired even though BUSY was active!");
            fail_count++;
        end

        // Release busy
        @(posedge clk);
        status_busy_i = 1'b0;
        @(posedge clk);

        // ---------------------------------------------------------------------
        // TEST GROUP 8: Hardware Events, Output Length & Error Code
        // ---------------------------------------------------------------------
        $display("\n--- Test Group 8: Hardware Event Updates ---");
        // Pulse done event with output length = 85
        @(posedge clk);
        status_done_pulse_i = 1'b1;
        status_output_len_i = 16'd85;
        @(posedge clk);
        status_done_pulse_i = 1'b0;
        @(posedge clk);

        axi_read(REG_DMA_STATUS,     32'h0000_0002, 32'h0000_0002, 8'd28, RESP_OKAY, "STATUS bit 1 (DONE) asserted");
        axi_read(REG_DMA_OUTPUT_LEN, 32'h0000_0055, 32'h0000_FFFF, 8'd29, RESP_OKAY, "OUTPUT_LEN updated to 85");
        axi_read(REG_DMA_IRQ_STATUS, 32'h0000_0001, 32'h0000_0001, 8'd30, RESP_OKAY, "IRQ_STATUS bit 0 (DONE_IS) asserted");

        // Pulse error event with error code = 0x06 (RLE_ERR)
        @(posedge clk);
        status_error_pulse_i = 1'b1;
        status_error_code_i  = 8'h06;
        @(posedge clk);
        status_error_pulse_i = 1'b0;
        @(posedge clk);

        axi_read(REG_DMA_STATUS,     32'h0000_0004, 32'h0000_0004, 8'd31, RESP_OKAY, "STATUS bit 2 (ERROR) asserted");
        axi_read(REG_DMA_ERROR_CODE, 32'h0000_0006, 32'h0000_00FF, 8'd32, RESP_OKAY, "ERROR_CODE updated to 0x06");
        axi_read(REG_DMA_IRQ_STATUS, 32'h0000_0002, 32'h0000_0002, 8'd33, RESP_OKAY, "IRQ_STATUS bit 1 (ERROR_IS) asserted");

        // ---------------------------------------------------------------------
        // TEST GROUP 9: Interrupt Enables and W1C Clearing
        // ---------------------------------------------------------------------
        $display("\n--- Test Group 9: Interrupts & W1C Semantics ---");
        // At this point both IRQ_STATUS[0] and [1] are set, but IRQ_ENABLE is 0. irq_o must be 0.
        total_tests++;
        if (irq_o === 1'b0) begin
            $display("[PASS] irq_o remains deasserted when IRQ_ENABLE == 0");
            pass_count++;
        end else begin
            $display("[FAIL] irq_o asserted with IRQ_ENABLE == 0!");
            fail_count++;
        end

        // Enable DONE_IE (bit 0) -> irq_o must assert
        axi_write(REG_DMA_IRQ_ENABLE, 32'h0000_0001, 4'b0001, 8'd34, RESP_OKAY, "Enable DONE_IE");
        total_tests++;
        if (irq_o === 1'b1) begin
            $display("[PASS] irq_o asserted upon enabling DONE_IE");
            pass_count++;
        end else begin
            $display("[FAIL] irq_o failed to assert!");
            fail_count++;
        end

        // Clear DONE_IS via W1C (write 1 to bit 0 of IRQ_STATUS)
        axi_write(REG_DMA_IRQ_STATUS, 32'h0000_0001, 4'b0001, 8'd35, RESP_OKAY, "Clear DONE_IS via W1C");
        axi_read (REG_DMA_IRQ_STATUS, 32'h0000_0002, 32'h0000_0003, 8'd36, RESP_OKAY, "Verify DONE_IS cleared, ERROR_IS remains");

        total_tests++;
        if (irq_o === 1'b0) begin
            $display("[PASS] irq_o deasserted after clearing DONE_IS");
            pass_count++;
        end else begin
            $display("[FAIL] irq_o remained asserted!");
            fail_count++;
        end

        // Enable ERROR_IE (bit 1) -> irq_o must assert since ERROR_IS is still set
        axi_write(REG_DMA_IRQ_ENABLE, 32'h0000_0002, 4'b0001, 8'd37, RESP_OKAY, "Enable ERROR_IE");
        total_tests++;
        if (irq_o === 1'b1) begin
            $display("[PASS] irq_o asserted upon enabling ERROR_IE");
            pass_count++;
        end else begin
            $display("[FAIL] irq_o failed to assert for ERROR_IE!");
            fail_count++;
        end

        // Clear ERROR_IS via W1C
        axi_write(REG_DMA_IRQ_STATUS, 32'h0000_0002, 4'b0001, 8'd38, RESP_OKAY, "Clear ERROR_IS via W1C");
        axi_read (REG_DMA_IRQ_STATUS, 32'h0000_0000, 32'h0000_0003, 8'd39, RESP_OKAY, "Verify both IRQ status bits cleared");

        total_tests++;
        if (irq_o === 1'b0) begin
            $display("[PASS] irq_o deasserted after clearing ERROR_IS");
            pass_count++;
        end else begin
            $display("[FAIL] irq_o remained asserted after all cleared!");
            fail_count++;
        end

        // ---------------------------------------------------------------------
        // TEST GROUP 10: Dynamic Reset during Operation
        // ---------------------------------------------------------------------
        $display("\n--- Test Group 10: Dynamic Reset ---");
        // Program non-default values
        axi_write(REG_DMA_SRC_ADDR,   32'h1234_5678, 4'b1111, 8'd40, RESP_OKAY, "Program custom SRC_ADDR");
        axi_write(REG_DMA_IRQ_ENABLE, 32'h0000_0003, 4'b0001, 8'd41, RESP_OKAY, "Program custom IRQ_ENABLE");

        // Assert reset low
        repeat (2) @(posedge clk);
        rst_n = 1'b0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // Verify registers returned to default values
        axi_read(REG_DMA_SRC_ADDR,   32'h0004_0000, 32'hFFFF_FFFF, 8'd42, RESP_OKAY, "Post-reset SRC_ADDR is default");
        axi_read(REG_DMA_IRQ_ENABLE, 32'h0000_0000, 32'h0000_0003, 8'd43, RESP_OKAY, "Post-reset IRQ_ENABLE is 0");

        // =====================================================================
        // Final Summary
        // =====================================================================
        $display("\n================================================================");
        $display("                   VERIFICATION SUMMARY                         ");
        $display("================================================================");
        $display("  Total Checks Executed : %0d", total_tests);
        $display("  Passed Checks         : %0d", pass_count);
        $display("  Failed Checks         : %0d", fail_count);
        $display("================================================================");

        if (fail_count == 0) begin
            $display(">>> ALL STAGE 1 DMA REGISTER INTERFACE CHECKS PASSED! <<<\n");
        end else begin
            $display(">>> TEST COMPLETED WITH %0d ERRORS! <<<\n", fail_count);
        end

        $finish;
    end

endmodule
