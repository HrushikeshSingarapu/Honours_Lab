// =============================================================================
// timer_top.v
//
// PURPOSE:
//   Synthesizable 64-bit RISC-V MTIME/MTIMECMP Timer with a 32-bit AXI4-Lite
//   slave interface and dedicated timer_irq interrupt output.
//
// SPECIFICATION & ARCHITECTURE:
//   - Monotonically incrementing 64-bit real-time counter (mtime)
//   - 64-bit compare threshold register (mtimecmp)
//   - Configurable clock prescaler (increments once every N+1 clock cycles)
//   - Interrupt generation when mtime >= mtimecmp and IRQ_EN is set
//   - Level-sensitive interrupt: clears automatically when mtimecmp > mtime
//   - Optional auto-reload mode (re-arms mtime to 0 upon reaching compare match)
//
// REGISTER MAP (Base: 0x0005_0000, 4 KB Aperture):
//   Offset 0x00 [RW]: MTIME_LOW     - Lower 32 bits of 64-bit counter mtime[31:0]
//   Offset 0x04 [RW]: MTIME_HIGH    - Upper 32 bits of 64-bit counter mtime[63:32]
//   Offset 0x08 [RW]: MTIMECMP_LOW  - Lower 32 bits of 64-bit compare mtimecmp[31:0]
//   Offset 0x0C [RW]: MTIMECMP_HIGH - Upper 32 bits of 64-bit compare mtimecmp[63:32]
//   Offset 0x10 [RW]: TIMER_CTRL    - [0]: EN (1=count, 0=hold)
//                                     [1]: IRQ_EN (1=drive timer_irq, 0=mask)
//                                     [2]: AUTO_RELOAD (1=reset mtime to 0 on match)
//                                     [15:8]: PRESCALE divider integer N
//   Offset 0x14 [RW]: TIMER_STATUS  - [0]: MATCH flag (sticky, Write-1-to-Clear)
//   Unmapped offsets                - Return SLVERR (2'b10) without bus deadlock
//
// AXI4-LITE BUS PROTOCOL:
//   - Fully decoupled AW and W handshakes (AW-before-W, W-before-AW, simultaneous)
//   - Single-cycle ready pulses (awready, wready, arready)
//   - Compliant response holding on bvalid/bready and rvalid/rready
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module timer_top #(
    parameter integer ADDR_WIDTH = 32,
    parameter integer DATA_WIDTH = 32,
    parameter integer STRB_WIDTH = DATA_WIDTH / 8
)(
    // Global Clock & Reset
    input  wire                  clk,
    input  wire                  rst_n,        // Active-low reset

    // Interrupt Request Output Pin
    output wire                  timer_irq,

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
        OFFSET_MTIME_LOW     = 12'h000,
        OFFSET_MTIME_HIGH    = 12'h004,
        OFFSET_MTIMECMP_LOW  = 12'h008,
        OFFSET_MTIMECMP_HIGH = 12'h00C,
        OFFSET_TIMER_CTRL    = 12'h010,
        OFFSET_TIMER_STATUS  = 12'h014;

    localparam [1:0]
        RESP_OKAY   = 2'b00,
        RESP_EXOKAY = 2'b01,
        RESP_SLVERR = 2'b10,
        RESP_DECERR = 2'b11;

    // =========================================================================
    // Core Internal Registers
    // =========================================================================
    reg [63:0] mtime;
    reg [63:0] mtimecmp;
    reg [15:0] ctrl_reg;      // [0]=EN, [1]=IRQ_EN, [2]=AUTO_RELOAD, [15:8]=PRESCALE
    reg [7:0]  prescale_cnt;
    reg        match_sticky;

    // Interrupt condition: mtime >= mtimecmp
    wire match_cond = (mtime >= mtimecmp);
    assign timer_irq = match_cond && ctrl_reg[1];

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

    // Synchronous Register & Counter Process
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

            mtime           <= 64'd0;
            mtimecmp        <= 64'hFFFF_FFFF_FFFF_FFFF;
            ctrl_reg        <= 16'h0001; // EN=1, IRQ_EN=0, AUTO_RELOAD=0, PRESCALE=0
            prescale_cnt    <= 8'd0;
            match_sticky    <= 1'b0;
        end else begin
            // -----------------------------------------------------------------
            // 1. Counter Tick Progression
            // -----------------------------------------------------------------
            if (ctrl_reg[0]) begin // EN
                if (prescale_cnt >= ctrl_reg[15:8]) begin
                    prescale_cnt <= 8'd0;
                    if (match_cond && ctrl_reg[2]) begin
                        mtime <= 64'd0; // Auto-reload to 0
                    end else begin
                        mtime <= mtime + 64'd1;
                    end
                end else begin
                    prescale_cnt <= prescale_cnt + 8'd1;
                end
            end

            if (match_cond) begin
                match_sticky <= 1'b1;
            end

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
                    OFFSET_MTIME_LOW: begin
                        if (strb[0]) mtime[7:0]   <= data[7:0];
                        if (strb[1]) mtime[15:8]  <= data[15:8];
                        if (strb[2]) mtime[23:16] <= data[23:16];
                        if (strb[3]) mtime[31:24] <= data[31:24];
                        s_axi_bresp <= RESP_OKAY;
                    end

                    OFFSET_MTIME_HIGH: begin
                        if (strb[0]) mtime[39:32] <= data[7:0];
                        if (strb[1]) mtime[47:40] <= data[15:8];
                        if (strb[2]) mtime[55:48] <= data[23:16];
                        if (strb[3]) mtime[63:56] <= data[31:24];
                        s_axi_bresp <= RESP_OKAY;
                    end

                    OFFSET_MTIMECMP_LOW: begin
                        if (strb[0]) mtimecmp[7:0]   <= data[7:0];
                        if (strb[1]) mtimecmp[15:8]  <= data[15:8];
                        if (strb[2]) mtimecmp[23:16] <= data[23:16];
                        if (strb[3]) mtimecmp[31:24] <= data[31:24];
                        s_axi_bresp <= RESP_OKAY;
                    end

                    OFFSET_MTIMECMP_HIGH: begin
                        if (strb[0]) mtimecmp[39:32] <= data[7:0];
                        if (strb[1]) mtimecmp[47:40] <= data[15:8];
                        if (strb[2]) mtimecmp[55:48] <= data[23:16];
                        if (strb[3]) mtimecmp[63:56] <= data[31:24];
                        s_axi_bresp <= RESP_OKAY;
                    end

                    OFFSET_TIMER_CTRL: begin
                        if (strb[0]) ctrl_reg[7:0]  <= data[7:0];
                        if (strb[1]) ctrl_reg[15:8] <= data[15:8];
                        prescale_cnt <= 8'd0;
                        s_axi_bresp <= RESP_OKAY;
                    end

                    OFFSET_TIMER_STATUS: begin
                        // Bit 0 is W1C (write-1-to-clear)
                        if (strb[0] && data[0]) begin
                            match_sticky <= 1'b0;
                        end
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
                    OFFSET_MTIME_LOW: begin
                        s_axi_rdata <= mtime[31:0];
                        s_axi_rresp <= RESP_OKAY;
                    end

                    OFFSET_MTIME_HIGH: begin
                        s_axi_rdata <= mtime[63:32];
                        s_axi_rresp <= RESP_OKAY;
                    end

                    OFFSET_MTIMECMP_LOW: begin
                        s_axi_rdata <= mtimecmp[31:0];
                        s_axi_rresp <= RESP_OKAY;
                    end

                    OFFSET_MTIMECMP_HIGH: begin
                        s_axi_rdata <= mtimecmp[63:32];
                        s_axi_rresp <= RESP_OKAY;
                    end

                    OFFSET_TIMER_CTRL: begin
                        s_axi_rdata <= {16'h0000, ctrl_reg};
                        s_axi_rresp <= RESP_OKAY;
                    end

                    OFFSET_TIMER_STATUS: begin
                        s_axi_rdata <= {30'h0, match_cond, match_sticky};
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
