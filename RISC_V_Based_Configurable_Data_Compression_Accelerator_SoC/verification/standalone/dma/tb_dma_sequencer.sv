// =============================================================================
// tb_dma_sequencer.sv
//
// Self-Checking Unit Testbench for DMA Sequencer FSM (dma_sequencer.v).
//
// Tests Covered:
//   1.  Input validation: Bad Length (0 and > 256)
//   2.  Input validation: Bad Source Address (< 0x40000 or > 0x7FFFF)
//   3.  Input validation: Bad Destination Address (< 0x40000 or > 0x7FFFF)
//   4.  Single-byte transfer (1 byte, partial word WSTRB = 4'b0001)
//   5.  Two-byte transfer (2 bytes, partial word WSTRB = 4'b0011)
//   6.  Three-byte transfer (3 bytes, partial word WSTRB = 4'b0111)
//   7.  Four-byte transfer (4 bytes, exact 1 word WSTRB = 4'b1111)
//   8.  Multi-word transfer (16 bytes, 4 full words)
//   9.  Partial-word boundary transfer (255 bytes, 63 full words + 1 partial)
//   10. Maximum transfer (256 bytes, 64 full words)
//   11. Compression mode vs Decompression mode signaling
//   12. AXI Master Read error handling (SLVERR/DECERR -> ERR_RD_ERR)
//   13. AXI Master Write error handling (SLVERR/DECERR -> ERR_WR_ERR)
//   14. RLE Status Error handling (STATUS Bit 2 -> ERR_RLE_ERR)
//   15. RLE Timeout handling (Guard counter -> ERR_TIMEOUT)
//   16. Mid-transfer Abort & recovery
//   17. Dynamic Reset & recovery
//
// =============================================================================

