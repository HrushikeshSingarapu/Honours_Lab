// =============================================================================
// reset_vip_pkg.sv — Package Definition for RESET VIP
// =============================================================================
`timescale 1ns/1ps

package reset_vip_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  `include "reset_seq_item.sv"
  `include "reset_cfg.sv"
  `include "reset_sequencer.sv"
  `include "reset_driver.sv"
  `include "reset_monitor.sv"
  `include "reset_agent.sv"
  `include "reset_base_seq.sv"
  `include "reset_scoreboard.sv"
  `include "reset_env.sv"
  `include "reset_test.sv"

endpackage : reset_vip_pkg
