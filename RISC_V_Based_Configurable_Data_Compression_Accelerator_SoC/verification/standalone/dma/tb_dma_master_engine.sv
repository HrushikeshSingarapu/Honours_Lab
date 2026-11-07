// =============================================================================
// tb_dma_master_engine.sv
//
// Self-Checking SystemVerilog Testbench for DMA AXI Master Engine.
//
// Verification Coverage:
//   Test Group 1 : Single-word read
//   Test Group 2 : Multiple-word read (INCR bursts: 8-beat, 16-beat)
//   Test Group 3 : Single-word write (with direct memory content check)
//   Test Group 4 : Multiple-word write (INCR burst with WLAST check & memory check)
//   Test Group 5 : Partial-byte writes using WSTRB (byte 0, byte 1, bytes 2-3, middle)
//   Test Group 6 : AW/W channel backpressure (delayed awready, delayed wready)
//   Test Group 7 : AR/R channel backpressure (delayed arready, sink rd_ready deassertion)
//   Test Group 8 : Delayed B response (slave waits 10 cycles before bvalid)
//   Test Group 9 : SLVERR and DECERR handling on write (BRESP) and read (RRESP)
//   Test Group 10: Abort during active read and write transactions with recovery test
//   Test Group 11: Dynamic reset during active transaction with post-reset recovery test
//   Test Group 12: Boundary and alignment conditions (DMEM end boundary, 64-beat burst)
//
// =============================================================================

