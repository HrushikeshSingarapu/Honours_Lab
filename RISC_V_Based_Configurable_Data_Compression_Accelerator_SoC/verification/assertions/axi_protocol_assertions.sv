// =============================================================================
// axi_protocol_assertions.sv — Reusable AXI4 / AXI4-Lite Protocol Checker & Assertions
// =============================================================================
`timescale 1ns/1ps

module axi_protocol_assertions #(
    parameter string NAME = "AXI_CHECKER"
)(
    input wire        clk,
    input wire        rst_n,

    // Write Address Channel
    input wire        awvalid,
    input wire        awready,
    input wire [31:0] awaddr,
    input wire [2:0]  awprot,

    // Write Data Channel
    input wire        wvalid,
    input wire        wready,
    input wire [31:0] wdata,
    input wire [3:0]  wstrb,

    // Write Response Channel
    input wire        bvalid,
    input wire        bready,
    input wire [1:0]  bresp,

    // Read Address Channel
    input wire        arvalid,
    input wire        arready,
    input wire [31:0] araddr,
    input wire [2:0]  arprot,

    // Read Data Channel
    input wire        rvalid,
    input wire        rready,
    input wire [31:0] rdata,
    input wire [1:0]  rresp
);

    // Track previous states for stability checks
    reg        prev_awvalid;
    reg        prev_awready;
    reg [31:0] prev_awaddr;
    reg [2:0]  prev_awprot;

    reg        prev_wvalid;
    reg        prev_wready;
    reg [31:0] prev_wdata;
    reg [3:0]  prev_wstrb;

    reg        prev_arvalid;
    reg        prev_arready;
    reg [31:0] prev_araddr;
    reg [2:0]  prev_arprot;

    reg        prev_rvalid;
    reg        prev_rready;
    reg [31:0] prev_rdata;
    reg [1:0]  prev_rresp;

    reg        prev_bvalid;
    reg        prev_bready;
    reg [1:0]  prev_bresp;

    int aw_stability_err = 0;
    int w_stability_err  = 0;
    int ar_stability_err = 0;
    int r_stability_err  = 0;
    int b_stability_err  = 0;
    int resp_invalid_err = 0;
    int reset_err        = 0;
    int x_check_err      = 0;
    int rst_low_cycles   = 0;

    always @(posedge clk) begin
        if (!rst_n) begin
            prev_awvalid <= 1'b0;
            prev_awready <= 1'b0;
            prev_wvalid  <= 1'b0;
            prev_wready  <= 1'b0;
            prev_arvalid <= 1'b0;
            prev_arready <= 1'b0;
            prev_rvalid  <= 1'b0;
            prev_rready  <= 1'b0;
            prev_bvalid  <= 1'b0;
            prev_bready  <= 1'b0;
            if ($time > 0) begin
                if (rst_low_cycles < 10) rst_low_cycles <= rst_low_cycles + 1;
                if (rst_low_cycles >= 1) begin
                    assert (bvalid === 1'b0) else begin
                        $display("[%0t ns] [%s ASSERTION ERROR] BVALID asserted while rst_n is low!", $time, NAME);
                        reset_err++;
                    end
                    assert (rvalid === 1'b0) else begin
                        $display("[%0t ns] [%s ASSERTION ERROR] RVALID asserted while rst_n is low!", $time, NAME);
                        reset_err++;
                    end
                end
            end
        end else begin
            rst_low_cycles <= 0;

            assert (!$isunknown({awvalid, wvalid, arvalid, bvalid, rvalid})) else begin
                $display("[%0t ns] [%s ASSERTION ERROR] Unknown X/Z on AXI VALID signals!", $time, NAME);
                x_check_err++;
            end
            // -----------------------------------------------------------------
            // 1. Write Address Channel Stability (A2.2.1)
            // -----------------------------------------------------------------
            if (prev_awvalid && !prev_awready) begin
                assert (awvalid == 1'b1) else begin
                    $display("[%0t ns] [%s ASSERTION ERROR] AWVALID deasserted before AWREADY handshake!", $time, NAME);
                    aw_stability_err++;
                end
                assert (awaddr === prev_awaddr) else begin
                    $display("[%0t ns] [%s ASSERTION ERROR] AWADDR changed while AWVALID was asserted without AWREADY!", $time, NAME);
                    aw_stability_err++;
                end
                assert (awprot === prev_awprot) else begin
                    $display("[%0t ns] [%s ASSERTION ERROR] AWPROT changed while AWVALID was asserted without AWREADY!", $time, NAME);
                    aw_stability_err++;
                end
            end

            // -----------------------------------------------------------------
            // 2. Write Data Channel Stability (A2.2.1)
            // -----------------------------------------------------------------
            if (prev_wvalid && !prev_wready) begin
                assert (wvalid == 1'b1) else begin
                    $display("[%0t ns] [%s ASSERTION ERROR] WVALID deasserted before WREADY handshake!", $time, NAME);
                    w_stability_err++;
                end
                assert (wdata === prev_wdata) else begin
                    $display("[%0t ns] [%s ASSERTION ERROR] WDATA changed while WVALID was asserted without WREADY!", $time, NAME);
                    w_stability_err++;
                end
                assert (wstrb === prev_wstrb) else begin
                    $display("[%0t ns] [%s ASSERTION ERROR] WSTRB changed while WVALID was asserted without WREADY!", $time, NAME);
                    w_stability_err++;
                end
            end

            // -----------------------------------------------------------------
            // 3. Read Address Channel Stability (A2.2.1)
            // -----------------------------------------------------------------
            if (prev_arvalid && !prev_arready) begin
                assert (arvalid == 1'b1) else begin
                    $display("[%0t ns] [%s ASSERTION ERROR] ARVALID deasserted before ARREADY handshake!", $time, NAME);
                    ar_stability_err++;
                end
                assert (araddr === prev_araddr) else begin
                    $display("[%0t ns] [%s ASSERTION ERROR] ARADDR changed while ARVALID was asserted without ARREADY!", $time, NAME);
                    ar_stability_err++;
                end
                assert (arprot === prev_arprot) else begin
                    $display("[%0t ns] [%s ASSERTION ERROR] ARPROT changed while ARVALID was asserted without ARREADY!", $time, NAME);
                    ar_stability_err++;
                end
            end

            // -----------------------------------------------------------------
            // 4. Read Data Channel Stability (A2.2.1)
            // -----------------------------------------------------------------
            if (prev_rvalid && !prev_rready) begin
                assert (rvalid == 1'b1) else begin
                    $display("[%0t ns] [%s ASSERTION ERROR] RVALID deasserted before RREADY handshake!", $time, NAME);
                    r_stability_err++;
                end
                assert (rdata === prev_rdata) else begin
                    $display("[%0t ns] [%s ASSERTION ERROR] RDATA changed while RVALID was asserted without RREADY!", $time, NAME);
                    r_stability_err++;
                end
                assert (rresp === prev_rresp) else begin
                    $display("[%0t ns] [%s ASSERTION ERROR] RRESP changed while RVALID was asserted without RREADY!", $time, NAME);
                    r_stability_err++;
                end
            end

            // -----------------------------------------------------------------
            // 5. Write Response Channel Stability (A2.2.1)
            // -----------------------------------------------------------------
            if (prev_bvalid && !prev_bready) begin
                assert (bvalid == 1'b1) else begin
                    $display("[%0t ns] [%s ASSERTION ERROR] BVALID deasserted before BREADY handshake!", $time, NAME);
                    b_stability_err++;
                end
                assert (bresp === prev_bresp) else begin
                    $display("[%0t ns] [%s ASSERTION ERROR] BRESP changed while BVALID was asserted without BREADY!", $time, NAME);
                    b_stability_err++;
                end
            end

            // -----------------------------------------------------------------
            // 6. Response Code Validity (Must not be reserved 2'b01 EXOKAY)
            // -----------------------------------------------------------------
            if (rvalid && rready) begin
                assert (!$isunknown(rresp) && rresp !== 2'b01) else begin
                    $display("[%0t ns] [%s ASSERTION ERROR] Invalid or X RRESP=0x%0h observed!", $time, NAME, rresp);
                    resp_invalid_err++;
                end
            end

            if (bvalid && bready) begin
                assert (!$isunknown(bresp) && bresp !== 2'b01) else begin
                    $display("[%0t ns] [%s ASSERTION ERROR] Invalid or X BRESP=0x%0h observed!", $time, NAME, bresp);
                    resp_invalid_err++;
                end
            end

            // Latch current states for next cycle evaluation
            prev_awvalid <= awvalid;
            prev_awready <= awready;
            prev_awaddr  <= awaddr;
            prev_awprot  <= awprot;

            prev_wvalid  <= wvalid;
            prev_wready  <= wready;
            prev_wdata   <= wdata;
            prev_wstrb   <= wstrb;

            prev_arvalid <= arvalid;
            prev_arready <= arready;
            prev_araddr  <= araddr;
            prev_arprot  <= arprot;

            prev_rvalid  <= rvalid;
            prev_rready  <= rready;
            prev_rdata   <= rdata;
            prev_rresp   <= rresp;

            prev_bvalid  <= bvalid;
            prev_bready  <= bready;
            prev_bresp   <= bresp;
        end
    end

    function int get_total_assertion_errors();
        return (aw_stability_err + w_stability_err + ar_stability_err +
                r_stability_err + b_stability_err + resp_invalid_err +
                reset_err + x_check_err);
    endfunction

endmodule: axi_protocol_assertions
