#include <stdint.h>

#define UART_BASE   0x00030000UL

#define UART_THR    (*(volatile uint32_t *)(UART_BASE + 0x00))
#define UART_LCR    (*(volatile uint32_t *)(UART_BASE + 0x0C))
#define UART_LSR    (*(volatile uint32_t *)(UART_BASE + 0x14))

#define UART_TX_READY (1U << 5)

static void uart_putc(char ch)
{
    while ((UART_LSR & UART_TX_READY) == 0U) {
    }

    UART_THR = (uint32_t)ch;
}

int main(void)
{
    UART_LCR = 0x03;

    uart_putc('H');
    uart_putc('I');

    while (1) {
    }

    return 0;
}
