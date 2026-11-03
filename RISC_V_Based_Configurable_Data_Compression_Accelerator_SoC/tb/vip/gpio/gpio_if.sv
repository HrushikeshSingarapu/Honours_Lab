// =============================================================================
// gpio_if.sv — GPIO Physical Interface
// =============================================================================
`timescale 1ns/1ps

interface gpio_if (
    input wire clk,
    input wire rst_n
);
    // Core DUT signals
    logic [31:0] gpio_i;  // Input to SoC
    logic [31:0] gpio_o;  // Output from SoC
    logic [31:0] gpio_oe; // Output Enable from SoC (1 = drive, 0 = high-Z)

    // Optional physical bidirectional pad lines
    wire  [31:0] gpio_pad;

    modport driver_mp (
        input  clk,
        input  rst_n,
        output gpio_i
    );

    modport monitor_mp (
        input clk,
        input rst_n,
        input gpio_i,
        input gpio_o,
        input gpio_oe,
        input gpio_pad
    );

endinterface: gpio_if

