// =============================================================================
// axi_vip_pkg.sv — Top Package for AXI Verification IP
// =============================================================================
`timescale 1ns/1ps

`ifndef AXI_VIP_PKG_SV
`define AXI_VIP_PKG_SV

package axi_vip_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  `include "axi_types.sv"
  `include "axi_seq_item.sv"
  `include "axi_cfg.sv"
  `include "axi_monitor.sv"
  `include "axi_agent.sv"

endpackage : axi_vip_pkg

`endif // AXI_VIP_PKG_SV
