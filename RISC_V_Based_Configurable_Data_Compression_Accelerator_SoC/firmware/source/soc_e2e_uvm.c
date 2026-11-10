#include <stdint.h>

// =============================================================================
// Authoritative SoC MMIO Register Map (Full_Soc_Address_Map.xlsx)
// =============================================================================
#define DMEM_BASE          0x00010000UL
#define UART_BASE          0x00030000UL
#define TIMER_BASE         0x00050000UL
#define GPIO_BASE          0x00060000UL
#define PKT_FIFO_RESERVED  0x00070000UL
#define CRC_BASE           0x000A0000UL
#define DMA_BASE           0x000B0000UL
#define RLE_BASE           0x000D0000UL

// UART Registers
#define UART_THR           (*(volatile uint32_t *)(UART_BASE + 0x00))
#define UART_BAUDDIV       (*(volatile uint32_t *)(UART_BASE + 0x08))
#define UART_LCR           (*(volatile uint32_t *)(UART_BASE + 0x0C))
#define UART_LSR           (*(volatile uint32_t *)(UART_BASE + 0x14))
#define UART_LSR_TX_READY  (1U << 5)
#define UART_LSR_TEMT      (1U << 6)

// Timer Registers
#define TIMER_MTIME_LO     (*(volatile uint32_t *)(TIMER_BASE + 0x00))
#define TIMER_MTIME_HI     (*(volatile uint32_t *)(TIMER_BASE + 0x04))
#define TIMER_MTIMECMP_LO  (*(volatile uint32_t *)(TIMER_BASE + 0x08))
#define TIMER_MTIMECMP_HI  (*(volatile uint32_t *)(TIMER_BASE + 0x0C))
#define TIMER_CTRL         (*(volatile uint32_t *)(TIMER_BASE + 0x10))
#define TIMER_STATUS       (*(volatile uint32_t *)(TIMER_BASE + 0x14))

// GPIO Registers
#define GPIO_DATA_IN       (*(volatile uint32_t *)(GPIO_BASE + 0x00))
#define GPIO_DATA_OUT      (*(volatile uint32_t *)(GPIO_BASE + 0x04))
#define GPIO_DIR           (*(volatile uint32_t *)(GPIO_BASE + 0x08))
#define GPIO_IRQ_EN        (*(volatile uint32_t *)(GPIO_BASE + 0x0C))
#define GPIO_IRQ_TYPE      (*(volatile uint32_t *)(GPIO_BASE + 0x10))
#define GPIO_IRQ_POL       (*(volatile uint32_t *)(GPIO_BASE + 0x14))
#define GPIO_IRQ_STAT      (*(volatile uint32_t *)(GPIO_BASE + 0x18))
#define GPIO_SET_OUT       (*(volatile uint32_t *)(GPIO_BASE + 0x1C))
#define GPIO_CLR_OUT       (*(volatile uint32_t *)(GPIO_BASE + 0x20))

// CRC-32 Registers
#define CRC_DATA           (*(volatile uint32_t *)(CRC_BASE + 0x00))
#define CRC_RESULT         (*(volatile uint32_t *)(CRC_BASE + 0x04))
#define CRC_CTRL           (*(volatile uint32_t *)(CRC_BASE + 0x08))
#define CRC_STATUS         (*(volatile uint32_t *)(CRC_BASE + 0x0C))

// DMA Registers
#define DMA_CTRL           (*(volatile uint32_t *)(DMA_BASE + 0x00))
#define DMA_STATUS         (*(volatile uint32_t *)(DMA_BASE + 0x04))
#define DMA_SRC_ADDR       (*(volatile uint32_t *)(DMA_BASE + 0x08))
#define DMA_DST_ADDR       (*(volatile uint32_t *)(DMA_BASE + 0x0C))
#define DMA_INPUT_LEN      (*(volatile uint32_t *)(DMA_BASE + 0x10))
#define DMA_OUTPUT_LEN     (*(volatile uint32_t *)(DMA_BASE + 0x14))
#define DMA_IRQ_ENABLE     (*(volatile uint32_t *)(DMA_BASE + 0x18))
#define DMA_IRQ_STATUS     (*(volatile uint32_t *)(DMA_BASE + 0x1C))
#define DMA_ERROR_CODE     (*(volatile uint32_t *)(DMA_BASE + 0x20))

