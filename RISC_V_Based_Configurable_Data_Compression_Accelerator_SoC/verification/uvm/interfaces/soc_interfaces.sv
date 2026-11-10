// =============================================================================
// soc_interfaces.sv — Unified SystemVerilog Interfaces for SoC Verification
// Includes UART, GPIO, Reset, IRQ physical interfaces and passive soc_obs_if.
// =============================================================================
`timescale 1ns/1ps

`ifndef SOC_INTERFACES_SV
`define SOC_INTERFACES_SV

`include "uart_if.sv"
`include "gpio_if.sv"
`include "reset_if.sv"
`include "irq_if.sv"
`include "soc_obs_if.sv"

`endif // SOC_INTERFACES_SV
