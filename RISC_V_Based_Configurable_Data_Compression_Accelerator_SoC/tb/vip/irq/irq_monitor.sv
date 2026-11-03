// =============================================================================
// irq_monitor.sv — Multi-Source Interrupt Observer and Integrity Monitor
// =============================================================================
`timescale 1ns/1ps

module irq_monitor #(
    parameter int MAX_EVENTS = 256
)(
    irq_if.monitor_mp vif
);
    import vip_types_pkg::*;
    import irq_pkg::*;

    // Channel tracking arrays
    int irq_assert_count [0:NUM_IRQS-1];
    int irq_deassert_count [0:NUM_IRQS-1];
    bit irq_active [0:NUM_IRQS-1];
    time irq_assert_time [0:NUM_IRQS-1];
    int irq_duration [0:NUM_IRQS-1];

    logic [NUM_IRQS-1:0] prev_irqs;

    wire [NUM_IRQS-1:0] cur_irqs = {
        vif.dma_irq,
        vif.rle_irq,
        vif.timer_irq,
        vif.gpio_irq
    };

    initial begin
        for (int i = 0; i < NUM_IRQS; i++) begin
            irq_assert_count[i]   = 0;
            irq_deassert_count[i] = 0;
            irq_active[i]         = 1'b0;
            irq_assert_time[i]    = 0;
            irq_duration[i]       = 0;
        end
        prev_irqs = 4'b0000;
    end

    always @(posedge vif.clk or negedge vif.rst_n) begin
        if (!vif.rst_n) begin
            prev_irqs <= 4'b0000;
            for (int i = 0; i < NUM_IRQS; i++) begin
                irq_active[i] <= 1'b0;
            end
        end else begin
            for (int ch = 0; ch < NUM_IRQS; ch++) begin
                // Rising Edge: IRQ Asserted
                if (cur_irqs[ch] && !prev_irqs[ch]) begin
                    irq_assert_count[ch] <= irq_assert_count[ch] + 1;
                    irq_active[ch]       <= 1'b1;
                    irq_assert_time[ch]  <= $time;
                    $display("[%0t ns] [IRQ VIP] >>> %s ASSERTED (Count #%0d)",
                             $time, get_irq_name(ch), irq_assert_count[ch] + 1);
                end
                // Falling Edge: IRQ Cleared / Deasserted
                else if (!cur_irqs[ch] && prev_irqs[ch]) begin
                    irq_deassert_count[ch] <= irq_deassert_count[ch] + 1;
                    irq_active[ch]         <= 1'b0;
                    irq_duration[ch]       <= ($time - irq_assert_time[ch]);
                    $display("[%0t ns] [IRQ VIP] --- %s DEASSERTED (Active duration: %0t ns)",
                             $time, get_irq_name(ch), $time - irq_assert_time[ch]);
                end
            end
            prev_irqs <= cur_irqs;
        end
    end

    // Wait for specified interrupt channel to assert
    task wait_for_irq(input int channel, input int timeout_cycles, output bit triggered);
        int elapsed;
        elapsed = 0;
        triggered = 1'b0;
        while (elapsed < timeout_cycles) begin
            @(posedge vif.clk);
            elapsed++;
            if (cur_irqs[channel] == 1'b1) begin
                triggered = 1'b1;
                break;
            end
        end
    endtask

    function int get_count(int channel);
        return irq_assert_count[channel];
    endfunction

    function bit is_active(int channel);
        return irq_active[channel];
    endfunction

    task print_summary();
        $display("\n========================================================");
        $display("             INTERRUPT MONITOR VIP SUMMARY              ");
        $display("========================================================");
        for (int ch = 0; ch < NUM_IRQS; ch++) begin
            $display("  Channel %0d [%-10s]: Assertions = %0d, Deassertions = %0d, Active = %b",
                     ch, get_irq_name(ch), irq_assert_count[ch], irq_deassert_count[ch], irq_active[ch]);
        end
        $display("========================================================\n");
    endtask

endmodule: irq_monitor