// RLE Registers
#define RLE_CTRL           (*(volatile uint32_t *)(RLE_BASE + 0x00))
#define RLE_STATUS         (*(volatile uint32_t *)(RLE_BASE + 0x04))
#define RLE_INPUT_LEN      (*(volatile uint32_t *)(RLE_BASE + 0x08))
#define RLE_OUTPUT_LEN     (*(volatile uint32_t *)(RLE_BASE + 0x0C))
#define RLE_INPUT_DATA     (*(volatile uint32_t *)(RLE_BASE + 0x10))
#define RLE_OUTPUT_DATA    (*(volatile uint32_t *)(RLE_BASE + 0x14))
#define RLE_IRQ_ENABLE     (*(volatile uint32_t *)(RLE_BASE + 0x18))
#define RLE_IRQ_STATUS     (*(volatile uint32_t *)(RLE_BASE + 0x1C))

static volatile uint32_t g_trap_seen = 0;
static volatile uint32_t g_mcause    = 0;

void __attribute__((interrupt, aligned(4))) e2e_trap_handler(void)
{
    uint32_t cause = 0;
    uint32_t epc   = 0;
    __asm__ volatile ("csrr %0, mcause" : "=r"(cause));
    __asm__ volatile ("csrr %0, mepc"   : "=r"(epc));
    g_mcause    = cause;
    g_trap_seen = 1;
    // Skip the 4-byte non-compressed faulting instruction
    epc += 4U;
    __asm__ volatile ("csrw mepc, %0" : : "r"(epc));
}

static inline void uart_putc(char ch)
{
    while ((UART_LSR & UART_LSR_TX_READY) == 0U) { }
    UART_THR = (uint32_t)(uint8_t)ch;
}

static uint32_t calc_hw_crc32(const volatile uint32_t *words, uint32_t n_words)
{
    CRC_CTRL = 1U;
    for (uint32_t i = 0; i < n_words; i++) {
        CRC_DATA = words[i];
    }
    return CRC_RESULT;
}

