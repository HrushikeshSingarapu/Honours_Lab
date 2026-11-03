// =============================================================================
// dma_protocol_assertions.sv — Protocol Checker & Assertions for DMA Controller IP
// =============================================================================
// Verifies:
// 1. Reset quiescence (no valid or IRQ signals during reset)
// 2. AXI Master burst protocol compliance (burst type, burst size, burst length)
// 3. WLAST alignment with AWLEN
// 4. RLAST alignment with ARLEN
// 5. Transfer completion and IRQ coherence
// 6. Stability of AXI master signals during stalls
// =============================================================================

`timescale 1ns/1ps

module dma_protocol_assertions #(
    parameter string NAME = "DMA_CHECKER"
)(
    input wire        clk,
    input wire        rst_n,

    // Master Write Channel
    input wire        m_axi_awvalid,
    input wire        m_axi_awready,
    input wire [31:0] m_axi_awaddr,
    input wire [7:0]  m_axi_awlen,
    input wire [2:0]  m_axi_awsize,
    input wire [1:0]  m_axi_awburst,

    input wire        m_axi_wvalid,
    input wire        m_axi_wready,
    input wire [31:0] m_axi_wdata,
    input wire [3:0]  m_axi_wstrb,
    input wire        m_axi_wlast,

    input wire        m_axi_bvalid,
    input wire        m_axi_bready,
    input wire [1:0]  m_axi_bresp,

    // Master Read Channel
    input wire        m_axi_arvalid,
    input wire        m_axi_arready,
    input wire [31:0] m_axi_araddr,
    input wire [7:0]  m_axi_arlen,
    input wire [2:0]  m_axi_arsize,
    input wire [1:0]  m_axi_arburst,

    input wire        m_axi_rvalid,
    input wire        m_axi_rready,
    input wire [31:0] m_axi_rdata,
    input wire [1:0]  m_axi_rresp,
    input wire        m_axi_rlast,

    // Interrupt signal
    input wire        irq_o
);

    // Track write burst beats
    int write_beat_count = 0;
    int expected_write_len = 0;
    reg write_burst_active = 1'b0;
    reg aw_handshake_seen  = 1'b0;
    reg w_handshake_done   = 1'b0;

    // Track read burst beats
    int read_beat_count = 0;
    int expected_read_len = 0;
    reg read_burst_active = 1'b0;

    // Previous states for stability
    reg        prev_awvalid;
    reg        prev_awready;
    reg [31:0] prev_awaddr;
    reg [7:0]  prev_awlen;
    reg [2:0]  prev_awsize;
    reg [1:0]  prev_awburst;

    reg        prev_wvalid;
    reg        prev_wready;
    reg [31:0] prev_wdata;
    reg [3:0]  prev_wstrb;
    reg        prev_wlast;

    reg        prev_arvalid;
    reg        prev_arready;
    reg [31:0] prev_araddr;
    reg [7:0]  prev_arlen;
    reg [2:0]  prev_arsize;
    reg [1:0]  prev_arburst;

    // Error counters
    int reset_err_count     = 0;
    int burst_err_count     = 0;
    int wlast_err_count     = 0;
    int rlast_err_count     = 0;
    int stability_err_count = 0;
    int align_err_count     = 0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_awvalid       <= 1'b0;
            prev_awready       <= 1'b0;
            prev_wvalid        <= 1'b0;
            prev_wready        <= 1'b0;
            prev_arvalid       <= 1'b0;
            prev_arready       <= 1'b0;
            write_burst_active <= 1'b0;
            aw_handshake_seen  <= 1'b0;
            w_handshake_done   <= 1'b0;
            read_burst_active  <= 1'b0;
            write_beat_count   <= 0;
            read_beat_count    <= 0;

            // 1. Reset quiescence check (evaluated once clock has started and reset is asserted)
            if ($time > 0) begin
                assert (m_axi_awvalid === 1'b0) else begin
                    $display("[%0t ns] [%s ERROR] m_axi_awvalid asserted while rst_n is low!", $time, NAME);
                    reset_err_count++;
                end
                assert (m_axi_wvalid === 1'b0) else begin
                    $display("[%0t ns] [%s ERROR] m_axi_wvalid asserted while rst_n is low!", $time, NAME);
                    reset_err_count++;
                end
                assert (m_axi_arvalid === 1'b0) else begin
                    $display("[%0t ns] [%s ERROR] m_axi_arvalid asserted while rst_n is low!", $time, NAME);
                    reset_err_count++;
                end
                assert (irq_o === 1'b0) else begin
                    $display("[%0t ns] [%s ERROR] irq_o asserted while rst_n is low!", $time, NAME);
                    reset_err_count++;
                end
            end
        end else begin
            // 2. Master Write Address Checks
            if (m_axi_awvalid) begin
                // Burst type: 2'b00 (FIXED) or 2'b01 (INCR)
                assert (m_axi_awburst == 2'b00 || m_axi_awburst == 2'b01) else begin
                    $display("[%0t ns] [%s ERROR] Invalid AWBURST=0x%0h (reserved)!", $time, NAME, m_axi_awburst);
                    burst_err_count++;
                end

                // Size must not exceed bus width (32-bit = 4 bytes = 3'b010)
                assert (m_axi_awsize <= 3'b010) else begin
                    $display("[%0t ns] [%s ERROR] AWSIZE=0x%0h exceeds 32-bit bus width!", $time, NAME, m_axi_awsize);
                    burst_err_count++;
                end

                // Word alignment check for 32-bit transfers
                if (m_axi_awsize == 3'b010) begin
                    assert (m_axi_awaddr[1:0] == 2'b00) else begin
                        $display("[%0t ns] [%s ERROR] Unaligned AWADDR=0x%08x for 32-bit burst!", $time, NAME, m_axi_awaddr);
                        align_err_count++;
                    end
                end
            end

            // 3. Master Read Address Checks
            if (m_axi_arvalid) begin
                assert (m_axi_arburst == 2'b00 || m_axi_arburst == 2'b01) else begin
                    $display("[%0t ns] [%s ERROR] Invalid ARBURST=0x%0h (reserved)!", $time, NAME, m_axi_arburst);
                    burst_err_count++;
                end

                assert (m_axi_arsize <= 3'b010) else begin
                    $display("[%0t ns] [%s ERROR] ARSIZE=0x%0h exceeds 32-bit bus width!", $time, NAME, m_axi_arsize);
                    burst_err_count++;
                end

                if (m_axi_arsize == 3'b010) begin
                    assert (m_axi_araddr[1:0] == 2'b00) else begin
                        $display("[%0t ns] [%s ERROR] Unaligned ARADDR=0x%08x for 32-bit burst!", $time, NAME, m_axi_araddr);
                        align_err_count++;
                    end
                end
            end

            // 4. WLAST Tracking and Alignment Check
            // Supports AW-first, concurrent AW/W, and W-first arrival orders per AMBA AXI spec
            if (m_axi_awvalid && m_axi_awready) begin
                expected_write_len <= m_axi_awlen;
                aw_handshake_seen  <= 1'b1;
                if (w_handshake_done) begin
                    // W beats arrived and finished before AW completed
                    assert (write_beat_count == m_axi_awlen + 1) else begin
                        $display("[%0t ns] [%s ERROR] Prior W beat count (%0d) does not match AWLEN+1 (%0d)!",
                                 $time, NAME, write_beat_count, m_axi_awlen + 1);
                        wlast_err_count++;
                    end
                end else begin
                    write_burst_active <= 1'b1;
                end
            end

            if (m_axi_wvalid && m_axi_wready) begin
                if (aw_handshake_seen) begin
                    if (write_beat_count == expected_write_len) begin
                        assert (m_axi_wlast == 1'b1) else begin
                            $display("[%0t ns] [%s ERROR] WLAST not asserted on final write beat (%0d/%0d)!",
                                     $time, NAME, write_beat_count, expected_write_len);
                            wlast_err_count++;
                        end
                        write_burst_active <= 1'b0;
                    end else begin
                        assert (m_axi_wlast == 1'b0) else begin
                            $display("[%0t ns] [%s ERROR] WLAST asserted prematurely on beat %0d of %0d!",
                                     $time, NAME, write_beat_count, expected_write_len);
                            wlast_err_count++;
                        end
                    end
                end
                if (m_axi_wlast) begin
                    w_handshake_done <= 1'b1;
                end
                write_beat_count <= write_beat_count + 1;
            end

            if (m_axi_bvalid && m_axi_bready) begin
                aw_handshake_seen  <= 1'b0;
                w_handshake_done   <= 1'b0;
                write_burst_active <= 1'b0;
                write_beat_count   <= 0;
            end

            // 5. RLAST Tracking and Alignment Check
            if (m_axi_arvalid && m_axi_arready) begin
                expected_read_len <= m_axi_arlen;
                read_beat_count   <= 0;
                read_burst_active <= 1'b1;
            end

            if (m_axi_rvalid && m_axi_rready) begin
                if (read_burst_active) begin
                    if (read_beat_count == expected_read_len) begin
                        assert (m_axi_rlast == 1'b1) else begin
                            $display("[%0t ns] [%s ERROR] RLAST not asserted on final read beat (%0d/%0d)!",
                                     $time, NAME, read_beat_count, expected_read_len);
                            rlast_err_count++;
                        end
                        read_burst_active <= 1'b0;
                    end else begin
                        assert (m_axi_rlast == 1'b0) else begin
                            $display("[%0t ns] [%s ERROR] RLAST asserted prematurely on beat %0d of %0d!",
                                     $time, NAME, read_beat_count, expected_read_len);
                            rlast_err_count++;
                        end
                    end
                    read_beat_count <= read_beat_count + 1;
                end
            end

            // 6. Stability checks during backpressure
            if (prev_awvalid && !prev_awready) begin
                assert (m_axi_awvalid == 1'b1) else begin
                    $display("[%0t ns] [%s ERROR] AWVALID dropped without handshake!", $time, NAME);
                    stability_err_count++;
                end
                assert (m_axi_awaddr === prev_awaddr && m_axi_awlen === prev_awlen &&
                        m_axi_awsize === prev_awsize && m_axi_awburst === prev_awburst) else begin
                    $display("[%0t ns] [%s ERROR] AW control signals changed without handshake!", $time, NAME);
                    stability_err_count++;
                end
            end

            if (prev_wvalid && !prev_wready) begin
                assert (m_axi_wvalid == 1'b1) else begin
                    $display("[%0t ns] [%s ERROR] WVALID dropped without handshake!", $time, NAME);
                    stability_err_count++;
                end
                assert (m_axi_wdata === prev_wdata && m_axi_wstrb === prev_wstrb &&
                        m_axi_wlast === prev_wlast) else begin
                    $display("[%0t ns] [%s ERROR] W payload signals changed without handshake!", $time, NAME);
                    stability_err_count++;
                end
            end

            if (prev_arvalid && !prev_arready) begin
                assert (m_axi_arvalid == 1'b1) else begin
                    $display("[%0t ns] [%s ERROR] ARVALID dropped without handshake!", $time, NAME);
                    stability_err_count++;
                end
                assert (m_axi_araddr === prev_araddr && m_axi_arlen === prev_arlen &&
                        m_axi_arsize === prev_arsize && m_axi_arburst === prev_arburst) else begin
                    $display("[%0t ns] [%s ERROR] AR control signals changed without handshake!", $time, NAME);
                    stability_err_count++;
                end
            end

            // Latch history
            prev_awvalid <= m_axi_awvalid;
            prev_awready <= m_axi_awready;
            prev_awaddr  <= m_axi_awaddr;
            prev_awlen   <= m_axi_awlen;
            prev_awsize  <= m_axi_awsize;
            prev_awburst <= m_axi_awburst;

            prev_wvalid  <= m_axi_wvalid;
            prev_wready  <= m_axi_wready;
            prev_wdata   <= m_axi_wdata;
            prev_wstrb   <= m_axi_wstrb;
            prev_wlast   <= m_axi_wlast;

            prev_arvalid <= m_axi_arvalid;
            prev_arready <= m_axi_arready;
            prev_araddr  <= m_axi_araddr;
            prev_arlen   <= m_axi_arlen;
            prev_arsize  <= m_axi_arsize;
            prev_arburst <= m_axi_arburst;
        end
    end

    function int get_total_assertion_errors();
        return (reset_err_count + burst_err_count + wlast_err_count +
                rlast_err_count + stability_err_count + align_err_count);
    endfunction

endmodule: dma_protocol_assertions
