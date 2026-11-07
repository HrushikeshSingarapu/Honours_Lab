// =============================================================================
// axi_cfg.sv — Configuration Object for AXI Agent & Passive Monitor
// =============================================================================
`ifndef AXI_CFG_SV
`define AXI_CFG_SV

class axi_cfg extends uvm_object;
  `uvm_object_utils(axi_cfg)

  uvm_active_passive_enum is_active = UVM_PASSIVE;
  string                  port_name = "AXI_PORT";
  bit                     enable_checks = 1'b1;
  int                     stall_timeout_cycles = 1000;

  function new(string name = "axi_cfg");
    super.new(name);
  endfunction

endclass : axi_cfg

`endif // AXI_CFG_SV
