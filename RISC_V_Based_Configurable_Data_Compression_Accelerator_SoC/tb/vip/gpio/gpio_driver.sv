// =============================================================================
// gpio_driver.sv — GPIO Input Stimulus Driver
// =============================================================================
`timescale 1ns/1ps

module gpio_driver (
    gpio_if.driver_mp vif
);
    import vip_types_pkg::*;
    import gpio_pkg::*;

    initial begin
        vif.gpio_i = 32'h0000_0000;
    end

    // Drive full 32-bit vector
    task drive_all(input logic [31:0] val);
        @(posedge vif.clk);
        #1;
        vif.gpio_i <= val;
    endtask

    // Drive single pin while holding other pins steady
    task drive_pin(input int pin, input logic val);
        @(posedge vif.clk);
        #1;
        vif.gpio_i[pin] <= val;
    endtask

    // Pulse a single pin for N clock cycles
    task pulse_pin(input int pin, input int num_cycles = 1);
        @(posedge vif.clk);
        #1;
        vif.gpio_i[pin] <= ~vif.gpio_i[pin];
        repeat (num_cycles) @(posedge vif.clk);
        #1;
        vif.gpio_i[pin] <= ~vif.gpio_i[pin];
    endtask

    // Walking ones test pattern
    task walking_ones(input int delay_cycles = 5);
        for (int p = 0; p < 32; p++) begin
            drive_all(32'h1 << p);
            repeat (delay_cycles) @(posedge vif.clk);
        end
        drive_all(32'h0000_0000);
    endtask

endmodule: gpio_driver

