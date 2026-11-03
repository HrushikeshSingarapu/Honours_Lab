// =============================================================================
// gpio_agent.sv — GPIO Complete Agent Wrapper
// =============================================================================
`timescale 1ns/1ps

module gpio_agent #(
    parameter bit ENABLE_PAD_MODEL = 1'b0
)(
    gpio_if vif
);
    import vip_types_pkg::*;
    import gpio_pkg::*;

    logic [31:0] ext_drive_val = 32'h0;
    logic [31:0] ext_drive_en  = 32'h0;
    wire  [31:0] resolved_gpio_i;

    // Sub-components
    gpio_driver driver (
        .vif(vif.driver_mp)
    );

    gpio_monitor monitor (
        .vif(vif.monitor_mp)
    );

    generate
        if (ENABLE_PAD_MODEL) begin : gen_pad
            gpio_pad_model pad_model (
                .vif(vif.monitor_mp),
                .resolved_gpio_i(resolved_gpio_i),
                .ext_drive_val(ext_drive_val),
                .ext_drive_en(ext_drive_en)
            );
            assign vif.gpio_i = resolved_gpio_i;
        end
    endgenerate

    // Driver Facade
    task drive_all(input logic [31:0] val);
        driver.drive_all(val);
    endtask

    task drive_pin(input int pin, input logic val);
        driver.drive_pin(pin, val);
    endtask

    task pulse_pin(input int pin, input int num_cycles = 1);
        driver.pulse_pin(pin, num_cycles);
    endtask

    // Monitor Facade
    function bit check_output(logic [31:0] exp_val, logic [31:0] mask = 32'hFFFF_FFFF);
        return monitor.check_output(exp_val, mask);
    endfunction

    task wait_for_output(
        input  logic [31:0] exp_val,
        input  logic [31:0] mask = 32'hFFFF_FFFF,
        input  int          timeout_cycles = 1000,
        output bit          matched
    );
        monitor.wait_for_output(exp_val, mask, timeout_cycles, matched);
    endtask

endmodule: gpio_agent

