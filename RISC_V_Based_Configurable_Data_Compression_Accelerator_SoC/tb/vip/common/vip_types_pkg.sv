// =============================================================================
// vip_types_pkg.sv — Common Verification IP Types and Package
// =============================================================================
`timescale 1ns/1ps

package vip_types_pkg;

    // Severity levels for VIP reporting
    typedef enum logic [1:0] {
        VIP_INFO    = 2'b00,
        VIP_WARNING = 2'b01,
        VIP_ERROR   = 2'b10,
        VIP_FATAL   = 2'b11
    } vip_severity_e;

    // Standard UART Parity Configurations
    typedef enum logic [2:0] {
        UART_PARITY_NONE  = 3'b000,
        UART_PARITY_ODD   = 3'b001,
        UART_PARITY_EVEN  = 3'b010,
        UART_PARITY_MARK  = 3'b011,
        UART_PARITY_SPACE = 3'b100
    } uart_parity_e;

    // GPIO Pad Pull Configurations
    typedef enum logic [1:0] {
        GPIO_PULL_NONE = 2'b00,
        GPIO_PULL_UP   = 2'b01,
        GPIO_PULL_DOWN = 2'b10
    } gpio_pull_e;

    // Interrupt Source Identifiers
    typedef enum logic [2:0] {
        IRQ_SRC_GPIO  = 3'd0,
        IRQ_SRC_TIMER = 3'd1,
        IRQ_SRC_RLE   = 3'd2,
        IRQ_SRC_DMA   = 3'd3
    } irq_source_e;

endpackage: vip_types_pkg

