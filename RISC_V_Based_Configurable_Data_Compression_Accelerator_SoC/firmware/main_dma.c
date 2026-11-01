// =============================================================================
// main_dma.c — CPU-Controlled End-to-End DMA, RLE, and CRC32 Verification
//
// Description:
//   Bare-metal C firmware running on the VeeR EL2 RISC-V core.
//   Orchestrates autonomous DMA compression and decompression through the
//   hardware RLE accelerator, and verifies end-to-end data integrity using
//   both byte-level memory comparisons and the MMIO CRC-32 peripheral.
//
// Test Patterns:
//   1. Short Input Pattern (8 bytes): [0xAA]*4 + [0xBB]*4 -> 4 bytes
//   2. Repeated-Byte Pattern (16 bytes): [0x55]*16 -> 2 bytes
//   3. Mixed Pattern (14 bytes): Alternating runs & singletons -> 14 bytes
//   4. Boundary-Length Pattern (32 bytes): Four 8-byte runs -> 8 bytes
//
// Memory Layout:
//   DMEM Base       : 0x0004_0000
//   Status Area     : DMEM[0..15] (0x0004_0000 - 0x0004_003C)
//   SRC_BUF         : 0x0004_0100 (256 bytes)
//   COMP_BUF        : 0x0004_0300 (256 bytes)
//   DECOMP_BUF      : 0x0004_0500 (256 bytes)
//
// Completion Status:
//   DMEM[0] = 0xCAFE_D00D  (All 4 patterns passed with CRC match)
//   DMEM[p] = 0xD3A0_000p  (Pattern p passed: p in 1..4)
//   DMEM[0] = 0xDEAD_0pxx  (Pattern p failed with error xx)
// =============================================================================

#include <stdint.h>

// Peripheral Base Addresses
#define UART_BASE       0x10000000UL
#define RLE_BASE        0x10010000UL
#define DMA_BASE        0x10011000UL
#define CRC_BASE        0x10012000UL

// DMEM Buffer Addresses
#define DMEM_BASE       0x00040000UL
#define DMEM_WORD(idx)  (*(volatile uint32_t *)(DMEM_BASE + ((idx) * 4)))

#define SRC_BUF_ADDR    0x00040100UL
#define COMP_BUF_ADDR   0x00040300UL
#define DECOMP_BUF_ADDR 0x00040500UL

// UART 16550 Registers
#define UART_THR        (*(volatile uint32_t *)(UART_BASE + 0x00))
#define UART_LCR        (*(volatile uint32_t *)(UART_BASE + 0x0C))
#define UART_LSR        (*(volatile uint32_t *)(UART_BASE + 0x14))
#define UART_TX_READY   (1U << 5)

// DMA Controller Registers (dma_reg_file.v)
#define DMA_CONTROL     (*(volatile uint32_t *)(DMA_BASE + 0x00))
#define DMA_STATUS      (*(volatile uint32_t *)(DMA_BASE + 0x04))
#define DMA_SRC_ADDR    (*(volatile uint32_t *)(DMA_BASE + 0x08))
#define DMA_DST_ADDR    (*(volatile uint32_t *)(DMA_BASE + 0x0C))
#define DMA_INPUT_LEN   (*(volatile uint32_t *)(DMA_BASE + 0x10))
#define DMA_OUTPUT_LEN  (*(volatile uint32_t *)(DMA_BASE + 0x14))
#define DMA_IRQ_ENABLE  (*(volatile uint32_t *)(DMA_BASE + 0x18))
#define DMA_IRQ_STATUS  (*(volatile uint32_t *)(DMA_BASE + 0x1C))
#define DMA_ERROR_CODE  (*(volatile uint32_t *)(DMA_BASE + 0x20))

// DMA Control Bits
#define DMA_CTRL_START      (1U << 0)
#define DMA_CTRL_MODE_COMP  (0U << 1)
#define DMA_CTRL_MODE_DECOMP (1U << 1)

// DMA Status Bits
#define DMA_STAT_BUSY   (1U << 0)
#define DMA_STAT_DONE   (1U << 1)
#define DMA_STAT_ERROR  (1U << 2)

// CRC32 Peripheral Registers (crc32_top.v)
#define CRC_DATA        (*(volatile uint32_t *)(CRC_BASE + 0x00))
#define CRC_RESULT      (*(volatile uint32_t *)(CRC_BASE + 0x04))
#define CRC_CTRL        (*(volatile uint32_t *)(CRC_BASE + 0x08))
#define CRC_STATUS      (*(volatile uint32_t *)(CRC_BASE + 0x0C))

// UART Logging Helpers (Direct MMIO write; TB captures character at THR)
static void uart_putc(char ch)
{
    UART_THR = (uint32_t)ch;
}

static void uart_puts(const char *s)
{
    while (*s) {
        uart_putc(*s++);
    }
}

