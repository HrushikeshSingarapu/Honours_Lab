// =============================================================================
// irq_pkg.sv — Interrupt Monitor VIP Package
// =============================================================================
`timescale 1ns/1ps

package irq_pkg;
    import vip_types_pkg::*;

    localparam int NUM_IRQS = 4;

    typedef struct {
        irq_source_e source;
        time         assert_time;
        time         deassert_time;
        int          duration_cycles;
    } irq_event_t;

    function automatic string get_irq_name(int idx);
        case (idx)
            0: return "GPIO_IRQ";
            1: return "TIMER_IRQ";
            2: return "RLE_IRQ";
            3: return "DMA_IRQ";
            default: return "UNKNOWN_IRQ";
        endcase
    endfunction

endpackage: irq_pkg

