// =============================================================================
// crc32_top.v
//
// PURPOSE:
//   Synthesizable IEEE 802.3 / ISO-HDLC CRC-32 Acceleration Engine with a
//   32-bit AXI4-Lite slave interface.
//
// ALGORITHM & SPECIFICATION:
//   - Standard: IEEE 802.3 / Ethernet / ISO-HDLC CRC-32
//   - Generator Polynomial: 0x04C11DB7 (reversed: 0xEDB88320)
//   - Initial Accumulator Value: 0xFFFFFFFF (configurable via CRC_INIT)
//   - Input Reflection: Reflected (LSB first, byte-by-byte)
//   - Output Reflection: Reflected
//   - Final XOR: 0xFFFFFFFF
//   - Standard Verification Vector: ASCII "123456789" -> 0xCBF43926
//
// REGISTER MAP (Base: 0x000A_0000, 4 KB Window):
//   Offset 0x00 [WO/RW]: CRC_DATA   - Word/subword write feeds byte(s) into CRC
//   Offset 0x04 [RO]   : CRC_RESULT - Current calculated reflected CRC-32 value
//   Offset 0x08 [RW]   : CRC_CTRL   - Bit 0: re-init to CRC_INIT & clear byte count
//   Offset 0x0C [RO]   : CRC_STATUS - [15:0]: byte_count, [0]: busy (always 0)
//   Offset 0x10 [RW]   : CRC_INIT   - Configurable initial seed (default 0xFFFFFFFF)
//   Unmapped offsets   : Return SLVERR (2'b10) on write and read without bus deadlock
//
// AXI4-LITE BUS PROTOCOL:
//   - Fully decoupled AW and W handshakes (AW-before-W, W-before-AW, simultaneous)
//   - Single-cycle ready pulses (awready, wready, arready)
//   - Compliant response holding on bvalid/bready and rvalid/rready
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module crc32_top #(
    parameter integer ADDR_WIDTH = 32,
    parameter integer DATA_WIDTH = 32,
    parameter integer STRB_WIDTH = DATA_WIDTH / 8
)(
    // Global Clock & Reset
    input  wire                  clk,
    input  wire                  rst_n,      // Active-low asynchronous/synchronous reset

    // AXI4-Lite Write Address Channel
    input  wire [ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire [2:0]            s_axi_awprot,
    input  wire                  s_axi_awvalid,
    output reg                   s_axi_awready,

    // AXI4-Lite Write Data Channel
    input  wire [DATA_WIDTH-1:0] s_axi_wdata,
    input  wire [STRB_WIDTH-1:0] s_axi_wstrb,
    input  wire                  s_axi_wvalid,
    output reg                   s_axi_wready,

    // AXI4-Lite Write Response Channel
    output reg  [1:0]            s_axi_bresp,
    output reg                   s_axi_bvalid,
    input  wire                  s_axi_bready,

    // AXI4-Lite Read Address Channel
    input  wire [ADDR_WIDTH-1:0] s_axi_araddr,
    input  wire [2:0]            s_axi_arprot,
    input  wire                  s_axi_arvalid,
    output reg                   s_axi_arready,

    // AXI4-Lite Read Data Channel
    output reg  [DATA_WIDTH-1:0] s_axi_rdata,
    output reg  [1:0]            s_axi_rresp,
    output reg                   s_axi_rlast,
    output reg                   s_axi_rvalid,
    input  wire                  s_axi_rready
);

    // =========================================================================
    // Register Offset Definitions (Decoded within lower 12 bits)
    // =========================================================================
    localparam [11:0]
        OFFSET_DATA   = 12'h000,
        OFFSET_RESULT = 12'h004,
        OFFSET_CTRL   = 12'h008,
        OFFSET_STATUS = 12'h00C,
        OFFSET_INIT   = 12'h010;

    localparam [1:0]
        RESP_OKAY   = 2'b00,
        RESP_EXOKAY = 2'b01,
        RESP_SLVERR = 2'b10,
        RESP_DECERR = 2'b11;

    // =========================================================================
    // Core Internal Registers
    // =========================================================================
    reg [31:0] crc_accum;
    reg [15:0] byte_count;
    reg [31:0] crc_init_val;
    reg [31:0] last_wdata;

    // =========================================================================
    // IEEE 802.3 CRC-32 Next-Byte Combinational Function
    // Polynomial: 0xEDB88320 (bit-reversed representation of 0x04C11DB7)
    // Processes 8 bits LSB-first.
    // =========================================================================
    function [31:0] crc32_byte;
        input [31:0] current_crc;
        input [7:0]  data_byte;
        reg   [31:0] c;
        integer      i;
        begin
            c = current_crc ^ {24'h000000, data_byte};
            for (i = 0; i < 8; i = i + 1) begin
                if (c[0])
                    c = (c >> 1) ^ 32'hEDB88320;
                else
                    c = c >> 1;
            end
            crc32_byte = c;
        end
    endfunction

    // =========================================================================
    // Combinational Multi-Byte Strobe Processing Logic
    // =========================================================================
    reg [31:0] next_crc_val;
    reg [2:0]  strobes_active;

    function [31:0] step_crc_word;
        input [31:0] crc_in;
        input [31:0] data_in;
        input [3:0]  strb_in;
        reg   [31:0] c;
        begin
            c = crc_in;
            if (strb_in[0]) c = crc32_byte(c, data_in[7:0]);
            if (strb_in[1]) c = crc32_byte(c, data_in[15:8]);
            if (strb_in[2]) c = crc32_byte(c, data_in[23:16]);
            if (strb_in[3]) c = crc32_byte(c, data_in[31:24]);
            step_crc_word = c;
        end
    endfunction

    function [2:0] count_strobes;
        input [3:0] strb_in;
        begin
            count_strobes = {2'b00, strb_in[0]} +
                            {2'b00, strb_in[1]} +
                            {2'b00, strb_in[2]} +
                            {2'b00, strb_in[3]};
        end
    endfunction

    // =========================================================================
    // AXI4-Lite Write State Machine
    // =========================================================================
    localparam [1:0]
        WR_IDLE      = 2'd0,
        WR_WAIT_DATA = 2'd1,
        WR_WAIT_ADDR = 2'd2,
        WR_RESP      = 2'd3;

    reg [1:0]            wr_state;
    reg [ADDR_WIDTH-1:0] wr_addr_latched;
    reg [DATA_WIDTH-1:0] wr_data_latched;
    reg [STRB_WIDTH-1:0] wr_strb_latched;

    task do_write;
        input [ADDR_WIDTH-1:0] addr;
        input [DATA_WIDTH-1:0] data;
        input [STRB_WIDTH-1:0] strb;
        reg   [11:0]           offset;
        begin
            offset = addr[11:0];
            // Address must be word-aligned
            if (addr[1:0] != 2'b00) begin
                s_axi_bresp <= RESP_SLVERR;
            end else begin
                case (offset)
                    OFFSET_DATA: begin
                        last_wdata  <= data;
                        crc_accum   <= step_crc_word(crc_accum, data, strb);
                        byte_count  <= byte_count + {13'h0000, count_strobes(strb)};
                        s_axi_bresp <= RESP_OKAY;
                    end

                    OFFSET_RESULT: begin
                        // Read-only register: write ignored with OKAY
                        s_axi_bresp <= RESP_OKAY;
                    end

                    OFFSET_CTRL: begin
                        // Bit 0: Re-seed accumulator to crc_init_val and clear byte count
                        if (strb[0] && data[0]) begin
                            crc_accum  <= crc_init_val;
                            byte_count <= 16'h0000;
                        end
                        s_axi_bresp <= RESP_OKAY;
                    end

                    OFFSET_STATUS: begin
                        // Read-only register: write ignored with OKAY
                        s_axi_bresp <= RESP_OKAY;
                    end

                    OFFSET_INIT: begin
                        // Custom initial seed value
                        if (strb[0]) crc_init_val[7:0]   <= data[7:0];
                        if (strb[1]) crc_init_val[15:8]  <= data[15:8];
                        if (strb[2]) crc_init_val[23:16] <= data[23:16];
                        if (strb[3]) crc_init_val[31:24] <= data[31:24];
                        s_axi_bresp <= RESP_OKAY;
                    end

                    default: begin
                        // Unmapped offset inside 4 KB window: return SLVERR cleanly
                        s_axi_bresp <= RESP_SLVERR;
                    end
                endcase
            end
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state        <= WR_IDLE;
            s_axi_awready   <= 1'b0;
            s_axi_wready    <= 1'b0;
            s_axi_bvalid    <= 1'b0;
            s_axi_bresp     <= RESP_OKAY;
            wr_addr_latched <= {ADDR_WIDTH{1'b0}};
            wr_data_latched <= {DATA_WIDTH{1'b0}};
            wr_strb_latched <= {STRB_WIDTH{1'b0}};
            crc_accum       <= 32'hFFFFFFFF;
            byte_count      <= 16'h0000;
            crc_init_val    <= 32'hFFFFFFFF;
            last_wdata      <= 32'h00000000;
        end else begin
            case (wr_state)
                WR_IDLE: begin
                    if (s_axi_awvalid && s_axi_wvalid) begin
                        s_axi_awready <= 1'b1;
                        s_axi_wready  <= 1'b1;
                        do_write(s_axi_awaddr, s_axi_wdata, s_axi_wstrb);
                        s_axi_bvalid  <= 1'b1;
                        wr_state      <= WR_RESP;
                    end else if (s_axi_awvalid) begin
                        s_axi_awready   <= 1'b1;
                        wr_addr_latched <= s_axi_awaddr;
                        wr_state        <= WR_WAIT_DATA;
                    end else if (s_axi_wvalid) begin
                        s_axi_wready    <= 1'b1;
                        wr_data_latched <= s_axi_wdata;
                        wr_strb_latched <= s_axi_wstrb;
                        wr_state        <= WR_WAIT_ADDR;
                    end
                end

                WR_WAIT_DATA: begin
                    s_axi_awready <= 1'b0;
                    if (s_axi_wvalid) begin
                        s_axi_wready <= 1'b1;
                        do_write(wr_addr_latched, s_axi_wdata, s_axi_wstrb);
                        s_axi_bvalid <= 1'b1;
                        wr_state     <= WR_RESP;
                    end
                end

                WR_WAIT_ADDR: begin
                    s_axi_wready <= 1'b0;
                    if (s_axi_awvalid) begin
                        s_axi_awready <= 1'b1;
                        do_write(s_axi_awaddr, wr_data_latched, wr_strb_latched);
                        s_axi_bvalid  <= 1'b1;
                        wr_state      <= WR_RESP;
                    end
                end

                WR_RESP: begin
                    s_axi_awready <= 1'b0;
                    s_axi_wready  <= 1'b0;
                    if (s_axi_bready) begin
                        s_axi_bvalid <= 1'b0;
                        wr_state     <= WR_IDLE;
                    end
                end

                default: begin
                    wr_state <= WR_IDLE;
                end
            endcase
        end
    end

    // =========================================================================
    // AXI4-Lite Read State Machine
    // =========================================================================
    localparam [0:0]
        RD_IDLE = 1'b0,
        RD_RESP = 1'b1;

    reg rd_state;

    task do_read;
        input [ADDR_WIDTH-1:0] addr;
        reg   [11:0]           offset;
        begin
            offset = addr[11:0];
            if (addr[1:0] != 2'b00) begin
                s_axi_rdata <= 32'h00000000;
                s_axi_rresp <= RESP_SLVERR;
            end else begin
                case (offset)
                    OFFSET_DATA: begin
                        s_axi_rdata <= last_wdata;
                        s_axi_rresp <= RESP_OKAY;
                    end

                    OFFSET_RESULT: begin
                        // Reflected and inverted CRC-32 result
                        s_axi_rdata <= crc_accum ^ 32'hFFFFFFFF;
                        s_axi_rresp <= RESP_OKAY;
                    end

                    OFFSET_CTRL: begin
                        s_axi_rdata <= 32'h00000000;
                        s_axi_rresp <= RESP_OKAY;
                    end

                    OFFSET_STATUS: begin
                        // [15:0] = byte count, bit 0 of status = busy (0 = idle)
                        s_axi_rdata <= {16'h0000, byte_count};
                        s_axi_rresp <= RESP_OKAY;
                    end

                    OFFSET_INIT: begin
                        s_axi_rdata <= crc_init_val;
                        s_axi_rresp <= RESP_OKAY;
                    end

                    default: begin
                        s_axi_rdata <= 32'h00000000;
                        s_axi_rresp <= RESP_SLVERR;
                    end
                endcase
            end
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state      <= RD_IDLE;
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rlast   <= 1'b0;
            s_axi_rdata   <= {DATA_WIDTH{1'b0}};
            s_axi_rresp   <= RESP_OKAY;
        end else begin
            case (rd_state)
                RD_IDLE: begin
                    if (s_axi_arvalid) begin
                        s_axi_arready <= 1'b1;
                        do_read(s_axi_araddr);
                        s_axi_rvalid  <= 1'b1;
                        s_axi_rlast   <= 1'b1;
                        rd_state      <= RD_RESP;
                    end
                end

                RD_RESP: begin
                    s_axi_arready <= 1'b0;
                    if (s_axi_rready) begin
                        s_axi_rvalid <= 1'b0;
                        s_axi_rlast  <= 1'b0;
                        rd_state     <= RD_IDLE;
                    end
                end

                default: begin
                    rd_state <= RD_IDLE;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
