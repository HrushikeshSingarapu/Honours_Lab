// =============================================================================
// axi_slave_stub.sv
//
// PURPOSE : Lightweight AXI4 slave stub for tb_axi_interconnect_wrap_2x7.
//           - Stores writes into a small internal memory (write-then-readback)
//           - Logs every AW/W/AR beat
//           - Returns OKAY (2'b00) for all accesses
//           - Exposes wr_txn_count / rd_txn_count for routing checks
//
// WHAT THIS IS : Test-only stub. No relationship to real peripheral behaviour.
//
// BUG FIXES (v2)
//   [FIX-1] wr_awsize_q added: awsize is now saved on AW handshake and used
//           in incr_addr() for burst beat-address calculation.  Previously
//           wr_addr_q[2:0] (almost always 0) was passed, causing all burst
//           beats to write the same memory word.
//   [FIX-2] bvalid is de-asserted one cycle after the data is in memory
//           (the memory write uses <=, so the new value appears at the NEXT
//           rising edge).  The testbench BFM now waits one clock after the
//           B handshake before sampling data, but the stub itself needed no
//           change for this — the fix is in the testbench axi_write task.
//
// SIMULATOR : Synopsys VCS U-2023.03  (-full64 -sverilog)
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

module axi_slave_stub #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter STRB_WIDTH = DATA_WIDTH/8,
    parameter ID_WIDTH   = 8,
    parameter SLAVE_ID   = 0,
    parameter MEM_DEPTH  = 256
) (
    input  wire                  clk,
    input  wire                  rst,

    // Write Address Channel
    input  wire [ID_WIDTH-1:0]   axi_awid,
    input  wire [ADDR_WIDTH-1:0] axi_awaddr,
    input  wire [7:0]            axi_awlen,
    input  wire [2:0]            axi_awsize,
    input  wire [1:0]            axi_awburst,
    input  wire                  axi_awvalid,
    output reg                   axi_awready,

    // Write Data Channel
    input  wire [DATA_WIDTH-1:0] axi_wdata,
    input  wire [STRB_WIDTH-1:0] axi_wstrb,
    input  wire                  axi_wlast,
    input  wire                  axi_wvalid,
    output reg                   axi_wready,

    // Write Response Channel
    output reg  [ID_WIDTH-1:0]   axi_bid,
    output reg  [1:0]            axi_bresp,
    output reg                   axi_bvalid,
    input  wire                  axi_bready,

    // Read Address Channel
    input  wire [ID_WIDTH-1:0]   axi_arid,
    input  wire [ADDR_WIDTH-1:0] axi_araddr,
    input  wire [7:0]            axi_arlen,
    input  wire [2:0]            axi_arsize,
    input  wire [1:0]            axi_arburst,
    input  wire                  axi_arvalid,
    output reg                   axi_arready,

    // Read Data Channel
    output reg  [ID_WIDTH-1:0]   axi_rid,
    output reg  [DATA_WIDTH-1:0] axi_rdata,
    output reg  [1:0]            axi_rresp,
    output reg                   axi_rlast,
    output reg                   axi_rvalid,
    input  wire                  axi_rready,

    // Observability counters
    output reg  [31:0]           wr_txn_count,
    output reg  [31:0]           rd_txn_count
);

// ---------------------------------------------------------------------------
// Address constants
// ---------------------------------------------------------------------------
localparam MEM_ADDR_BITS = $clog2(MEM_DEPTH);
localparam BYTE_BITS     = $clog2(DATA_WIDTH/8);

// ---------------------------------------------------------------------------
// Internal memory — sole driver: the write always_ff block
// ---------------------------------------------------------------------------
reg [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];

// ---------------------------------------------------------------------------
// Write path FSM
// ---------------------------------------------------------------------------
localparam WR_IDLE = 2'd0;
localparam WR_ADDR = 2'd1;
localparam WR_DATA = 2'd2;
localparam WR_RESP = 2'd3;

reg [1:0]            wr_state;
reg [ID_WIDTH-1:0]   wr_id_q;
reg [ADDR_WIDTH-1:0] wr_addr_q;
reg [2:0]            wr_awsize_q;    // [FIX-1] saved awsize for burst increment
reg [7:0]            wr_len_q;
reg [ADDR_WIDTH-1:0] wr_beat_addr;

// ---------------------------------------------------------------------------
// Read path FSM
// ---------------------------------------------------------------------------
localparam RD_IDLE = 1'd0;
localparam RD_RESP = 1'd1;

