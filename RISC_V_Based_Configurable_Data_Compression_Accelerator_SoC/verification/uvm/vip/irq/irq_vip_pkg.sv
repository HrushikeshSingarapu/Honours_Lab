// =============================================================================
// irq_vip_pkg.sv — Package Definition for IRQ VIP
// =============================================================================
`timescale 1ns/1ps

package irq_vip_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  `include "irq_seq_item.sv"
  `include "irq_cfg.sv"
  `include "irq_monitor.sv"
  `include "irq_agent.sv"
  `include "irq_scoreboard.sv"
  `include "irq_env.sv"
  `include "irq_test.sv"

endpackage : irq_vip_pkg
