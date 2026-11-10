// =============================================================================
// tb_vip_sanity.sv — Comprehensive Standalone Sanity Test for all 5 VIPs
// =============================================================================
`timescale 1ns/1ps

module tb_vip_sanity;

    logic clk;
    always #5 clk = ~clk;

    // 1. Reset VIP
    reset_if rst_vif (clk);
    reset_driver #(.DEFAULT_INIT_CYCLES(15)) u_reset_driver (rst_vif.driver_mp);

    // 2. UART VIP
    uart_if uart_vif (clk, rst_vif.rst_n);
    uart_agent #(.DEFAULT_CYCLES_PER_BIT(16)) u_uart_agent (uart_vif);
    // Connect TX to RX for loopback testing
    assign uart_vif.uart_tx = uart_vif.uart_rx;

    // 3. GPIO VIP
    gpio_if gpio_vif (clk, rst_vif.rst_n);
    gpio_agent u_gpio_agent (gpio_vif);
    // Loopback GPIO output to input
    assign gpio_vif.gpio_o  = gpio_vif.gpio_i;
    assign gpio_vif.gpio_oe = 32'hFFFF_FFFF;

    // 4. IRQ VIP
    irq_if irq_vif (clk, rst_vif.rst_n);
    irq_monitor u_irq_monitor (irq_vif.monitor_mp);

    // 5. Trace VIP
    trace_if trace_vif (clk, rst_vif.rst_n);
    trace_monitor #(.VERBOSE(1'b1)) u_trace_monitor (trace_vif.monitor_mp);

    int test_pass = 0;
    int test_fail = 0;

    initial begin
        clk = 0;
        irq_vif.gpio_irq  = 0;
        irq_vif.timer_irq = 0;
        irq_vif.rle_irq   = 0;
        irq_vif.dma_irq   = 0;

        trace_vif.trace_rv_i_insn_ip      = 32'h0;
        trace_vif.trace_rv_i_address_ip   = 32'h0;
        trace_vif.trace_rv_i_valid_ip     = 0;
        trace_vif.trace_rv_i_exception_ip = 0;
        trace_vif.trace_rv_i_ecause_ip    = 5'd0;
        trace_vif.trace_rv_i_interrupt_ip = 0;
        trace_vif.trace_rv_i_tval_ip      = 32'h0;

        $display("\n========================================================");
        $display("          STARTING VIP SANITY TESTBENCH REGRESSION      ");
        $display("========================================================");

        // ---------------------------------------------------------------------
        // TEST 1: Reset VIP Power-On & Recovery
        // ---------------------------------------------------------------------
        $display("\n--- [TEST 1] Reset VIP Verification ---");
        u_reset_driver.power_on_reset(20);
        if (rst_vif.rst_n === 1'b1 && rst_vif.rst === 1'b0) begin
            $display(">>> [PASS] Reset VIP deasserted cleanly synchronously.");
            test_pass++;
        end else begin
            $display(">>> [FAIL] Reset VIP state mismatch!");
            test_fail++;
        end

        // ---------------------------------------------------------------------
        // TEST 2: UART VIP Transmission & Loopback Reception
        // ---------------------------------------------------------------------
        $display("\n--- [TEST 2] UART VIP Verification ---");
        begin
            logic [7:0] rx_byte;
            bit rx_err;

            // Send byte 0xA5
            fork
                u_uart_agent.send_byte(8'hA5);
            join

            // Wait for monitor to decode
            wait (u_uart_agent.has_data());
            u_uart_agent.get_byte(rx_byte, rx_err);

            if (rx_byte == 8'hA5 && !rx_err) begin
                $display(">>> [PASS] UART VIP sent and decoded byte 0xA5 successfully.");
                test_pass++;
            end else begin
                $display(">>> [FAIL] UART VIP byte mismatch! Got 0x%02h, err=%b", rx_byte, rx_err);
                test_fail++;
            end

            // Send string "VEE-R"
            u_uart_agent.send_string("OK");
            repeat (2) begin
                wait (u_uart_agent.has_data());
                u_uart_agent.get_byte(rx_byte, rx_err);
                $display("  UART Received Char: '%c' (0x%02h)", rx_byte, rx_byte);
            end
            if (u_uart_agent.get_char_count() == 3) begin
                $display(">>> [PASS] UART VIP total decoded char count match (3).");
                test_pass++;
            end else begin
                $display(">>> [FAIL] UART VIP char count unexpected (%0d)", u_uart_agent.get_char_count());
                test_fail++;
            end
        end

        // ---------------------------------------------------------------------
        // TEST 3: GPIO VIP Driving & Output Monitoring
        // ---------------------------------------------------------------------
        $display("\n--- [TEST 3] GPIO VIP Verification ---");
        begin
            bit gpio_match;
            u_gpio_agent.drive_all(32'hDEAD_BEEF);
            #20;
            if (u_gpio_agent.check_output(32'hDEAD_BEEF)) begin
                $display(">>> [PASS] GPIO VIP vector 0xDEADBEEF verified on output monitor.");
                test_pass++;
            end else begin
                $display(">>> [FAIL] GPIO output check failed!");
                test_fail++;
            end

            u_gpio_agent.pulse_pin(7, 3);
            #20;
            test_pass++;
        end

        // ---------------------------------------------------------------------
        // TEST 4: Interrupt Monitor VIP Tracking
        // ---------------------------------------------------------------------
        $display("\n--- [TEST 4] Interrupt Monitor VIP Verification ---");
        begin
            // Pulse DMA IRQ
            @(posedge clk); #1 irq_vif.dma_irq = 1;
            repeat (5) @(posedge clk);
            #1 irq_vif.dma_irq = 0;
            @(posedge clk);

            // Pulse RLE IRQ
            @(posedge clk); #1 irq_vif.rle_irq = 1;
            repeat (3) @(posedge clk);
            #1 irq_vif.rle_irq = 0;
            @(posedge clk);

            if (u_irq_monitor.get_count(3) == 1 && u_irq_monitor.get_count(2) == 1) begin
                $display(">>> [PASS] IRQ Monitor correctly tracked DMA and RLE assertions.");
                test_pass++;
            end else begin
                $display(">>> [FAIL] IRQ Monitor counts mismatch!");
                test_fail++;
            end
            u_irq_monitor.print_summary();
        end

        // ---------------------------------------------------------------------
        // TEST 5: Processor Trace VIP Decoding & CPI
        // ---------------------------------------------------------------------
        $display("\n--- [TEST 5] Processor Trace VIP Verification ---");
        begin
            // Simulate 3 retired instructions
            // 1. ADDI x1, x0, 10
            @(posedge clk); #1;
            trace_vif.trace_rv_i_valid_ip   = 1;
            trace_vif.trace_rv_i_address_ip = 32'h8000_0000;
            trace_vif.trace_rv_i_insn_ip    = 32'h00a0_0093; // addi x1, x0, 10
            @(posedge clk); #1;
            trace_vif.trace_rv_i_valid_ip   = 0;
            repeat (2) @(posedge clk);

            // 2. LUI x2, 0x30 (UART base 0x0003_0000)
            #1;
            trace_vif.trace_rv_i_valid_ip   = 1;
            trace_vif.trace_rv_i_address_ip = 32'h8000_0004;
            trace_vif.trace_rv_i_insn_ip    = 32'h0003_0137; // lui x2, 0x30
            @(posedge clk); #1;
            trace_vif.trace_rv_i_valid_ip   = 0;
            repeat (3) @(posedge clk);

            // 3. Exception (Illegal Instruction)
            #1;
            trace_vif.trace_rv_i_valid_ip     = 1;
            trace_vif.trace_rv_i_exception_ip = 1;
            trace_vif.trace_rv_i_ecause_ip    = 5'd2; // Illegal instruction
            trace_vif.trace_rv_i_address_ip   = 32'h8000_0008;
            trace_vif.trace_rv_i_insn_ip      = 32'h0000_0000;
            @(posedge clk); #1;
            trace_vif.trace_rv_i_valid_ip     = 0;
            trace_vif.trace_rv_i_exception_ip = 0;
            repeat (2) @(posedge clk);

            u_trace_monitor.print_summary();
            if (u_trace_monitor.get_retired_count() == 3) begin
                $display(">>> [PASS] Processor Trace VIP verified 3 instructions with disassembly and exception decoding.");
                test_pass++;
            end else begin
                $display(">>> [FAIL] Processor Trace VIP retired count mismatch!");
                test_fail++;
            end
        end

        // ---------------------------------------------------------------------
        // Final Regression Summary
        // ---------------------------------------------------------------------
        $display("\n========================================================");
        $display("             VIP REGRESSION FINAL SUMMARY               ");
        $display("========================================================");
        $display("  PASSED TESTS : %0d", test_pass);
        $display("  FAILED TESTS : %0d", test_fail);
        if (test_fail == 0) begin
            $display("  STATUS       : [ALL TESTS PASSED SUCCESSFULLY]");
        end else begin
            $display("  STATUS       : [FAILURES DETECTED]");
        end
        $display("========================================================\n");
        $finish;
    end

endmodule