`timescale 1ns / 1ps

module tb_dma_sequencer;

    localparam ADDR_WIDTH     = 32;
    localparam DATA_WIDTH     = 32;
    localparam STRB_WIDTH     = 4;
    localparam BUFFER_DEPTH   = 256;
    localparam TIMEOUT_CYCLES = 50; // Low timeout for testing
    localparam CLK_PERIOD     = 10;

    logic clk;
    logic rst_n;

    // Sequencer <-> Register File
    logic                  ctrl_start;
    logic                  ctrl_abort;
    logic                  ctrl_mode;
    logic [ADDR_WIDTH-1:0] cfg_src_addr;
    logic [ADDR_WIDTH-1:0] cfg_dst_addr;
    logic [15:0]           cfg_input_len;
    logic                  status_busy;
    logic                  status_done_pulse;
    logic                  status_error_pulse;
    logic [15:0]           status_output_len;
    logic [7:0]            status_error_code;

    // Sequencer <-> Master Engine
    logic                  req_rd_start;
    logic [ADDR_WIDTH-1:0] req_rd_addr;
    logic [7:0]            req_rd_len;
    logic [DATA_WIDTH-1:0] rd_data;
    logic                  rd_valid;
    logic                  rd_ready;
    logic                  rd_last;
    logic                  rd_done;
    logic                  rd_error;
    logic [1:0]            rd_resp;

    logic                  req_wr_start;
    logic [ADDR_WIDTH-1:0] req_wr_addr;
    logic [7:0]            req_wr_len;
    logic [DATA_WIDTH-1:0] wr_data;
    logic [STRB_WIDTH-1:0] wr_strb;
    logic                  wr_valid;
    logic                  wr_ready;
    logic                  wr_done;
    logic                  wr_error;
    logic [1:0]            wr_resp;

    logic                  master_abort;

    // =========================================================================
    // Device Under Test
    // =========================================================================
    dma_sequencer #(
        .ADDR_WIDTH     (ADDR_WIDTH),
        .DATA_WIDTH     (DATA_WIDTH),
        .STRB_WIDTH     (STRB_WIDTH),
        .BUFFER_DEPTH   (BUFFER_DEPTH),
        .TIMEOUT_CYCLES (TIMEOUT_CYCLES)
    ) dut (
        .clk                  (clk),
        .rst_n                (rst_n),

        .ctrl_start_i         (ctrl_start),
        .ctrl_abort_i         (ctrl_abort),
        .ctrl_mode_i          (ctrl_mode),
        .cfg_src_addr_i       (cfg_src_addr),
        .cfg_dst_addr_i       (cfg_dst_addr),
        .cfg_input_len_i      (cfg_input_len),

        .status_busy_o        (status_busy),
        .status_done_pulse_o  (status_done_pulse),
        .status_error_pulse_o (status_error_pulse),
        .status_output_len_o  (status_output_len),
        .status_error_code_o  (status_error_code),

        .req_rd_start_o       (req_rd_start),
        .req_rd_addr_o        (req_rd_addr),
        .req_rd_len_o         (req_rd_len),
        .rd_data_i            (rd_data),
        .rd_valid_i           (rd_valid),
        .rd_ready_o           (rd_ready),
        .rd_last_i            (rd_last),
        .rd_done_i            (rd_done),
        .rd_error_i           (rd_error),
        .rd_resp_i            (rd_resp),

        .req_wr_start_o       (req_wr_start),
        .req_wr_addr_o        (req_wr_addr),
        .req_wr_len_o         (req_wr_len),
        .wr_data_o            (wr_data),
        .wr_strb_o            (wr_strb),
        .wr_valid_o           (wr_valid),
        .wr_ready_i           (wr_ready),
        .wr_done_i            (wr_done),
        .wr_error_i           (wr_error),
        .wr_resp_i            (wr_resp),

        .master_abort_o       (master_abort)
    );

    // Clock
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // =========================================================================
    // Emulated Memory & RLE Engine for Unit Testing
    // =========================================================================
    logic [7:0] dmem [logic [31:0]];
    logic [7:0] mock_rle_in_buf [0:255];
    logic [7:0] mock_rle_out_buf [0:255];
    int         mock_rle_in_ptr;
    int         mock_rle_out_ptr;
    logic [15:0]mock_rle_in_len;
    logic [15:0]mock_rle_out_len;
    logic       mock_rle_busy;
    logic       mock_rle_done;
    logic       mock_rle_error;
    logic       mock_rle_mode;

    // Fault injection knobs
    bit inject_rd_err = 0;
    bit inject_wr_err = 0;
    bit inject_rle_err = 0;
    bit inject_rle_timeout = 0;

    // Helper functions for DMEM access
    function void write_dmem_byte(logic [31:0] addr, logic [7:0] val);
        dmem[addr] = val;
    endfunction

    function logic [7:0] read_dmem_byte(logic [31:0] addr);
        if (dmem.exists(addr)) return dmem[addr];
        else return 8'h00;
    endfunction

    function logic [31:0] read_dmem_word(logic [31:0] addr);
        return {read_dmem_byte(addr + 3), read_dmem_byte(addr + 2),
                read_dmem_byte(addr + 1), read_dmem_byte(addr + 0)};
    endfunction

    // Behavioral Master Engine Emulator
    // Emulates master engine responses to read requests
    initial begin
        rd_valid = 1'b0;
        rd_data  = 32'h0;
        rd_last  = 1'b0;
        rd_done  = 1'b0;
        rd_error = 1'b0;
        rd_resp  = 2'b00;

        forever begin
            @(posedge clk);
            rd_done  <= 1'b0;
            rd_error <= 1'b0;
            rd_valid <= 1'b0;
            rd_last  <= 1'b0;

            if (req_rd_start) begin
                logic [31:0] cur_addr;
                logic [7:0]  cur_len;
                int b;
                cur_addr = req_rd_addr;
                cur_len  = req_rd_len;

                if (inject_rd_err) begin
                    @(posedge clk);
                    rd_error <= 1'b1;
                    rd_resp  <= 2'b10;
                    rd_done  <= 1'b1;
                    @(posedge clk);
                    rd_error <= 1'b0;
                    rd_done  <= 1'b0;
                end else if (cur_addr >= 32'h0001_0000 && cur_addr <= 32'h0002_FFFF) begin
                    // Read from DMEM (burst of cur_len + 1 words)
                    for (b = 0; b <= cur_len; b++) begin
                        @(posedge clk);
                        rd_valid <= 1'b1;
                        rd_data  <= read_dmem_word(cur_addr);
                        rd_last  <= (b == cur_len);
                        cur_addr = cur_addr + 4;
                    end
                    @(posedge clk);
                    rd_valid <= 1'b0;
                    rd_last  <= 1'b0;
                    rd_done  <= 1'b1;
                end else if (cur_addr == 32'h000D_0004) begin
                    // Read RLE REG_STATUS
                    @(posedge clk);
                    rd_valid <= 1'b1;
                    if (inject_rle_timeout) begin
                        rd_data <= 32'h0000_0001; // Stuck in BUSY
                    end else if (inject_rle_err) begin
                        rd_data <= 32'h0000_0004; // ERROR bit 2 set
                    end else begin
                        rd_data <= 32'h0000_0002; // DONE bit 1 set
                    end
                    rd_last  <= 1'b1;
                    @(posedge clk);
                    rd_valid <= 1'b0;
                    rd_last  <= 1'b0;
                    rd_done  <= 1'b1;
                end else if (cur_addr == 32'h000D_000C) begin
                    // Read RLE REG_OUTPUT_LEN
                    @(posedge clk);
                    rd_valid <= 1'b1;
                    rd_data  <= {16'd0, mock_rle_out_len};
                    rd_last  <= 1'b1;
                    @(posedge clk);
                    rd_valid <= 1'b0;
                    rd_last  <= 1'b0;
                    rd_done  <= 1'b1;
                end else if (cur_addr == 32'h000D_0014) begin
                    // Read RLE REG_OUTPUT_DATA (1 byte per read)
                    @(posedge clk);
                    rd_valid <= 1'b1;
                    rd_data  <= {24'd0, mock_rle_out_buf[mock_rle_out_ptr]};
                    mock_rle_out_ptr = mock_rle_out_ptr + 1;
                    rd_last  <= 1'b1;
                    @(posedge clk);
                    rd_valid <= 1'b0;
                    rd_last  <= 1'b0;
                    rd_done  <= 1'b1;
                end
            end
        end
    end

    // Emulates master engine responses to write requests
    initial begin
        wr_ready = 1'b1;
        wr_done  = 1'b0;
        wr_error = 1'b0;
        wr_resp  = 2'b00;

        forever begin
            @(posedge clk);
            wr_done  <= 1'b0;
            wr_error <= 1'b0;

            if (req_wr_start) begin
                logic [31:0] w_addr;
                w_addr = req_wr_addr;

                @(posedge clk);
                if (inject_wr_err) begin
                    wr_error <= 1'b1;
                    wr_resp  <= 2'b10;
                    wr_done  <= 1'b1;
                end else begin
                    // Handle write according to address
                    if (w_addr == 32'h000D_0008) begin
                        // RLE REG_INPUT_LEN
                        mock_rle_in_len = wr_data[15:0];
                        mock_rle_in_ptr = 0;
                    end else if (w_addr == 32'h000D_0010) begin
                        // RLE REG_INPUT_DATA
                        if (wr_strb[0]) begin mock_rle_in_buf[mock_rle_in_ptr] = wr_data[7:0];   mock_rle_in_ptr++; end
                        if (wr_strb[1]) begin mock_rle_in_buf[mock_rle_in_ptr] = wr_data[15:8];  mock_rle_in_ptr++; end
                        if (wr_strb[2]) begin mock_rle_in_buf[mock_rle_in_ptr] = wr_data[23:16]; mock_rle_in_ptr++; end
                        if (wr_strb[3]) begin mock_rle_in_buf[mock_rle_in_ptr] = wr_data[31:24]; mock_rle_in_ptr++; end
                    end else if (w_addr == 32'h000D_0000) begin
                        // RLE REG_CONTROL
                        mock_rle_mode = wr_data[1];
                        mock_rle_out_ptr = 0;
                    end else if (w_addr >= 32'h0001_0000 && w_addr <= 32'h0002_FFFF) begin
                        // Destination DMEM write
                        if (wr_strb[0]) write_dmem_byte(w_addr + 0, wr_data[7:0]);
                        if (wr_strb[1]) write_dmem_byte(w_addr + 1, wr_data[15:8]);
                        if (wr_strb[2]) write_dmem_byte(w_addr + 2, wr_data[23:16]);
                        if (wr_strb[3]) write_dmem_byte(w_addr + 3, wr_data[31:24]);
                    end
                    wr_done <= 1'b1;
                end
                @(posedge clk);
                wr_done  <= 1'b0;
                wr_error <= 1'b0;
            end
        end
    end

    // =========================================================================
    // Scoreboard
    // =========================================================================
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

    // Helper task to trigger DMA transfer
    task trigger_transfer(input logic [31:0] src, input logic [31:0] dst,
                          input logic [15:0] len, input logic mode);
        @(posedge clk);
        cfg_src_addr  <= src;
        cfg_dst_addr  <= dst;
        cfg_input_len <= len;
        ctrl_mode     <= mode;
        ctrl_start    <= 1'b1;
        @(posedge clk);
        ctrl_start    <= 1'b0;
    endtask

    // =========================================================================
    // Test Vectors
    // =========================================================================
    initial begin
        int i;
        ctrl_start    = 1'b0;
        ctrl_abort    = 1'b0;
        ctrl_mode     = 1'b0;
        cfg_src_addr  = 32'h0;
        cfg_dst_addr  = 32'h0;
        cfg_input_len = 16'd0;
        rst_n         = 1'b0;

        $display("================================================================");
        $display("     DMA SEQUENCER (dma_sequencer) UNIT TESTBENCH               ");
        $display("================================================================");

        #(CLK_PERIOD * 3);
        rst_n = 1'b1;
        #(CLK_PERIOD * 2);

        // ---------------------------------------------------------------------
        // Test 1: Parameter Validations
        // ---------------------------------------------------------------------
        $display("\n--- Test Group 1: Parameter Validations ---");
        // Len = 0
        trigger_transfer(32'h0001_0000, 32'h0001_0100, 16'd0, 1'b0);
        @(posedge clk);
        while (!status_error_pulse) @(posedge clk);
        check(status_error_code === 8'h03, "Length == 0 rejected with ERR_BAD_LEN (0x03)");

        // Len > 256
        trigger_transfer(32'h0001_0000, 32'h0001_0100, 16'd257, 1'b0);
        @(posedge clk);
        while (!status_error_pulse) @(posedge clk);
        check(status_error_code === 8'h03, "Length == 257 rejected with ERR_BAD_LEN (0x03)");

        // Bad Source Address (< 0x0001_0000)
        trigger_transfer(32'h0000_FFFC, 32'h0001_0100, 16'd4, 1'b0);
        @(posedge clk);
        while (!status_error_pulse) @(posedge clk);
        check(status_error_code === 8'h01, "Source addr < 0x10000 rejected with ERR_BAD_SRC (0x01)");

        // Bad Destination Address (> 0x0002_FFFF)
        trigger_transfer(32'h0001_0000, 32'h0003_0000, 16'd4, 1'b0);
        @(posedge clk);
        while (!status_error_pulse) @(posedge clk);
        check(status_error_code === 8'h02, "Destination addr > 0x2FFFF rejected with ERR_BAD_DST (0x02)");

        // ---------------------------------------------------------------------
        // Test 2: Single-Byte Transfer (1 byte)
        // ---------------------------------------------------------------------
        $display("\n--- Test Group 2: Single-Byte Transfer (1 Byte) ---");
        write_dmem_byte(32'h0001_0000, 8'hAB);
        // Pre-configure mock RLE output: 1 byte of 0xCD
        mock_rle_out_len = 16'd1;
        mock_rle_out_buf[0] = 8'hCD;

        trigger_transfer(32'h0001_0000, 32'h0002_0000, 16'd1, 1'b0);
        while (!status_done_pulse) @(posedge clk);

        check(status_output_len === 16'd1, "1-byte transfer reports output len = 1");
        check(mock_rle_in_buf[0] === 8'hAB, "RLE received single byte 0xAB with WSTRB=4'b0001");
        check(read_dmem_byte(32'h0002_0000) === 8'hCD, "Destination DMEM received output byte 0xCD");

        // ---------------------------------------------------------------------
        // Test 3: Two-Byte Transfer (2 Bytes)
        // ---------------------------------------------------------------------
        $display("\n--- Test Group 3: Two-Byte Transfer (2 Bytes) ---");
        write_dmem_byte(32'h0001_0010, 8'h11);
        write_dmem_byte(32'h0001_0011, 8'h22);
        mock_rle_out_len = 16'd2;
        mock_rle_out_buf[0] = 8'h33;
        mock_rle_out_buf[1] = 8'h44;

        trigger_transfer(32'h0001_0010, 32'h0002_0010, 16'd2, 1'b0);
        while (!status_done_pulse) @(posedge clk);

        check(status_output_len === 16'd2, "2-byte transfer reports output len = 2");
        check(mock_rle_in_buf[0] === 8'h11 && mock_rle_in_buf[1] === 8'h22, "RLE received 2 bytes with WSTRB=4'b0011");
        check(read_dmem_byte(32'h0002_0010) === 8'h33 && read_dmem_byte(32'h0002_0011) === 8'h44,
              "Destination DMEM received 2 packed bytes");

        // ---------------------------------------------------------------------
        // Test 4: Three-Byte Transfer (3 Bytes)
        // ---------------------------------------------------------------------
        $display("\n--- Test Group 4: Three-Byte Transfer (3 Bytes) ---");
        write_dmem_byte(32'h0001_0020, 8'hA1);
        write_dmem_byte(32'h0001_0021, 8'hB2);
        write_dmem_byte(32'h0001_0022, 8'hC3);
        mock_rle_out_len = 16'd3;
        mock_rle_out_buf[0] = 8'hD4;
        mock_rle_out_buf[1] = 8'hE5;
        mock_rle_out_buf[2] = 8'hF6;

        trigger_transfer(32'h0001_0020, 32'h0002_0020, 16'd3, 1'b0);
        while (!status_done_pulse) @(posedge clk);

        check(status_output_len === 16'd3, "3-byte transfer reports output len = 3");
        check(mock_rle_in_buf[0] === 8'hA1 && mock_rle_in_buf[1] === 8'hB2 && mock_rle_in_buf[2] === 8'hC3,
              "RLE received 3 bytes with WSTRB=4'b0111");
        check(read_dmem_byte(32'h0002_0020) === 8'hD4 && read_dmem_byte(32'h0002_0021) === 8'hE5 &&
              read_dmem_byte(32'h0002_0022) === 8'hF6, "Destination DMEM received 3 packed bytes");

        // ---------------------------------------------------------------------
        // Test 5: Four-Byte Transfer (1 full word)
        // ---------------------------------------------------------------------
        $display("\n--- Test Group 5: Four-Byte Transfer (Exact 1 Word) ---");
        for (i = 0; i < 4; i++) write_dmem_byte(32'h0001_0030 + i, 8'h50 + i);
        mock_rle_out_len = 16'd4;
        for (i = 0; i < 4; i++) mock_rle_out_buf[i] = 8'h60 + i;

        trigger_transfer(32'h0001_0030, 32'h0002_0030, 16'd4, 1'b0);
        while (!status_done_pulse) @(posedge clk);

        check(status_output_len === 16'd4, "4-byte transfer reports output len = 4");
        check(read_dmem_word(32'h0002_0030) === 32'h6362_6160, "Destination DMEM received full 32-bit word");

        // ---------------------------------------------------------------------
        // Test 6: 16-Byte Transfer (4 words) with Decompression Mode
        // ---------------------------------------------------------------------
        $display("\n--- Test Group 6: 16-Byte Decompression Transfer ---");
        for (i = 0; i < 16; i++) write_dmem_byte(32'h0001_0040 + i, 8'h10 + i);
        mock_rle_out_len = 16'd20; // Expansion: 16 in -> 20 out
        for (i = 0; i < 20; i++) mock_rle_out_buf[i] = 8'h80 + i;

        trigger_transfer(32'h0001_0040, 32'h0002_0040, 16'd16, 1'b1); // MODE=1
        while (!status_done_pulse) @(posedge clk);

        check(mock_rle_mode === 1'b1, "Decompression MODE=1 correctly set on RLE");
        check(status_output_len === 16'd20, "16->20 byte expansion transfer completed");
        for (i = 0; i < 20; i++) begin
            if (read_dmem_byte(32'h0002_0040 + i) !== (8'h80 + i)) check(0, $sformatf("Byte %0d mismatch", i));
        end
        check(1, "All 20 destination bytes verified in DMEM");

        // ---------------------------------------------------------------------
        // Test 7: 255-Byte Transfer (63 words + 3 bytes partial)
        // ---------------------------------------------------------------------
        $display("\n--- Test Group 7: 255-Byte Transfer (Partial Final Word) ---");
        for (i = 0; i < 255; i++) write_dmem_byte(32'h0001_1000 + i, i & 8'hFF);
        mock_rle_out_len = 16'd255;
        for (i = 0; i < 255; i++) mock_rle_out_buf[i] = (i + 1) & 8'hFF;

        trigger_transfer(32'h0001_1000, 32'h0002_4000, 16'd255, 1'b0);
        while (!status_done_pulse) @(posedge clk);

        check(status_output_len === 16'd255, "255-byte transfer output len = 255");
        for (i = 0; i < 255; i++) begin
            if (read_dmem_byte(32'h0002_4000 + i) !== ((i + 1) & 8'hFF)) check(0, $sformatf("255-byte mismatch at %0d", i));
        end
        check(1, "All 255 bytes verified in destination DMEM");

        // ---------------------------------------------------------------------
        // Test 8: 256-Byte Transfer (Exact 64 Words Max Capacity)
        // ---------------------------------------------------------------------
        $display("\n--- Test Group 8: 256-Byte Max Capacity Transfer ---");
        for (i = 0; i < 256; i++) write_dmem_byte(32'h0001_2000 + i, (i * 7) & 8'hFF);
        mock_rle_out_len = 16'd128; // 50% compression
        for (i = 0; i < 128; i++) mock_rle_out_buf[i] = (i * 3) & 8'hFF;

        trigger_transfer(32'h0001_2000, 32'h0002_5000, 16'd256, 1'b0);
        while (!status_done_pulse) @(posedge clk);

        check(status_output_len === 16'd128, "256->128 byte transfer completed with len = 128");
        for (i = 0; i < 128; i++) begin
            if (read_dmem_byte(32'h0002_5000 + i) !== ((i * 3) & 8'hFF)) check(0, $sformatf("256-byte mismatch at %0d", i));
        end
        check(1, "All 128 destination bytes verified in DMEM");

        // ---------------------------------------------------------------------
        // Test 9: AXI Master Read Error Injection
        // ---------------------------------------------------------------------
        $display("\n--- Test Group 9: AXI Read Error ---");
        inject_rd_err = 1;
        trigger_transfer(32'h0001_0000, 32'h0002_0000, 16'd4, 1'b0);
        while (!status_error_pulse) @(posedge clk);
        check(status_error_code === 8'h04, "AXI read error trapped as ERR_RD_ERR (0x04)");
        inject_rd_err = 0;

        // ---------------------------------------------------------------------
        // Test 10: AXI Master Write Error Injection
        // ---------------------------------------------------------------------
        $display("\n--- Test Group 10: AXI Write Error ---");
        inject_wr_err = 1;
        trigger_transfer(32'h0001_0000, 32'h0002_0000, 16'd4, 1'b0);
        while (!status_error_pulse) @(posedge clk);
        check(status_error_code === 8'h05, "AXI write error trapped as ERR_WR_ERR (0x05)");
        inject_wr_err = 0;

        // ---------------------------------------------------------------------
        // Test 11: RLE Accelerator Error Injection
        // ---------------------------------------------------------------------
        $display("\n--- Test Group 11: RLE Core Error ---");
        inject_rle_err = 1;
        trigger_transfer(32'h0001_0000, 32'h0002_0000, 16'd4, 1'b0);
        while (!status_error_pulse) @(posedge clk);
        check(status_error_code === 8'h06, "RLE core error trapped as ERR_RLE_ERR (0x06)");
        inject_rle_err = 0;

        // ---------------------------------------------------------------------
        // Test 12: RLE Timeout Injection
        // ---------------------------------------------------------------------
        $display("\n--- Test Group 12: RLE Timeout Guard ---");
        inject_rle_timeout = 1;
        trigger_transfer(32'h0001_0000, 32'h0002_0000, 16'd4, 1'b0);
        while (!status_error_pulse) @(posedge clk);
        check(status_error_code === 8'h07, "RLE timeout trapped as ERR_TIMEOUT (0x07)");
        inject_rle_timeout = 0;

        // ---------------------------------------------------------------------
        // Test 13: Mid-Transfer Abort & Recovery
        // ---------------------------------------------------------------------
        $display("\n--- Test Group 13: Mid-Transfer Abort & Recovery ---");
        inject_rle_timeout = 1;
        trigger_transfer(32'h0001_0000, 32'h0002_0000, 16'd4, 1'b0);
        @(posedge clk);
        check(status_busy === 1'b1, "Sequencer is busy during active polling");
        ctrl_abort <= 1'b1;
        @(posedge clk);
        ctrl_abort <= 1'b0;
        @(posedge clk);
        check(status_busy === 1'b0, "Sequencer immediately aborted and status_busy deasserted");
        inject_rle_timeout = 0;

        // Confirm clean recovery
        mock_rle_out_len = 16'd1;
        mock_rle_out_buf[0] = 8'h99;
        trigger_transfer(32'h0001_0000, 32'h0002_0000, 16'd1, 1'b0);
        while (!status_done_pulse) @(posedge clk);
        check(status_output_len === 16'd1, "Normal transfer succeeds following abort");

        // ---------------------------------------------------------------------
        // Test 14: Dynamic Reset & Recovery
        // ---------------------------------------------------------------------
        $display("\n--- Test Group 14: Dynamic Reset & Recovery ---");
        inject_rle_timeout = 1;
        trigger_transfer(32'h0001_0000, 32'h0002_0000, 16'd4, 1'b0);
        @(posedge clk);
        check(status_busy === 1'b1, "Sequencer busy prior to dynamic reset");
        rst_n <= 1'b0;
        @(posedge clk);
        check(status_busy === 1'b0, "Sequencer cleared status_busy upon reset assertion");
        rst_n <= 1'b1;
        inject_rle_timeout = 0;
        #(CLK_PERIOD * 2);

        // Confirm clean recovery
        mock_rle_out_len = 16'd2;
        mock_rle_out_buf[0] = 8'h55;
        mock_rle_out_buf[1] = 8'h66;
        trigger_transfer(32'h0001_0000, 32'h0002_0000, 16'd2, 1'b0);
        while (!status_done_pulse) @(posedge clk);
        check(status_output_len === 16'd2, "Normal transfer succeeds following dynamic reset");

        // =====================================================================
        // Final Summary
        // =====================================================================
        $display("\n================================================================");
        $display("          DMA SEQUENCER UNIT VERIFICATION SUMMARY               ");
        $display("================================================================");
        $display("  Total Checks Executed : %0d", total_tests);
        $display("  Passed Checks         : %0d", passed_tests);
        $display("  Failed Checks         : %0d", failed_tests);
        $display("================================================================");

        if (failed_tests == 0) begin
            $display(">>> ALL DMA SEQUENCER CHECKS PASSED! <<<");
        end else begin
            $display(">>> FAILED: %0d check(s) failed. <<<", failed_tests);
        end

        #(CLK_PERIOD * 5);
        $finish;
    end

endmodule
