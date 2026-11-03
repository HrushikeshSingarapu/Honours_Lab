// =============================================================================
// reset_if.sv — Reset Interface
// =============================================================================
`timescale 1ns/1ps

interface reset_if (
    input wire clk
);
    logic rst_n; // Active-low reset (DUT convention)
    logic rst;   // Active-high reset (internally rst = ~rst_n)

    modport driver_mp (
        input  clk,
        output rst_n,
        output rst
    );

    modport monitor_mp (
        input clk,
        input rst_n,
        input rst
    );

endinterface: reset_if

