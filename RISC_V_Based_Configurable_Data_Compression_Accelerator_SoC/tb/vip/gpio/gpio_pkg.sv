// =============================================================================
// gpio_pkg.sv — GPIO VIP Package
// =============================================================================
`timescale 1ns/1ps

package gpio_pkg;
    import vip_types_pkg::*;

    typedef struct {
        logic [31:0] val;
        logic [31:0] oe;
        time         timestamp;
    } gpio_event_t;

    typedef struct {
        gpio_pull_e default_pull;
        bit         enable_contention_check;
    } gpio_config_t;

    function automatic gpio_config_t get_default_gpio_config();
        gpio_config_t cfg;
        cfg.default_pull            = GPIO_PULL_NONE;
        cfg.enable_contention_check = 1'b1;
        return cfg;
    endfunction

endpackage: gpio_pkg

