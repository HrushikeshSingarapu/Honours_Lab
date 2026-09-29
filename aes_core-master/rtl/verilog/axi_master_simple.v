// axi_master_simple.v  (robust version)
`resetall
`timescale 1ns / 1ps
`default_nettype none

module axi_master_simple #
(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter STRB_WIDTH = (DATA_WIDTH/8),
    parameter ID_WIDTH   = 8
)
(
    input  wire                     clk,
    input  wire                     rst,

    // Command interface
    input  wire                     cmd_valid,
    output reg                      cmd_ready,
    input  wire                     cmd_write,
    input  wire [ADDR_WIDTH-1:0]    cmd_addr,
    input  wire [DATA_WIDTH-1:0]    cmd_wdata,
    input  wire [STRB_WIDTH-1:0]    cmd_wstrb,
    output reg  [DATA_WIDTH-1:0]    cmd_rdata,
    output reg                      cmd_done,
    output reg  [1:0]               cmd_resp,

    // AXI Master
    output reg  [ID_WIDTH-1:0]      m_axi_awid,
    output reg  [ADDR_WIDTH-1:0]    m_axi_awaddr,
    output reg  [7:0]               m_axi_awlen,
    output reg  [2:0]               m_axi_awsize,
    output reg  [1:0]               m_axi_awburst,
    output reg                      m_axi_awlock,
    output reg  [3:0]               m_axi_awcache,
    output reg  [2:0]               m_axi_awprot,
    output reg  [3:0]               m_axi_awqos,
    output reg                      m_axi_awvalid,
    input  wire                     m_axi_awready,

    output reg  [DATA_WIDTH-1:0]    m_axi_wdata,
    output reg  [STRB_WIDTH-1:0]    m_axi_wstrb,
    output reg                      m_axi_wlast,
    output reg                      m_axi_wvalid,
    input  wire                     m_axi_wready,

    input  wire [ID_WIDTH-1:0]      m_axi_bid,
    input  wire [1:0]               m_axi_bresp,
    input  wire                     m_axi_bvalid,
    output reg                      m_axi_bready,

    output reg  [ID_WIDTH-1:0]      m_axi_arid,
    output reg  [ADDR_WIDTH-1:0]    m_axi_araddr,
    output reg  [7:0]               m_axi_arlen,
    output reg  [2:0]               m_axi_arsize,
    output reg  [1:0]               m_axi_arburst,
    output reg                      m_axi_arlock,
    output reg  [3:0]               m_axi_arcache,
    output reg  [2:0]               m_axi_arprot,
    output reg  [3:0]               m_axi_arqos,
    output reg                      m_axi_arvalid,
    input  wire                     m_axi_arready,

    input  wire [ID_WIDTH-1:0]      m_axi_rid,
    input  wire [DATA_WIDTH-1:0]    m_axi_rdata,
    input  wire [1:0]               m_axi_rresp,
    input  wire                     m_axi_rlast,
    input  wire                     m_axi_rvalid,
    output reg                      m_axi_rready
);

localparam S_IDLE  = 3'd0,
           S_WAW   = 3'd1,   // write address
           S_WD    = 3'd2,   // write data
           S_WB    = 3'd3,   // write response
           S_RA    = 3'd4,   // read address
           S_RD    = 3'd5;   // read data

reg [2:0] state;

always @(posedge clk) begin
    if (rst) begin
        state         <= S_IDLE;
        cmd_ready     <= 1'b1;
        cmd_done      <= 1'b0;
        m_axi_awvalid <= 1'b0;
        m_axi_wvalid  <= 1'b0;
        m_axi_bready  <= 1'b0;
        m_axi_arvalid <= 1'b0;
        m_axi_rready  <= 1'b0;
    end else begin
        cmd_done <= 1'b0;

        case (state)
            S_IDLE: begin
                cmd_ready <= 1'b1;
                if (cmd_valid && cmd_ready) begin
                    cmd_ready <= 1'b0;
                    if (cmd_write) begin
                        // prepare write address
                        m_axi_awid    <= 0;
                        m_axi_awaddr  <= cmd_addr;
                        m_axi_awlen   <= 0;
                        m_axi_awsize  <= $clog2(STRB_WIDTH);
                        m_axi_awburst <= 2'b01;
                        m_axi_awlock  <= 0;
                        m_axi_awcache <= 4'b0011;
                        m_axi_awprot  <= 0;
                        m_axi_awqos   <= 0;
                        m_axi_awvalid <= 1'b1;

                        m_axi_wdata   <= cmd_wdata;
                        m_axi_wstrb   <= cmd_wstrb;
                        m_axi_wlast   <= 1'b1;
                        m_axi_wvalid  <= 1'b1;

                        state <= S_WAW;
                    end else begin
                        // prepare read address
                        m_axi_arid    <= 0;
                        m_axi_araddr  <= cmd_addr;
                        m_axi_arlen   <= 0;
                        m_axi_arsize  <= $clog2(STRB_WIDTH);
                        m_axi_arburst <= 2'b01;
                        m_axi_arlock  <= 0;
                        m_axi_arcache <= 4'b0011;
                        m_axi_arprot  <= 0;
                        m_axi_arqos   <= 0;
                        m_axi_arvalid <= 1'b1;
                        state <= S_RA;
                    end
                end
            end

            S_WAW: begin
                if (m_axi_awready) m_axi_awvalid <= 1'b0;
                if (m_axi_wready)  m_axi_wvalid  <= 1'b0;

                if ((~m_axi_awvalid || m_axi_awready) &&
                    (~m_axi_wvalid  || m_axi_wready)) begin
                    m_axi_bready <= 1'b1;
                    state <= S_WB;
                end
            end

            S_WB: begin
                if (m_axi_bvalid && m_axi_bready) begin
                    m_axi_bready <= 1'b0;
                    cmd_resp     <= m_axi_bresp;
                    cmd_done     <= 1'b1;
                    state        <= S_IDLE;
                end
            end

            S_RA: begin
                if (m_axi_arready) begin
                    m_axi_arvalid <= 1'b0;
                    m_axi_rready  <= 1'b1;
                    state <= S_RD;
                end
            end

            S_RD: begin
                if (m_axi_rvalid && m_axi_rready) begin
                    m_axi_rready <= 1'b0;
                    cmd_rdata    <= m_axi_rdata;
                    cmd_resp     <= m_axi_rresp;
                    cmd_done     <= 1'b1;
                    state        <= S_IDLE;
                end
            end
        endcase
    end
end

endmodule
`resetall
