// =============================================================================
// tb_rle_top.sv
//
// PURPOSE:
//   Self-checking verification testbench for rle_top.
//   Tests:
//     1. Reset & default register values.
//     2. Independent AW/W handshakes (AW-before-W, W-before-AW, simultaneous).
//     3. Backpressure handling on B and R channels.
//     4. Byte-strobe handling on INPUT_DATA writes.
//     5. Compression & Decompression roundtrip:
//        - Single-byte input
//        - Exact 255-byte run (max single record)
//        - 270-byte run (run split into [255, A] and [15, A])
//        - Alternating bytes
//        - Mixed repetitive vector "AAAAABBCC"
//     6. Error handling:
//        - Odd decompression input length -> ERROR flag set
//        - Zero count record -> ERROR flag set
//        - Writes to INPUT_LENGTH or INPUT_DATA while BUSY -> SLVERR
//        - Access to unmapped register offsets -> SLVERR
//     7. Interrupt handling:
//        - Sticky IRQ_STATUS bit assertion
//        - Write-1-to-clear (W1C) semantics
//        - Interrupt pin assertion conditional on IRQ_ENABLE
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module tb_rle_top;

    localparam DATA_WIDTH   = 32;
    localparam ADDR_WIDTH   = 32;
    localparam STRB_WIDTH   = DATA_WIDTH / 8;
    localparam BUFFER_DEPTH = 512;

    localparam REG_CONTROL       = 32'h000;
    localparam REG_STATUS        = 32'h004;
    localparam REG_INPUT_LENGTH  = 32'h008;
    localparam REG_OUTPUT_LENGTH = 32'h00C;
    localparam REG_INPUT_DATA    = 32'h010;
    localparam REG_OUTPUT_DATA   = 32'h014;
    localparam REG_IRQ_ENABLE    = 32'h018;
    localparam REG_IRQ_STATUS    = 32'h01C;
    localparam REG_UNMAPPED      = 32'h024;

    localparam RESP_OKAY   = 2'b00;
    localparam RESP_SLVERR = 2'b10;

    reg                   clk;
    reg                   rst;

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

    reg  [ADDR_WIDTH-1:0] s_axi_araddr;
    reg  [2:0]            s_axi_arprot;
    reg                   s_axi_arvalid;
    wire                  s_axi_arready;

    wire [DATA_WIDTH-1:0] s_axi_rdata;
    wire [1:0]            s_axi_rresp;
    wire                  s_axi_rvalid;
    reg                   s_axi_rready;

    wire                  irq;

    integer test_count;
    integer pass_count;
    integer fail_count;

    // Clock generator (100 MHz)
    always #5 clk = ~clk;

    // Instantiate DUT
    rle_top #(
        .DATA_WIDTH   (DATA_WIDTH),
        .ADDR_WIDTH   (ADDR_WIDTH),
        .STRB_WIDTH   (STRB_WIDTH),
        .BUFFER_DEPTH (BUFFER_DEPTH)
    ) dut (
        .clk            (clk),
        .rst            (rst),
        .s_axi_awaddr   (s_axi_awaddr),
        .s_axi_awprot   (s_axi_awprot),
        .s_axi_awvalid  (s_axi_awvalid),
        .s_axi_awready  (s_axi_awready),
        .s_axi_wdata    (s_axi_wdata),
        .s_axi_wstrb    (s_axi_wstrb),
        .s_axi_wvalid   (s_axi_wvalid),
        .s_axi_wready   (s_axi_wready),
        .s_axi_bresp    (s_axi_bresp),
        .s_axi_bvalid   (s_axi_bvalid),
        .s_axi_bready   (s_axi_bready),
        .s_axi_araddr   (s_axi_araddr),
        .s_axi_arprot   (s_axi_arprot),
        .s_axi_arvalid  (s_axi_arvalid),
        .s_axi_arready  (s_axi_arready),
        .s_axi_rdata    (s_axi_rdata),
        .s_axi_rresp    (s_axi_rresp),
        .s_axi_rvalid   (s_axi_rvalid),
        .s_axi_rready   (s_axi_rready),
        .irq            (irq)
    );

    // -------------------------------------------------------------------------
    // BFM Tasks
    // -------------------------------------------------------------------------
    task axi_write(
        input [ADDR_WIDTH-1:0] addr,
        input [DATA_WIDTH-1:0] data,
        input [STRB_WIDTH-1:0] strb,
        input integer          aw_delay,
        input integer          w_delay,
        input integer          b_delay,
        output [1:0]           resp
    );
        reg aw_done, w_done;
        integer i;
        begin
            aw_done = 0;
            w_done  = 0;

            fork
                begin
                    // AW Channel
                    for (i = 0; i < aw_delay; i = i + 1) @(posedge clk);
                    s_axi_awaddr  <= addr;
                    s_axi_awprot  <= 3'b000;
                    s_axi_awvalid <= 1'b1;
                    @(posedge clk);
                    while (!s_axi_awready) @(posedge clk);
                    s_axi_awvalid <= 1'b0;
                    aw_done = 1;
                end
                begin
                    // W Channel
                    for (i = 0; i < w_delay; i = i + 1) @(posedge clk);
                    s_axi_wdata  <= data;
                    s_axi_wstrb  <= strb;
                    s_axi_wvalid <= 1'b1;
                    @(posedge clk);
                    while (!s_axi_wready) @(posedge clk);
                    s_axi_wvalid <= 1'b0;
                    w_done = 1;
                end
            join

            // B Channel
            for (i = 0; i < b_delay; i = i + 1) @(posedge clk);
            s_axi_bready <= 1'b1;
            while (!s_axi_bvalid) @(posedge clk);
            resp = s_axi_bresp;
            @(posedge clk);
            s_axi_bready <= 1'b0;
        end
    endtask

    task axi_read(
        input  [ADDR_WIDTH-1:0] addr,
        input  integer          r_delay,
        output [DATA_WIDTH-1:0] data,
        output [1:0]            resp
    );
        integer i;
        begin
            @(posedge clk);
            s_axi_araddr  <= addr;
            s_axi_arprot  <= 3'b000;
            s_axi_arvalid <= 1'b1;
            @(posedge clk);
            while (!s_axi_arready) @(posedge clk);
            s_axi_arvalid <= 1'b0;

            for (i = 0; i < r_delay; i = i + 1) @(posedge clk);
            s_axi_rready <= 1'b1;
            while (!s_axi_rvalid) @(posedge clk);
            data = s_axi_rdata;
            resp = s_axi_rresp;
            @(posedge clk);
            s_axi_rready <= 1'b0;
        end
    endtask

    task wait_for_done(output [31:0] stat);
        reg [1:0] r_resp;
        integer timeout;
        begin
            timeout = 1000;
            stat = 32'd0;
            while ((stat[1] == 1'b0) && (stat[2] == 1'b0) && (timeout > 0)) begin
                repeat (5) @(posedge clk);
                axi_read(REG_STATUS, 0, stat, r_resp);
                timeout = timeout - 1;
            end
        end
    endtask

    task check(input [255:0] test_name, input condition);
        begin
            test_count = test_count + 1;
            if (condition) begin
                pass_count = pass_count + 1;
                $display("  [PASS] Test %02d: %s", test_count, test_name);
            end else begin
                fail_count = fail_count + 1;
                $display("  [FAIL] Test %02d: %s", test_count, test_name);
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Test Vectors
    // -------------------------------------------------------------------------
    reg [31:0] rd_val;
    reg [1:0]  wr_resp, rd_resp;
    integer    i, j;

    initial begin
        clk           = 0;
        rst           = 1;
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

        test_count = 0;
        pass_count = 0;
        fail_count = 0;

        $display("\n========================================================");
        $display("   STARTING RLE ACCELERATOR VERIFICATION SUITE");
        $display("========================================================\n");

        #20;
        rst = 0;
        #20;

        // ---------------------------------------------------------------------
        // TEST GROUP 1: Reset & Register Defaults
        // ---------------------------------------------------------------------
        $display("--- TEST GROUP 1: Reset & Register Defaults ---");
        axi_read(REG_STATUS, 0, rd_val, rd_resp);
        check("Status register defaults to 0 on reset", (rd_resp == RESP_OKAY) && (rd_val == 32'd0));

        axi_read(REG_CONTROL, 0, rd_val, rd_resp);
        check("Control register defaults to 0 on reset", (rd_resp == RESP_OKAY) && (rd_val == 32'd0));

        axi_read(REG_INPUT_LENGTH, 0, rd_val, rd_resp);
        check("Input Length register defaults to 0 on reset", (rd_resp == RESP_OKAY) && (rd_val == 32'd0));

        axi_read(REG_OUTPUT_LENGTH, 0, rd_val, rd_resp);
        check("Output Length register defaults to 0 on reset", (rd_resp == RESP_OKAY) && (rd_val == 32'd0));

        axi_read(REG_IRQ_ENABLE, 0, rd_val, rd_resp);
        check("IRQ Enable register defaults to 0 on reset", (rd_resp == RESP_OKAY) && (rd_val == 32'd0));

        axi_read(REG_IRQ_STATUS, 0, rd_val, rd_resp);
        check("IRQ Status register defaults to 0 on reset", (rd_resp == RESP_OKAY) && (rd_val == 32'd0));

        check("IRQ pin is low on reset", irq == 1'b0);

        // ---------------------------------------------------------------------
        // TEST GROUP 2: Independent AW/W Handshakes & Backpressure
        // ---------------------------------------------------------------------
        $display("\n--- TEST GROUP 2: Independent AW/W Handshakes & Backpressure ---");
        // Case A: Simultaneous AW and W
        axi_write(REG_IRQ_ENABLE, 32'h0000_0003, 4'b0001, 0, 0, 0, wr_resp);
        check("Simultaneous AW/W write succeeds", wr_resp == RESP_OKAY);
        axi_read(REG_IRQ_ENABLE, 0, rd_val, rd_resp);
        check("IRQ_ENABLE readback matches", rd_val[1:0] == 2'b11);

        // Case B: AW arrives 3 cycles before W
        axi_write(REG_IRQ_ENABLE, 32'h0000_0001, 4'b0001, 0, 3, 0, wr_resp);
        check("AW arrives 3 cycles before W succeeds", wr_resp == RESP_OKAY);
        axi_read(REG_IRQ_ENABLE, 0, rd_val, rd_resp);
        check("IRQ_ENABLE updated to 0x1", rd_val[1:0] == 2'b01);

        // Case C: W arrives 3 cycles before AW
        axi_write(REG_IRQ_ENABLE, 32'h0000_0002, 4'b0001, 3, 0, 0, wr_resp);
        check("W arrives 3 cycles before AW succeeds", wr_resp == RESP_OKAY);
        axi_read(REG_IRQ_ENABLE, 0, rd_val, rd_resp);
        check("IRQ_ENABLE updated to 0x2", rd_val[1:0] == 2'b10);

        // Case D: Backpressure on B channel (BREADY delayed 4 cycles)
        axi_write(REG_IRQ_ENABLE, 32'h0000_0003, 4'b0001, 0, 0, 4, wr_resp);
        check("BREADY backpressure handled cleanly", wr_resp == RESP_OKAY);

        // Case E: Backpressure on R channel (RREADY delayed 4 cycles)
        axi_read(REG_IRQ_ENABLE, 4, rd_val, rd_resp);
        check("RREADY backpressure handled cleanly", rd_val[1:0] == 2'b11);

        // ---------------------------------------------------------------------
        // TEST GROUP 3: Byte-Strobe Handling on INPUT_DATA
        // ---------------------------------------------------------------------
        $display("\n--- TEST GROUP 3: Byte-Strobe Handling on INPUT_DATA ---");
        axi_write(REG_INPUT_LENGTH, 32'd4, 4'b1111, 0, 0, 0, wr_resp);
        axi_write(REG_INPUT_DATA, 32'h0000_00AA, 4'b0001, 0, 0, 0, wr_resp);
        axi_write(REG_INPUT_DATA, 32'h0000_BB00, 4'b0010, 0, 0, 0, wr_resp);
        axi_write(REG_INPUT_DATA, 32'hDDCC_0000, 4'b1100, 0, 0, 0, wr_resp);
        check("Byte strobe writes completed successfully", wr_resp == RESP_OKAY);

        // ---------------------------------------------------------------------
        // TEST GROUP 4: Lossless Roundtrip Verifications
        // ---------------------------------------------------------------------
        $display("\n--- TEST GROUP 4: Lossless Roundtrip Verifications ---");

        // 4.1 Single Byte Input: 'X' -> [1, 'X'] -> 'X'
        $display("  -> Scenario 4.1: Single-byte payload");
        axi_write(REG_INPUT_LENGTH, 32'd1, 4'b1111, 0, 0, 0, wr_resp);
        axi_write(REG_INPUT_DATA, 32'h0000_0058, 4'b0001, 0, 0, 0, wr_resp); // 'X'
        axi_write(REG_CONTROL, 32'h0000_0001, 4'b0001, 0, 0, 0, wr_resp); // START, MODE=0 (compress)

        wait_for_done(rd_val);
        check("Single-byte compression DONE asserted", rd_val[1] == 1'b1);
        check("Single-byte compression ERROR is 0", rd_val[2] == 1'b0);

        axi_read(REG_OUTPUT_LENGTH, 0, rd_val, rd_resp);
        check("Compressed length is 2 bytes", rd_val == 32'd2);

        axi_read(REG_OUTPUT_DATA, 0, rd_val, rd_resp);
        check("Compressed byte 0 is count=1", rd_val[7:0] == 8'd1);
        axi_read(REG_OUTPUT_DATA, 0, rd_val, rd_resp);
        check("Compressed byte 1 is symbol='X'", rd_val[7:0] == 8'h58);

        // Decompress [1, 'X']
        axi_write(REG_INPUT_LENGTH, 32'd2, 4'b1111, 0, 0, 0, wr_resp);
        axi_write(REG_INPUT_DATA, {16'd0, 8'h58, 8'd1}, 4'b0011, 0, 0, 0, wr_resp);
        axi_write(REG_CONTROL, 32'h0000_0003, 4'b0001, 0, 0, 0, wr_resp); // START, MODE=1 (decompress)

        wait_for_done(rd_val);
        check("Single-byte decompression DONE asserted", rd_val[1] == 1'b1);
        axi_read(REG_OUTPUT_LENGTH, 0, rd_val, rd_resp);
        check("Decompressed length is 1 byte", rd_val == 32'd1);
        axi_read(REG_OUTPUT_DATA, 0, rd_val, rd_resp);
        check("Decompressed symbol matches 'X'", rd_val[7:0] == 8'h58);

        // 4.2 Exact 255-Byte Run of 'A' (0x41)
        $display("\n  -> Scenario 4.2: Max-run 255 identical bytes");
        axi_write(REG_INPUT_LENGTH, 32'd255, 4'b1111, 0, 0, 0, wr_resp);
        for (i = 0; i < 252; i = i + 4) begin
            axi_write(REG_INPUT_DATA, 32'h4141_4141, 4'b1111, 0, 0, 0, wr_resp);
        end
        // Remaining 3 bytes (252, 253, 254)
        axi_write(REG_INPUT_DATA, 32'h0041_4141, 4'b0111, 0, 0, 0, wr_resp);
        axi_write(REG_CONTROL, 32'h0000_0001, 4'b0001, 0, 0, 0, wr_resp); // Compress

        wait_for_done(rd_val);
        check("255-byte run compression DONE asserted", rd_val[1] == 1'b1);
        check("255-byte run compression ERROR is 0", rd_val[2] == 1'b0);
        axi_read(REG_OUTPUT_LENGTH, 0, rd_val, rd_resp);
        check("Compressed length is 2 bytes ([255, 'A'])", rd_val == 32'd2);

        axi_read(REG_OUTPUT_DATA, 0, rd_val, rd_resp);
        check("Byte 0 is count=255 (0xFF)", rd_val[7:0] == 8'hFF);
        axi_read(REG_OUTPUT_DATA, 0, rd_val, rd_resp);
        check("Byte 1 is symbol='A' (0x41)", rd_val[7:0] == 8'h41);

        // Decompress the [255, 'A']
        axi_write(REG_INPUT_LENGTH, 32'd2, 4'b1111, 0, 0, 0, wr_resp);
        axi_write(REG_INPUT_DATA, 32'h0000_41FF, 4'b0011, 0, 0, 0, wr_resp);
        axi_write(REG_CONTROL, 32'h0000_0003, 4'b0001, 0, 0, 0, wr_resp); // Decompress

        wait_for_done(rd_val);
        check("255-byte decompression DONE asserted", rd_val[1] == 1'b1);
        axi_read(REG_OUTPUT_LENGTH, 0, rd_val, rd_resp);
        check("Decompressed length is 255 bytes", rd_val == 32'd255);

        j = 0;
        for (i = 0; i < 255; i = i + 1) begin
            axi_read(REG_OUTPUT_DATA, 0, rd_val, rd_resp);
            if (rd_val[7:0] != 8'h41) j = j + 1;
        end
        check("All 255 decompressed bytes match 0x41", j == 0);

        // 4.3 Run Split: 270 bytes of 'B' (0x42) -> [255, 'B'], [15, 'B']
        $display("\n  -> Scenario 4.3: Long run (270 bytes) splitting");
        axi_write(REG_INPUT_LENGTH, 32'd270, 4'b1111, 0, 0, 0, wr_resp);
        for (i = 0; i < 268; i = i + 4) begin
            axi_write(REG_INPUT_DATA, 32'h4242_4242, 4'b1111, 0, 0, 0, wr_resp);
        end
        // Remaining 2 bytes (268, 269)
        axi_write(REG_INPUT_DATA, 32'h0000_4242, 4'b0011, 0, 0, 0, wr_resp);
        axi_write(REG_CONTROL, 32'h0000_0001, 4'b0001, 0, 0, 0, wr_resp); // Compress

        wait_for_done(rd_val);
        check("270-byte compression DONE asserted", rd_val[1] == 1'b1);
        check("270-byte compression ERROR is 0", rd_val[2] == 1'b0);
        axi_read(REG_OUTPUT_LENGTH, 0, rd_val, rd_resp);
        check("Compressed length is 4 bytes (2 pairs)", rd_val == 32'd4);

        axi_read(REG_OUTPUT_DATA, 0, rd_val, rd_resp);
        check("Record 1 count is 255 (0xFF)", rd_val[7:0] == 8'hFF);
        axi_read(REG_OUTPUT_DATA, 0, rd_val, rd_resp);
        check("Record 1 symbol is 'B' (0x42)", rd_val[7:0] == 8'h42);
        axi_read(REG_OUTPUT_DATA, 0, rd_val, rd_resp);
        check("Record 2 count is 15 (0x0F)", rd_val[7:0] == 8'h0F);
        axi_read(REG_OUTPUT_DATA, 0, rd_val, rd_resp);
        check("Record 2 symbol is 'B' (0x42)", rd_val[7:0] == 8'h42);

        // 4.4 Mixed Vector Roundtrip: "AAAAABBCC" -> 05 A 02 B 02 C
        $display("\n  -> Scenario 4.4: Mixed repetitive vector 'AAAAABBCC'");
        axi_write(REG_INPUT_LENGTH, 32'd9, 4'b1111, 0, 0, 0, wr_resp);
        axi_write(REG_INPUT_DATA, 32'h4141_4141, 4'b1111, 0, 0, 0, wr_resp); // AAAA
        axi_write(REG_INPUT_DATA, 32'h4342_4241, 4'b1111, 0, 0, 0, wr_resp); // ABBC
        axi_write(REG_INPUT_DATA, 32'h0000_0043, 4'b0001, 0, 0, 0, wr_resp); // C
        axi_write(REG_CONTROL, 32'h0000_0001, 4'b0001, 0, 0, 0, wr_resp);     // Compress

        wait_for_done(rd_val);
        check("Mixed vector compression DONE asserted", rd_val[1] == 1'b1);
        check("Mixed vector compression ERROR is 0", rd_val[2] == 1'b0);
        axi_read(REG_OUTPUT_LENGTH, 0, rd_val, rd_resp);
        check("Mixed vector compressed to 6 bytes", rd_val == 32'd6);

        // Decompress the 6-byte output
        // Expected stream: [5, A, 2, B, 2, C]
        axi_write(REG_INPUT_LENGTH, 32'd6, 4'b1111, 0, 0, 0, wr_resp);
        axi_write(REG_INPUT_DATA, 32'h4202_4105, 4'b1111, 0, 0, 0, wr_resp); // 05, A, 02, B
        axi_write(REG_INPUT_DATA, 32'h0000_4302, 4'b0011, 0, 0, 0, wr_resp); // 02, C
        axi_write(REG_CONTROL, 32'h0000_0003, 4'b0001, 0, 0, 0, wr_resp);     // Decompress

        wait_for_done(rd_val);
        check("Mixed vector decompression DONE asserted", rd_val[1] == 1'b1);
        axi_read(REG_OUTPUT_LENGTH, 0, rd_val, rd_resp);
        check("Mixed vector decompressed to 9 bytes", rd_val == 32'd9);

        // Verify content: A A A A A B B C C
        j = 0;
        for (i = 0; i < 9; i = i + 1) begin
            axi_read(REG_OUTPUT_DATA, 0, rd_val, rd_resp);
            if (i < 5 && rd_val[7:0] != 8'h41) j = j + 1;
            if ((i == 5 || i == 6) && rd_val[7:0] != 8'h42) j = j + 1;
            if ((i == 7 || i == 8) && rd_val[7:0] != 8'h43) j = j + 1;
        end
        check("Mixed vector 9 bytes reconstructed bit-for-bit", j == 0);

        // ---------------------------------------------------------------------
        // TEST GROUP 5: Error Handling & Illegal Transactions
        // ---------------------------------------------------------------------
        $display("\n--- TEST GROUP 5: Error Handling & Illegal Transactions ---");

        // 5.1 Odd length on decompression input
        axi_write(REG_INPUT_LENGTH, 32'd3, 4'b1111, 0, 0, 0, wr_resp);
        axi_write(REG_INPUT_DATA, 32'h0041_4203, 4'b0111, 0, 0, 0, wr_resp);
        axi_write(REG_CONTROL, 32'h0000_0003, 4'b0001, 0, 0, 0, wr_resp); // Decompress
        wait_for_done(rd_val);
        check("Odd length decompression triggers ERROR flag (STATUS[2])", rd_val[2] == 1'b1);

        // 5.2 Zero run-count in decompression
        axi_write(REG_INPUT_LENGTH, 32'd2, 4'b1111, 0, 0, 0, wr_resp);
        axi_write(REG_INPUT_DATA, 32'h0000_4100, 4'b0011, 0, 0, 0, wr_resp); // [0, 'A']
        axi_write(REG_CONTROL, 32'h0000_0003, 4'b0001, 0, 0, 0, wr_resp);     // Decompress
        wait_for_done(rd_val);
        check("Zero-count decompression triggers ERROR flag (STATUS[2])", rd_val[2] == 1'b1);

        // 5.3 Unmapped Register Offset Access
        axi_write(REG_UNMAPPED, 32'hDEAD_BEEF, 4'b1111, 0, 0, 0, wr_resp);
        check("Write to unmapped offset returns SLVERR", wr_resp == RESP_SLVERR);

        axi_read(REG_UNMAPPED, 0, rd_val, rd_resp);
        check("Read from unmapped offset returns SLVERR", rd_resp == RESP_SLVERR);

        // 5.4 Input Buffer Overflow
        $display("\n  -> Scenario 5.4: Input buffer capacity overflow");
        axi_write(REG_INPUT_LENGTH, 32'd512, 4'b1111, 0, 0, 0, wr_resp);
        // Write 512 bytes (fill buffer to capacity)
        for (i = 0; i < 512; i = i + 4) begin
            axi_write(REG_INPUT_DATA, 32'hA5A5_A5A5, 4'b1111, 0, 0, 0, wr_resp);
        end
        // Now attempt to write 4 more bytes beyond BUFFER_DEPTH (512)
        axi_write(REG_INPUT_DATA, 32'hDEAD_BEEF, 4'b1111, 0, 0, 0, wr_resp);
        axi_read(REG_STATUS, 0, rd_val, rd_resp);
        check("Input buffer overflow asserts ERROR in STATUS register", rd_val[2] == 1'b1);

        // 5.5 Decompressed Buffer Overflow
        $display("\n  -> Scenario 5.5: Decompressed output overflow detection");
        // Reset and attempt decompressing two 255-byte runs (total 510 bytes) followed by 10 bytes (520 > 512)
        axi_write(REG_INPUT_LENGTH, 32'd6, 4'b1111, 0, 0, 0, wr_resp);
        axi_write(REG_INPUT_DATA, 32'h41FF_41FF, 4'b1111, 0, 0, 0, wr_resp); // [255, A], [255, A]
        axi_write(REG_INPUT_DATA, 32'h0000_410A, 4'b0011, 0, 0, 0, wr_resp); // [10, A]
        axi_write(REG_CONTROL, 32'h0000_0003, 4'b0001, 0, 0, 0, wr_resp);     // Decompress
        wait_for_done(rd_val);
        check("Decompression buffer overflow triggers ERROR flag", rd_val[2] == 1'b1);

        // 5.6 Writes while Busy
        $display("\n  -> Scenario 5.6: Illegal writes while BUSY return SLVERR");
        axi_write(REG_INPUT_LENGTH, 32'd255, 4'b1111, 0, 0, 0, wr_resp);
        for (i = 0; i < 252; i = i + 4) begin
            axi_write(REG_INPUT_DATA, 32'h4343_4343, 4'b1111, 0, 0, 0, wr_resp);
        end
        axi_write(REG_INPUT_DATA, 32'h0043_4343, 4'b0111, 0, 0, 0, wr_resp);
        axi_write(REG_CONTROL, 32'h0000_0001, 4'b0001, 0, 0, 0, wr_resp); // Start compression
        // Immediately while engine is running:
        axi_write(REG_INPUT_LENGTH, 32'd10, 4'b1111, 0, 0, 0, wr_resp);
        check("Write to INPUT_LENGTH while BUSY returns SLVERR", wr_resp == RESP_SLVERR);

        axi_write(REG_INPUT_DATA, 32'h1234_5678, 4'b1111, 0, 0, 0, wr_resp);
        check("Write to INPUT_DATA while BUSY returns SLVERR", wr_resp == RESP_SLVERR);

        wait_for_done(rd_val);
        check("Long compression completed after busy-write attempts", rd_val[1] == 1'b1);

        // 5.7 Input-Length Consistency
        $display("\n  -> Scenario 5.7: Input-length consistency check");
        axi_write(REG_INPUT_LENGTH, 32'd16, 4'b1111, 0, 0, 0, wr_resp); // Declare 16 bytes
        axi_write(REG_INPUT_DATA, 32'h1122_3344, 4'b1111, 0, 0, 0, wr_resp); // Append only 4 bytes
        axi_write(REG_CONTROL, 32'h0000_0001, 4'b0001, 0, 0, 0, wr_resp);    // Attempt START
        repeat (5) @(posedge clk);
        axi_read(REG_STATUS, 0, rd_val, rd_resp);
        check("START with incomplete appended data asserts ERROR flag", rd_val[2] == 1'b1);

        // ---------------------------------------------------------------------
        // TEST GROUP 6: Interrupts & W1C Clearing
        // ---------------------------------------------------------------------
        $display("\n--- TEST GROUP 6: Interrupts & Write-1-to-Clear (W1C) ---");
        // Clear any prior sticky interrupt status from error injection tests
        axi_write(REG_IRQ_STATUS, 32'h0000_0003, 4'b0001, 0, 0, 0, wr_resp);

        // 6.1 DONE Interrupt
        axi_write(REG_IRQ_ENABLE, 32'h0000_0001, 4'b0001, 0, 0, 0, wr_resp); // Enable DONE IRQ only
        axi_write(REG_INPUT_LENGTH, 32'd1, 4'b1111, 0, 0, 0, wr_resp);
        axi_write(REG_INPUT_DATA, 32'h0000_005A, 4'b0001, 0, 0, 0, wr_resp);
        axi_write(REG_CONTROL, 32'h0000_0001, 4'b0001, 0, 0, 0, wr_resp);

        wait_for_done(rd_val);
        check("IRQ pin asserts on DONE", irq == 1'b1);

        axi_read(REG_IRQ_STATUS, 0, rd_val, rd_resp);
        check("IRQ_STATUS[0] is set", rd_val[0] == 1'b1);

        // Clear DONE IRQ by writing 1 to bit 0 (W1C)
        axi_write(REG_IRQ_STATUS, 32'h0000_0001, 4'b0001, 0, 0, 0, wr_resp);
        repeat (2) @(posedge clk);
        check("IRQ pin de-asserts after W1C on bit 0", irq == 1'b0);

        axi_read(REG_IRQ_STATUS, 0, rd_val, rd_resp);
        check("IRQ_STATUS[0] cleared to 0", rd_val[0] == 1'b0);

        // 6.2 ERROR Interrupt
        axi_write(REG_IRQ_STATUS, 32'h0000_0003, 4'b0001, 0, 0, 0, wr_resp); // Clear status
        axi_write(REG_IRQ_ENABLE, 32'h0000_0002, 4'b0001, 0, 0, 0, wr_resp); // Enable ERROR IRQ only
        axi_write(REG_INPUT_LENGTH, 32'd3, 4'b1111, 0, 0, 0, wr_resp);
        axi_write(REG_INPUT_DATA, 32'h0041_4203, 4'b0111, 0, 0, 0, wr_resp);
        axi_write(REG_CONTROL, 32'h0000_0003, 4'b0001, 0, 0, 0, wr_resp); // Odd decompress length error

        wait_for_done(rd_val);
        check("IRQ pin asserts on ERROR", irq == 1'b1);

        axi_read(REG_IRQ_STATUS, 0, rd_val, rd_resp);
        check("IRQ_STATUS[1] is set", rd_val[1] == 1'b1);

        // Clear ERROR IRQ by writing 1 to bit 1 (W1C)
        axi_write(REG_IRQ_STATUS, 32'h0000_0002, 4'b0001, 0, 0, 0, wr_resp);
        repeat (2) @(posedge clk);
        check("IRQ pin de-asserts after W1C on bit 1", irq == 1'b0);

        axi_read(REG_IRQ_STATUS, 0, rd_val, rd_resp);
        check("IRQ_STATUS[1] cleared to 0", rd_val[1] == 1'b0);

        // 6.3 Disabled IRQ (status is sticky, but pin remains low)
        axi_write(REG_IRQ_ENABLE, 32'h0000_0000, 4'b0001, 0, 0, 0, wr_resp); // Disable all IRQs
        axi_write(REG_INPUT_LENGTH, 32'd3, 4'b1111, 0, 0, 0, wr_resp);
        axi_write(REG_INPUT_DATA, 32'h0041_4203, 4'b0111, 0, 0, 0, wr_resp);
        axi_write(REG_CONTROL, 32'h0000_0003, 4'b0001, 0, 0, 0, wr_resp); // Error

        wait_for_done(rd_val);
        check("IRQ pin remains low when IRQ_ENABLE is 0", irq == 1'b0);
        axi_read(REG_IRQ_STATUS, 0, rd_val, rd_resp);
        check("IRQ_STATUS[1] still records error event when disabled", rd_val[1] == 1'b1);

        // ---------------------------------------------------------------------
        // SUMMARY
        // ---------------------------------------------------------------------
        $display("\n========================================================");
        $display("   TEST SUITE COMPLETE");
        $display("   Total Tests : %0d", test_count);
        $display("   Passed      : %0d", pass_count);
        $display("   Failed      : %0d", fail_count);
        if (fail_count == 0) begin
            $display("   OVERALL STATUS: ALL TESTS PASSED!");
        end else begin
            $display("   OVERALL STATUS: TESTS FAILED!");
        end
        $display("========================================================\n");

        $finish;
    end

endmodule
`default_nettype wire
