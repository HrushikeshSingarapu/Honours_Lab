// =============================================================================
// reset_pkg.sv — Reset VIP Package
// =============================================================================
`timescale 1ns/1ps

package reset_pkg;

    typedef struct {
        int  init_assert_cycles; // Initial power-on reset length (default 30)
        time clk_period_ns;      // Clock period in ns (default 10)
        bit  active_low;         // 1 = rst_n active low, 0 = rst active high
    } reset_config_t;

    function automatic reset_config_t get_default_reset_config(int cycles = 30);
        reset_config_t cfg;
        cfg.init_assert_cycles = cycles;
        cfg.clk_period_ns      = 10.0;
        cfg.active_low         = 1'b1;
        return cfg;
    endfunction

endpackage: reset_pkg

