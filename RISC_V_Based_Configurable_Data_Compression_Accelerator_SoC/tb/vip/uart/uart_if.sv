// =============================================================================
// uart_if.sv — UART Physical Interface
// =============================================================================
`timescale 1ns/1ps

interface uart_if (
    input wire clk,
    input wire rst_n
);
    logic uart_rx; // Driven by testbench VIP into DUT
    logic uart_tx; // Driven by DUT into testbench VIP

    modport driver_mp (
        input  clk,
        input  rst_n,
        input  uart_tx,
        output uart_rx
    );

    modport monitor_mp (
        input clk,
        input rst_n,
        input uart_rx,
        input uart_tx
    );

endinterface: uart_if

