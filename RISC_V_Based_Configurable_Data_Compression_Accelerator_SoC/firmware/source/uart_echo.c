#include <stdint.h>

#define UART_BASE            0x00030000UL

// UART 16550 Registers (32-bit word aligned)
#define UART_RBR             (*(volatile uint32_t *)(UART_BASE + 0x00))
#define UART_THR             (*(volatile uint32_t *)(UART_BASE + 0x00))
#define UART_IER             (*(volatile uint32_t *)(UART_BASE + 0x04))
#define UART_LCR             (*(volatile uint32_t *)(UART_BASE + 0x0C))
#define UART_LSR             (*(volatile uint32_t *)(UART_BASE + 0x14))

// LSR Bit Masks
#define UART_LSR_DATA_READY  (1U << 0) // Bit 0: RX FIFO has data available
#define UART_LSR_TX_READY    (1U << 5) // Bit 5: TX FIFO has available write space

static inline int uart_rx_data_available(void)
{
    return ((UART_LSR & UART_LSR_DATA_READY) != 0U);
}

static inline char uart_read(void)
{
    while (!uart_rx_data_available()) {
        // Wait for incoming character
    }
    return (char)(UART_RBR & 0xFFU);
}

static inline void uart_write(char ch)
{
    while ((UART_LSR & UART_LSR_TX_READY) == 0U) {
        // Wait until transmitter FIFO has space
    }
    UART_THR = (uint32_t)(uint8_t)ch;
}

int main(void)
{
    // Initialize Line Control: 8 data bits, 1 stop bit, no parity (8N1, DLAB=0)
    UART_LCR = 0x03;

    // Interactive Echo Loop:
    // Continuously read characters from UART RX and echo each character back through UART TX
    while (1) {
        char ch = uart_read();
        uart_write(ch);
    }

    return 0;
}
