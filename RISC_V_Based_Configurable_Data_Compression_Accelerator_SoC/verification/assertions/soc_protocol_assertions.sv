// =============================================================================
// soc_protocol_assertions.sv
//
// SoC Top-Level Passive Invariants & Quiescence Assertions
// Checks:
//   1. Reset quiescence on IRQs (timer, gpio, rle, dma), gpio_oe == 0, uart_tx == 1
//   2. Zero X/Z on external outputs and interrupts after reset deassertion
// =============================================================================

`timescale 1ns/1ps

module soc_protocol_assertions #(
    parameter string NAME = "SOC_CHECKER"
)(
    input wire        clk,
    input wire        rst_n,
    input wire        uart_tx,
    input wire [31:0] gpio_o,
    input wire [31:0] gpio_oe,
    input wire        timer_irq,
    input wire        gpio_irq,
    input wire        rle_irq,
    input wire        dma_irq
);

    int rst_low_cycles  = 0;
    int reset_err_count = 0;
    int x_err_count     = 0;

    always @(posedge clk) begin
        if (!rst_n) begin
            if ($time > 0) begin
                if (rst_low_cycles < 10) rst_low_cycles <= rst_low_cycles + 1;
                if (rst_low_cycles >= 1) begin
                    assert (timer_irq === 1'b0 && gpio_irq === 1'b0 &&
                            rle_irq === 1'b0 && dma_irq === 1'b0) else begin
                        $display("[%0t ns] [%s ERROR] IRQ asserted while rst_n=0 (t=%b g=%b r=%b d=%b)!",
                                 $time, NAME, timer_irq, gpio_irq, rle_irq, dma_irq);
                        reset_err_count++;
                    end
                    assert (gpio_oe === 32'h0) else begin
                        $display("[%0t ns] [%s ERROR] gpio_oe=0x%08x nonzero while rst_n=0!",
                                 $time, NAME, gpio_oe);
                        reset_err_count++;
                    end
                    assert (uart_tx === 1'b1) else begin
                        $display("[%0t ns] [%s ERROR] uart_tx not idle high while rst_n=0!",
                                 $time, NAME);
                        reset_err_count++;
                    end
                end
            end
        end else begin
            rst_low_cycles <= 0;

            assert (!$isunknown({uart_tx, gpio_o, gpio_oe, timer_irq, gpio_irq, rle_irq, dma_irq})) else begin
                $display("[%0t ns] [%s ERROR] Unknown X/Z on SoC external pins or IRQs!", $time, NAME);
                x_err_count++;
            end
        end
    end

    function int get_total_assertion_errors();
        return (reset_err_count + x_err_count);
    endfunction

endmodule: soc_protocol_assertions
