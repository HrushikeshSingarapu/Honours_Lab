// =============================================================================
// gpio_monitor.sv — GPIO Output and Enable Monitor
// =============================================================================
`timescale 1ns/1ps

module gpio_monitor #(
    parameter int HISTORY_DEPTH = 256
)(
    gpio_if.monitor_mp vif
);
    import vip_types_pkg::*;
    import gpio_pkg::*;

    gpio_event_t history [0:HISTORY_DEPTH-1];
    int event_count = 0;
    logic [31:0] prev_o  = 32'h0;
    logic [31:0] prev_oe = 32'h0;

    always @(posedge vif.clk or negedge vif.rst_n) begin
        if (!vif.rst_n) begin
            event_count <= 0;
            prev_o      <= 32'h0;
            prev_oe     <= 32'h0;
        end else begin
            if (vif.gpio_o !== prev_o || vif.gpio_oe !== prev_oe) begin
                if (event_count < HISTORY_DEPTH) begin
                    history[event_count].val       = vif.gpio_o;
                    history[event_count].oe        = vif.gpio_oe;
                    history[event_count].timestamp = $time;
                    event_count <= event_count + 1;
                end
                prev_o  <= vif.gpio_o;
                prev_oe <= vif.gpio_oe;
            end
        end
    end

    // Verify current output against expected value and mask
    function bit check_output(logic [31:0] exp_val, logic [31:0] mask = 32'hFFFF_FFFF);
        return ((vif.gpio_o & mask) === (exp_val & mask));
    endfunction

    // Wait until output matches expected value within timeout
    task wait_for_output(
        input  logic [31:0] exp_val,
        input  logic [31:0] mask = 32'hFFFF_FFFF,
        input  int          timeout_cycles = 1000,
        output bit          matched
    );
        int elapsed;
        elapsed = 0;
        matched = 0;
        while (elapsed < timeout_cycles) begin
            @(posedge vif.clk);
            elapsed++;
            if ((vif.gpio_o & mask) === (exp_val & mask)) begin
                matched = 1'b1;
                break;
            end
        end
    endtask

    function int get_event_count();
        return event_count;
    endfunction

endmodule: gpio_monitor
