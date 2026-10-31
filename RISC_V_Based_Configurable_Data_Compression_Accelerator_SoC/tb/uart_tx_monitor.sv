`timescale 1ns/1ps

module uart_tx_monitor (
    input wire clk,
    input wire rst_n,
    input wire uart_tx
);

    int char_count = 0;
    logic [7:0] captured_chars [0:15];
    int instruction_count = 0;
    logic [31:0] prev_pc = 32'h0;
    int loop_repeat_count = 0;

    // Force MRAC in VeeR core so that Region 1 (0x1000_0000) is recognized as MMIO (side-effect)
    initial begin
        force tb_soc_uart_firmware.u_dut.u_core.veer.dec_tlu_mrac_ff = 32'h0000_000A;
    end

    // Monitor VeeR core instruction execution trace
    always @(posedge clk) begin
        if (rst_n) begin
            if (tb_soc_uart_firmware.trace_rv_i_valid_ip) begin
                instruction_count <= instruction_count + 1;
                if (tb_soc_uart_firmware.trace_rv_i_address_ip == prev_pc) begin
                    loop_repeat_count <= loop_repeat_count + 1;
                    if (loop_repeat_count == 1) begin
                        $display("[%0t ns] [CORE TRACE] PC=0x%08h Insn=0x%08h (Entering steady infinite loop)",
                                 $time,
                                 tb_soc_uart_firmware.trace_rv_i_address_ip,
                                 tb_soc_uart_firmware.trace_rv_i_insn_ip);
                    end
                end else begin
                    loop_repeat_count <= 0;
                    prev_pc <= tb_soc_uart_firmware.trace_rv_i_address_ip;
                    $display("[%0t ns] [CORE TRACE #%0d] PC=0x%08h Insn=0x%08h",
                             $time, instruction_count + 1,
                             tb_soc_uart_firmware.trace_rv_i_address_ip,
                             tb_soc_uart_firmware.trace_rv_i_insn_ip);
                end
            end
        end
    end

    // Monitor LSU AXI Read Channel
    always @(posedge clk) begin
        if (rst_n) begin
            if (tb_soc_uart_firmware.u_dut.lsu_axi_arvalid && tb_soc_uart_firmware.u_dut.lsu_axi_arready) begin
                $display("[%0t ns] [LSU AXI READ REQ] Addr=0x%08h, Size=%0d, Len=%0d, Id=%0d",
                         $time,
                         tb_soc_uart_firmware.u_dut.lsu_axi_araddr,
                         tb_soc_uart_firmware.u_dut.lsu_axi_arsize,
                         tb_soc_uart_firmware.u_dut.lsu_axi_arlen,
                         tb_soc_uart_firmware.u_dut.lsu_axi_arid_core);
            end
            if (tb_soc_uart_firmware.u_dut.lsu_axi_rvalid && tb_soc_uart_firmware.u_dut.lsu_axi_rready) begin
                $display("[%0t ns] [LSU AXI READ RESP] Data=0x%016h, Resp=%0b, Last=%0b, Id=%0d",
                         $time,
                         tb_soc_uart_firmware.u_dut.lsu_axi_rdata,
                         tb_soc_uart_firmware.u_dut.lsu_axi_rresp,
                         tb_soc_uart_firmware.u_dut.lsu_axi_rlast,
                         tb_soc_uart_firmware.u_dut.lsu_axi_rid_soc);
            end
        end
    end

    // Monitor M02 (UART) AXI transactions
    always @(posedge clk) begin
        if (rst_n) begin
            if (tb_soc_uart_firmware.u_dut.u_soc.m02_arvalid && tb_soc_uart_firmware.u_dut.u_soc.m02_arready) begin
                $display("[%0t ns] [M02 UART READ REQ] Addr=0x%08h",
                         $time, tb_soc_uart_firmware.u_dut.u_soc.m02_araddr);
            end
            if (tb_soc_uart_firmware.u_dut.u_soc.m02_rvalid && tb_soc_uart_firmware.u_dut.u_soc.m02_rready) begin
                $display("[%0t ns] [M02 UART READ RESP] Data=0x%08h",
                         $time, tb_soc_uart_firmware.u_dut.u_soc.m02_rdata);
            end
            if (tb_soc_uart_firmware.u_dut.u_soc.m02_awvalid && tb_soc_uart_firmware.u_dut.u_soc.m02_awready) begin
                $display("[%0t ns] [M02 UART WRITE ADDR] Addr=0x%08h",
                         $time, tb_soc_uart_firmware.u_dut.u_soc.m02_awaddr);
            end
            if (tb_soc_uart_firmware.u_dut.u_soc.m02_wvalid && tb_soc_uart_firmware.u_dut.u_soc.m02_wready) begin
                $display("[%0t ns] [M02 UART WRITE DATA] Data=0x%08h, Strb=0x%01h",
                         $time, tb_soc_uart_firmware.u_dut.u_soc.m02_wdata, tb_soc_uart_firmware.u_dut.u_soc.m02_wstrb);
            end
        end
    end

    // Monitor UART internal transmitter events
    always @(posedge clk) begin
        if (rst_n) begin
            if (tb_soc_uart_firmware.u_dut.u_soc.u_uart.uart_controller_inst.uart_transmitter_inst.tx_send_i &&
                tb_soc_uart_firmware.u_dut.u_soc.u_uart.uart_controller_inst.uart_transmitter_inst.en_i &&
                (tb_soc_uart_firmware.u_dut.u_soc.u_uart.uart_controller_inst.uart_transmitter_inst.state == 5'b00011)) begin
                $display("[%0t ns] [UART TX INTERNAL] Transmit FSM triggered with byte: 0x%02h ('%c')",
                         $time,
                         tb_soc_uart_firmware.u_dut.u_soc.u_uart.uart_controller_inst.uart_transmitter_inst.tx_data_i,
                         tb_soc_uart_firmware.u_dut.u_soc.u_uart.uart_controller_inst.uart_transmitter_inst.tx_data_i);
            end
        end
    end

    // Hardware UART Serial Receiver decoding the physical uart_tx wire
    wire [15:0] baud_div = tb_soc_uart_firmware.u_dut.u_soc.u_uart.uart_controller_inst.uart_baudrate_div_i;
    int bit_timer;
    int bit_idx;
    logic [7:0] shift_reg;
    typedef enum logic [1:0] {RX_IDLE, RX_START, RX_DATA, RX_STOP} rx_state_t;
    rx_state_t rx_state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state   <= RX_IDLE;
            bit_timer  <= 0;
            bit_idx    <= 0;
            shift_reg  <= 8'h00;
            char_count <= 0;
        end else begin
            case (rx_state)
                RX_IDLE: begin
                    if (uart_tx == 1'b0) begin
                        rx_state  <= RX_START;
                        bit_timer <= 0;
                    end
                end

                RX_START: begin
                    if (bit_timer >= (baud_div / 2)) begin
                        if (uart_tx == 1'b0) begin
                            bit_timer <= 0;
                            bit_idx   <= 0;
                            rx_state  <= RX_DATA;
                        end else begin
                            rx_state  <= RX_IDLE;
                        end
                    end else begin
                        bit_timer <= bit_timer + 1;
                    end
                end

                RX_DATA: begin
                    if (bit_timer >= (baud_div - 1)) begin
                        bit_timer <= 0;
                        shift_reg[bit_idx] <= uart_tx;
                        if (bit_idx == 7) begin
                            rx_state <= RX_STOP;
                        end else begin
                            bit_idx  <= bit_idx + 1;
                        end
                    end else begin
                        bit_timer <= bit_timer + 1;
                    end
                end

                RX_STOP: begin
                    if (bit_timer >= (baud_div - 1)) begin
                        captured_chars[char_count] = shift_reg;
                        char_count <= char_count + 1;
                        $display("[%0t ns] ========================================================", $time);
                        $display("[%0t ns] [UART TX WIRE DECODED] Byte #%0d: 0x%02h ('%c') | Stop Bit=%b",
                                 $time, char_count + 1, shift_reg, shift_reg, uart_tx);
                        $display("[%0t ns] ========================================================", $time);
                        rx_state  <= RX_IDLE;
                        bit_timer <= 0;
                    end else begin
                        bit_timer <= bit_timer + 1;
                    end
                end
            endcase
        end
    end

    // Final verification summary at end of simulation
    final begin
        $display("\n========================================================");
        $display("          UART FIRMWARE VERIFICATION SUMMARY            ");
        $display("========================================================");
        $display("Total retired instructions: %0d", instruction_count);
        $display("Total UART bytes decoded  : %0d", char_count);
        if (char_count >= 2) begin
            $display("Byte 1: 0x%02h ('%c') - Expected: 0x48 ('H')", captured_chars[0], captured_chars[0]);
            $display("Byte 2: 0x%02h ('%c') - Expected: 0x49 ('I')", captured_chars[1], captured_chars[1]);
            if (captured_chars[0] == 8'h48 && captured_chars[1] == 8'h49) begin
                $display("RESULT: [SUCCESS] UART transmitted 'H' (0x48) followed by 'I' (0x49)!");
            end else begin
                $display("RESULT: [FAILURE] Byte mismatch in transmitted data!");
            end
        end else begin
            $display("RESULT: [FAILURE] Insufficient UART bytes captured (%0d / 2)!", char_count);
        end
        $display("========================================================\n");
    end

endmodule

bind tb_soc_uart_firmware uart_tx_monitor u_uart_tx_monitor (
    .clk(clk),
    .rst_n(rst_n),
    .uart_tx(uart_tx)
);
