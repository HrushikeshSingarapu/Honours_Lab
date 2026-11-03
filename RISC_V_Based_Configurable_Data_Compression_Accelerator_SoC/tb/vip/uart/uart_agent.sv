// =============================================================================
// uart_agent.sv — UART Complete Agent Wrapper
// =============================================================================
`timescale 1ns/1ps

module uart_agent #(
    parameter int DEFAULT_CYCLES_PER_BIT = 17,
    parameter int QUEUE_DEPTH            = 1024
)(
    uart_if vif
);
    import vip_types_pkg::*;
    import uart_pkg::*;

    // Sub-components
    uart_driver #(
        .DEFAULT_CYCLES_PER_BIT(DEFAULT_CYCLES_PER_BIT)
    ) driver (
        .vif(vif.driver_mp)
    );

    uart_monitor #(
        .DEFAULT_CYCLES_PER_BIT(DEFAULT_CYCLES_PER_BIT),
        .QUEUE_DEPTH(QUEUE_DEPTH)
    ) monitor (
        .vif(vif.monitor_mp)
    );

    function void set_config(uart_config_t cfg);
        driver.set_config(cfg);
        monitor.set_config(cfg);
    endfunction

    // Facade API for ease of testbench use
    task send_byte(input logic [7:0] byte_data);
        driver.send_byte(byte_data);
    endtask

    task send_string(input string str);
        driver.send_string(str);
    endtask

    task get_byte(output logic [7:0] byte_data, output bit err);
        monitor.get_byte(byte_data, err);
    endtask

    function bit has_data();
        return monitor.has_data();
    endfunction

    function int get_char_count();
        return monitor.get_char_count();
    endfunction

endmodule: uart_agent

