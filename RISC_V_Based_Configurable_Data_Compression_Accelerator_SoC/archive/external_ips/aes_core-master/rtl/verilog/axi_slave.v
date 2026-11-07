// axi_slave.v  (FINAL WORKING VERSION)
`resetall
`timescale 1ns / 1ps
`default_nettype none

module axi_slave #
(
    parameter DATA_WIDTH  = 32,
    parameter ADDR_WIDTH  = 32,
    parameter STRB_WIDTH  = (DATA_WIDTH/8),
    parameter ID_WIDTH    = 8
)
(
    input  wire                     clk,
    input  wire                     rst,

    // AXI Slave interface
    input  wire [ID_WIDTH-1:0]      s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]    s_axi_awaddr,
    input  wire [7:0]               s_axi_awlen,
    input  wire [2:0]               s_axi_awsize,
    input  wire [1:0]               s_axi_awburst,
    input  wire                     s_axi_awlock,
    input  wire [3:0]               s_axi_awcache,
    input  wire [2:0]               s_axi_awprot,
    input  wire [3:0]               s_axi_awqos,
    input  wire                     s_axi_awvalid,
    output reg                      s_axi_awready,

    input  wire [DATA_WIDTH-1:0]    s_axi_wdata,
    input  wire [STRB_WIDTH-1:0]    s_axi_wstrb,
    input  wire                     s_axi_wlast,
    input  wire                     s_axi_wvalid,
    output reg                      s_axi_wready,

    output reg  [ID_WIDTH-1:0]      s_axi_bid,
    output reg  [1:0]               s_axi_bresp,
    output reg                      s_axi_bvalid,
    input  wire                     s_axi_bready,

    input  wire [ID_WIDTH-1:0]      s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]    s_axi_araddr,
    input  wire [7:0]               s_axi_arlen,
    input  wire [2:0]               s_axi_arsize,
    input  wire [1:0]               s_axi_arburst,
    input  wire                     s_axi_arlock,
    input  wire [3:0]               s_axi_arcache,
    input  wire [2:0]               s_axi_arprot,
    input  wire [3:0]               s_axi_arqos,
    input  wire                     s_axi_arvalid,
    output reg                      s_axi_arready,

    output reg  [ID_WIDTH-1:0]      s_axi_rid,
    output reg  [DATA_WIDTH-1:0]    s_axi_rdata,
    output reg  [1:0]               s_axi_rresp,
    output reg                      s_axi_rlast,
    output reg                      s_axi_rvalid,
    input  wire                     s_axi_rready,

    // Simple register interface
    output reg  [ADDR_WIDTH-1:0]    reg_addr,
    output reg  [DATA_WIDTH-1:0]    reg_wdata,
    output reg  [STRB_WIDTH-1:0]    reg_wstrb,
    output reg                      reg_wen,
    output reg                      reg_ren,
    input  wire [DATA_WIDTH-1:0]    reg_rdata
);

reg [ADDR_WIDTH-1:0] awaddr_r;
reg [ID_WIDTH-1:0]   awid_r;
reg                  aw_received, w_received;

//==============================================================
// WRITE CHANNEL
//==============================================================
always @(posedge clk) begin
    if (rst) begin
        s_axi_awready <= 1'b0;
        s_axi_wready  <= 1'b0;
        s_axi_bvalid  <= 1'b0;
        reg_wen       <= 1'b0;
        aw_received   <= 1'b0;
        w_received    <= 1'b0;
    end else begin
        reg_wen <= 1'b0;

        // Address handshake
        if (!aw_received && !s_axi_bvalid) begin
            s_axi_awready <= 1'b1;
            if (s_axi_awvalid && s_axi_awready) begin
                awaddr_r      <= s_axi_awaddr;
                awid_r        <= s_axi_awid;
                s_axi_awready <= 1'b0;
                aw_received   <= 1'b1;
            end
        end else begin
            s_axi_awready <= 1'b0;
        end

        // Data handshake
        if (!w_received && !s_axi_bvalid) begin
            s_axi_wready <= 1'b1;
            if (s_axi_wvalid && s_axi_wready) begin
                reg_addr   <= aw_received ? awaddr_r : s_axi_awaddr;
                reg_wdata  <= s_axi_wdata;
                reg_wstrb  <= s_axi_wstrb;
                reg_wen    <= 1'b1;
                s_axi_wready <= 1'b0;
                w_received <= 1'b1;
            end
        end else begin
            s_axi_wready <= 1'b0;
        end

        // Response
        if (aw_received && w_received && !s_axi_bvalid) begin
            s_axi_bid    <= awid_r;
            s_axi_bresp  <= 2'b00; // OKAY
            s_axi_bvalid <= 1'b1;
            aw_received  <= 1'b0;
            w_received   <= 1'b0;
        end

        if (s_axi_bvalid && s_axi_bready)
            s_axi_bvalid <= 1'b0;
    end
end

//==============================================================
// READ CHANNEL (FIXED)
//==============================================================
reg read_pending;

always @(posedge clk) begin
    if (rst) begin
        s_axi_arready  <= 1'b0;
        s_axi_rvalid   <= 1'b0;
        reg_ren        <= 1'b0;
        read_pending   <= 1'b0;
        s_axi_rlast    <= 1'b1;
        s_axi_rresp    <= 2'b00;
    end else begin
        reg_ren <= 1'b0;

        // Accept address
        if (!read_pending && !s_axi_rvalid) begin
            s_axi_arready <= 1'b1;
            if (s_axi_arvalid && s_axi_arready) begin
                reg_addr      <= s_axi_araddr;
                reg_ren       <= 1'b1;          // request data this cycle
                s_axi_rid     <= s_axi_arid;
                s_axi_arready <= 1'b0;
                read_pending  <= 1'b1;
            end
        end else begin
            s_axi_arready <= 1'b0;
        end

        // One cycle later the data is ready → assert RVALID
        if (read_pending) begin
            s_axi_rdata  <= reg_rdata;         // capture the data
            s_axi_rvalid <= 1'b1;
            read_pending <= 1'b0;
        end

        if (s_axi_rvalid && s_axi_rready)
            s_axi_rvalid <= 1'b0;
    end
end

endmodule
`resetall
