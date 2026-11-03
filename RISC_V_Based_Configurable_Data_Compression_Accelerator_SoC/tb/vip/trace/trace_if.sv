// =============================================================================
// trace_if.sv — VeeR EL2 Core Trace Interface
// =============================================================================
`timescale 1ns/1ps

interface trace_if (
    input wire clk,
    input wire rst_n
);
    logic [31:0] trace_rv_i_insn_ip;
    logic [31:0] trace_rv_i_address_ip;
    logic        trace_rv_i_valid_ip;
    logic        trace_rv_i_exception_ip;
    logic [ 4:0] trace_rv_i_ecause_ip;
    logic        trace_rv_i_interrupt_ip;
    logic [31:0] trace_rv_i_tval_ip;

    modport monitor_mp (
        input clk,
        input rst_n,
        input trace_rv_i_insn_ip,
        input trace_rv_i_address_ip,
        input trace_rv_i_valid_ip,
        input trace_rv_i_exception_ip,
        input trace_rv_i_ecause_ip,
        input trace_rv_i_interrupt_ip,
        input trace_rv_i_tval_ip
    );

endinterface: trace_if

