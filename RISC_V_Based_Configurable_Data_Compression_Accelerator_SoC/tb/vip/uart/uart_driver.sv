// =============================================================================
// uart_driver.sv — UART Serial Transmitter / Stimulus Driver
// =============================================================================
`timescale 1ns/1ps

module uart_driver #(
    parameter int DEFAULT_CYCLES_PER_BIT = 17
)(
    uart_if.driver_mp vif
);
    import vip_types_pkg::*;
    import uart_pkg::*;

    uart_config_t cfg;

    initial begin
        cfg = get_default_uart_config(DEFAULT_CYCLES_PER_BIT);
        vif.uart_rx = 1'b1; // UART idle line is HIGH
    end

    function void set_config(uart_config_t new_cfg);
        cfg = new_cfg;
    endfunction

    function int get_cycles();
        if (cfg.cycles_per_bit > 0)
            return cfg.cycles_per_bit;
        else if (cfg.baud_rate > 0 && cfg.clock_freq_hz > 0)
            return (cfg.clock_freq_hz / cfg.baud_rate);
        else
            return DEFAULT_CYCLES_PER_BIT;
    endfunction

    // Compute parity bit
    function logic calc_parity(logic [7:0] d);
        case (cfg.parity)
            UART_PARITY_ODD:   return ~(^d);
            UART_PARITY_EVEN:  return (^d);
            UART_PARITY_MARK:  return 1'b1;
            UART_PARITY_SPACE: return 1'b0;
            default:           return 1'b0;
        endcase
    endfunction

    // Transmit a single byte over uart_rx line
    task send_byte(input logic [7:0] byte_data);
        int bit_cycles;
        int num_bits;
        logic par_bit;
        bit_cycles = get_cycles();
        num_bits   = (cfg.data_bits > 0 && cfg.data_bits <= 8) ? cfg.data_bits : 8;

        // Wait until out of reset
        while (!vif.rst_n) @(posedge vif.clk);

        // 1. Start Bit (Logic 0)
        vif.uart_rx <= 1'b0;
        repeat (bit_cycles) @(posedge vif.clk);

        // 2. Data Bits (LSB first)
        for (int i = 0; i < num_bits; i++) begin
            vif.uart_rx <= byte_data[i];
            repeat (bit_cycles) @(posedge vif.clk);
        end

        // 3. Parity Bit (Optional)
        if (cfg.parity != UART_PARITY_NONE) begin
            par_bit = calc_parity(byte_data);
            vif.uart_rx <= par_bit;
            repeat (bit_cycles) @(posedge vif.clk);
        end

        // 4. Stop Bit(s) (Logic 1)
        vif.uart_rx <= 1'b1;
        repeat (bit_cycles * cfg.stop_bits) @(posedge vif.clk);
    endtask

    // Transmit a string
    task send_string(input string str);
        for (int i = 0; i < str.len(); i++) begin
            send_byte(str[i]);
        end
    endtask

    // Send a break condition (line held low)
    task send_break(input int bit_periods = 10);
        int bit_cycles;
        bit_cycles = get_cycles();
        vif.uart_rx <= 1'b0;
        repeat (bit_cycles * bit_periods) @(posedge vif.clk);
        vif.uart_rx <= 1'b1;
        repeat (bit_cycles) @(posedge vif.clk);
    endtask

endmodule: uart_driver
