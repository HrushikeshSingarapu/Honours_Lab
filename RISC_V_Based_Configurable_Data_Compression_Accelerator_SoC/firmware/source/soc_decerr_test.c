#include <stdint.h>

#define UART_BASE         0x00030000UL
#define UART_THR          (*(volatile uint32_t *)(UART_BASE + 0x00))
#define UART_BAUDDIV      (*(volatile uint32_t *)(UART_BASE + 0x08))
#define UART_LCR          (*(volatile uint32_t *)(UART_BASE + 0x0C))
#define UART_LSR          (*(volatile uint32_t *)(UART_BASE + 0x14))
#define UART_LSR_TX_READY (1U << 5)

// Unimplemented reserved Packet FIFO slot (must return AXI DECERR 2'b11)
#define PKT_FIFO_RESERVED 0x00070000UL

static inline void uart_putc(char ch)
{
    while ((UART_LSR & UART_LSR_TX_READY) == 0U) { }
    UART_THR = (uint32_t)(uint8_t)ch;
}

int main(void)
{
    UART_LCR     = 0x83U;
    UART_BAUDDIV = 49U; // 2,000,000 bps @ 100 MHz (50 cycles/bit)
    UART_LCR     = 0x03U;

    // Emit 'D' to confirm healthy boot prior to deliberate DECERR probe
    uart_putc('D');

    // Intentional load to unimplemented Packet FIFO address (0x0007_0000)
    // Expects interconnect AXI RRESP=DECERR (2'b11) -> VeeR EL2 imprecise bus error NMI
    volatile uint32_t val = (*(volatile uint32_t *)PKT_FIFO_RESERVED);
    (void)val;

    while (1) {
        __asm__ volatile ("nop");
    }
    return 0;
}
