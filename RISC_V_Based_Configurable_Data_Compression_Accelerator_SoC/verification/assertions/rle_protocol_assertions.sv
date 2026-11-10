// =============================================================================
// rle_protocol_assertions.sv — Protocol Checker & Assertions for RLE Accelerator IP
// =============================================================================
// Verifies:
// 1. Reset quiescence (no valid or IRQ signals during active-high reset)
// 2. Mutual exclusivity of BUSY and DONE in status register
// 3. Informational logging when invalid input lengths are driven (negative testing)
// 4. AXI4-Lite slave response protocol compliance & IRQ known value (non-X/Z)
// 5. AW, W, AR, R, B channel valid/payload stability during stalls
// =============================================================================

`timescale 1ns/1ps

module rle_protocol_assertions #(
    parameter string NAME = "RLE_CHECKER",
    parameter int    MAX_BUFFER_DEPTH = 512
)(
    input wire        clk,
    input wire        rst, // Active-high reset

    // Slave AXI-Lite Write Channels
    input wire        s_axi_awvalid,
    input wire        s_axi_awready,
    input wire [31:0] s_axi_awaddr,

    input wire        s_axi_wvalid,
    input wire        s_axi_wready,
    input wire [31:0] s_axi_wdata,
    input wire [3:0]  s_axi_wstrb,

    input wire        s_axi_bvalid,
    input wire        s_axi_bready,
    input wire [1:0]  s_axi_bresp,

    // Slave AXI-Lite Read Channels
    input wire        s_axi_arvalid,
    input wire        s_axi_arready,
    input wire [31:0] s_axi_araddr,

    input wire        s_axi_rvalid,
    input wire        s_axi_rready,
    input wire [31:0] s_axi_rdata,
    input wire [1:0]  s_axi_rresp,

    // Interrupt
    input wire        irq
);

    // Track active read/write address
    reg [31:0] last_read_addr  = 32'hFFFF_FFFF;
    reg [31:0] last_write_addr = 32'hFFFF_FFFF;

    // Previous states for stability
    reg        prev_awvalid = 1'b0;
    reg        prev_awready = 1'b0;
    reg [31:0] prev_awaddr  = 32'h0;

    reg        prev_wvalid  = 1'b0;
    reg        prev_wready  = 1'b0;
    reg [31:0] prev_wdata   = 32'h0;
    reg [3:0]  prev_wstrb   = 4'h0;

    reg        prev_arvalid = 1'b0;
    reg        prev_arready = 1'b0;
    reg [31:0] prev_araddr  = 32'h0;

    reg        prev_rvalid = 1'b0;
    reg        prev_rready = 1'b0;
    reg [31:0] prev_rdata  = 32'h0;
    reg [1:0]  prev_rresp  = 2'b0;

    reg        prev_bvalid = 1'b0;
    reg        prev_bready = 1'b0;
    reg [1:0]  prev_bresp  = 2'b0;

    // Error & warning counters
    int reset_err_count     = 0;
    int mutex_err_count     = 0;
    int config_err_count    = 0; // Kept for API compatibility; negative tests do not count as errors
    int config_warn_count   = 0;
    int resp_err_count      = 0;
    int stability_err_count = 0;

    always @(posedge clk) begin
        if (rst) begin
            prev_awvalid    <= 1'b0;
            prev_awready    <= 1'b0;
            prev_wvalid     <= 1'b0;
            prev_wready     <= 1'b0;
            prev_arvalid    <= 1'b0;
            prev_arready    <= 1'b0;
            prev_rvalid     <= 1'b0;
            prev_rready     <= 1'b0;
            prev_bvalid     <= 1'b0;
            prev_bready     <= 1'b0;
            last_read_addr  <= 32'hFFFF_FFFF;
            last_write_addr <= 32'hFFFF_FFFF;

            // 1. Reset quiescence check (evaluated once clock starts and reset is asserted)
            if ($time > 0) begin
                assert (s_axi_bvalid === 1'b0) else begin
                    $display("[%0t ns] [%s ERROR] s_axi_bvalid asserted during reset!", $time, NAME);
                    reset_err_count++;
                end
                assert (s_axi_rvalid === 1'b0) else begin
                    $display("[%0t ns] [%s ERROR] s_axi_rvalid asserted during reset!", $time, NAME);
                    reset_err_count++;
                end
                assert (irq === 1'b0) else begin
                    $display("[%0t ns] [%s ERROR] irq asserted during reset!", $time, NAME);
                    reset_err_count++;
                end
            end
        end else begin
            assert (!$isunknown({s_axi_bvalid, s_axi_rvalid, irq})) else begin
                $display("[%0t ns] [%s ERROR] Unknown X/Z on s_axi_bvalid/s_axi_rvalid/irq!", $time, NAME);
                resp_err_count++;
            end

            // Track write addresses
            if (s_axi_awvalid && s_axi_awready) begin
                last_write_addr <= s_axi_awaddr;
            end

            // Track read addresses
            if (s_axi_arvalid && s_axi_arready) begin
                last_read_addr <= s_axi_araddr;
            end

            // 2. Mutual exclusivity of BUSY and DONE in status register (Address offset 0x004)
            if (s_axi_rvalid && s_axi_rready) begin
                logic [31:0] active_raddr;
                active_raddr = (s_axi_arvalid && s_axi_arready) ? s_axi_araddr : last_read_addr;

                if (active_raddr[7:0] == 8'h04) begin
                    bit bit_busy;
                    bit bit_done;
                    bit_busy = s_axi_rdata[0];
                    bit_done = s_axi_rdata[1];
                    assert (!(bit_busy && bit_done)) else begin
                        $display("[%0t ns] [%s ERROR] Status register reported both BUSY and DONE asserted! (val=0x%08x)",
                                 $time, NAME, s_axi_rdata);
                        mutex_err_count++;
                    end
                end

                // Response check
                assert (s_axi_rresp != 2'b01) else begin
                    $display("[%0t ns] [%s ERROR] Reserved EXOKAY read response received!", $time, NAME);
                    resp_err_count++;
                end
            end

            // 3. Configuration bounds check (informational only; intentional negative stimulus is legal over AXI4-Lite)
            if (s_axi_wvalid && s_axi_wready) begin
                logic [31:0] active_waddr;
                active_waddr = (s_axi_awvalid && s_axi_awready) ? s_axi_awaddr : last_write_addr;

                // Input Length Register at offset 0x008
                if (active_waddr[7:0] == 8'h08) begin
                    if (s_axi_wdata == 32'd0 || s_axi_wdata > MAX_BUFFER_DEPTH) begin
                        $display("[%0t ns] [%s INFO] Out-of-range input length %0d observed (MAX_BUFFER_DEPTH=%0d)",
                                 $time, NAME, s_axi_wdata, MAX_BUFFER_DEPTH);
                        config_warn_count++;
                    end
                end
            end

            // 4. Response check on write
            if (s_axi_bvalid && s_axi_bready) begin
                assert (s_axi_bresp != 2'b01) else begin
                    $display("[%0t ns] [%s ERROR] Reserved EXOKAY write response received!", $time, NAME);
                    resp_err_count++;
                end
                last_write_addr <= 32'hFFFF_FFFF;
            end

            // 5. Master & slave channel stability during stalls
            if (prev_awvalid && !prev_awready) begin
                assert (s_axi_awvalid == 1'b1 && s_axi_awaddr === prev_awaddr) else begin
                    $display("[%0t ns] [%s ERROR] AWVALID/AWADDR unstable before AWREADY!", $time, NAME);
                    stability_err_count++;
                end
            end

            if (prev_wvalid && !prev_wready) begin
                assert (s_axi_wvalid == 1'b1 && s_axi_wdata === prev_wdata && s_axi_wstrb === prev_wstrb) else begin
                    $display("[%0t ns] [%s ERROR] WVALID/WDATA/WSTRB unstable before WREADY!", $time, NAME);
                    stability_err_count++;
                end
            end

            if (prev_arvalid && !prev_arready) begin
                assert (s_axi_arvalid == 1'b1 && s_axi_araddr === prev_araddr) else begin
                    $display("[%0t ns] [%s ERROR] ARVALID/ARADDR unstable before ARREADY!", $time, NAME);
                    stability_err_count++;
                end
            end

            if (prev_rvalid && !prev_rready) begin
                assert (s_axi_rvalid == 1'b1) else begin
                    $display("[%0t ns] [%s ERROR] RVALID dropped before master ready!", $time, NAME);
                    stability_err_count++;
                end
                assert (s_axi_rdata === prev_rdata && s_axi_rresp === prev_rresp) else begin
                    $display("[%0t ns] [%s ERROR] RDATA/RRESP changed before master ready!", $time, NAME);
                    stability_err_count++;
                end
            end

            if (prev_bvalid && !prev_bready) begin
                assert (s_axi_bvalid == 1'b1) else begin
                    $display("[%0t ns] [%s ERROR] BVALID dropped before master ready!", $time, NAME);
                    stability_err_count++;
                end
                assert (s_axi_bresp === prev_bresp) else begin
                    $display("[%0t ns] [%s ERROR] BRESP changed before master ready!", $time, NAME);
                    stability_err_count++;
                end
            end

            // Latch history
            prev_awvalid <= s_axi_awvalid;
            prev_awready <= s_axi_awready;
            prev_awaddr  <= s_axi_awaddr;
            prev_wvalid  <= s_axi_wvalid;
            prev_wready  <= s_axi_wready;
            prev_wdata   <= s_axi_wdata;
            prev_wstrb   <= s_axi_wstrb;
            prev_arvalid <= s_axi_arvalid;
            prev_arready <= s_axi_arready;
            prev_araddr  <= s_axi_araddr;
            prev_rvalid  <= s_axi_rvalid;
            prev_rready  <= s_axi_rready;
            prev_rdata   <= s_axi_rdata;
            prev_rresp   <= s_axi_rresp;
            prev_bvalid  <= s_axi_bvalid;
            prev_bready  <= s_axi_bready;
            prev_bresp   <= s_axi_bresp;
        end
    end

    function int get_total_assertion_errors();
        return (reset_err_count + mutex_err_count + config_err_count +
                resp_err_count + stability_err_count);
    endfunction

endmodule: rle_protocol_assertions
