// =============================================================================
// irq_if.sv — Interrupt Interface
// =============================================================================
`timescale 1ns/1ps

interface irq_if (
    input wire clk,
    input wire rst_n
);
    // 4 SoC Interrupt lines
    logic gpio_irq;
    logic timer_irq;
    logic rle_irq;
    logic dma_irq;

    modport monitor_mp (
        input clk,
        input rst_n,
        input gpio_irq,
        input timer_irq,
        input rle_irq,
        input dma_irq
    );

endinterface: irq_if

