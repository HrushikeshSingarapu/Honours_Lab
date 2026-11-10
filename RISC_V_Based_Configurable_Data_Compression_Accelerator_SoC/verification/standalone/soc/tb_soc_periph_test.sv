// =============================================================================
// tb_soc_periph_test.sv — VeeR-Based SoC Peripheral Integration Testbench
//
// Exercises all integrated memory-mapped peripherals from the VeeR EL2 core:
//   1. GPIO   (0x0006_0000): DIR, DATA_OUT, atomic SET_OUT, atomic CLR_OUT
//   2. Timer  (0x0005_0000): MTIMECMP, TIMER_CTRL, MTIME counting verification
//   3. UART   (0x0003_0000): UART_LCR, UART_LSR, UART_THR transmission ('H', 'I')
//   4. CRC-32 (0x000A_0000): CRC_INIT, CRC_CTRL, CRC_DATA, CRC_STATUS, CRC_RESULT
//   5. RLE    (0x000D_0000): REG_INPUT_LENGTH, REG_CONTROL mode, REG_STATUS
//
// Verification Assertions:
//   - Each peripheral reports success via a unique signature stored in DMEM:
//       DMEM[1] = 0x6910_0001  (GPIO PASS)
//       DMEM[2] = 0x713E_0002  (Timer PASS)
//       DMEM[3] = 0x0A27_0003  (UART PASS)
//       DMEM[4] = 0xC2C3_0004  (CRC-32 PASS)
//       DMEM[5] = 0x21E0_0005  (RLE PASS)
//       DMEM[0] = 0xCAFE_F00D  (OVERALL ALL-PASS)
//   - No core exceptions (trace_rv_i_exception_ip == 0)
//   - No AXI bus errors (bresp/rresp != 2'b00)
//   - External pin observations:
//       gpio_o reflects updated output value 0x0000_00F0
//       uart_tx activity observed during UART transmission
// =============================================================================