// -----------------------------------------------------------------------------
// DMA Transfer Execution
// -----------------------------------------------------------------------------
// mode: 0 = Compression (DMEM -> RLE -> DMEM)
//       1 = Decompression (DMEM -> RLE -> DMEM)
// -----------------------------------------------------------------------------
static int dma_transfer(uint32_t src, uint32_t dst, uint32_t len, uint32_t mode, uint32_t *out_len)
{
    DMA_SRC_ADDR   = src;
    DMA_DST_ADDR   = dst;
    DMA_INPUT_LEN  = len;
    DMA_IRQ_STATUS = 0x03; // W1C: Clear any residual IRQ status

    uint32_t ctrl = DMA_CTRL_START | (mode ? DMA_CTRL_MODE_DECOMP : DMA_CTRL_MODE_COMP);
    DMA_CONTROL   = ctrl;

    // Poll until DONE or ERROR
    uint32_t timeout = 200000;
    while (timeout > 0) {
        uint32_t status = DMA_STATUS;
        if (status & DMA_STAT_ERROR) {
            return -1; // Hardware reported error
        }
        if (status & DMA_STAT_DONE) {
            break;
        }
        timeout--;
    }

    if (timeout == 0) {
        return -2; // Timed out waiting for DMA
    }

    *out_len = DMA_OUTPUT_LEN;
    DMA_IRQ_STATUS = 0x01; // Clear DONE IRQ
    return 0;
}

// -----------------------------------------------------------------------------
// Hardware CRC-32 Peripheral Ingestion
// -----------------------------------------------------------------------------
static uint32_t compute_hw_crc32(const uint8_t *data, uint32_t len)
{
    CRC_CTRL = 1; // Reset accumulator to 0xFFFFFFFF and byte_count to 0

    uint32_t i = 0;
    // Feed 32-bit word chunks (little-endian byte pack)
    while (i + 4 <= len) {
        uint32_t word = (uint32_t)data[i] |
                       ((uint32_t)data[i+1] << 8) |
                       ((uint32_t)data[i+2] << 16) |
                       ((uint32_t)data[i+3] << 24);
        CRC_DATA = word;
        i += 4;
    }

    // Feed remaining trailing bytes (1..3) with byte stores to 0x10012000
    while (i < len) {
        *(volatile uint8_t *)(CRC_BASE + 0x00) = data[i];
        i++;
    }

    return CRC_RESULT;
}

// -----------------------------------------------------------------------------
// Pattern Verification Runner
// -----------------------------------------------------------------------------
static int run_test_pattern(
    uint32_t test_num,
    const uint8_t *src_data,
    uint32_t src_len,
    const uint8_t *exp_comp,
    uint32_t exp_comp_len,
    uint32_t exp_crc
) {
    uint8_t *src_buf   = (uint8_t *)SRC_BUF_ADDR;
    uint8_t *comp_buf  = (uint8_t *)COMP_BUF_ADDR;
    uint8_t *decomp_buf= (uint8_t *)DECOMP_BUF_ADDR;

    // 1. Populate source buffer in DMEM and zero output buffers
    for (uint32_t i = 0; i < src_len; i++) {
        src_buf[i] = src_data[i];
    }
    for (uint32_t i = 0; i < 256; i++) {
        comp_buf[i]   = 0;
        decomp_buf[i] = 0;
    }

    // 2. Compute hardware CRC-32 of original data and verify against independent golden value
    uint32_t orig_crc = compute_hw_crc32(src_buf, src_len);
    if (orig_crc != exp_crc) {
        DMEM_WORD(0) = 0xDEAD0000 | (test_num << 8) | 0x07;
        return -1;
    }

    // 3. Perform DMA Compression (DMEM -> RLE -> DMEM)
    uint32_t comp_out_len = 0;
    int err = dma_transfer(SRC_BUF_ADDR, COMP_BUF_ADDR, src_len, 0, &comp_out_len);
    if (err != 0) {
        DMEM_WORD(0) = 0xDEAD0000 | (test_num << 8) | 0x01;
        return -1;
    }

    // Verify compressed output length
    if (comp_out_len != exp_comp_len) {
        DMEM_WORD(0) = 0xDEAD0000 | (test_num << 8) | 0x02;
        return -1;
    }

    // 4. Verify compressed bytes against golden RLE tokens
    for (uint32_t i = 0; i < exp_comp_len; i++) {
        if (comp_buf[i] != exp_comp[i]) {
            DMEM_WORD(0) = 0xDEAD0000 | (test_num << 8) | 0x03;
            return -1;
        }
    }

    // 5. Perform DMA Decompression (DMEM -> RLE -> DMEM)
    uint32_t decomp_out_len = 0;
    err = dma_transfer(COMP_BUF_ADDR, DECOMP_BUF_ADDR, comp_out_len, 1, &decomp_out_len);
    if (err != 0) {
        DMEM_WORD(0) = 0xDEAD0000 | (test_num << 8) | 0x04;
        return -1;
    }

    // Verify decompressed output length matches original length
    if (decomp_out_len != src_len) {
        DMEM_WORD(0) = 0xDEAD0000 | (test_num << 8) | 0x05;
        return -1;
    }

    // 6. Verify decompressed bytes match original source data byte-by-byte
    for (uint32_t i = 0; i < src_len; i++) {
        if (decomp_buf[i] != src_buf[i]) {
            DMEM_WORD(0) = 0xDEAD0000 | (test_num << 8) | 0x06;
            return -1;
        }
    }

    // 7. Compute hardware CRC-32 of reconstructed data and verify match with original CRC
    uint32_t decomp_crc = compute_hw_crc32(decomp_buf, decomp_out_len);
    if (decomp_crc != orig_crc) {
        DMEM_WORD(0) = 0xDEAD0000 | (test_num << 8) | 0x08;
        return -1;
    }

    // Mark pattern pass signature
    DMEM_WORD(test_num) = 0xD3A00000 | test_num;
    return 0;
}