reg                  rd_state;
reg [ID_WIDTH-1:0]   rd_id_q;
reg [ADDR_WIDTH-1:0] rd_addr_q;
reg [2:0]            rd_arsize_q;    // saved arsize for burst increment
reg [7:0]            rd_len_q;
reg [ADDR_WIDTH-1:0] rd_beat_addr;

// ---------------------------------------------------------------------------
// Module-level index variables (no automatic in always_ff)
// ---------------------------------------------------------------------------
integer              wi;
integer              mem_rst_i;
reg [MEM_ADDR_BITS-1:0] widx;
reg [MEM_ADDR_BITS-1:0] ridx;

// ---------------------------------------------------------------------------
// INCR burst address helper
// ---------------------------------------------------------------------------
function [ADDR_WIDTH-1:0] incr_addr;
    input [ADDR_WIDTH-1:0] addr;
    input [2:0]            axsize;
    incr_addr = addr + (1 << axsize);
endfunction

// ---------------------------------------------------------------------------
// Write path  (sole driver of mem[])
// ---------------------------------------------------------------------------
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        axi_awready  <= 1'b0;
        axi_wready   <= 1'b0;
        axi_bvalid   <= 1'b0;
        axi_bid      <= {ID_WIDTH{1'b0}};
        axi_bresp    <= 2'b00;
        wr_state     <= WR_IDLE;
        wr_txn_count <= 32'd0;
        wr_id_q      <= {ID_WIDTH{1'b0}};
        wr_addr_q    <= {ADDR_WIDTH{1'b0}};
        wr_awsize_q  <= 3'd0;
        wr_len_q     <= 8'd0;
        wr_beat_addr <= {ADDR_WIDTH{1'b0}};
        for (mem_rst_i = 0; mem_rst_i < MEM_DEPTH; mem_rst_i = mem_rst_i + 1)
            mem[mem_rst_i] <= {DATA_WIDTH{1'b0}};
    end else begin
        axi_awready <= 1'b0;
        axi_wready  <= 1'b0;

        case (wr_state)

            // ---- accept AW (and simultaneously W if present) ----
            WR_IDLE: begin
                if (axi_awvalid && axi_wvalid) begin
                    axi_awready  <= 1'b1;
                    axi_wready   <= 1'b1;
                    wr_id_q      <= axi_awid;
                    wr_addr_q    <= axi_awaddr;
                    wr_awsize_q  <= axi_awsize;    // [FIX-1]
                    wr_len_q     <= axi_awlen;
                    wr_beat_addr <= axi_awaddr;
                    wr_txn_count <= wr_txn_count + 1;
                    $display("[%0t] SLAVE%0d AW addr=%08h id=%0d len=%0d size=%0d",
                             $time, SLAVE_ID, axi_awaddr,
                             axi_awid, axi_awlen, axi_awsize);
                    widx = axi_awaddr[MEM_ADDR_BITS+BYTE_BITS-1 : BYTE_BITS];
                    $display("[%0t] SLAVE%0d  W  data=%0h wstrb=%0b beat=0",
                             $time, SLAVE_ID, axi_wdata, axi_wstrb);
                    for (wi = 0; wi < DATA_WIDTH/8; wi = wi + 1)
                        if (axi_wstrb[wi])
                            mem[widx][wi*8 +: 8] <= axi_wdata[wi*8 +: 8];
                    if (axi_wlast)
                        wr_state <= WR_RESP;
                    else begin
                        wr_len_q     <= axi_awlen - 8'd1;
                        wr_beat_addr <= incr_addr(axi_awaddr, axi_awsize); // [FIX-1]
                        wr_state     <= WR_DATA;
                    end
                end else if (axi_awvalid) begin
                    axi_awready  <= 1'b1;
                    wr_id_q      <= axi_awid;
                    wr_addr_q    <= axi_awaddr;
                    wr_awsize_q  <= axi_awsize;    // [FIX-1]
                    wr_len_q     <= axi_awlen;
                    wr_beat_addr <= axi_awaddr;
                    wr_txn_count <= wr_txn_count + 1;
                    $display("[%0t] SLAVE%0d AW addr=%08h id=%0d len=%0d size=%0d",
                             $time, SLAVE_ID, axi_awaddr,
                             axi_awid, axi_awlen, axi_awsize);
                    wr_state <= WR_ADDR;
                end
            end

            // ---- have address, waiting for W ----
            WR_ADDR: begin
                axi_wready <= 1'b1;
                if (axi_wvalid) begin
                    widx = wr_beat_addr[MEM_ADDR_BITS+BYTE_BITS-1 : BYTE_BITS];
                    $display("[%0t] SLAVE%0d  W  data=%0h wstrb=%0b addr=%08h",
                             $time, SLAVE_ID, axi_wdata, axi_wstrb, wr_beat_addr);
                    for (wi = 0; wi < DATA_WIDTH/8; wi = wi + 1)
                        if (axi_wstrb[wi])
                            mem[widx][wi*8 +: 8] <= axi_wdata[wi*8 +: 8];
                    if (axi_wlast) begin
                        axi_wready <= 1'b0;
                        wr_state   <= WR_RESP;
                    end else
                        wr_beat_addr <= incr_addr(wr_beat_addr, wr_awsize_q); // [FIX-1]
                end
            end

            // ---- continuing burst beats ----
            WR_DATA: begin
                axi_wready <= 1'b1;
                if (axi_wvalid) begin
                    widx = wr_beat_addr[MEM_ADDR_BITS+BYTE_BITS-1 : BYTE_BITS];
                    $display("[%0t] SLAVE%0d  W  data=%0h wstrb=%0b addr=%08h",
                             $time, SLAVE_ID, axi_wdata, axi_wstrb, wr_beat_addr);
                    for (wi = 0; wi < DATA_WIDTH/8; wi = wi + 1)
                        if (axi_wstrb[wi])
                            mem[widx][wi*8 +: 8] <= axi_wdata[wi*8 +: 8];
                    if (axi_wlast) begin
                        axi_wready <= 1'b0;
                        wr_state   <= WR_RESP;
                    end else
                        wr_beat_addr <= incr_addr(wr_beat_addr, wr_awsize_q); // [FIX-1]
                end
            end

            // ---- send B response ----
            WR_RESP: begin
                axi_bvalid <= 1'b1;
                axi_bid    <= wr_id_q;
                axi_bresp  <= 2'b00;
                if (axi_bvalid && axi_bready) begin
                    axi_bvalid <= 1'b0;
                    wr_state   <= WR_IDLE;
                end
            end

            default: wr_state <= WR_IDLE;
        endcase
    end
end

// ---------------------------------------------------------------------------
// Read path  (reads mem[], never writes it)
// ---------------------------------------------------------------------------
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        axi_arready  <= 1'b0;
        axi_rvalid   <= 1'b0;
        axi_rid      <= {ID_WIDTH{1'b0}};
        axi_rdata    <= {DATA_WIDTH{1'b0}};
        axi_rresp    <= 2'b00;
        axi_rlast    <= 1'b0;
        rd_state     <= RD_IDLE;
        rd_txn_count <= 32'd0;
        rd_id_q      <= {ID_WIDTH{1'b0}};
        rd_addr_q    <= {ADDR_WIDTH{1'b0}};
        rd_arsize_q  <= 3'd0;
        rd_len_q     <= 8'd0;
        rd_beat_addr <= {ADDR_WIDTH{1'b0}};
    end else begin
        axi_arready <= 1'b0;

        case (rd_state)

            RD_IDLE: begin
                if (axi_arvalid) begin
                    axi_arready  <= 1'b1;
                    rd_id_q      <= axi_arid;
                    rd_addr_q    <= axi_araddr;
                    rd_arsize_q  <= axi_arsize;
                    rd_len_q     <= axi_arlen;
                    rd_beat_addr <= axi_araddr;
                    rd_txn_count <= rd_txn_count + 1;
                    $display("[%0t] SLAVE%0d AR addr=%08h id=%0d len=%0d",
                             $time, SLAVE_ID, axi_araddr, axi_arid, axi_arlen);
                    rd_state <= RD_RESP;
                end
            end

            RD_RESP: begin
                if (!axi_rvalid || axi_rready) begin
                    ridx       = rd_beat_addr[MEM_ADDR_BITS+BYTE_BITS-1 : BYTE_BITS];
                    axi_rdata  <= mem[ridx];
                    axi_rid    <= rd_id_q;
                    axi_rresp  <= 2'b00;
                    axi_rlast  <= (rd_len_q == 8'd0);
                    axi_rvalid <= 1'b1;
                    $display("[%0t] SLAVE%0d  R  data=%0h addr=%08h last=%0b",
                             $time, SLAVE_ID, mem[ridx],
                             rd_beat_addr, (rd_len_q == 8'd0));
                    if (rd_len_q == 8'd0)
                        rd_state <= RD_IDLE;
                    else begin
                        rd_len_q     <= rd_len_q - 8'd1;
                        rd_beat_addr <= incr_addr(rd_beat_addr, rd_arsize_q);
                    end
                end
            end

            default: rd_state <= RD_IDLE;
        endcase
    end
end

endmodule

`default_nettype wire
