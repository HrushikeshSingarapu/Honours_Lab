// =============================================================================
// gpio_top.v
//
// PURPOSE:
//   Synthesizable 32-bit Bidirectional GPIO Controller with AXI4-Lite
//   slave interface, pin synchronization, atomic set/clear/toggle operations,
//   and configurable edge/level interrupt generation.
//
// SPECIFICATION:
//   - 32 general-purpose digital I/O pins (gpio_i, gpio_o, gpio_oe)
//   - 2-stage input synchronizer on gpio_i to prevent metastability
//   - Configurable direction per pin (1 = output, 0 = input)
//   - Atomic set (SET_OUT), clear (CLR_OUT), and toggle (TOG_OUT) registers
//   - Per-pin configurable interrupt triggering:
//     - Type: Level (0) or Edge (1)
//     - Polarity: Active-Low / Falling-Edge (0) or Active-High / Rising-Edge (1)
//     - Sticky interrupt status with Write-1-to-Clear (W1C)
//
// REGISTER MAP (Base: 0x0006_0000, 4 KB Aperture):
//   Offset 0x00 [RO]: DATA_IN  - Synchronized external input values gpio_i[31:0]
//   Offset 0x04 [RW]: DATA_OUT - Output data register driving gpio_o[31:0]
//   Offset 0x08 [RW]: DIR      - Direction control (1=output, 0=input) driving gpio_oe
//   Offset 0x0C [RW]: IRQ_EN   - Interrupt enable mask per pin
//   Offset 0x10 [RW]: IRQ_TYPE - Trigger type (0=level, 1=edge)
//   Offset 0x14 [RW]: IRQ_POL  - Polarity (0=low/falling, 1=high/rising)
//   Offset 0x18 [RW]: IRQ_STAT - Interrupt status (W1C sticky flag)
//   Offset 0x1C [WO]: SET_OUT  - Atomic set: DATA_OUT <= DATA_OUT | WDATA
//   Offset 0x20 [WO]: CLR_OUT  - Atomic clear: DATA_OUT <= DATA_OUT & ~WDATA
//   Offset 0x24 [WO]: TOG_OUT  - Atomic toggle: DATA_OUT <= DATA_OUT ^ WDATA
//   Unmapped offsets           - Return SLVERR (2'b10) without bus deadlock
//
// AXI4-LITE BUS PROTOCOL:
//   - Fully decoupled AW and W handshakes (AW-before-W, W-before-AW, simultaneous)
//   - Single-cycle ready pulses (awready, wready, arready)
//   - Compliant response holding on bvalid/bready and rvalid/rready
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module gpio_top #(
    parameter integer ADDR_WIDTH = 32,
    parameter integer DATA_WIDTH = 32,
    parameter integer STRB_WIDTH = DATA_WIDTH / 8
)(
    // Global Clock & Reset
    input  wire                  clk,
    input  wire                  rst_n,

    // External GPIO Pins
    input  wire [31:0]           gpio_i,       // External input pins
    output wire [31:0]           gpio_o,       // Driven output pins
    output wire [31:0]           gpio_oe,      // Output enable controls
    output wire                  gpio_irq,     // Combined interrupt request pin

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
    // Register Offset Definitions
    // =========================================================================
    localparam [11:0]
        OFFSET_DATA_IN  = 12'h000,
        OFFSET_DATA_OUT = 12'h004,
        OFFSET_DIR      = 12'h008,
        OFFSET_IRQ_EN   = 12'h00C,
        OFFSET_IRQ_TYPE = 12'h010,
        OFFSET_IRQ_POL  = 12'h014,
        OFFSET_IRQ_STAT = 12'h018,
        OFFSET_SET_OUT  = 12'h01C,
        OFFSET_CLR_OUT  = 12'h020,
        OFFSET_TOG_OUT  = 12'h024;

    localparam [1:0]
        RESP_OKAY   = 2'b00,
        RESP_EXOKAY = 2'b01,
        RESP_SLVERR = 2'b10,
        RESP_DECERR = 2'b11;

    // =========================================================================
    // Core Internal Registers
    // =========================================================================
    reg [31:0] data_out_reg;
    reg [31:0] dir_reg;
    reg [31:0] irq_en_reg;
    reg [31:0] irq_type_reg;
    reg [31:0] irq_pol_reg;
    reg [31:0] irq_stat_reg;

    // Pin connections
    assign gpio_o   = data_out_reg;
    assign gpio_oe  = dir_reg;
    assign gpio_irq = |(irq_stat_reg & irq_en_reg);

    // =========================================================================
    // 2-Stage Input Synchronizer & Edge Detection
    // =========================================================================
    reg [31:0] sync_stage0;
    reg [31:0] sync_stage1;
    reg [31:0] sync_prev;

    wire [31:0] pos_edge   =  sync_stage1 & ~sync_prev;
    wire [31:0] neg_edge   = ~sync_stage1 &  sync_prev;
    wire [31:0] level_high =  sync_stage1;
    wire [31:0] level_low  = ~sync_stage1;

    reg [31:0] irq_triggers;
    integer k;
    always @(*) begin
        for (k = 0; k < 32; k = k + 1) begin
            if (irq_type_reg[k]) begin
                // Edge-triggered
                irq_triggers[k] = irq_pol_reg[k] ? pos_edge[k] : neg_edge[k];
            end else begin
                // Level-triggered
                irq_triggers[k] = irq_pol_reg[k] ? level_high[k] : level_low[k];
            end
        end
    end

    // =========================================================================
    // AXI4-Lite Write State Machine & Datapath
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

    // Synchronous GPIO Register & Synchronizer Process
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

            data_out_reg    <= 32'h0000_0000;
            dir_reg         <= 32'h0000_0000; // All inputs by default
            irq_en_reg      <= 32'h0000_0000;
            irq_type_reg    <= 32'h0000_0000;
            irq_pol_reg     <= 32'h0000_0000;
            irq_stat_reg    <= 32'h0000_0000;

            sync_stage0     <= 32'h0000_0000;
            sync_stage1     <= 32'h0000_0000;
            sync_prev       <= 32'h0000_0000;
        end else begin
            // -----------------------------------------------------------------
            // 1. Input Synchronization and Interrupt Sampling
            // -----------------------------------------------------------------
            sync_stage0 <= gpio_i;
            sync_stage1 <= sync_stage0;
            sync_prev   <= sync_stage1;

            // Latch active triggers into sticky status register
            irq_stat_reg <= irq_stat_reg | (irq_triggers & irq_en_reg);

            // -----------------------------------------------------------------
            // 2. AXI Write Channel State Machine
            // -----------------------------------------------------------------
            case (wr_state)
                WR_IDLE: begin
                    if (s_axi_awvalid && s_axi_wvalid) begin
                        s_axi_awready <= 1'b1;
                        s_axi_wready  <= 1'b1;
                        perform_write(s_axi_awaddr, s_axi_wdata, s_axi_wstrb);
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
                        perform_write(wr_addr_latched, s_axi_wdata, s_axi_wstrb);
                        s_axi_bvalid <= 1'b1;
                        wr_state     <= WR_RESP;
                    end
                end

                WR_WAIT_ADDR: begin
                    s_axi_wready <= 1'b0;
                    if (s_axi_awvalid) begin
                        s_axi_awready <= 1'b1;
                        perform_write(s_axi_awaddr, wr_data_latched, wr_strb_latched);
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

    // Helper task to execute register write on bus match
    task perform_write;
        input [ADDR_WIDTH-1:0] addr;
        input [DATA_WIDTH-1:0] data;
        input [STRB_WIDTH-1:0] strb;
        reg   [11:0]           offset;
        begin
            offset = addr[11:0];
            if (addr[1:0] != 2'b00) begin
                s_axi_bresp <= RESP_SLVERR;
            end else begin
                case (offset)
                    OFFSET_DATA_IN: begin
                        // Read-only register
                        s_axi_bresp <= RESP_OKAY;
                    end

                    OFFSET_DATA_OUT: begin
                        if (strb[0]) data_out_reg[7:0]   <= data[7:0];
                        if (strb[1]) data_out_reg[15:8]  <= data[15:8];
                        if (strb[2]) data_out_reg[23:16] <= data[23:16];
                        if (strb[3]) data_out_reg[31:24] <= data[31:24];
                        s_axi_bresp <= RESP_OKAY;
                    end

                    OFFSET_DIR: begin
                        if (strb[0]) dir_reg[7:0]   <= data[7:0];
                        if (strb[1]) dir_reg[15:8]  <= data[15:8];
                        if (strb[2]) dir_reg[23:16] <= data[23:16];
                        if (strb[3]) dir_reg[31:24] <= data[31:24];
                        s_axi_bresp <= RESP_OKAY;
                    end

                    OFFSET_IRQ_EN: begin
                        if (strb[0]) irq_en_reg[7:0]   <= data[7:0];
                        if (strb[1]) irq_en_reg[15:8]  <= data[15:8];
                        if (strb[2]) irq_en_reg[23:16] <= data[23:16];
                        if (strb[3]) irq_en_reg[31:24] <= data[31:24];
                        s_axi_bresp <= RESP_OKAY;
                    end

                    OFFSET_IRQ_TYPE: begin
                        if (strb[0]) irq_type_reg[7:0]   <= data[7:0];
                        if (strb[1]) irq_type_reg[15:8]  <= data[15:8];
                        if (strb[2]) irq_type_reg[23:16] <= data[23:16];
                        if (strb[3]) irq_type_reg[31:24] <= data[31:24];
                        s_axi_bresp <= RESP_OKAY;
                    end

                    OFFSET_IRQ_POL: begin
                        if (strb[0]) irq_pol_reg[7:0]   <= data[7:0];
                        if (strb[1]) irq_pol_reg[15:8]  <= data[15:8];
                        if (strb[2]) irq_pol_reg[23:16] <= data[23:16];
                        if (strb[3]) irq_pol_reg[31:24] <= data[31:24];
                        s_axi_bresp <= RESP_OKAY;
                    end

                    OFFSET_IRQ_STAT: begin
                        // Write-1-to-Clear (W1C)
                        if (strb[0]) irq_stat_reg[7:0]   <= irq_stat_reg[7:0]   & ~data[7:0];
                        if (strb[1]) irq_stat_reg[15:8]  <= irq_stat_reg[15:8]  & ~data[15:8];
                        if (strb[2]) irq_stat_reg[23:16] <= irq_stat_reg[23:16] & ~data[23:16];
                        if (strb[3]) irq_stat_reg[31:24] <= irq_stat_reg[31:24] & ~data[31:24];
                        s_axi_bresp <= RESP_OKAY;
                    end

                    OFFSET_SET_OUT: begin
                        // Atomic set
                        if (strb[0]) data_out_reg[7:0]   <= data_out_reg[7:0]   | data[7:0];
                        if (strb[1]) data_out_reg[15:8]  <= data_out_reg[15:8]  | data[15:8];
                        if (strb[2]) data_out_reg[23:16] <= data_out_reg[23:16] | data[23:16];
                        if (strb[3]) data_out_reg[31:24] <= data_out_reg[31:24] | data[31:24];
                        s_axi_bresp <= RESP_OKAY;
                    end

                    OFFSET_CLR_OUT: begin
                        // Atomic clear
                        if (strb[0]) data_out_reg[7:0]   <= data_out_reg[7:0]   & ~data[7:0];
                        if (strb[1]) data_out_reg[15:8]  <= data_out_reg[15:8]  & ~data[15:8];
                        if (strb[2]) data_out_reg[23:16] <= data_out_reg[23:16] & ~data[23:16];
                        if (strb[3]) data_out_reg[31:24] <= data_out_reg[31:24] & ~data[31:24];
                        s_axi_bresp <= RESP_OKAY;
                    end

                    OFFSET_TOG_OUT: begin
                        // Atomic toggle
                        if (strb[0]) data_out_reg[7:0]   <= data_out_reg[7:0]   ^ data[7:0];
                        if (strb[1]) data_out_reg[15:8]  <= data_out_reg[15:8]  ^ data[15:8];
                        if (strb[2]) data_out_reg[23:16] <= data_out_reg[23:16] ^ data[23:16];
                        if (strb[3]) data_out_reg[31:24] <= data_out_reg[31:24] ^ data[31:24];
                        s_axi_bresp <= RESP_OKAY;
                    end

                    default: begin
                        s_axi_bresp <= RESP_SLVERR;
                    end
                endcase
            end
        end
    endtask

    // =========================================================================
    // AXI4-Lite Read State Machine
    // =========================================================================
    localparam [0:0]
        RD_IDLE = 1'b0,
        RD_RESP = 1'b1;

    reg rd_state;

    task perform_read;
        input [ADDR_WIDTH-1:0] addr;
        reg   [11:0]           offset;
        begin
            offset = addr[11:0];
            if (addr[1:0] != 2'b00) begin
                s_axi_rdata <= 32'h00000000;
                s_axi_rresp <= RESP_SLVERR;
            end else begin
                case (offset)
                    OFFSET_DATA_IN: begin
                        s_axi_rdata <= sync_stage1;
                        s_axi_rresp <= RESP_OKAY;
                    end

                    OFFSET_DATA_OUT: begin
                        s_axi_rdata <= data_out_reg;
                        s_axi_rresp <= RESP_OKAY;
                    end

                    OFFSET_DIR: begin
                        s_axi_rdata <= dir_reg;
                        s_axi_rresp <= RESP_OKAY;
                    end

                    OFFSET_IRQ_EN: begin
                        s_axi_rdata <= irq_en_reg;
                        s_axi_rresp <= RESP_OKAY;
                    end

                    OFFSET_IRQ_TYPE: begin
                        s_axi_rdata <= irq_type_reg;
                        s_axi_rresp <= RESP_OKAY;
                    end

                    OFFSET_IRQ_POL: begin
                        s_axi_rdata <= irq_pol_reg;
                        s_axi_rresp <= RESP_OKAY;
                    end

                    OFFSET_IRQ_STAT: begin
                        s_axi_rdata <= irq_stat_reg;
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
                        perform_read(s_axi_araddr);
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
