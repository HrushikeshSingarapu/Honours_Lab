// =============================================================================
// axi4_full_protocol_assertions.sv
//
// Passive SystemVerilog Protocol Checker for Full AXI4 Interfaces
// Checks:
//   1. Reset quiescence on response/request valids
//   2. Channel valid & payload stability during stalls (AW, W, B, AR, R)
//   3. Write burst beat count == AWLEN + 1 and exact WLAST framing (decoupled AW/W)
//   4. Read burst beat count == ARLEN + 1 and exact RLAST framing
//   5. Optional in-order BID/RID matching against AWID/ARID
//   6. Transfer size <= bus width, no EXOKAY (2'b01), zero X/Z on valid/resp
// =============================================================================

`timescale 1ns/1ps

module axi4_full_protocol_assertions #(
    parameter string NAME          = "AXI4_CHECKER",
    parameter int    ADDR_WIDTH    = 32,
    parameter int    DATA_WIDTH    = 32,
    parameter int    ID_WIDTH      = 8,
    parameter bit    CHECK_ID      = 1'b1,
    parameter bit    CHECK_RST_MST = 1'b1
)(
    input wire                    clk,
    input wire                    rst_n,

    input wire                    awvalid,
    input wire                    awready,
    input wire [ID_WIDTH-1:0]     awid,
    input wire [ADDR_WIDTH-1:0]   awaddr,
    input wire [7:0]              awlen,
    input wire [2:0]              awsize,
    input wire [1:0]              awburst,
    input wire [2:0]              awprot,

    input wire                    wvalid,
    input wire                    wready,
    input wire [DATA_WIDTH-1:0]   wdata,
    input wire [DATA_WIDTH/8-1:0] wstrb,
    input wire                    wlast,

    input wire                    bvalid,
    input wire                    bready,
    input wire [ID_WIDTH-1:0]     bid,
    input wire [1:0]              bresp,

    input wire                    arvalid,
    input wire                    arready,
    input wire [ID_WIDTH-1:0]     arid,
    input wire [ADDR_WIDTH-1:0]   araddr,
    input wire [7:0]              arlen,
    input wire [2:0]              arsize,
    input wire [1:0]              arburst,
    input wire [2:0]              arprot,

    input wire                    rvalid,
    input wire                    rready,
    input wire [ID_WIDTH-1:0]     rid,
    input wire [DATA_WIDTH-1:0]   rdata,
    input wire [1:0]              rresp,
    input wire                    rlast
);

    localparam int MAX_SIZE = $clog2(DATA_WIDTH / 8);

    typedef struct packed {
        logic [ID_WIDTH-1:0] id;
        logic [7:0]          len;
    } rd_req_t;

    int unsigned awlen_q[$];
    int unsigned wr_done_beats_q[$];
    logic [ID_WIDTH-1:0] awid_q[$];
    rd_req_t ar_q[$];

    int unsigned cur_w_beats = 0;
    int unsigned cur_r_beats = 0;
    int          rst_low_cycles = 0;

    // Stability latches
    reg                    p_awvalid, p_awready;
    reg [ID_WIDTH-1:0]     p_awid;
    reg [ADDR_WIDTH-1:0]   p_awaddr;
    reg [7:0]              p_awlen;
    reg [2:0]              p_awsize;
    reg [1:0]              p_awburst;
    reg [2:0]              p_awprot;

    reg                    p_wvalid, p_wready, p_wlast;
    reg [DATA_WIDTH-1:0]   p_wdata;
    reg [DATA_WIDTH/8-1:0] p_wstrb;

    reg                    p_bvalid, p_bready;
    reg [ID_WIDTH-1:0]     p_bid;
    reg [1:0]              p_bresp;

    reg                    p_arvalid, p_arready;
    reg [ID_WIDTH-1:0]     p_arid;
    reg [ADDR_WIDTH-1:0]   p_araddr;
    reg [7:0]              p_arlen;
    reg [2:0]              p_arsize;
    reg [1:0]              p_arburst;
    reg [2:0]              p_arprot;

    reg                    p_rvalid, p_rready, p_rlast;
    reg [ID_WIDTH-1:0]     p_rid;
    reg [DATA_WIDTH-1:0]   p_rdata;
    reg [1:0]              p_rresp;

    // Error counters
    int reset_err_count     = 0;
    int stability_err_count = 0;
    int burst_err_count     = 0;
    int id_err_count        = 0;
    int resp_err_count      = 0;
    int x_err_count         = 0;

    always @(posedge clk) begin
        if (!rst_n) begin
            p_awvalid <= 1'b0; p_awready <= 1'b0;
            p_wvalid  <= 1'b0; p_wready  <= 1'b0;
            p_bvalid  <= 1'b0; p_bready  <= 1'b0;
            p_arvalid <= 1'b0; p_arready <= 1'b0;
            p_rvalid  <= 1'b0; p_rready  <= 1'b0;

            awlen_q.delete();
            wr_done_beats_q.delete();
            awid_q.delete();
            ar_q.delete();
            cur_w_beats <= 0;
            cur_r_beats <= 0;

            if ($time > 0) begin
                if (rst_low_cycles < 10) rst_low_cycles <= rst_low_cycles + 1;
                if (rst_low_cycles >= 1) begin
                    assert (bvalid === 1'b0 && rvalid === 1'b0) else begin
                        $display("[%0t ns] [%s ERROR] Response VALID asserted during reset!", $time, NAME);
                        reset_err_count++;
                    end
                    if (CHECK_RST_MST) begin
                        assert (awvalid === 1'b0 && wvalid === 1'b0 && arvalid === 1'b0) else begin
                            $display("[%0t ns] [%s ERROR] Master VALID asserted during reset!", $time, NAME);
                            reset_err_count++;
                        end
                    end
                end
            end
        end else begin
            rst_low_cycles <= 0;

            // X/Z checks on control valids
            assert (!$isunknown({awvalid, wvalid, bvalid, arvalid, rvalid})) else begin
                $display("[%0t ns] [%s ERROR] Unknown X/Z on AXI4 VALID signals!", $time, NAME);
                x_err_count++;
            end

            // Channel Stability Checks
            if (p_awvalid && !p_awready) begin
                assert (awvalid == 1'b1 && awaddr === p_awaddr && awlen === p_awlen &&
                        awsize === p_awsize && awburst === p_awburst && awprot === p_awprot &&
                        (!CHECK_ID || awid === p_awid)) else begin
                    $display("[%0t ns] [%s ERROR] AW channel unstable before AWREADY!", $time, NAME);
                    stability_err_count++;
                end
            end

            if (p_wvalid && !p_wready) begin
                assert (wvalid == 1'b1 && wdata === p_wdata && wstrb === p_wstrb && wlast === p_wlast) else begin
                    $display("[%0t ns] [%s ERROR] W channel unstable before WREADY!", $time, NAME);
                    stability_err_count++;
                end
            end

            if (p_bvalid && !p_bready) begin
                assert (bvalid == 1'b1 && bresp === p_bresp && (!CHECK_ID || bid === p_bid)) else begin
                    $display("[%0t ns] [%s ERROR] B channel unstable before BREADY!", $time, NAME);
                    stability_err_count++;
                end
            end

            if (p_arvalid && !p_arready) begin
                assert (arvalid == 1'b1 && araddr === p_araddr && arlen === p_arlen &&
                        arsize === p_arsize && arburst === p_arburst && arprot === p_arprot &&
                        (!CHECK_ID || arid === p_arid)) else begin
                    $display("[%0t ns] [%s ERROR] AR channel unstable before ARREADY!", $time, NAME);
                    stability_err_count++;
                end
            end

            if (p_rvalid && !p_rready) begin
                assert (rvalid == 1'b1 && rdata === p_rdata && rresp === p_rresp &&
                        rlast === p_rlast && (!CHECK_ID || rid === p_rid)) else begin
                    $display("[%0t ns] [%s ERROR] R channel unstable before RREADY!", $time, NAME);
                    stability_err_count++;
                end
            end

            // Transfer attribute legality
            if (awvalid) begin
                assert (awsize <= MAX_SIZE && awburst != 2'b11) else begin
                    $display("[%0t ns] [%s ERROR] Illegal AWSIZE=%0d or AWBURST=%0b!", $time, NAME, awsize, awburst);
                    burst_err_count++;
                end
            end
            if (arvalid) begin
                assert (arsize <= MAX_SIZE && arburst != 2'b11) else begin
                    $display("[%0t ns] [%s ERROR] Illegal ARSIZE=%0d or ARBURST=%0b!", $time, NAME, arsize, arburst);
                    burst_err_count++;
                end
            end

            // AW & W decoupled burst framing check
            if (awvalid && awready) begin
                awid_q.push_back(awid);
                if (wr_done_beats_q.size() > 0) begin
                    automatic int unsigned got_beats = wr_done_beats_q.pop_front();
                    assert (got_beats == (awlen + 1)) else begin
                        $display("[%0t ns] [%s ERROR] Pre-sent W burst beats (%0d) != AWLEN+1 (%0d)!",
                                 $time, NAME, got_beats, awlen + 1);
                        burst_err_count++;
                    end
                end else begin
                    awlen_q.push_back(awlen);
                end
            end

            if (wvalid && wready) begin
                automatic int unsigned next_beats = cur_w_beats + 1;
                if (wlast) begin
                    if (awlen_q.size() > 0) begin
                        automatic int unsigned exp_len = awlen_q.pop_front();
                        assert (next_beats == (exp_len + 1)) else begin
                            $display("[%0t ns] [%s ERROR] WLAST after %0d beats != AWLEN+1 (%0d)!",
                                     $time, NAME, next_beats, exp_len + 1);
                            burst_err_count++;
                        end
                    end else begin
                        wr_done_beats_q.push_back(next_beats);
                    end
                    cur_w_beats <= 0;
                end else begin
                    cur_w_beats <= next_beats;
                end
            end

            // Write Response check
            if (bvalid && bready) begin
                assert (!$isunknown(bresp) && bresp !== 2'b01) else begin
                    $display("[%0t ns] [%s ERROR] Illegal/X BRESP=0x%0h!", $time, NAME, bresp);
                    resp_err_count++;
                end
                if (awid_q.size() == 0) begin
                    $display("[%0t ns] [%s ERROR] Spurious BVALID without preceding AW handshake!", $time, NAME);
                    burst_err_count++;
                end else begin
                    automatic logic [ID_WIDTH-1:0] exp_bid = awid_q.pop_front();
                    if (CHECK_ID) begin
                        assert (bid === exp_bid) else begin
                            $display("[%0t ns] [%s ERROR] BID=0x%0h != expected AWID=0x%0h!", $time, NAME, bid, exp_bid);
                            id_err_count++;
                        end
                    end
                end
            end

            // AR & R burst framing check
            if (arvalid && arready) begin
                rd_req_t req;
                req.id  = arid;
                req.len = arlen;
                ar_q.push_back(req);
            end

            if (rvalid && rready) begin
                assert (!$isunknown(rresp) && rresp !== 2'b01) else begin
                    $display("[%0t ns] [%s ERROR] Illegal/X RRESP=0x%0h!", $time, NAME, rresp);
                    resp_err_count++;
                end
                if (ar_q.size() == 0) begin
                    $display("[%0t ns] [%s ERROR] Spurious RVALID without preceding AR handshake!", $time, NAME);
                    burst_err_count++;
                end else begin
                    automatic rd_req_t cur_req = ar_q[0];
                    if (CHECK_ID) begin
                        assert (rid === cur_req.id) else begin
                            $display("[%0t ns] [%s ERROR] RID=0x%0h != expected ARID=0x%0h!", $time, NAME, rid, cur_req.id);
                            id_err_count++;
                        end
                    end
                    if (cur_r_beats == cur_req.len) begin
                        assert (rlast === 1'b1) else begin
                            $display("[%0t ns] [%s ERROR] RLAST missing on final beat (%0d)!", $time, NAME, cur_r_beats);
                            burst_err_count++;
                        end
                        void'(ar_q.pop_front());
                        cur_r_beats <= 0;
                    end else begin
                        assert (rlast === 1'b0) else begin
                            $display("[%0t ns] [%s ERROR] RLAST asserted early on beat %0d of %0d!",
                                     $time, NAME, cur_r_beats, cur_req.len + 1);
                            burst_err_count++;
                        end
                        cur_r_beats <= cur_r_beats + 1;
                    end
                end
            end

            // Latch history
            p_awvalid <= awvalid; p_awready <= awready;
            p_awid    <= awid;    p_awaddr  <= awaddr;
            p_awlen   <= awlen;   p_awsize  <= awsize;
            p_awburst <= awburst; p_awprot  <= awprot;

            p_wvalid  <= wvalid;  p_wready  <= wready;
            p_wdata   <= wdata;   p_wstrb   <= wstrb;
            p_wlast   <= wlast;

            p_bvalid  <= bvalid;  p_bready  <= bready;
            p_bid     <= bid;     p_bresp   <= bresp;

            p_arvalid <= arvalid; p_arready <= arready;
            p_arid    <= arid;    p_araddr  <= araddr;
            p_arlen   <= arlen;   p_arsize  <= arsize;
            p_arburst <= arburst; p_arprot  <= arprot;

            p_rvalid  <= rvalid;  p_rready  <= rready;
            p_rid     <= rid;     p_rdata   <= rdata;
            p_rresp   <= rresp;   p_rlast   <= rlast;
        end
    end

    function int get_total_assertion_errors();
        return (reset_err_count + stability_err_count + burst_err_count +
                id_err_count + resp_err_count + x_err_count);
    endfunction

endmodule: axi4_full_protocol_assertions
