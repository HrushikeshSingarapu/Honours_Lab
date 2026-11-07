// =============================================================================
// soc_interfaces.sv — Unified SystemVerilog Interfaces for SoC Verification
// Includes UART, GPIO, Reset, and IRQ physical interfaces.
// =============================================================================
`timescale 1ns/1ps

`ifndef SOC_INTERFACES_SV
`define SOC_INTERFACES_SV

`include "uart_if.sv"
`include "gpio_if.sv"
`include "reset_if.sv"
`include "irq_if.sv"

`endif // SOC_INTERFACES_SV
