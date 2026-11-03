// =============================================================================
// reset_driver.sv — Reset Sequencer and Driver
// =============================================================================
`timescale 1ns/1ps

module reset_driver #(
    parameter int DEFAULT_INIT_CYCLES = 30
)(
    reset_if.driver_mp vif
);
    import reset_pkg::*;

    reset_config_t cfg;
    int reset_count = 0;

    initial begin
        cfg = get_default_reset_config(DEFAULT_INIT_CYCLES);
        // Start immediately asserted
        vif.rst_n = 1'b0;
        vif.rst   = 1'b1;
    end

    // Standard Power-On Reset Sequence
    task power_on_reset(input int num_cycles = 0);
        int cycles;
        cycles = (num_cycles > 0) ? num_cycles : cfg.init_assert_cycles;
        vif.rst_n = 1'b0;
        vif.rst   = 1'b1;
        repeat (cycles) @(posedge vif.clk);
        #1;
        vif.rst_n = 1'b1;
        vif.rst   = 1'b0;
        reset_count++;
        $display("[%0t ns] [RESET VIP] Reset successfully released after %0d clock cycles.", $time, cycles);
    endtask

    // Warm reset pulse
    task pulse_reset(input int duration_cycles = 10);
        @(posedge vif.clk);
        #1;
        vif.rst_n = 1'b0;
        vif.rst   = 1'b1;
        $display("[%0t ns] [RESET VIP] Warm reset asserted.", $time);
        repeat (duration_cycles) @(posedge vif.clk);
        #1;
        vif.rst_n = 1'b1;
        vif.rst   = 1'b0;
        reset_count++;
        $display("[%0t ns] [RESET VIP] Warm reset released after %0d clock cycles.", $time, duration_cycles);
    endtask

endmodule: reset_driver