int main(void)
{
    uint32_t ok = 1U;

    // -------------------------------------------------------------------------
    // Configure UART for fast 2,000,000 bps @ 100 MHz (divisor=49 -> 50 clks/bit)
    // -------------------------------------------------------------------------
    UART_LCR     = 0x83U; // DLAB=1, 8N1
    UART_BAUDDIV = 49U;
    UART_LCR     = 0x03U; // DLAB=0, 8N1

    // Verify IMEM Base (0x0000_0000) == Reset Alias (0x8000_0000) and DMEM Lower (0x0001_0000)
    uintptr_t imem_base_p = 0x00000000UL;
    uint32_t imem_lo_word = 0U;
    __asm__ volatile ("lw %0, 0(%1)" : "=r"(imem_lo_word) : "r"(imem_base_p));
    if (imem_lo_word != (*(volatile uint32_t *)0x80000000UL)) ok = 0U;
    (*(volatile uint32_t *)0x00010000UL) = 0x1234ABCDUL;
    if ((*(volatile uint32_t *)0x00010000UL) != 0x1234ABCDUL) ok = 0U;

    // -------------------------------------------------------------------------
    // Step A: Timer & timer_irq Assertion + W1C Clearing
    // -------------------------------------------------------------------------
    TIMER_CTRL        = 0U;
    TIMER_STATUS      = 1U;
    TIMER_MTIMECMP_HI = 0U;
    TIMER_MTIMECMP_LO = TIMER_MTIME_LO + 80U;
    TIMER_CTRL        = 3U; // EN=1, IRQ_EN=1
    while ((TIMER_STATUS & 1U) == 0U) { }
    for (volatile int d = 0; d < 4; d++) { } // Hold IRQ observable for irq_monitor
    TIMER_MTIMECMP_HI = 0xFFFFFFFFUL;
    TIMER_STATUS      = 1U;                  // Clear sticky W1C timer_irq
    if ((TIMER_STATUS & 1U) != 0U) ok = 0U;
    uart_putc('T');

    // -------------------------------------------------------------------------
    // Step B: GPIO Output, Set/Clear & External gpio_i[8] -> gpio_irq Handshake
    // -------------------------------------------------------------------------
    GPIO_DIR      = 0x000000FFUL; // [7:0] out, [31:8] in
    GPIO_DATA_OUT = 0x000000A5UL;
    GPIO_SET_OUT  = 0x00000010UL; // -> 0xB5
    if ((GPIO_DATA_OUT & 0xFFU) != 0xB5U) ok = 0U;
    GPIO_CLR_OUT  = 0x00000010UL; // -> 0xA5
    if ((GPIO_DATA_OUT & 0xFFU) != 0xA5U) ok = 0U;

    GPIO_IRQ_STAT = 0xFFFFFFFFUL;
    GPIO_IRQ_TYPE = 0x00000100UL; // Edge on bit 8
    GPIO_IRQ_POL  = 0x00000100UL; // Rising
    GPIO_IRQ_EN   = 0x00000100UL;
    uart_putc('G');               // Signal UVM gpio_agnt to assert gpio_i[8]=1

    uint32_t gpio_to = 50000U;
    while (((GPIO_IRQ_STAT & 0x00000100UL) == 0U) && (gpio_to > 0U)) {
        gpio_to--;
    }
    if ((GPIO_IRQ_STAT & 0x00000100UL) == 0U) ok = 0U;
    GPIO_IRQ_STAT = 0x00000100UL; // Clear W1C
    GPIO_DATA_OUT = 0x0000005AUL;

    // -------------------------------------------------------------------------
    // Step C: Direct RLE Accelerator + rle_irq Verification
    // -------------------------------------------------------------------------
    RLE_IRQ_STATUS = 3U;
    RLE_IRQ_ENABLE = 1U; // DONE IRQ enable
    RLE_INPUT_LEN  = 8U;
    RLE_INPUT_DATA = 0x41414141UL; // "AAAA"
    RLE_INPUT_DATA = 0x42424242UL; // "BBBB"
    RLE_CTRL       = 1U;           // START compress
    while ((RLE_STATUS & 2U) == 0U) { }
    if ((RLE_STATUS & 4U) != 0U || RLE_OUTPUT_LEN != 4U) ok = 0U;
    uint32_t r0 = RLE_OUTPUT_DATA;
    uint32_t r1 = RLE_OUTPUT_DATA;
    uint32_t r2 = RLE_OUTPUT_DATA;
    uint32_t r3 = RLE_OUTPUT_DATA;
    if (r0 != 4U || r1 != 0x41U || r2 != 4U || r3 != 0x42U) ok = 0U;
    RLE_IRQ_STATUS = 3U;
    uart_putc('R');

    // -------------------------------------------------------------------------
    // Step D: End-to-End Flow: Input DMEM -> DMA Compress -> DMA Decompress -> CRC-32
    // -------------------------------------------------------------------------
    volatile uint32_t *src_buf  = (volatile uint32_t *)(0x00020000UL);
    volatile uint32_t *cmp_buf  = (volatile uint32_t *)(0x00021000UL);
    volatile uint32_t *dec_buf  = (volatile uint32_t *)(0x00022000UL);

    // 32-byte source vector: 8x'X', 12x'Y', 8x'Z', "1234"
    src_buf[0] = 0x58585858UL;
    src_buf[1] = 0x58585858UL;
    src_buf[2] = 0x59595959UL;
    src_buf[3] = 0x59595959UL;
    src_buf[4] = 0x59595959UL;
    src_buf[5] = 0x5A5A5A5AUL;
    src_buf[6] = 0x5A5A5A5AUL;
    src_buf[7] = 0x34333231UL;

    // Known IEEE 802.3 "123456789" sanity check -> 0xCBF43926
    CRC_CTRL = 1U;
    CRC_DATA = 0x34333231UL;
    CRC_DATA = 0x38373635UL;
    (*(volatile uint8_t *)(CRC_BASE + 0x00)) = 0x39U;
    if (CRC_RESULT != 0xCBF43926UL) ok = 0U;

    uint32_t crc_orig = calc_hw_crc32(src_buf, 8U);

    // DMA Compress: 0x0002_0000 (32B) -> 0x0002_1000
    DMA_IRQ_STATUS = 3U;
    DMA_IRQ_ENABLE = 3U;
    DMA_SRC_ADDR   = (uint32_t)src_buf;
    DMA_DST_ADDR   = (uint32_t)cmp_buf;
    DMA_INPUT_LEN  = 32U;
    DMA_CTRL       = 1U; // MODE=0 (Compress), START=1
    while ((DMA_STATUS & 1U) != 0U || (DMA_STATUS & 6U) == 0U) { }
    uint32_t cmp_len = DMA_OUTPUT_LEN;
    if ((DMA_STATUS & 4U) != 0U || DMA_ERROR_CODE != 0U || cmp_len == 0U) ok = 0U;
    DMA_IRQ_STATUS = 3U;

    // DMA Decompress: 0x0002_1000 (cmp_len) -> 0x0002_2000
    DMA_SRC_ADDR   = (uint32_t)cmp_buf;
    DMA_DST_ADDR   = (uint32_t)dec_buf;
    DMA_INPUT_LEN  = cmp_len;
    DMA_CTRL       = 3U; // MODE=1 (Decompress), START=1
    while ((DMA_STATUS & 1U) != 0U || (DMA_STATUS & 6U) == 0U) { }
    if ((DMA_STATUS & 4U) != 0U || DMA_ERROR_CODE != 0U || DMA_OUTPUT_LEN != 32U) ok = 0U;
    DMA_IRQ_STATUS = 3U;

    uint32_t crc_recon = calc_hw_crc32(dec_buf, 8U);
    if (crc_recon != crc_orig) ok = 0U;
    for (uint32_t i = 0; i < 8U; i++) {
        if (dec_buf[i] != src_buf[i]) ok = 0U;
    }
    uart_putc('D');

    // -------------------------------------------------------------------------
    // Step E: Negative Error Handling & Reserved Region DECERR Trap Test
    // -------------------------------------------------------------------------
    // E1: DMA Zero Length -> ERR_BAD_LEN (0x03)
    DMA_SRC_ADDR  = (uint32_t)src_buf;
    DMA_DST_ADDR  = (uint32_t)cmp_buf;
    DMA_INPUT_LEN = 0U;
    DMA_CTRL      = 1U;
    while ((DMA_STATUS & 1U) != 0U || (DMA_STATUS & 6U) == 0U) { }
    if ((DMA_STATUS & 4U) == 0U || DMA_ERROR_CODE != 0x03U) ok = 0U;
    DMA_IRQ_STATUS = 3U;

    // E2: DMA Invalid SRC in Reserved Slot (0x0007_0000) -> ERR_BAD_SRC (0x01)
    DMA_SRC_ADDR  = PKT_FIFO_RESERVED;
    DMA_DST_ADDR  = (uint32_t)cmp_buf;
    DMA_INPUT_LEN = 4U;
    DMA_CTRL      = 1U;
    while ((DMA_STATUS & 1U) != 0U || (DMA_STATUS & 6U) == 0U) { }
    if ((DMA_STATUS & 4U) == 0U || DMA_ERROR_CODE != 0x01U) ok = 0U;
    DMA_IRQ_STATUS = 3U;

    // E3: DMA End-of-DMEM Source Spillover (0x0002_FFFC, len=8) -> ERR_BAD_SRC (0x01)
    DMA_SRC_ADDR  = 0x0002FFFCUL;
    DMA_DST_ADDR  = (uint32_t)cmp_buf;
    DMA_INPUT_LEN = 8U;
    DMA_CTRL      = 1U;
    while ((DMA_STATUS & 1U) != 0U || (DMA_STATUS & 6U) == 0U) { }
    if ((DMA_STATUS & 4U) == 0U || DMA_ERROR_CODE != 0x01U) ok = 0U;
    DMA_IRQ_STATUS = 3U;

    // E4: DMA Odd Decompression Length -> ERR_RLE_ERR (0x06)
    DMA_SRC_ADDR  = (uint32_t)cmp_buf;
    DMA_DST_ADDR  = (uint32_t)dec_buf;
    DMA_INPUT_LEN = 3U;
    DMA_CTRL      = 3U; // MODE=1 (Decompress), START=1
    while ((DMA_STATUS & 1U) != 0U || (DMA_STATUS & 6U) == 0U) { }
    if ((DMA_STATUS & 4U) == 0U || DMA_ERROR_CODE != 0x06U) ok = 0U;
    DMA_IRQ_STATUS = 3U;
    uart_putc('E');

    // -------------------------------------------------------------------------
    // Step F: Fast UART RX -> CPU -> TX Interactive Echo Handshake ('K')
    // -------------------------------------------------------------------------
    uint32_t rx_to = 50000U;
    while ((((*(volatile uint32_t *)(UART_BASE + 0x14)) & 1U) == 0U) && (rx_to > 0U)) {
        rx_to--;
    }
    if (rx_to == 0U) {
        ok = 0U;
    } else {
        uint8_t rx_ch = (uint8_t)((*(volatile uint32_t *)(UART_BASE + 0x00)) & 0xFFU);
        if (rx_ch != 'K') ok = 0U;
        uart_putc((char)rx_ch);
    }

    // -------------------------------------------------------------------------
    // Step G: Final Verdict Character ('P' = ALL PASS, 'X' = FAILURE)
    // -------------------------------------------------------------------------
    uart_putc(ok ? 'P' : 'X');

    while (1) {
        __asm__ volatile ("nop");
    }
    return 0;
}