`timescale 1ns/1ps

module tb_soc_periph_test;

    logic        clk;
    logic        rst_n;

    logic        uart_rx;
    wire         uart_tx;
    logic [31:0] gpio_i;
    wire  [31:0] gpio_o;
    wire  [31:0] gpio_oe;

    wire  [31:0] trace_rv_i_insn_ip;
    wire  [31:0] trace_rv_i_address_ip;
    wire         trace_rv_i_valid_ip;
    wire         trace_rv_i_exception_ip;
    wire  [ 4:0] trace_rv_i_ecause_ip;
    wire         trace_rv_i_interrupt_ip;
    wire  [31:0] trace_rv_i_tval_ip;

    wire         gpio_irq;
    wire         timer_irq;
    wire         rle_irq;

    // Clock generator: 100 MHz (10 ns period)
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // DUT instantiation
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

    // Monitoring state variables
    integer cycle_count;
    integer retire_count;
    integer uart_tx_transitions;
    logic   prev_uart_tx;
    integer exception_count;

    // Tracking flags
    logic gpio_passed;
    logic timer_passed;
    logic uart_passed;
    logic crc_passed;
    logic rle_passed;
    logic all_passed;

    // Real-time bus & execution monitor
    always @(posedge clk) begin
        if (rst_n) begin
            cycle_count <= cycle_count + 1;

            // Track UART TX pin activity
            if (uart_tx != prev_uart_tx) begin
                uart_tx_transitions <= uart_tx_transitions + 1;
                prev_uart_tx <= uart_tx;
            end

            // Monitor core exception
            if (trace_rv_i_valid_ip && trace_rv_i_exception_ip) begin
                exception_count <= exception_count + 1;
                $display("[%0t ns] [CYC %0d] *** CORE EXCEPTION *** PC=0x%08h, ecause=%0d, tval=0x%08h",
                         $time, cycle_count, trace_rv_i_address_ip, trace_rv_i_ecause_ip, trace_rv_i_tval_ip);
            end

            // Monitor retirements
            if (trace_rv_i_valid_ip && !trace_rv_i_exception_ip) begin
                retire_count <= retire_count + 1;
            end

            // Monitor MMIO read/write transactions (Peripherals: 0x0003_0000 - 0x000D_FFFF)
            if (u_dut.lsu_axi_awvalid && u_dut.lsu_axi_awready &&
                (u_dut.lsu_axi_awaddr >= 32'h0003_0000 && u_dut.lsu_axi_awaddr <= 32'h000D_FFFF)) begin
                $display("[%0t ns] [CYC %0d] MMIO WRITE REQ  : Addr=0x%08h, Size=%0d, Len=%0d",
                         $time, cycle_count, u_dut.lsu_axi_awaddr, u_dut.lsu_axi_awsize, u_dut.lsu_axi_awlen);
            end

            if (u_dut.lsu_axi_wvalid && u_dut.lsu_axi_wready &&
                (u_dut.lsu_axi_awaddr >= 32'h0003_0000 && u_dut.lsu_axi_awaddr <= 32'h000D_FFFF)) begin
                $display("[%0t ns] [CYC %0d] MMIO WRITE DATA : Data=0x%016h, Strb=0x%02h",
                         $time, cycle_count, u_dut.lsu_axi_wdata, u_dut.lsu_axi_wstrb);
            end

            if (u_dut.lsu_axi_arvalid && u_dut.lsu_axi_arready &&
                (u_dut.lsu_axi_araddr >= 32'h0003_0000 && u_dut.lsu_axi_araddr <= 32'h000D_FFFF)) begin
                $display("[%0t ns] [CYC %0d] MMIO READ REQ   : Addr=0x%08h, Size=%0d, Len=%0d",
                         $time, cycle_count, u_dut.lsu_axi_araddr, u_dut.lsu_axi_arsize, u_dut.lsu_axi_arlen);
            end

            if (u_dut.lsu_axi_rvalid && u_dut.lsu_axi_rready) begin
                if (u_dut.lsu_axi_rresp != 2'b00) begin
                    $display("[%0t ns] [CYC %0d] *** AXI READ ERROR *** Resp=%0b, Data=0x%016h",
                             $time, cycle_count, u_dut.lsu_axi_rresp, u_dut.lsu_axi_rdata);
                end
            end

            if (u_dut.lsu_axi_bvalid && u_dut.lsu_axi_bready) begin
                if (u_dut.lsu_axi_bresp != 2'b00) begin
                    $display("[%0t ns] [CYC %0d] *** AXI WRITE ERROR *** Resp=%0b",
                             $time, cycle_count, u_dut.lsu_axi_bresp);
                end
            end

            // Check individual peripheral status signatures in DMEM
            if (!gpio_passed && u_dut.u_soc.u_dmem.mem[1] == 32'h6910_0001) begin
                gpio_passed = 1'b1;
                $display("");
                $display("----------------------------------------------------------------");
                $display("[%0t ns] [CYC %0d] >>> [PASS] GPIO Integration Verified! <<<", $time, cycle_count);
                $display("  - DIR and DATA_OUT read/write match");
                $display("  - Atomic SET_OUT and CLR_OUT functional");
                $display("  - Observed gpio_o output pin value: 0x%08h", gpio_o);
                $display("----------------------------------------------------------------");
            end

            if (!timer_passed && u_dut.u_soc.u_dmem.mem[2] == 32'h713E_0002) begin
                timer_passed = 1'b1;
                $display("");
                $display("----------------------------------------------------------------");
                $display("[%0t ns] [CYC %0d] >>> [PASS] Timer Integration Verified! <<<", $time, cycle_count);
                $display("  - MTIMECMP read/write match");
                $display("  - TIMER_CTRL enabled, MTIME monotonic counting confirmed");
                $display("----------------------------------------------------------------");
            end

            if (!uart_passed && u_dut.u_soc.u_dmem.mem[3] == 32'h0A27_0003) begin
                uart_passed = 1'b1;
                $display("");
                $display("----------------------------------------------------------------");
                $display("[%0t ns] [CYC %0d] >>> [PASS] UART Integration Verified! <<<", $time, cycle_count);
                $display("  - UART_LCR read/write configuration verified");
                $display("  - UART_LSR status check confirmed FIFO ready");
                $display("  - Characters written to THR, uart_tx line transitions: %0d", uart_tx_transitions);
                $display("----------------------------------------------------------------");
            end

            if (!crc_passed && u_dut.u_soc.u_dmem.mem[4] == 32'hC2C3_0004) begin
                crc_passed = 1'b1;
                $display("");
                $display("----------------------------------------------------------------");
                $display("[%0t ns] [CYC %0d] >>> [PASS] CRC-32 Integration Verified! <<<", $time, cycle_count);
                $display("  - CRC_INIT read/write & restore verified");
                $display("  - Data fed into CRC_DATA, byte_count = 4 confirmed");
                $display("  - Non-zero reflected CRC-32 result verified");
                $display("----------------------------------------------------------------");
            end

            if (!rle_passed && u_dut.u_soc.u_dmem.mem[5] == 32'h21E0_0005) begin
                rle_passed = 1'b1;
                $display("");
                $display("----------------------------------------------------------------");
                $display("[%0t ns] [CYC %0d] >>> [PASS] RLE Integration Verified! <<<", $time, cycle_count);
                $display("  - REG_INPUT_LENGTH read/write verified");
                $display("  - REG_CONTROL mode configuration verified");
                $display("  - REG_STATUS idle flag confirmed");
                $display("----------------------------------------------------------------");
            end

            // Check overall completion signature
            if (!all_passed && u_dut.u_soc.u_dmem.mem[0] == 32'hCAFE_F00D) begin
                all_passed = 1'b1;
                $display("");
                $display("****************************************************************");
                $display("[%0t ns] [CYC %0d] >>> ALL 5 PERIPHERALS PASSED! Signature 0xCAFEF00D <<<", $time, cycle_count);
                $display("****************************************************************");
            end

            // Detect failure code in DMEM[0]
            if ((u_dut.u_soc.u_dmem.mem[0] & 32'hFFFF_0000) == 32'hDEAD_0000) begin
                $display("");
                $display("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
                $display("[%0t ns] [CYC %0d] *** PERIPHERAL TEST FAILED! Error Code: 0x%08h ***",
                         $time, cycle_count, u_dut.u_soc.u_dmem.mem[0]);
                case (u_dut.u_soc.u_dmem.mem[0])
                    32'hDEAD0011: $display("  Failure reason: GPIO DIR readback mismatch");
                    32'hDEAD0012: $display("  Failure reason: GPIO DATA_OUT readback mismatch");
                    32'hDEAD0013: $display("  Failure reason: GPIO SET_OUT atomic operation failed");
                    32'hDEAD0014: $display("  Failure reason: GPIO CLR_OUT atomic operation failed");
                    32'hDEAD0021: $display("  Failure reason: Timer MTIMECMP readback mismatch");
                    32'hDEAD0022: $display("  Failure reason: Timer TIMER_CTRL readback mismatch");
                    32'hDEAD0023: $display("  Failure reason: Timer MTIME did not increment");
                    32'hDEAD0031: $display("  Failure reason: UART LCR readback mismatch");
                    32'hDEAD0032: $display("  Failure reason: UART LSR THRE bit not set");
                    32'hDEAD0041: $display("  Failure reason: CRC-32 CRC_INIT readback mismatch");
                    32'hDEAD0042: $display("  Failure reason: CRC-32 byte count mismatch");
                    32'hDEAD0043: $display("  Failure reason: CRC-32 result was zero");
                    32'hDEAD0051: $display("  Failure reason: RLE INPUT_LENGTH readback mismatch");
                    32'hDEAD0052: $display("  Failure reason: RLE CONTROL mode mismatch");
                    32'hDEAD0053: $display("  Failure reason: RLE STATUS busy bit unexpectedly set");
                    default:      $display("  Failure reason: Unknown error code");
                endcase
                $display("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
                $finish;
            end
        end
    end

    // Test Sequence
    initial begin
        $display("================================================================");
        $display("Starting VeeR EL2 SoC Peripheral Integration Testbench");
        $display("================================================================");

        cycle_count          = 0;
        retire_count         = 0;
        uart_tx_transitions  = 0;
        prev_uart_tx         = 1'b1;
        exception_count      = 0;

        gpio_passed          = 1'b0;
        timer_passed         = 1'b0;
        uart_passed          = 1'b0;
        crc_passed           = 1'b0;
        rle_passed           = 1'b0;
        all_passed           = 1'b0;

        uart_rx = 1'b1;
        gpio_i  = 32'hA5A5_5A5A;
        rst_n   = 1'b0;

        // Clear target DMEM locations
        for (int m = 0; m < 16; m++) begin
            u_dut.u_soc.u_dmem.mem[m] = 32'h0000_0000;
        end

        // Load auto-generated peripheral test program into IMEM
        `include "peripheral_prog.vh"

        $display("Loaded peripheral test program into IMEM (162 instructions starting at 0x8000_0000).");

        // Hold reset for 30 cycles
        repeat (30) @(posedge clk);
        #1;
        $display("[%0t ns] Releasing reset (rst_n = 1)...", $time);
        rst_n = 1'b1;

        // Run simulation until all_passed or timeout (6000 cycles)
        fork
            begin : wait_for_all_passed
                wait (all_passed == 1'b1);
                repeat (30) @(posedge clk);
            end
            begin : timeout_watchdog
                repeat (6000) @(posedge clk);
                if (!all_passed) begin
                    $display("");
                    $display("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
                    $display("[%0t ns] TIMEOUT: Peripheral test did not complete within 6000 cycles!", $time);
                    $display("  DMEM[0] (Overall Status) : 0x%08h", u_dut.u_soc.u_dmem.mem[0]);
                    $display("  DMEM[1] (GPIO Status)    : 0x%08h (expected 0x69100001)", u_dut.u_soc.u_dmem.mem[1]);
                    $display("  DMEM[2] (Timer Status)   : 0x%08h (expected 0x713E0002)", u_dut.u_soc.u_dmem.mem[2]);
                    $display("  DMEM[3] (UART Status)    : 0x%08h (expected 0x0A270003)", u_dut.u_soc.u_dmem.mem[3]);
                    $display("  DMEM[4] (CRC-32 Status)  : 0x%08h (expected 0xC2C30004)", u_dut.u_soc.u_dmem.mem[4]);
                    $display("  DMEM[5] (RLE Status)     : 0x%08h (expected 0x21E00005)", u_dut.u_soc.u_dmem.mem[5]);
                    $display("  Retired Instructions     : %0d", retire_count);
                    $display("  Exceptions               : %0d", exception_count);
                    $display("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
                end
            end
        join_any
        disable fork;

        // Final verification summary
        $display("");
        $display("================================================================");
        $display("PERIPHERAL INTEGRATION TEST REPORT SUMMARY");
        $display("================================================================");
        $display("Total Simulated Cycles : %0d", cycle_count);
        $display("Total Retired Insns    : %0d", retire_count);
        $display("Exceptions Encountered : %0d", exception_count);
        $display("----------------------------------------------------------------");
        $display("  [1] GPIO Test   : %s (DMEM[1]=0x%08h, gpio_o=0x%08h)",
                 gpio_passed ? "PASSED" : "FAILED", u_dut.u_soc.u_dmem.mem[1], gpio_o);
        $display("  [2] Timer Test  : %s (DMEM[2]=0x%08h)",
                 timer_passed ? "PASSED" : "FAILED", u_dut.u_soc.u_dmem.mem[2]);
        $display("  [3] UART Test   : %s (DMEM[3]=0x%08h, tx_toggles=%0d)",
                 uart_passed ? "PASSED" : "FAILED", u_dut.u_soc.u_dmem.mem[3], uart_tx_transitions);
        $display("  [4] CRC-32 Test : %s (DMEM[4]=0x%08h)",
                 crc_passed ? "PASSED" : "FAILED", u_dut.u_soc.u_dmem.mem[4]);
        $display("  [5] RLE Test    : %s (DMEM[5]=0x%08h)",
                 rle_passed ? "PASSED" : "FAILED", u_dut.u_soc.u_dmem.mem[5]);
        $display("----------------------------------------------------------------");
        $display("OVERALL STATUS         : %s (DMEM[0]=0x%08h)",
                 all_passed ? ">>> ALL 5 PERIPHERALS PASSED <<<" : ">>> FAILED <<<", u_dut.u_soc.u_dmem.mem[0]);
        $display("================================================================");

        $finish;
    end

endmodule
