// aes_reg_set.v  — FINAL CORRECT VERSION
`resetall
`timescale 1ns / 1ps
`default_nettype none

module aes_reg_set #
(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter STRB_WIDTH = (DATA_WIDTH/8)
)
(
    input  wire                     clk,
    input  wire                     rst,

    input  wire [ADDR_WIDTH-1:0]    reg_addr,
    input  wire [DATA_WIDTH-1:0]    reg_wdata,
    input  wire [STRB_WIDTH-1:0]    reg_wstrb,
    input  wire                     reg_wen,
    input  wire                     reg_ren,
    output reg  [DATA_WIDTH-1:0]    reg_rdata
);

//------------------------------------------------------------------
// Registers
//------------------------------------------------------------------
reg [31:0]  ctrl_reg;
reg [31:0]  status_reg;
reg [127:0] key_reg;
reg [127:0] data_in_reg;
reg [127:0] data_out_reg;

wire start   = ctrl_reg[0];
wire decrypt = ctrl_reg[1];

//------------------------------------------------------------------
// AES signals
//------------------------------------------------------------------
reg         aes_ld;
reg         aes_kld;
wire        done_enc, done_dec;
wire [127:0] out_enc, out_dec;

wire [127:0] aes_out  = decrypt ? out_dec : out_enc;
wire         aes_done = decrypt ? done_dec : done_enc;

//------------------------------------------------------------------
// Write logic
//------------------------------------------------------------------
always @(posedge clk) begin
    if (rst) begin
        ctrl_reg <= 32'd0;
    end else begin
        if (reg_wen) begin
            case (reg_addr[7:0])
                8'h00: begin
                    if (reg_wstrb[0]) ctrl_reg[7:0]   <= reg_wdata[7:0];
                    if (reg_wstrb[1]) ctrl_reg[15:8]  <= reg_wdata[15:8];
                    if (reg_wstrb[2]) ctrl_reg[23:16] <= reg_wdata[23:16];
                    if (reg_wstrb[3]) ctrl_reg[31:24] <= reg_wdata[31:24];
                end
                8'h10: if (&reg_wstrb) key_reg[31:0]     <= reg_wdata;
                8'h14: if (&reg_wstrb) key_reg[63:32]    <= reg_wdata;
                8'h18: if (&reg_wstrb) key_reg[95:64]    <= reg_wdata;
                8'h1C: if (&reg_wstrb) key_reg[127:96]   <= reg_wdata;
                8'h20: if (&reg_wstrb) data_in_reg[31:0]   <= reg_wdata;
                8'h24: if (&reg_wstrb) data_in_reg[63:32]  <= reg_wdata;
                8'h28: if (&reg_wstrb) data_in_reg[95:64]  <= reg_wdata;
                8'h2C: if (&reg_wstrb) data_in_reg[127:96] <= reg_wdata;
                default: ;
            endcase
        end

        // Auto-clear START
        if (aes_ld)
            ctrl_reg[0] <= 1'b0;
    end
end

//------------------------------------------------------------------
// Read logic
//------------------------------------------------------------------
always @* begin
    case (reg_addr[7:0])
        8'h00: reg_rdata = ctrl_reg;
        8'h04: reg_rdata = status_reg;
        8'h10: reg_rdata = key_reg[31:0];
        8'h14: reg_rdata = key_reg[63:32];
        8'h18: reg_rdata = key_reg[95:64];
        8'h1C: reg_rdata = key_reg[127:96];
        8'h20: reg_rdata = data_in_reg[31:0];
        8'h24: reg_rdata = data_in_reg[63:32];
        8'h28: reg_rdata = data_in_reg[95:64];
        8'h2C: reg_rdata = data_in_reg[127:96];
        8'h30: reg_rdata = data_out_reg[31:0];
        8'h34: reg_rdata = data_out_reg[63:32];
        8'h38: reg_rdata = data_out_reg[95:64];
        8'h3C: reg_rdata = data_out_reg[127:96];
        default: reg_rdata = 32'hDEADBEEF;
    endcase
end

//------------------------------------------------------------------
// AES Control FSM  (with proper key-expansion wait)
//------------------------------------------------------------------
reg [2:0]  state;
reg [3:0]  kexp_cnt;          // counter for key expansion delay

localparam IDLE      = 3'd0,
           KEY_PULSE = 3'd1,
           KEY_WAIT  = 3'd2,
           START     = 3'd3,
           WAIT_DONE = 3'd4;

always @(posedge clk) begin
    if (rst) begin
        state        <= IDLE;
        aes_ld       <= 1'b0;
        aes_kld      <= 1'b0;
        kexp_cnt     <= 4'd0;
        status_reg   <= 32'd0;
        data_out_reg <= 128'd0;
    end else begin
        aes_ld  <= 1'b0;
        aes_kld <= 1'b0;

        case (state)
            IDLE: begin
                status_reg[1] <= 1'b0;               // clear BUSY
                if (start) begin
                    status_reg[1] <= 1'b1;           // set BUSY
                    status_reg[0] <= 1'b0;           // clear DONE
                    if (decrypt)
                        state <= KEY_PULSE;
                    else
                        state <= START;              // encrypt needs no long key expand
                end
            end

            KEY_PULSE: begin
                aes_kld  <= 1'b1;                    // start key expansion
                kexp_cnt <= 4'd12;                   // wait 12 cycles
                state    <= KEY_WAIT;
            end

            KEY_WAIT: begin
                if (kexp_cnt == 0)
                    state <= START;
                else
                    kexp_cnt <= kexp_cnt - 1'b1;
            end

            START: begin
                aes_ld <= 1'b1;                      // start cipher / inv-cipher
                state  <= WAIT_DONE;
            end

            WAIT_DONE: begin
                if (aes_done) begin
                    data_out_reg  <= aes_out;
                    status_reg[0] <= 1'b1;           // DONE
                    status_reg[1] <= 1'b0;           // clear BUSY
                    state         <= IDLE;
                end
            end
        endcase
    end
end

//------------------------------------------------------------------
// AES cores (active-low reset)
//------------------------------------------------------------------
aes_cipher_top u_enc (
    .clk      (clk),
    .rst      (~rst),
    .ld       (aes_ld & ~decrypt),
    .done     (done_enc),
    .key      (key_reg),
    .text_in  (data_in_reg),
    .text_out (out_enc)
);

aes_inv_cipher_top u_dec (
    .clk      (clk),
    .rst      (~rst),
    .kld      (aes_kld),
    .ld       (aes_ld &  decrypt),
    .done     (done_dec),
    .key      (key_reg),
    .text_in  (data_in_reg),
    .text_out (out_dec)
);

endmodule
`resetall
