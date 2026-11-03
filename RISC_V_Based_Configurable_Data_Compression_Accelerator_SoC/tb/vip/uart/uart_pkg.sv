// =============================================================================
// uart_pkg.sv — UART VIP Package
// =============================================================================
`timescale 1ns/1ps

package uart_pkg;
    import vip_types_pkg::*;

    typedef struct {
        int           baud_rate;        // e.g. 115200
        int           clock_freq_hz;    // e.g. 100_000_000 (100 MHz)
        int           cycles_per_bit;   // Overrides baud_rate calculation if > 0
        int           data_bits;        // 5, 6, 7, 8 (default 8)
        int           stop_bits;        // 1 or 2 (default 1)
        uart_parity_e parity;           // Default NONE
    } uart_config_t;

    function automatic uart_config_t get_default_uart_config(int cycles_per_bit = 17);
        uart_config_t cfg;
        cfg.baud_rate      = 115200;
        cfg.clock_freq_hz  = 100_000_000;
        cfg.cycles_per_bit = cycles_per_bit;
        cfg.data_bits      = 8;
        cfg.stop_bits      = 1;
        cfg.parity         = UART_PARITY_NONE;
        return cfg;
    endfunction

    typedef struct {
        logic [7:0] data;
        bit         parity_err;
        bit         framing_err;
        time        timestamp;
    } uart_frame_t;

endpackage: uart_pkg

