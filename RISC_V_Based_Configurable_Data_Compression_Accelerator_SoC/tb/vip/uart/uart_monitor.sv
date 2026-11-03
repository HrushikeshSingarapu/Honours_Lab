// =============================================================================
// uart_monitor.sv — UART Serial Receiver / Protocol Monitor
// =============================================================================
`timescale 1ns/1ps

module uart_monitor #(
    parameter int DEFAULT_CYCLES_PER_BIT = 17,
    parameter int QUEUE_DEPTH            = 1024
)(
    uart_if.monitor_mp vif
);
    import vip_types_pkg::*;
    import uart_pkg::*;

    uart_config_t cfg;

    // Received frame buffer
    uart_frame_t frame_queue [0:QUEUE_DEPTH-1];
    int wr_ptr = 0;
    int rd_ptr = 0;
    int total_chars_received = 0;
    int framing_errors = 0;
    int parity_errors = 0;

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_START,
        ST_DATA,
        ST_PARITY,
        ST_STOP
    } rx_state_e;

    rx_state_e state = ST_IDLE;
    int bit_timer = 0;
    int bit_idx = 0;
    logic [7:0] shift_reg = 8'h00;
    logic par_bit_rx = 1'b0;

    initial begin
        cfg = get_default_uart_config(DEFAULT_CYCLES_PER_BIT);
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

    function logic calc_parity(logic [7:0] d);
        case (cfg.parity)
            UART_PARITY_ODD:   return ~(^d);
            UART_PARITY_EVEN:  return (^d);
            UART_PARITY_MARK:  return 1'b1;
            UART_PARITY_SPACE: return 1'b0;
            default:           return 1'b0;
        endcase
    endfunction

    // Receiver FSM sampling DUT's uart_tx wire
    always @(posedge vif.clk or negedge vif.rst_n) begin
        if (!vif.rst_n) begin
            state        <= ST_IDLE;
            bit_timer    <= 0;
            bit_idx      <= 0;
            shift_reg    <= 8'h00;
        end else begin
            automatic int bit_cycles = get_cycles();
            automatic int num_bits   = (cfg.data_bits > 0 && cfg.data_bits <= 8) ? cfg.data_bits : 8;

            case (state)
                ST_IDLE: begin
                    if (vif.uart_tx == 1'b0) begin
                        state     <= ST_START;
                        bit_timer <= 0;
                    end
                end

                ST_START: begin
                    // Sample start bit at midpoint
                    if (bit_timer >= (bit_cycles / 2)) begin
                        if (vif.uart_tx == 1'b0) begin
                            // Legitimate start bit verified
                            state     <= ST_DATA;
                            bit_timer <= 0;
                            bit_idx   <= 0;
                            shift_reg <= 8'h00;
                        end else begin
                            // False start bit glitch
                            state     <= ST_IDLE;
                            bit_timer <= 0;
                        end
                    end else begin
                        bit_timer <= bit_timer + 1;
                    end
                end

                ST_DATA: begin
                    if (bit_timer >= (bit_cycles - 1)) begin
                        bit_timer <= 0;
                        shift_reg[bit_idx] <= vif.uart_tx;
                        if (bit_idx == num_bits - 1) begin
                            if (cfg.parity != UART_PARITY_NONE)
                                state <= ST_PARITY;
                            else
                                state <= ST_STOP;
                        end else begin
                            bit_idx <= bit_idx + 1;
                        end
                    end else begin
                        bit_timer <= bit_timer + 1;
                    end
                end

                ST_PARITY: begin
                    if (bit_timer >= (bit_cycles - 1)) begin
                        bit_timer   <= 0;
                        par_bit_rx  <= vif.uart_tx;
                        state       <= ST_STOP;
                    end else begin
                        bit_timer <= bit_timer + 1;
                    end
                end

                ST_STOP: begin
                    if (bit_timer >= (bit_cycles - 1)) begin
                        uart_frame_t frame;
                        bit framing_err;
                        bit parity_err;
                        framing_err = (vif.uart_tx !== 1'b1);
                        parity_err  = (cfg.parity != UART_PARITY_NONE) ?
                                      (par_bit_rx !== calc_parity(shift_reg)) : 1'b0;

                        frame.data        = shift_reg;
                        frame.framing_err = framing_err;
                        frame.parity_err  = parity_err;
                        frame.timestamp   = $time;

                        if (framing_err) framing_errors <= framing_errors + 1;
                        if (parity_err)  parity_errors  <= parity_errors + 1;

                        if ((wr_ptr + 1) % QUEUE_DEPTH != rd_ptr) begin
                            frame_queue[wr_ptr] = frame;
                            wr_ptr <= (wr_ptr + 1) % QUEUE_DEPTH;
                        end
                        total_chars_received <= total_chars_received + 1;

                        state     <= ST_IDLE;
                        bit_timer <= 0;
                    end else begin
                        bit_timer <= bit_timer + 1;
                    end
                end
            endcase
        end
    end

    // Accessor tasks
    function bit has_data();
        return (wr_ptr != rd_ptr);
    endfunction

    function int get_char_count();
        return total_chars_received;
    endfunction

    task get_frame(output uart_frame_t frame, output bit success);
        if (wr_ptr == rd_ptr) begin
            success = 1'b0;
        end else begin
            frame   = frame_queue[rd_ptr];
            rd_ptr  = (rd_ptr + 1) % QUEUE_DEPTH;
            success = 1'b1;
        end
    endtask

    task get_byte(output logic [7:0] data, output bit err);
        uart_frame_t fr;
        bit ok;
        get_frame(fr, ok);
        if (ok) begin
            data = fr.data;
            err  = fr.framing_err | fr.parity_err;
        end else begin
            data = 8'h00;
            err  = 1'b1;
        end
    endtask

endmodule: uart_monitor