// -----------------------------------------------------------------------------
// Main Function
// -----------------------------------------------------------------------------
int main(void)
{
    // Initialize UART 8N1
    UART_LCR = 0x03;
    uart_puts("\n[FW] VeeR EL2 End-to-End DMA, RLE & CRC Verification\n");

    // Clear DMEM status area
    for (int i = 0; i < 16; i++) {
        DMEM_WORD(i) = 0;
    }

    // Pattern 1: Short Input (8 bytes) -> 4 bytes compressed
    static const uint8_t p1_data[8] = { 0xAA, 0xAA, 0xAA, 0xAA, 0xBB, 0xBB, 0xBB, 0xBB };
    static const uint8_t p1_comp[4] = { 4, 0xAA, 4, 0xBB };
    if (run_test_pattern(1, p1_data, 8, p1_comp, 4, 0x679ED8AF) != 0) {
        uart_puts("[FW] FAIL: Pattern 1\n");
        while (1);
    }
    uart_puts("[FW] PASS: Pattern 1 (Short 8B -> 4B -> 8B, CRC 0x679ED8AF)\n");

    // Pattern 2: Repeated-Byte Input (16 bytes) -> 2 bytes compressed
    static const uint8_t p2_data[16] = {
        0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55,
        0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55
    };
    static const uint8_t p2_comp[2] = { 16, 0x55 };
    if (run_test_pattern(2, p2_data, 16, p2_comp, 2, 0x1493CDAF) != 0) {
        uart_puts("[FW] FAIL: Pattern 2\n");
        while (1);
    }
    uart_puts("[FW] PASS: Pattern 2 (Repeated 16B -> 2B -> 16B, CRC 0x1493CDAF)\n");

    // Pattern 3: Mixed Input (14 bytes) -> 14 bytes compressed
    static const uint8_t p3_data[14] = {
        0x11, 0x11, 0x11,
        0x22,
        0x33,
        0x44, 0x44, 0x44, 0x44,
        0x55, 0x55,
        0x66,
        0x77, 0x77
    };
    static const uint8_t p3_comp[14] = {
        3, 0x11,
        1, 0x22,
        1, 0x33,
        4, 0x44,
        2, 0x55,
        1, 0x66,
        2, 0x77
    };
    if (run_test_pattern(3, p3_data, 14, p3_comp, 14, 0x6D5FF127) != 0) {
        uart_puts("[FW] FAIL: Pattern 3\n");
        while (1);
    }
    uart_puts("[FW] PASS: Pattern 3 (Mixed 14B -> 14B -> 14B, CRC 0x6D5FF127)\n");

    // Pattern 4: Boundary-Length Input (32 bytes) -> 8 bytes compressed
    static const uint8_t p4_data[32] = {
        0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x10,
        0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20,
        0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30,
        0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40
    };
    static const uint8_t p4_comp[8] = {
        8, 0x10,
        8, 0x20,
        8, 0x30,
        8, 0x40
    };
    if (run_test_pattern(4, p4_data, 32, p4_comp, 8, 0xBB19A46E) != 0) {
        uart_puts("[FW] FAIL: Pattern 4\n");
        while (1);
    }
    uart_puts("[FW] PASS: Pattern 4 (Boundary 32B -> 8B -> 32B, CRC 0xBB19A46E)\n");

    // ALL 4 PATTERNS PASSED!
    DMEM_WORD(0) = 0xCAFED00D;
    uart_puts("[FW] ALL 4 PATTERNS PASSED! Signature 0xCAFED00D written to DMEM[0].\n");

    while (1) {
        // Sleep / idle loop
    }

    return 0;
}

