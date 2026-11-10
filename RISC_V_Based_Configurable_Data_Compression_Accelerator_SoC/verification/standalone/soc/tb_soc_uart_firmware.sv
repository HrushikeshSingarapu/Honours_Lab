`timescale 1ns/1ps

module tb_soc_uart_firmware;

    logic clk;
    logic rst_n;

    logic uart_rx;
    wire uart_tx;

    logic [31:0] gpio_i;
    wire [31:0] gpio_o;
    wire [31:0] gpio_oe;

    wire [31:0] trace_rv_i_insn_ip;
    wire [31:0] trace_rv_i_address_ip;
    wire trace_rv_i_valid_ip;
    wire trace_rv_i_exception_ip;
    wire [4:0] trace_rv_i_ecause_ip;
    wire trace_rv_i_interrupt_ip;
    wire [31:0] trace_rv_i_tval_ip;

    wire gpio_irq;
    wire timer_irq;
    wire rle_irq;

    integer uart_tx_transitions;
    logic prev_uart_tx;

    initial clk = 0;
    always #5 clk = ~clk;

    soc_core_top #(
        .IMEM_DEPTH(16384),
        .DMEM_DEPTH(32768)
    ) u_dut (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .uart_rx                (uart_rx),
        .uart_tx                (uart_tx),
        .gpio_i                 (gpio_i),
        .gpio_o                 (gpio_o),
        .gpio_oe                (gpio_oe),
        .trace_rv_i_insn_ip     (trace_rv_i_insn_ip),
        .trace_rv_i_address_ip  (trace_rv_i_address_ip),
        .trace_rv_i_valid_ip    (trace_rv_i_valid_ip),
        .trace_rv_i_exception_ip(trace_rv_i_exception_ip),
        .trace_rv_i_ecause_ip   (trace_rv_i_ecause_ip),
        .trace_rv_i_interrupt_ip(trace_rv_i_interrupt_ip),
        .trace_rv_i_tval_ip     (trace_rv_i_tval_ip),
        .gpio_irq               (gpio_irq),
        .timer_irq              (timer_irq),
        .rle_irq                (rle_irq)
    );

    initial begin
`ifdef FSDB
        $fsdbDumpfile("uart_firmware.fsdb");
        $fsdbDumpvars(0, tb_soc_uart_firmware);
`elsif VCD
        $dumpfile("uart_firmware.vcd");
        $dumpvars(0, tb_soc_uart_firmware);
`endif

        clk = 0;
        rst_n = 0;
        uart_rx = 1;
        gpio_i = 32'h00000000;

        uart_tx_transitions = 0;
        prev_uart_tx = 1;

        // Load the 27 words generated from the C firmware.
        begin
            int fd;
            fd = $fopen("firmware/images/uart_test_word.hex", "r");
            if (fd != 0) begin
                $fclose(fd);
                $readmemh("firmware/images/uart_test_word.hex", u_dut.u_soc.u_imem.mem);
            end else begin
                fd = $fopen("../firmware/images/uart_test_word.hex", "r");
                if (fd != 0) begin
                    $fclose(fd);
                    $readmemh("../firmware/images/uart_test_word.hex", u_dut.u_soc.u_imem.mem);
                end else begin
                    fd = $fopen("../../firmware/images/uart_test_word.hex", "r");
                    if (fd != 0) begin
                        $fclose(fd);
                        $readmemh("../../firmware/images/uart_test_word.hex", u_dut.u_soc.u_imem.mem);
                    end else begin
                        $readmemh("../../../firmware/images/uart_test_word.hex", u_dut.u_soc.u_imem.mem);
                    end
                end
            end
        end

        $display("==============================================");
        $display("VeeR EL2 C Firmware UART Test");
        $display("Loaded 27 firmware instruction words");
        $display("==============================================");

        repeat (30) @(posedge clk);
        #1;
        rst_n = 1;

        $display("[%0t] Reset released. Firmware executing.", $time);

        // Allow sufficient time for UART transmission.
        fork
            begin
                wait (u_uart_tx_monitor.char_count >= 2);
                repeat (100) @(posedge clk);
            end
            begin
                repeat (30000) @(posedge clk);
            end
        join_any
        disable fork;

        $display("");
        $display("UART TX transitions observed: %0d",
                 uart_tx_transitions);
        $display("Final UART TX level: %b", uart_tx);
        $display("Final PC: 0x%08h", trace_rv_i_address_ip);

        $display("Simulation completed.");
        $finish;
    end

    always @(posedge clk) begin
        if (rst_n) begin
            if (trace_rv_i_valid_ip && trace_rv_i_exception_ip) begin
                $display("[%0t] CORE EXCEPTION: PC=0x%08h ecause=%0d",
                         $time,
                         trace_rv_i_address_ip,
                         trace_rv_i_ecause_ip);
            end
        end
    end

    always @(uart_tx) begin
        if (rst_n && uart_tx !== prev_uart_tx) begin
            uart_tx_transitions = uart_tx_transitions + 1;
            prev_uart_tx = uart_tx;
        end
    end

endmodule
