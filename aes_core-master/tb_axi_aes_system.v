// tb_axi_aes_system.v
`timescale 1ns / 1ps
`default_nettype none

module tb_axi_aes_system;

    parameter DATA_WIDTH = 32;
    parameter ADDR_WIDTH = 32;
    parameter ID_WIDTH   = 8;
    parameter STRB_WIDTH = DATA_WIDTH/8;

    //------------------------------------------------------------------
    // Clock & Reset
    //------------------------------------------------------------------
    reg clk = 0;
    reg rst = 1;
    always #5 clk = ~clk;

    initial begin
        rst = 1;
        #50;
        rst = 0;
    end

    //------------------------------------------------------------------
    // Master command interface
    //------------------------------------------------------------------
    reg                     cmd_valid = 0;
    wire                    cmd_ready;
    reg                     cmd_write;
    reg  [ADDR_WIDTH-1:0]   cmd_addr;
    reg  [DATA_WIDTH-1:0]   cmd_wdata;
    reg  [STRB_WIDTH-1:0]   cmd_wstrb = 4'hF;
    wire [DATA_WIDTH-1:0]   cmd_rdata;
    wire                    cmd_done;
    wire [1:0]              cmd_resp;

    //------------------------------------------------------------------
    // AXI between Master <-> Interconnect
    //------------------------------------------------------------------
    wire [ID_WIDTH-1:0]     s_axi_awid;
    wire [ADDR_WIDTH-1:0]   s_axi_awaddr;
    wire [7:0]              s_axi_awlen;
    wire [2:0]              s_axi_awsize;
    wire [1:0]              s_axi_awburst;
    wire                    s_axi_awlock;
    wire [3:0]              s_axi_awcache;
    wire [2:0]              s_axi_awprot;
    wire [3:0]              s_axi_awqos;
    wire                    s_axi_awvalid;
    wire                    s_axi_awready;

    wire [DATA_WIDTH-1:0]   s_axi_wdata;
    wire [STRB_WIDTH-1:0]   s_axi_wstrb;
    wire                    s_axi_wlast;
    wire                    s_axi_wvalid;
    wire                    s_axi_wready;

    wire [ID_WIDTH-1:0]     s_axi_bid;
    wire [1:0]              s_axi_bresp;
    wire                    s_axi_bvalid;
    wire                    s_axi_bready;

    wire [ID_WIDTH-1:0]     s_axi_arid;
    wire [ADDR_WIDTH-1:0]   s_axi_araddr;
    wire [7:0]              s_axi_arlen;
    wire [2:0]              s_axi_arsize;
    wire [1:0]              s_axi_arburst;
    wire                    s_axi_arlock;
    wire [3:0]              s_axi_arcache;
    wire [2:0]              s_axi_arprot;
    wire [3:0]              s_axi_arqos;
    wire                    s_axi_arvalid;
    wire                    s_axi_arready;

    wire [ID_WIDTH-1:0]     s_axi_rid;
    wire [DATA_WIDTH-1:0]   s_axi_rdata;
    wire [1:0]              s_axi_rresp;
    wire                    s_axi_rlast;
    wire                    s_axi_rvalid;
    wire                    s_axi_rready;

    //------------------------------------------------------------------
    // AXI between Interconnect <-> AXI Slave
    //------------------------------------------------------------------
    wire [ID_WIDTH-1:0]     m_axi_awid;
    wire [ADDR_WIDTH-1:0]   m_axi_awaddr;
    wire [7:0]              m_axi_awlen;
    wire [2:0]              m_axi_awsize;
    wire [1:0]              m_axi_awburst;
    wire                    m_axi_awlock;
    wire [3:0]              m_axi_awcache;
    wire [2:0]              m_axi_awprot;
    wire [3:0]              m_axi_awqos;
    wire [3:0]              m_axi_awregion;
    wire                    m_axi_awvalid;
    wire                    m_axi_awready;

    wire [DATA_WIDTH-1:0]   m_axi_wdata;
    wire [STRB_WIDTH-1:0]   m_axi_wstrb;
    wire                    m_axi_wlast;
    wire                    m_axi_wvalid;
    wire                    m_axi_wready;

    wire [ID_WIDTH-1:0]     m_axi_bid;
    wire [1:0]              m_axi_bresp;
    wire                    m_axi_bvalid;
    wire                    m_axi_bready;

    wire [ID_WIDTH-1:0]     m_axi_arid;
    wire [ADDR_WIDTH-1:0]   m_axi_araddr;
    wire [7:0]              m_axi_arlen;
    wire [2:0]              m_axi_arsize;
    wire [1:0]              m_axi_arburst;
    wire                    m_axi_arlock;
    wire [3:0]              m_axi_arcache;
    wire [2:0]              m_axi_arprot;
    wire [3:0]              m_axi_arqos;
    wire [3:0]              m_axi_arregion;
    wire                    m_axi_arvalid;
    wire                    m_axi_arready;

    wire [ID_WIDTH-1:0]     m_axi_rid;
    wire [DATA_WIDTH-1:0]   m_axi_rdata;
    wire [1:0]              m_axi_rresp;
    wire                    m_axi_rlast;
    wire                    m_axi_rvalid;
    wire                    m_axi_rready;

    //------------------------------------------------------------------
    // Simple register bus between axi_slave <-> aes_reg_set
    //------------------------------------------------------------------
    wire [ADDR_WIDTH-1:0]   reg_addr;
    wire [DATA_WIDTH-1:0]   reg_wdata;
    wire [STRB_WIDTH-1:0]   reg_wstrb;
    wire                    reg_wen;
    wire                    reg_ren;
    wire [DATA_WIDTH-1:0]   reg_rdata;

    //------------------------------------------------------------------
    // DUT Instantiations
    //------------------------------------------------------------------

    // 1. AXI Master
    axi_master_simple #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH),
        .ID_WIDTH   (ID_WIDTH)
    ) u_master (
        .clk        (clk),
        .rst        (rst),
        .cmd_valid  (cmd_valid),
        .cmd_ready  (cmd_ready),
        .cmd_write  (cmd_write),
        .cmd_addr   (cmd_addr),
        .cmd_wdata  (cmd_wdata),
        .cmd_wstrb  (cmd_wstrb),
        .cmd_rdata  (cmd_rdata),
        .cmd_done   (cmd_done),
        .cmd_resp   (cmd_resp),

        .m_axi_awid     (s_axi_awid),
        .m_axi_awaddr   (s_axi_awaddr),
        .m_axi_awlen    (s_axi_awlen),
        .m_axi_awsize   (s_axi_awsize),
        .m_axi_awburst  (s_axi_awburst),
        .m_axi_awlock   (s_axi_awlock),
        .m_axi_awcache  (s_axi_awcache),
        .m_axi_awprot   (s_axi_awprot),
        .m_axi_awqos    (s_axi_awqos),
        .m_axi_awvalid  (s_axi_awvalid),
        .m_axi_awready  (s_axi_awready),
        .m_axi_wdata    (s_axi_wdata),
        .m_axi_wstrb    (s_axi_wstrb),
        .m_axi_wlast    (s_axi_wlast),
        .m_axi_wvalid   (s_axi_wvalid),
        .m_axi_wready   (s_axi_wready),
        .m_axi_bid      (s_axi_bid),
        .m_axi_bresp    (s_axi_bresp),
        .m_axi_bvalid   (s_axi_bvalid),
        .m_axi_bready   (s_axi_bready),
        .m_axi_arid     (s_axi_arid),
        .m_axi_araddr   (s_axi_araddr),
        .m_axi_arlen    (s_axi_arlen),
        .m_axi_arsize   (s_axi_arsize),
        .m_axi_arburst  (s_axi_arburst),
        .m_axi_arlock   (s_axi_arlock),
        .m_axi_arcache  (s_axi_arcache),
        .m_axi_arprot   (s_axi_arprot),
        .m_axi_arqos    (s_axi_arqos),
        .m_axi_arvalid  (s_axi_arvalid),
        .m_axi_arready  (s_axi_arready),
        .m_axi_rid      (s_axi_rid),
        .m_axi_rdata    (s_axi_rdata),
        .m_axi_rresp    (s_axi_rresp),
        .m_axi_rlast    (s_axi_rlast),
        .m_axi_rvalid   (s_axi_rvalid),
        .m_axi_rready   (s_axi_rready)
    );

    // 2. AXI Interconnect
    axi_interconnect #(
        .S_COUNT      (1),
        .M_COUNT      (1),
        .DATA_WIDTH   (DATA_WIDTH),
        .ADDR_WIDTH   (ADDR_WIDTH),
        .ID_WIDTH     (ID_WIDTH),
        .M_REGIONS    (1),
        .M_BASE_ADDR  (32'h0000_0000),
        .M_ADDR_WIDTH (32'd16)
    ) u_interconnect (
        .clk (clk),
        .rst (rst),

        .s_axi_awid     (s_axi_awid),
        .s_axi_awaddr   (s_axi_awaddr),
        .s_axi_awlen    (s_axi_awlen),
        .s_axi_awsize   (s_axi_awsize),
        .s_axi_awburst  (s_axi_awburst),
        .s_axi_awlock   (s_axi_awlock),
        .s_axi_awcache  (s_axi_awcache),
        .s_axi_awprot   (s_axi_awprot),
        .s_axi_awqos    (s_axi_awqos),
        .s_axi_awuser   (1'b0),
        .s_axi_awvalid  (s_axi_awvalid),
        .s_axi_awready  (s_axi_awready),
        .s_axi_wdata    (s_axi_wdata),
        .s_axi_wstrb    (s_axi_wstrb),
        .s_axi_wlast    (s_axi_wlast),
        .s_axi_wuser    (1'b0),
        .s_axi_wvalid   (s_axi_wvalid),
        .s_axi_wready   (s_axi_wready),
        .s_axi_bid      (s_axi_bid),
        .s_axi_bresp    (s_axi_bresp),
        .s_axi_buser    (),
        .s_axi_bvalid   (s_axi_bvalid),
        .s_axi_bready   (s_axi_bready),
        .s_axi_arid     (s_axi_arid),
        .s_axi_araddr   (s_axi_araddr),
        .s_axi_arlen    (s_axi_arlen),
        .s_axi_arsize   (s_axi_arsize),
        .s_axi_arburst  (s_axi_arburst),
        .s_axi_arlock   (s_axi_arlock),
        .s_axi_arcache  (s_axi_arcache),
        .s_axi_arprot   (s_axi_arprot),
        .s_axi_arqos    (s_axi_arqos),
        .s_axi_aruser   (1'b0),
        .s_axi_arvalid  (s_axi_arvalid),
        .s_axi_arready  (s_axi_arready),
        .s_axi_rid      (s_axi_rid),
        .s_axi_rdata    (s_axi_rdata),
        .s_axi_rresp    (s_axi_rresp),
        .s_axi_rlast    (s_axi_rlast),
        .s_axi_ruser    (),
        .s_axi_rvalid   (s_axi_rvalid),
        .s_axi_rready   (s_axi_rready),

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
        .m_axi_awuser   (),
        .m_axi_awvalid  (m_axi_awvalid),
        .m_axi_awready  (m_axi_awready),
        .m_axi_wdata    (m_axi_wdata),
        .m_axi_wstrb    (m_axi_wstrb),
        .m_axi_wlast    (m_axi_wlast),
        .m_axi_wuser    (),
        .m_axi_wvalid   (m_axi_wvalid),
        .m_axi_wready   (m_axi_wready),
        .m_axi_bid      (m_axi_bid),
        .m_axi_bresp    (m_axi_bresp),
        .m_axi_buser    (1'b0),
        .m_axi_bvalid   (m_axi_bvalid),
        .m_axi_bready   (m_axi_bready),
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
        .m_axi_aruser   (),
        .m_axi_arvalid  (m_axi_arvalid),
        .m_axi_arready  (m_axi_arready),
        .m_axi_rid      (m_axi_rid),
        .m_axi_rdata    (m_axi_rdata),
        .m_axi_rresp    (m_axi_rresp),
        .m_axi_rlast    (m_axi_rlast),
        .m_axi_ruser    (1'b0),
        .m_axi_rvalid   (m_axi_rvalid),
        .m_axi_rready   (m_axi_rready)
    );

    // 3. Pure AXI Slave
    axi_slave #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH),
        .ID_WIDTH   (ID_WIDTH)
    ) u_axi_slave (
        .clk (clk),
        .rst (rst),

        .s_axi_awid     (m_axi_awid),
        .s_axi_awaddr   (m_axi_awaddr),
        .s_axi_awlen    (m_axi_awlen),
        .s_axi_awsize   (m_axi_awsize),
        .s_axi_awburst  (m_axi_awburst),
        .s_axi_awlock   (m_axi_awlock),
        .s_axi_awcache  (m_axi_awcache),
        .s_axi_awprot   (m_axi_awprot),
        .s_axi_awqos    (m_axi_awqos),
        .s_axi_awvalid  (m_axi_awvalid),
        .s_axi_awready  (m_axi_awready),
        .s_axi_wdata    (m_axi_wdata),
        .s_axi_wstrb    (m_axi_wstrb),
        .s_axi_wlast    (m_axi_wlast),
        .s_axi_wvalid   (m_axi_wvalid),
        .s_axi_wready   (m_axi_wready),
        .s_axi_bid      (m_axi_bid),
        .s_axi_bresp    (m_axi_bresp),
        .s_axi_bvalid   (m_axi_bvalid),
        .s_axi_bready   (m_axi_bready),
        .s_axi_arid     (m_axi_arid),
        .s_axi_araddr   (m_axi_araddr),
        .s_axi_arlen    (m_axi_arlen),
        .s_axi_arsize   (m_axi_arsize),
        .s_axi_arburst  (m_axi_arburst),
        .s_axi_arlock   (m_axi_arlock),
        .s_axi_arcache  (m_axi_arcache),
        .s_axi_arprot   (m_axi_arprot),
        .s_axi_arqos    (m_axi_arqos),
        .s_axi_arvalid  (m_axi_arvalid),
        .s_axi_arready  (m_axi_arready),
        .s_axi_rid      (m_axi_rid),
        .s_axi_rdata    (m_axi_rdata),
        .s_axi_rresp    (m_axi_rresp),
        .s_axi_rlast    (m_axi_rlast),
        .s_axi_rvalid   (m_axi_rvalid),
        .s_axi_rready   (m_axi_rready),

        .reg_addr  (reg_addr),
        .reg_wdata (reg_wdata),
        .reg_wstrb (reg_wstrb),
        .reg_wen   (reg_wen),
        .reg_ren   (reg_ren),
        .reg_rdata (reg_rdata)
    );

    // 4. AES Register Set
    aes_reg_set #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) u_aes_reg_set (
        .clk       (clk),
        .rst       (rst),
        .reg_addr  (reg_addr),
        .reg_wdata (reg_wdata),
        .reg_wstrb (reg_wstrb),
        .reg_wen   (reg_wen),
        .reg_ren   (reg_ren),
        .reg_rdata (reg_rdata)
    );

    //------------------------------------------------------------------
    // Helper tasks
    //------------------------------------------------------------------
    task axi_write(input [31:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            while (!cmd_ready) @(posedge clk);
            cmd_write = 1;
            cmd_addr  = addr;
            cmd_wdata = data;
            cmd_wstrb = 4'hF;
            cmd_valid = 1;
            @(posedge clk);
            cmd_valid = 0;
            while (!cmd_done) @(posedge clk);
            $display("[%0t] WRITE  0x%08X = 0x%08X", $time, addr, data);
        end
    endtask

    task axi_read(input [31:0] addr, output [31:0] data);
        begin
            @(posedge clk);
            while (!cmd_ready) @(posedge clk);
            cmd_write = 0;
            cmd_addr  = addr;
            cmd_valid = 1;
            @(posedge clk);
            cmd_valid = 0;
            while (!cmd_done) @(posedge clk);
            data = cmd_rdata;
            $display("[%0t] READ   0x%08X = 0x%08X", $time, addr, data);
        end
    endtask

    	    //------------------------------------------------------------------
    // Test sequence (clear printing)
    //------------------------------------------------------------------
    reg [31:0]  rdata;
    reg [127:0] key, plaintext, ciphertext, decrypted;

    initial begin
        wait(rst == 0);
        #100;

        $display("\n====================================================");
        $display("          AES AXI System - Clear Test Report");
        $display("====================================================\n");

        //--------------------------------------------------------------
        // 1. Load KEY and PLAINTEXT
        //--------------------------------------------------------------
        key       = 128'h000102030405060708090a0b0c0d0e0f;
        plaintext = 128'h00112233445566778899aabbccddeeff;

        $display(">>> STEP 1: Loading KEY");
        $display("    Addr 0x10 = %h", key[31:0]);
        $display("    Addr 0x14 = %h", key[63:32]);
        $display("    Addr 0x18 = %h", key[95:64]);
        $display("    Addr 0x1C = %h", key[127:96]);
        axi_write(32'h10, key[31:0]);
        axi_write(32'h14, key[63:32]);
        axi_write(32'h18, key[95:64]);
        axi_write(32'h1C, key[127:96]);

        $display("\n>>> STEP 2: Loading PLAINTEXT (Data before encryption)");
        $display("    Addr 0x20 = %h", plaintext[31:0]);
        $display("    Addr 0x24 = %h", plaintext[63:32]);
        $display("    Addr 0x28 = %h", plaintext[95:64]);
        $display("    Addr 0x2C = %h", plaintext[127:96]);
        $display("    Full Plaintext = %h", plaintext);
        axi_write(32'h20, plaintext[31:0]);
        axi_write(32'h24, plaintext[63:32]);
        axi_write(32'h28, plaintext[95:64]);
        axi_write(32'h2C, plaintext[127:96]);

        //--------------------------------------------------------------
        // 2. Start ENCRYPT
        //--------------------------------------------------------------
        $display("\n>>> STEP 3: Starting ENCRYPTION");
        axi_write(32'h00, 32'h0000_0001);   // START=1, DECRYPT=0

        do begin
            #50;
            axi_read(32'h04, rdata);
        end while (rdata[0] == 0);

        //--------------------------------------------------------------
        // 3. Read CIPHERTEXT
        //--------------------------------------------------------------
        $display("\n>>> STEP 4: Reading CIPHERTEXT (Encrypted data)");
        axi_read(32'h30, ciphertext[31:0]);
        axi_read(32'h34, ciphertext[63:32]);
        axi_read(32'h38, ciphertext[95:64]);
        axi_read(32'h3C, ciphertext[127:96]);

        $display("    Addr 0x30 = %h", ciphertext[31:0]);
        $display("    Addr 0x34 = %h", ciphertext[63:32]);
        $display("    Addr 0x38 = %h", ciphertext[95:64]);
        $display("    Addr 0x3C = %h", ciphertext[127:96]);
        $display("    Full Ciphertext = %h", ciphertext);

        //--------------------------------------------------------------
        // 4. Load KEY + CIPHERTEXT for DECRYPT
        //--------------------------------------------------------------
        $display("\n>>> STEP 5: Loading KEY again for decryption");
        axi_write(32'h10, key[31:0]);
        axi_write(32'h14, key[63:32]);
        axi_write(32'h18, key[95:64]);
        axi_write(32'h1C, key[127:96]);

        $display("\n>>> STEP 6: Loading CIPHERTEXT as input");
        axi_write(32'h20, ciphertext[31:0]);
        axi_write(32'h24, ciphertext[63:32]);
        axi_write(32'h28, ciphertext[95:64]);
        axi_write(32'h2C, ciphertext[127:96]);

        //--------------------------------------------------------------
        // 5. Start DECRYPT
        //--------------------------------------------------------------
        $display("\n>>> STEP 7: Starting DECRYPTION");
        axi_write(32'h00, 32'h0000_0003);   // START=1, DECRYPT=1

        do begin
            #50;
            axi_read(32'h04, rdata);
        end while (rdata[0] == 0);

        //--------------------------------------------------------------
        // 6. Read DECRYPTED data
        //--------------------------------------------------------------
        $display("\n>>> STEP 8: Reading DECRYPTED data (Data after decryption)");
        axi_read(32'h30, decrypted[31:0]);
        axi_read(32'h34, decrypted[63:32]);
        axi_read(32'h38, decrypted[95:64]);
        axi_read(32'h3C, decrypted[127:96]);

        $display("    Addr 0x30 = %h", decrypted[31:0]);
        $display("    Addr 0x34 = %h", decrypted[63:32]);
        $display("    Addr 0x38 = %h", decrypted[95:64]);
        $display("    Addr 0x3C = %h", decrypted[127:96]);
        $display("    Full Decrypted  = %h", decrypted);

        //--------------------------------------------------------------
        // 7. Final comparison
        //--------------------------------------------------------------
        $display("\n====================================================");
        $display("                    FINAL RESULT");
        $display("====================================================");
        $display("Plaintext  (before) : %h", plaintext);
        $display("Ciphertext (middle) : %h", ciphertext);
        $display("Decrypted  (after)  : %h", decrypted);

        if (decrypted === plaintext) begin
            $display("\n*** SUCCESS: Decrypted data matches original plaintext ***");
            $display("*** TEST PASSED ***\n");
        end else begin
            $display("\n*** FAILURE: Data does not match ***");
            $display("*** TEST FAILED ***\n");
        end

        #100;
        $finish;
    end

    // Waveform dump (optional)
    initial begin
        $fsdbDumpfile("dump.fsdb");
        $fsdbDumpvars(0, tb_axi_aes_system);
    end

endmodule
`default_nettype wire