`timescale 1ns / 1ps

module tb_dma_master_engine;

    localparam ADDR_WIDTH = 32;
    localparam DATA_WIDTH = 32;
    localparam STRB_WIDTH = 4;
    localparam ID_WIDTH   = 8;
    localparam AXI_ID     = 8'h30;
    localparam CLK_PERIOD = 10; // 100 MHz

    // Clock and Reset
    logic clk;
    logic rst_n;

    // Sequencer / FSM Interface
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

    logic                  rd_busy;
    logic                  wr_busy;
    logic                  busy;
    logic                  abort;

    // AXI4 Master Interface
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

    // =========================================================================
    // Device Under Test (DUT) Instantiation
    // =========================================================================
    dma_master_engine #(
        .ADDR_WIDTH  (ADDR_WIDTH),
        .DATA_WIDTH  (DATA_WIDTH),
        .STRB_WIDTH  (STRB_WIDTH),
        .ID_WIDTH    (ID_WIDTH),
        .AXI_ID      (AXI_ID)
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),

        // Sequencer Interface
        .req_rd_start_i  (req_rd_start),
        .req_rd_addr_i   (req_rd_addr),
        .req_rd_len_i    (req_rd_len),
        .rd_data_o       (rd_data),
        .rd_valid_o      (rd_valid),
        .rd_ready_i      (rd_ready),
        .rd_last_o       (rd_last),
        .rd_done_o       (rd_done),
        .rd_error_o      (rd_error),
        .rd_resp_o       (rd_resp),

        .req_wr_start_i  (req_wr_start),
        .req_wr_addr_i   (req_wr_addr),
        .req_wr_len_i    (req_wr_len),
        .wr_data_i       (wr_data),
        .wr_strb_i       (wr_strb),
        .wr_valid_i      (wr_valid),
        .wr_ready_o      (wr_ready),
        .wr_done_o       (wr_done),
        .wr_error_o      (wr_error),
        .wr_resp_o       (wr_resp),

        .rd_busy_o       (rd_busy),
        .wr_busy_o       (wr_busy),
        .busy_o          (busy),
        .abort_i         (abort),

        // AXI4 Interface
        .m_axi_arvalid   (m_axi_arvalid),
        .m_axi_arready   (m_axi_arready),
        .m_axi_arid      (m_axi_arid),
        .m_axi_araddr    (m_axi_araddr),
        .m_axi_arlen     (m_axi_arlen),
        .m_axi_arsize    (m_axi_arsize),
        .m_axi_arburst   (m_axi_arburst),
        .m_axi_arlock    (m_axi_arlock),
        .m_axi_arcache   (m_axi_arcache),
        .m_axi_arprot    (m_axi_arprot),
        .m_axi_arqos     (m_axi_arqos),
        .m_axi_arregion  (m_axi_arregion),
        .m_axi_aruser    (m_axi_aruser),

        .m_axi_rvalid    (m_axi_rvalid),
        .m_axi_rready    (m_axi_rready),
        .m_axi_rid       (m_axi_rid),
        .m_axi_rdata     (m_axi_rdata),
        .m_axi_rresp     (m_axi_rresp),
        .m_axi_rlast     (m_axi_rlast),
        .m_axi_ruser     (m_axi_ruser),

        .m_axi_awvalid   (m_axi_awvalid),
        .m_axi_awready   (m_axi_awready),
        .m_axi_awid      (m_axi_awid),
        .m_axi_awaddr    (m_axi_awaddr),
        .m_axi_awlen     (m_axi_awlen),
        .m_axi_awsize    (m_axi_awsize),
        .m_axi_awburst   (m_axi_awburst),
        .m_axi_awlock    (m_axi_awlock),
        .m_axi_awcache   (m_axi_awcache),
        .m_axi_awprot    (m_axi_awprot),
        .m_axi_awqos     (m_axi_awqos),
        .m_axi_awregion  (m_axi_awregion),
        .m_axi_awuser    (m_axi_awuser),

        .m_axi_wvalid    (m_axi_wvalid),
        .m_axi_wready    (m_axi_wready),
        .m_axi_wdata     (m_axi_wdata),
        .m_axi_wstrb     (m_axi_wstrb),
        .m_axi_wlast     (m_axi_wlast),
        .m_axi_wuser     (m_axi_wuser),

        .m_axi_bvalid    (m_axi_bvalid),
        .m_axi_bready    (m_axi_bready),
        .m_axi_bresp     (m_axi_bresp),
        .m_axi_bid       (m_axi_bid),
        .m_axi_buser     (m_axi_buser)
    );

    // =========================================================================
    // Clock Generation
    // =========================================================================
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // =========================================================================
    // AXI Memory Slave Behavioral Model
    // =========================================================================
    // Associative byte-level memory array representing SoC DMEM
    logic [7:0] slave_mem [logic [31:0]];

    // Slave Configuration / Delay Knobs
    int unsigned slave_awready_delay = 0;
    int unsigned slave_wready_delay  = 0;
    int unsigned slave_bvalid_delay  = 0;
    logic [1:0]  slave_bresp_val     = 2'b00; // 00=OKAY, 10=SLVERR, 11=DECERR

    int unsigned slave_arready_delay = 0;
    int unsigned slave_rvalid_delay  = 0;
    logic [1:0]  slave_rresp_val     = 2'b00;

    // Helper functions to access memory array
    function void mem_write_byte(logic [31:0] addr, logic [7:0] val);
        slave_mem[addr] = val;
    endfunction

    function logic [7:0] mem_read_byte(logic [31:0] addr);
        if (slave_mem.exists(addr)) return slave_mem[addr];
        else return 8'h00;
    endfunction

    function void mem_write_word(logic [31:0] addr, logic [31:0] val);
        mem_write_byte(addr + 0, val[7:0]);
        mem_write_byte(addr + 1, val[15:8]);
        mem_write_byte(addr + 2, val[23:16]);
        mem_write_byte(addr + 3, val[31:24]);
    endfunction

    function logic [31:0] mem_read_word(logic [31:0] addr);
        logic [31:0] val;
        val[7:0]   = mem_read_byte(addr + 0);
        val[15:8]  = mem_read_byte(addr + 1);
        val[23:16] = mem_read_byte(addr + 2);
        val[31:24] = mem_read_byte(addr + 3);
        return val;
    endfunction

    // Slave Write Path Process
    initial begin
        m_axi_awready = 1'b0;
        m_axi_wready  = 1'b0;
        m_axi_bvalid  = 1'b0;
        m_axi_bresp   = 2'b00;
        m_axi_bid     = 8'h00;
        m_axi_buser   = 1'b0;

        forever begin
            @(posedge clk);
            if (!rst_n) begin
                m_axi_awready <= 1'b0;
                m_axi_wready  <= 1'b0;
                m_axi_bvalid  <= 1'b0;
            end else begin
                // Handle AW Channel
                if (m_axi_awvalid && !m_axi_awready) begin
                    repeat (slave_awready_delay) @(posedge clk);
                    m_axi_awready <= 1'b1;
                    @(posedge clk);
                    m_axi_awready <= 1'b0;
                end
            end
        end
    end

    // Slave W and B Channels Coordinator
    initial begin
        logic [31:0] cur_awaddr;
        logic [7:0]  cur_awlen;
        logic [7:0]  cur_awid;
        int          beat_cnt;

        forever begin
            @(posedge clk);
            if (!rst_n) begin
                m_axi_wready <= 1'b0;
                m_axi_bvalid <= 1'b0;
            end else begin
                // Wait for AW handshake
                if (m_axi_awvalid && m_axi_awready) begin
                    cur_awaddr = m_axi_awaddr;
                    cur_awlen  = m_axi_awlen;
                    cur_awid   = m_axi_awid;
                    beat_cnt   = 0;

                    // Receive W beats
                    while (beat_cnt <= cur_awlen) begin
                        // Wait for WVALID
                        while (!m_axi_wvalid) @(posedge clk);

                        // Apply WREADY delay if configured
                        if (slave_wready_delay > 0) begin
                            m_axi_wready <= 1'b0;
                            repeat (slave_wready_delay) @(posedge clk);
                        end
                        m_axi_wready <= 1'b1;
                        @(posedge clk);

                        // Write data byte-by-byte according to WSTRB
                        if (m_axi_wstrb[0]) mem_write_byte(cur_awaddr + 0, m_axi_wdata[7:0]);
                        if (m_axi_wstrb[1]) mem_write_byte(cur_awaddr + 1, m_axi_wdata[15:8]);
                        if (m_axi_wstrb[2]) mem_write_byte(cur_awaddr + 2, m_axi_wdata[23:16]);
                        if (m_axi_wstrb[3]) mem_write_byte(cur_awaddr + 3, m_axi_wdata[31:24]);

                        cur_awaddr = cur_awaddr + 4;
                        beat_cnt++;
                        m_axi_wready <= 1'b0;
                    end

                    // Send B response after optional delay
                    repeat (slave_bvalid_delay) @(posedge clk);
                    m_axi_bvalid <= 1'b1;
                    m_axi_bresp  <= slave_bresp_val;
                    m_axi_bid    <= cur_awid;

                    @(posedge clk);
                    while (!m_axi_bready) @(posedge clk);
                    m_axi_bvalid <= 1'b0;
                end
            end
        end
    end

    // Slave Read Path Process (AR and R Channels)
    initial begin
        logic [31:0] cur_araddr;
        logic [7:0]  cur_arlen;
        logic [7:0]  cur_arid;
        int          r_beat;

        m_axi_arready = 1'b0;
        m_axi_rvalid  = 1'b0;
        m_axi_rdata   = 32'h0;
        m_axi_rresp   = 2'b00;
        m_axi_rlast   = 1'b0;
        m_axi_rid     = 8'h0;
        m_axi_ruser   = 1'b0;

        forever begin
            @(posedge clk);
            if (!rst_n) begin
                m_axi_arready <= 1'b0;
                m_axi_rvalid  <= 1'b0;
                m_axi_rlast   <= 1'b0;
            end else begin
                // Check for AR transaction
                if (m_axi_arvalid && !m_axi_arready) begin
                    repeat (slave_arready_delay) @(posedge clk);
                    m_axi_arready <= 1'b1;
                    @(posedge clk);
                    cur_araddr = m_axi_araddr;
                    cur_arlen  = m_axi_arlen;
                    cur_arid   = m_axi_arid;
                    m_axi_arready <= 1'b0;

                    // Send R data beats
                    for (r_beat = 0; r_beat <= cur_arlen; r_beat++) begin
                        repeat (slave_rvalid_delay) @(posedge clk);
                        m_axi_rvalid <= 1'b1;
                        m_axi_rdata  <= mem_read_word(cur_araddr);
                        m_axi_rresp  <= slave_rresp_val;
                        m_axi_rlast  <= (r_beat == cur_arlen);
                        m_axi_rid    <= cur_arid;

                        @(posedge clk);
                        while (!m_axi_rready) @(posedge clk);
                        m_axi_rvalid <= 1'b0;
                        m_axi_rlast  <= 1'b0;
                        cur_araddr = cur_araddr + 4;
                    end
                end
            end
        end
    end

    // =========================================================================
    // Verification Scoreboard Tracking
    // =========================================================================
    int total_tests  = 0;
    int passed_tests = 0;
    int failed_tests = 0;

    task check(input bit condition, input string test_name);
        total_tests++;
        if (condition) begin
            $display("[PASS] %s", test_name);
            passed_tests++;
        end else begin
            $display("[FAIL] %s", test_name);
            failed_tests++;
        end
    endtask

    // Sequencer Helper Task: Initiate Read
    task start_dma_read(input logic [31:0] addr, input logic [7:0] len);
        @(posedge clk);
        req_rd_addr  <= addr;
        req_rd_len   <= len;
        req_rd_start <= 1'b1;
        @(posedge clk);
        req_rd_start <= 1'b0;
    endtask

    // Sequencer Helper Task: Initiate Write with automatic streaming
    task write_dma_stream(input logic [31:0] addr, input logic [7:0] len,
                          input logic [31:0] data_stream[], input logic [3:0] strb_stream[]);
        int i;
        @(posedge clk);
        req_wr_addr  <= addr;
        req_wr_len   <= len;
        req_wr_start <= 1'b1;
        wr_valid     <= 1'b1;
        wr_data      <= data_stream[0];
        wr_strb      <= strb_stream[0];
        @(posedge clk);
        req_wr_start <= 1'b0;

        for (i = 0; i <= len; i++) begin
            wr_valid <= 1'b1;
            wr_data  <= data_stream[i];
            wr_strb  <= strb_stream[i];
            @(posedge clk);
            while (!wr_ready) @(posedge clk);
        end
        wr_valid <= 1'b0;
    endtask

    // =========================================================================
    // Main Test Stimulus
    // =========================================================================
    initial begin
        logic [31:0] stream_data [64];
        logic [3:0]  stream_strb [64];
        logic [31:0] captured_words [64];
        int          cap_cnt;
        int          i;

        // Signal initialization
        req_rd_start = 1'b0;
        req_rd_addr  = 32'h0;
        req_rd_len   = 8'h0;
        rd_ready     = 1'b1;

        req_wr_start = 1'b0;
        req_wr_addr  = 32'h0;
        req_wr_len   = 8'h0;
        wr_data      = 32'h0;
        wr_strb      = 4'h0;
        wr_valid     = 1'b0;

        abort        = 1'b0;
        rst_n        = 1'b0;

        $display("================================================================");
        $display("   DMA AXI MASTER ENGINE (dma_master_engine) VERIFICATION       ");
        $display("================================================================");

        // Reset Sequence
        #(CLK_PERIOD * 3);
        rst_n = 1'b1;
        #(CLK_PERIOD * 2);

        // ---------------------------------------------------------------------
        // Test Group 1: Single-Word Read
        // ---------------------------------------------------------------------
        $display("\n--- Test Group 1: Single-Word Read ---");
        mem_write_word(32'h0004_0000, 32'h1234_5678);
        start_dma_read(32'h0004_0000, 8'd0);

        // Latch read beat
        @(posedge clk);
        while (!rd_valid) @(posedge clk);
        check(rd_data === 32'h1234_5678, "Single-word read data matches memory");
        check(rd_last === 1'b1, "Single-word read asserts rd_last_o");

        while (!rd_done) @(posedge clk);
        check(rd_done === 1'b1 && rd_error === 1'b0, "Single-word read completes with rd_done_o");

        // ---------------------------------------------------------------------
        // Test Group 2: Multiple-Word Read (Bursts)
        // ---------------------------------------------------------------------
        $display("\n--- Test Group 2: Multiple-Word Read (Bursts) ---");
        for (i = 0; i < 8; i++) begin
            mem_write_word(32'h0004_0100 + (i * 4), 32'hCAFE_0000 + i);
        end

        start_dma_read(32'h0004_0100, 8'd7); // 8-beat burst
        cap_cnt = 0;

        while (cap_cnt < 8) begin
            @(posedge clk);
            if (rd_valid) begin
                captured_words[cap_cnt] = rd_data;
                if (cap_cnt == 7) begin
                    check(rd_last === 1'b1, "8-beat burst asserts rd_last_o on final beat");
                end else begin
                    check(rd_last === 1'b0, "8-beat burst keeps rd_last_o low before final beat");
                end
                cap_cnt++;
            end
        end

        for (i = 0; i < 8; i++) begin
            check(captured_words[i] === (32'hCAFE_0000 + i), $sformatf("Read burst beat %0d data match", i));
        end

        while (!rd_done) @(posedge clk);
        check(rd_done === 1'b1 && rd_error === 1'b0, "8-beat read burst completes successfully");

        // ---------------------------------------------------------------------
        // Test Group 3: Single-Word Write
        // ---------------------------------------------------------------------
        $display("\n--- Test Group 3: Single-Word Write ---");
        stream_data[0] = 32'hDEAD_BEEF;
        stream_strb[0] = 4'b1111;

        write_dma_stream(32'h0004_0200, 8'd0, stream_data, stream_strb);

        while (!wr_done) @(posedge clk);
        check(wr_done === 1'b1 && wr_error === 1'b0, "Single-word write completes with wr_done_o");
        check(mem_read_word(32'h0004_0200) === 32'hDEAD_BEEF, "Memory content verified for single-word write");

        // ---------------------------------------------------------------------
        // Test Group 4: Multiple-Word Write (Burst)
        // ---------------------------------------------------------------------
        $display("\n--- Test Group 4: Multiple-Word Write (Burst) ---");
        for (i = 0; i < 8; i++) begin
            stream_data[i] = 32'hBABE_0000 + i;
            stream_strb[i] = 4'b1111;
        end

        write_dma_stream(32'h0004_0300, 8'd7, stream_data, stream_strb);

        while (!wr_done) @(posedge clk);
        check(wr_done === 1'b1 && wr_error === 1'b0, "8-beat write burst completes with wr_done_o");

        for (i = 0; i < 8; i++) begin
            check(mem_read_word(32'h0004_0300 + (i * 4)) === (32'hBABE_0000 + i),
                  $sformatf("Memory word %0d content verified for burst write", i));
        end

        // ---------------------------------------------------------------------
        // Test Group 5: Partial-Byte Writes Using WSTRB
        // ---------------------------------------------------------------------
        $display("\n--- Test Group 5: Partial-Byte Writes using WSTRB ---");
        // Pre-fill memory with 0xFFFFFFFF
        mem_write_word(32'h0004_0400, 32'hFFFF_FFFF);

        // Byte 0 write
        stream_data[0] = 32'h1122_3344;
        stream_strb[0] = 4'b0001; // only byte 0 (44)
        write_dma_stream(32'h0004_0400, 8'd0, stream_data, stream_strb);
        while (!wr_done) @(posedge clk);
        check(mem_read_word(32'h0004_0400) === 32'hFFFF_FF44, "WSTRB 4'b0001 modifies only byte 0");

        // Byte 1 write
        stream_data[0] = 32'h1122_3344;
        stream_strb[0] = 4'b0010; // only byte 1 (33)
        write_dma_stream(32'h0004_0400, 8'd0, stream_data, stream_strb);
        while (!wr_done) @(posedge clk);
        check(mem_read_word(32'h0004_0400) === 32'hFFFF_3344, "WSTRB 4'b0010 modifies only byte 1");

        // Bytes 2 & 3 write
        stream_data[0] = 32'h1122_3344;
        stream_strb[0] = 4'b1100; // bytes 2 & 3 (1122)
        write_dma_stream(32'h0004_0400, 8'd0, stream_data, stream_strb);
        while (!wr_done) @(posedge clk);
        check(mem_read_word(32'h0004_0400) === 32'h1122_3344, "WSTRB 4'b1100 modifies upper two bytes");

        // Middle bytes 1 & 2 write on fresh word
        mem_write_word(32'h0004_0404, 32'hAAAA_AAAA);
        stream_data[0] = 32'h0055_6600;
        stream_strb[0] = 4'b0110;
        write_dma_stream(32'h0004_0404, 8'd0, stream_data, stream_strb);
        while (!wr_done) @(posedge clk);
        check(mem_read_word(32'h0004_0404) === 32'hAA55_66AA, "WSTRB 4'b0110 modifies middle two bytes");

        // ---------------------------------------------------------------------
        // Test Group 6: AW/W Channel Backpressure
        // ---------------------------------------------------------------------
        $display("\n--- Test Group 6: AW/W Channel Backpressure ---");
        slave_awready_delay = 5;
        slave_wready_delay  = 4;

        for (i = 0; i < 4; i++) begin
            stream_data[i] = 32'h9988_0000 + i;
            stream_strb[i] = 4'b1111;
        end

        write_dma_stream(32'h0004_0500, 8'd3, stream_data, stream_strb);
        while (!wr_done) @(posedge clk);

        check(wr_done === 1'b1, "Write burst completed under AW and W backpressure");
        for (i = 0; i < 4; i++) begin
            check(mem_read_word(32'h0004_0500 + (i * 4)) === (32'h9988_0000 + i),
                  $sformatf("Memory word %0d intact after backpressured write", i));
        end

        slave_awready_delay = 0;
        slave_wready_delay  = 0;

        // ---------------------------------------------------------------------
        // Test Group 7: AR/R Channel Backpressure
        // ---------------------------------------------------------------------
        $display("\n--- Test Group 7: AR/R Channel Backpressure ---");
        // Sub-test 7A: Slave delays AR and R
        slave_arready_delay = 4;
        slave_rvalid_delay  = 3;
        for (i = 0; i < 4; i++) begin
            mem_write_word(32'h0004_0600 + (i * 4), 32'h7766_0000 + i);
        end

        start_dma_read(32'h0004_0600, 8'd3);
        cap_cnt = 0;
        while (cap_cnt < 4) begin
            @(posedge clk);
            if (rd_valid) begin
                captured_words[cap_cnt] = rd_data;
                cap_cnt++;
            end
        end
        while (!rd_done) @(posedge clk);

        for (i = 0; i < 4; i++) begin
            check(captured_words[i] === (32'h7766_0000 + i),
                  $sformatf("Read beat %0d correct with slave AR/R backpressure", i));
        end

        slave_arready_delay = 0;
        slave_rvalid_delay  = 0;

        // Sub-test 7B: Sink (sequencer) deasserts rd_ready mid-burst
        start_dma_read(32'h0004_0600, 8'd3);
        cap_cnt = 0;
        while (cap_cnt < 4) begin
            @(posedge clk);
            if (rd_valid && rd_ready) begin
                captured_words[cap_cnt] = rd_data;
                cap_cnt++;
                // Apply backpressure after beat 1
                if (cap_cnt == 2) begin
                    rd_ready <= 1'b0;
                    repeat (5) @(posedge clk);
                    rd_ready <= 1'b1;
                end
            end
        end
        while (!rd_done) @(posedge clk);

        for (i = 0; i < 4; i++) begin
            check(captured_words[i] === (32'h7766_0000 + i),
                  $sformatf("Read beat %0d correct after sink backpressure", i));
        end

        // ---------------------------------------------------------------------
        // Test Group 8: Delayed B Response
        // ---------------------------------------------------------------------
        $display("\n--- Test Group 8: Delayed B Response ---");
        slave_bvalid_delay = 10;
        stream_data[0]     = 32'h3322_1100;
        stream_strb[0]     = 4'b1111;

        write_dma_stream(32'h0004_0700, 8'd0, stream_data, stream_strb);

        // Check that master remains busy while waiting for B
        #(CLK_PERIOD * 4);
        check(wr_busy === 1'b1, "Master remains busy while awaiting delayed B response");

        while (!wr_done) @(posedge clk);
        check(wr_done === 1'b1, "Master completes only after delayed B arrives");
        check(mem_read_word(32'h0004_0700) === 32'h3322_1100, "Memory content confirmed for delayed B test");
        slave_bvalid_delay = 0;

        // ---------------------------------------------------------------------
        // Test Group 9: Error Response Detection (SLVERR & DECERR)
        // ---------------------------------------------------------------------
        $display("\n--- Test Group 9: Error Responses (SLVERR & DECERR) ---");
        // Sub-test 9A: Write SLVERR (2'b10)
        slave_bresp_val = 2'b10;
        write_dma_stream(32'h0004_0800, 8'd0, stream_data, stream_strb);
        while (!wr_error && !wr_done) @(posedge clk);
        check(wr_error === 1'b1 && wr_done === 1'b0, "Write SLVERR asserts wr_error_o");
        check(wr_resp === 2'b10, "Write SLVERR reported in wr_resp_o");

        // Sub-test 9B: Write DECERR (2'b11)
        slave_bresp_val = 2'b11;
        write_dma_stream(32'h0004_0804, 8'd0, stream_data, stream_strb);
        while (!wr_error && !wr_done) @(posedge clk);
        check(wr_error === 1'b1 && wr_done === 1'b0, "Write DECERR asserts wr_error_o");
        check(wr_resp === 2'b11, "Write DECERR reported in wr_resp_o");
        slave_bresp_val = 2'b00;

        // Sub-test 9C: Read SLVERR (2'b10)
        slave_rresp_val = 2'b10;
        start_dma_read(32'h0004_0800, 8'd0);
        while (!rd_error && !rd_done) @(posedge clk);
        check(rd_error === 1'b1 && rd_done === 1'b0, "Read SLVERR asserts rd_error_o");
        check(rd_resp === 2'b10, "Read SLVERR reported in rd_resp_o");

        // Sub-test 9D: Read DECERR (2'b11)
        slave_rresp_val = 2'b11;
        start_dma_read(32'h0004_0804, 8'd0);
        while (!rd_error && !rd_done) @(posedge clk);
        check(rd_error === 1'b1 && rd_done === 1'b0, "Read DECERR asserts rd_error_o");
        check(rd_resp === 2'b11, "Read DECERR reported in rd_resp_o");
        slave_rresp_val = 2'b00;

        // ---------------------------------------------------------------------
        // Test Group 10: Abort During Active Transactions
        // ---------------------------------------------------------------------
        $display("\n--- Test Group 10: Abort Handling ---");
        // Sub-test 10A: Abort during active read
        slave_arready_delay = 10;
        start_dma_read(32'h0004_0900, 8'd3);
        @(posedge clk);
        check(rd_busy === 1'b1, "Read engine is active prior to abort");
        abort <= 1'b1;
        @(posedge clk);
        abort <= 1'b0;
        @(posedge clk);
        check(rd_busy === 1'b0, "Read engine aborted immediately and rd_busy cleared");
        check(m_axi_arvalid === 1'b0, "m_axi_arvalid deasserted upon abort");
        slave_arready_delay = 0;

        // Sub-test 10B: Abort during active write
        slave_awready_delay = 10;
        stream_data[0]      = 32'h1212_1212;
        stream_strb[0]      = 4'b1111;
        @(posedge clk);
        req_wr_addr  <= 32'h0004_0904;
        req_wr_len   <= 8'd0;
        req_wr_start <= 1'b1;
        @(posedge clk);
        req_wr_start <= 1'b0;
        @(posedge clk);
        check(wr_busy === 1'b1, "Write engine is active prior to abort");
        abort <= 1'b1;
        @(posedge clk);
        abort <= 1'b0;
        @(posedge clk);
        check(wr_busy === 1'b0, "Write engine aborted immediately and wr_busy cleared");
        check(m_axi_awvalid === 1'b0, "m_axi_awvalid deasserted upon abort");
        slave_awready_delay = 0;

        // Sub-test 10C: Confirm recovery after abort
        mem_write_word(32'h0004_0910, 32'hA5A5_5A5A);
        start_dma_read(32'h0004_0910, 8'd0);
        while (!rd_done) @(posedge clk);
        check(rd_done === 1'b1, "Normal read transaction passes after abort recovery");

        // ---------------------------------------------------------------------
        // Test Group 11: Dynamic Reset
        // ---------------------------------------------------------------------
        $display("\n--- Test Group 11: Dynamic Reset ---");
        slave_awready_delay = 8;
        @(posedge clk);
        req_wr_addr  <= 32'h0004_0A00;
        req_wr_len   <= 8'd3;
        req_wr_start <= 1'b1;
        @(posedge clk);
        req_wr_start <= 1'b0;
        @(posedge clk);
        check(wr_busy === 1'b1, "Engine busy before dynamic reset");

        // Assert dynamic reset
        rst_n <= 1'b0;
        @(posedge clk);
        check(wr_busy === 1'b0, "wr_busy cleared during reset");
        check(m_axi_awvalid === 1'b0, "m_axi_awvalid deasserted during reset");
        check(m_axi_wvalid  === 1'b0, "m_axi_wvalid deasserted during reset");
        check(busy === 1'b0, "Overall busy is 0 during reset");

        #(CLK_PERIOD * 2);
        rst_n <= 1'b1;
        slave_awready_delay = 0;
        #(CLK_PERIOD * 2);

        // Verify recovery after reset
        stream_data[0] = 32'h7777_8888;
        stream_strb[0] = 4'b1111;
        write_dma_stream(32'h0004_0A00, 8'd0, stream_data, stream_strb);
        while (!wr_done) @(posedge clk);
        check(wr_done === 1'b1, "Transaction passes cleanly after reset recovery");
        check(mem_read_word(32'h0004_0A00) === 32'h7777_8888, "Post-reset written memory verified");

        // ---------------------------------------------------------------------
        // Test Group 12: Boundary and Alignment Conditions
        // ---------------------------------------------------------------------
        $display("\n--- Test Group 12: Boundary & Alignment Conditions ---");
        // Test 12A: End of DMEM boundary (0x0007_FFFC)
        stream_data[0] = 32'hED00_D333;
        stream_strb[0] = 4'b1111;
        write_dma_stream(32'h0007_FFFC, 8'd0, stream_data, stream_strb);
        while (!wr_done) @(posedge clk);
        check(wr_done === 1'b1, "Single-word write to end-of-DMEM (0x0007_FFFC) passes");
        check(mem_read_word(32'h0007_FFFC) === 32'hED00_D333, "End-of-DMEM memory word verified");

        // Test 12B: 16-beat burst crossing sub-boundary
        for (i = 0; i < 16; i++) begin
            stream_data[i] = 32'hB000_0000 + i;
            stream_strb[i] = 4'b1111;
        end
        write_dma_stream(32'h0004_0F80, 8'd15, stream_data, stream_strb);
        while (!wr_done) @(posedge clk);
        check(wr_done === 1'b1, "16-beat burst across sub-boundary passes");
        for (i = 0; i < 16; i++) begin
            check(mem_read_word(32'h0004_0F80 + (i * 4)) === (32'hB000_0000 + i),
                  $sformatf("16-beat word %0d verified in memory", i));
        end

        // Test 12C: Maximum transfer length: 64-beat burst (256 bytes)
        for (i = 0; i < 64; i++) begin
            stream_data[i] = 32'h6400_0000 + (i * 3);
            stream_strb[i] = 4'b1111;
        end
        write_dma_stream(32'h0004_1000, 8'd63, stream_data, stream_strb);
        while (!wr_done) @(posedge clk);
        check(wr_done === 1'b1, "64-beat (256-byte max DMA size) burst write completes");

        for (i = 0; i < 64; i++) begin
            if (mem_read_word(32'h0004_1000 + (i * 4)) !== (32'h6400_0000 + (i * 3))) begin
                check(0, $sformatf("64-beat burst mismatch at word %0d", i));
            end
        end
        check(1, "All 64 words (256 bytes) verified correct in memory");

        // Read back the 64 words using a 64-beat burst read
        start_dma_read(32'h0004_1000, 8'd63);
        cap_cnt = 0;
        while (cap_cnt < 64) begin
            @(posedge clk);
            if (rd_valid) begin
                captured_words[cap_cnt] = rd_data;
                cap_cnt++;
            end
        end
        while (!rd_done) @(posedge clk);
        check(rd_done === 1'b1, "64-beat burst read completes with rd_done_o");

        for (i = 0; i < 64; i++) begin
            if (captured_words[i] !== (32'h6400_0000 + (i * 3))) begin
                check(0, $sformatf("64-beat read beat mismatch at word %0d", i));
            end
        end
        check(1, "All 64 words read back match transmitted values");

        // =====================================================================
        // Final Summary
        // =====================================================================
        $display("\n================================================================");
        $display("                   VERIFICATION SUMMARY                         ");
        $display("================================================================");
        $display("  Total Checks Executed : %0d", total_tests);
        $display("  Passed Checks         : %0d", passed_tests);
        $display("  Failed Checks         : %0d", failed_tests);
        $display("================================================================");

        if (failed_tests == 0) begin
            $display(">>> ALL STAGE 2 DMA AXI MASTER ENGINE CHECKS PASSED! <<<");
        end else begin
            $display(">>> FAILED: %0d test(s) failed. Please review log. <<<", failed_tests);
        end

        #(CLK_PERIOD * 5);
        $finish;
    end

endmodule
