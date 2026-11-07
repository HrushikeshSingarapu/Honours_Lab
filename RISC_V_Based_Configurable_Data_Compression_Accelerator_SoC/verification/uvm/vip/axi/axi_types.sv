// =============================================================================
// axi_types.sv — Common Type Definitions for AXI VIP
// =============================================================================
`ifndef AXI_TYPES_SV
`define AXI_TYPES_SV

typedef enum bit {
  AXI_WRITE = 1'b0,
  AXI_READ  = 1'b1
} axi_xact_type_e;

typedef enum bit [1:0] {
  AXI_FIXED      = 2'b00,
  AXI_INCR       = 2'b01,
  AXI_WRAP       = 2'b10,
  AXI_BURST_RSVD = 2'b11
} axi_burst_e;

typedef enum bit [1:0] {
  AXI_RESP_OKAY   = 2'b00,
  AXI_RESP_EXOKAY = 2'b01,
  AXI_RESP_SLVERR = 2'b10,
  AXI_RESP_DECERR = 2'b11
} axi_resp_e;

`endif // AXI_TYPES_SV
