// =============================================================================
// soc_uvm_pkg.sv — Unified Package for SoC Verification Environment
// Aggregates VIP packages and defines environment, scoreboard, coverage, and tests.
// =============================================================================
`timescale 1ns/1ps

package soc_uvm_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import uart_vip_pkg::*;
  import gpio_vip_pkg::*;
  import reset_vip_pkg::*;
  import irq_vip_pkg::*;

  `include "soc_env_cfg.sv"
  `include "soc_scoreboard.sv"
  `include "soc_coverage.sv"
  `include "soc_env.sv"
  `include "soc_smoke_seq.sv"
  `include "uart_echo_seq.sv"
  `include "soc_gpio_irq_seq.sv"
  `include "soc_warm_reset_seq.sv"
  `include "soc_uart_echo_fast_seq.sv"
  `include "soc_smoke_test.sv"
  `include "uart_echo_test.sv"
  `include "soc_e2e_flow_test.sv"
  `include "soc_reset_recovery_test.sv"
  `include "soc_decerr_trap_test.sv"

endpackage : soc_uvm_pkg
