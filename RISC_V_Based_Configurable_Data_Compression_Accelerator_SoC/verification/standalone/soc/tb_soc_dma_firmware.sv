// =============================================================================
// tb_soc_dma_firmware.sv — VeeR EL2 SoC End-to-End DMA, RLE & CRC Verification
//
// Description:
//   Instantiates the complete VeeR EL2-based SoC (soc_core_top) including:
//     - Real VeeR EL2 RISC-V Core executing C firmware from reset vector 0x8000_0000
//     - Real AXI 4x8 Crossbar Interconnect
//     - Autonomous DMA Controller IP (0x000B_0000)
//     - Hardware Run-Length Encoding / Decoding Accelerator (0x000D_0000)
//     - Hardware IEEE 802.3 CRC-32 Peripheral (0x000A_0000)
//     - UART 16550 Console (0x0003_0000)
//     - 64 KB Instruction SRAM (IMEM) and 128 KB Data SRAM (DMEM)
//
// Verification Methodology:
//   1. Autonomous firmware running on VeeR CPU sets up test patterns in DMEM.
//   2. CPU programs DMA registers via AXI MMIO.
//   3. DMA autonomously orchestrates data movement from DMEM -> RLE -> DMEM.
//   4. Firmware verifies compression output length and compressed tokens.
//   5. DMA autonomously orchestrates decompression from DMEM -> RLE -> DMEM.
//   6. Firmware verifies reconstructed data matches original byte-by-byte.
//   7. Firmware feeds original and reconstructed data to CRC-32 MMIO peripheral
//      and validates match against independently calculated golden CRC.
//   8. Firmware writes completion signature 0xCAFE_D00D to DMEM[0].
//   9. Testbench autonomously performs independent cross-checks on memory buffers.
//  10. Strict watchdog timer guards against hangs or infinite loops.
// =============================================================================

`timescale 1ns/1ps

module tb_soc_dma_firmware;

    // Clock and Reset Signals
    logic clk;
    logic rst_n;

    // Peripheral IO Pins
    logic        uart_rx;
    wire         uart_tx;
    logic [31:0] gpio_i;
    wire  [31:0] gpio_o;
    wire  [31:0] gpio_oe;

    // VeeR Core Trace / Monitor Interface
    wire  [31:0] trace_rv_i_insn_ip;
    wire  [31:0] trace_rv_i_address_ip;
    wire         trace_rv_i_valid_ip;
    wire         trace_rv_i_exception_ip;
    wire  [ 4:0] trace_rv_i_ecause_ip;
    wire         trace_rv_i_interrupt_ip;
    wire  [31:0] trace_rv_i_tval_ip;

    // Interrupt Lines
    wire         gpio_irq;
    wire         timer_irq;
    wire         rle_irq;
    wire         dma_irq;

    // Clock Generation: 100 MHz (10 ns period)
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // DUT Instantiation: Complete VeeR EL2 SoC Subsystem
    // -------------------------------------------------------------------------
    soc_core_top #(
        .IMEM_DEPTH(16384), // 64 KB
        .DMEM_DEPTH(32768)  // 128 KB
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
        .rle_irq                (rle_irq),
        .dma_irq                (dma_irq)
    );

    // -------------------------------------------------------------------------
    // Testbench Tracking Variables
    // -------------------------------------------------------------------------
    integer cycle_count;
    integer retire_count;
    integer exception_count;
    integer dma_start_count;
    integer dma_done_count;

    logic pat1_passed;
    logic pat2_passed;
    logic pat3_passed;
    logic pat4_passed;
    logic all_passed;
    logic mem_match;

    // -------------------------------------------------------------------------
    // Real-Time Bus & Execution Monitoring
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst_n) begin
            cycle_count <= cycle_count + 1;

            // Monitor Instruction Retirements
            if (trace_rv_i_valid_ip && !trace_rv_i_exception_ip) begin
                retire_count <= retire_count + 1;
            end

            // Monitor Core Exceptions
            if (trace_rv_i_valid_ip && trace_rv_i_exception_ip) begin
                exception_count <= exception_count + 1;
                $display("[%0t ns] [CYC %0d] *** CORE EXCEPTION *** PC=0x%08h, ecause=%0d, tval=0x%08h",
                         $time, cycle_count, trace_rv_i_address_ip, trace_rv_i_ecause_ip, trace_rv_i_tval_ip);
            end

            // Monitor CPU writes to UART THR (0x00030000) for console display
            if (u_dut.u_soc.m02_wvalid && u_dut.u_soc.m02_wready && (u_dut.u_soc.m02_awaddr[11:0] == 12'h000)) begin
                $write("%c", u_dut.u_soc.m02_wdata[7:0]);
            end

            // Monitor DMA Register Operations (M06)
            if (u_dut.u_soc.m06_awvalid && u_dut.u_soc.m06_awready) begin
                case (u_dut.u_soc.m06_awaddr[11:0])
                    12'h000: begin
                        dma_start_count <= dma_start_count + 1;
                        $display("[%0t ns] [CYC %0d] [DMA MMIO] Write CONTROL=0x%08h (START=%0d, MODE=%s)",
                                 $time, cycle_count, u_dut.u_soc.m06_wdata,
                                 u_dut.u_soc.m06_wdata[0],
                                 u_dut.u_soc.m06_wdata[1] ? "DECOMPRESS" : "COMPRESS");
                    end
                    12'h008: $display("[%0t ns] [CYC %0d] [DMA MMIO] Set SRC_ADDR = 0x%08h", $time, cycle_count, u_dut.u_soc.m06_wdata);
                    12'h00C: $display("[%0t ns] [CYC %0d] [DMA MMIO] Set DST_ADDR = 0x%08h", $time, cycle_count, u_dut.u_soc.m06_wdata);
                    12'h010: $display("[%0t ns] [CYC %0d] [DMA MMIO] Set INPUT_LEN = %0d bytes", $time, cycle_count, u_dut.u_soc.m06_wdata[15:0]);
                    default: ;
                endcase
            end

            // Monitor DMA Done pulse
            if (u_dut.u_soc.u_dma.u_sequencer.status_done_pulse_o) begin
                dma_done_count <= dma_done_count + 1;
                $display("[%0t ns] [CYC %0d] [DMA HW] Transfer Completed! Produced %0d bytes.",
                         $time, cycle_count, u_dut.u_soc.u_dma.u_sequencer.status_output_len_o);
            end

            // Track Pattern Milestones in DMEM
            if (!pat1_passed && (u_dut.u_soc.u_dmem.mem[1] == 32'hD3A0_0001)) begin
                pat1_passed = 1'b1;
                $display("[%0t ns] [CYC %0d] >>> Pattern 1 Milestone Verified (DMEM[1]=0x%08h) <<<",
                         $time, cycle_count, u_dut.u_soc.u_dmem.mem[1]);
            end

            if (!pat2_passed && (u_dut.u_soc.u_dmem.mem[2] == 32'hD3A0_0002)) begin
                pat2_passed = 1'b1;
                $display("[%0t ns] [CYC %0d] >>> Pattern 2 Milestone Verified (DMEM[2]=0x%08h) <<<",
                         $time, cycle_count, u_dut.u_soc.u_dmem.mem[2]);
            end

            if (!pat3_passed && (u_dut.u_soc.u_dmem.mem[3] == 32'hD3A0_0003)) begin
                pat3_passed = 1'b1;
                $display("[%0t ns] [CYC %0d] >>> Pattern 3 Milestone Verified (DMEM[3]=0x%08h) <<<",
                         $time, cycle_count, u_dut.u_soc.u_dmem.mem[3]);
            end

            if (!pat4_passed && (u_dut.u_soc.u_dmem.mem[4] == 32'hD3A0_0004)) begin
                pat4_passed = 1'b1;
                $display("[%0t ns] [CYC %0d] >>> Pattern 4 Milestone Verified (DMEM[4]=0x%08h) <<<",
                         $time, cycle_count, u_dut.u_soc.u_dmem.mem[4]);
            end

            // Track Overall Completion Signature
            if (!all_passed && (u_dut.u_soc.u_dmem.mem[0] == 32'hCAFE_D00D)) begin
                all_passed = 1'b1;
                $display("\n****************************************************************");
                $display("[%0t ns] [CYC %0d] >>> FIRMWARE COMPLETION SIGNATURE 0xCAFED00D DETECTED! <<<", $time, cycle_count);
                $display("****************************************************************\n");
            end

            // Track Firmware Failure Reporting
            if ((u_dut.u_soc.u_dmem.mem[0] & 32'hFFFF_0000) == 32'hDEAD_0000) begin
                $display("\n!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
                $display("[%0t ns] [CYC %0d] *** FIRMWARE REPORTED FAILURE! Code: 0x%08h ***",
                         $time, cycle_count, u_dut.u_soc.u_dmem.mem[0]);
                case (u_dut.u_soc.u_dmem.mem[0][7:0])
                    8'h01: $display("  Reason: DMA Compression transfer failed / timeout");
                    8'h02: $display("  Reason: DMA Compression output length mismatch");
                    8'h03: $display("  Reason: Compressed data content mismatch against expected");
                    8'h04: $display("  Reason: DMA Decompression transfer failed / timeout");
                    8'h05: $display("  Reason: DMA Decompression output length mismatch");
                    8'h06: $display("  Reason: Decompressed data content mismatch against original");
                    8'h07: $display("  Reason: Hardware CRC-32 mismatch on original data");
                    8'h08: $display("  Reason: Hardware CRC-32 mismatch on reconstructed data");
                    default: $display("  Reason: Unknown error subtype");
                endcase
                $display("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n");
                $finish;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Main Verification Process
    // -------------------------------------------------------------------------
    initial begin
        $display("================================================================");
        $display("Starting VeeR EL2 SoC End-to-End DMA, RLE & CRC Verification TB");
        $display("================================================================");

        cycle_count     = 0;
        retire_count    = 0;
        exception_count = 0;
        dma_start_count = 0;
        dma_done_count  = 0;

        pat1_passed     = 1'b0;
        pat2_passed     = 1'b0;
        pat3_passed     = 1'b0;
        pat4_passed     = 1'b0;
        all_passed      = 1'b0;

        uart_rx = 1'b1;
        gpio_i  = 32'h0000_0000;
        rst_n   = 1'b0;

        // Clear target DMEM locations (word addresses 0 to 1023)
        for (int m = 0; m < 1024; m++) begin
            u_dut.u_soc.u_dmem.mem[m] = 32'h0000_0000;
        end

        // Load compiled RISC-V C firmware into IMEM
        begin
            int fd;
            fd = $fopen("firmware/images/dma_test_word.hex", "r");
            if (fd != 0) begin
                $fclose(fd);
                $readmemh("firmware/images/dma_test_word.hex", u_dut.u_soc.u_imem.mem);
            end else begin
                fd = $fopen("../firmware/images/dma_test_word.hex", "r");
                if (fd != 0) begin
                    $fclose(fd);
                    $readmemh("../firmware/images/dma_test_word.hex", u_dut.u_soc.u_imem.mem);
                end else begin
                    fd = $fopen("../../firmware/images/dma_test_word.hex", "r");
                    if (fd != 0) begin
                        $fclose(fd);
                        $readmemh("../../firmware/images/dma_test_word.hex", u_dut.u_soc.u_imem.mem);
                    end else begin
                        $readmemh("../../../firmware/images/dma_test_word.hex", u_dut.u_soc.u_imem.mem);
                    end
                end
            end
        end
        $display("[TB] Loaded compiled firmware into IMEM (dma_test_word.hex).");

        // Hold reset low for 30 cycles
        repeat (30) @(posedge clk);
        #1;
        $display("[%0t ns] Releasing reset (rst_n = 1). CPU starting from reset vector 0x8000_0000...", $time);
        rst_n = 1'b1;

        // Execution watchdog: 40,000 cycles
        fork
            begin : wait_for_completion
                wait (all_passed == 1'b1);
                repeat (100) @(posedge clk);
            end
            begin : timeout_watchdog
                repeat (40000) @(posedge clk);
                if (!all_passed) begin
                    $display("\n!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
                    $display("[%0t ns] TIMEOUT: Firmware did not reach 0xCAFED00D within 40,000 cycles!", $time);
                    $display("  DMEM[0] (Overall Status) : 0x%08h", u_dut.u_soc.u_dmem.mem[0]);
                    $display("  DMEM[1] (Pattern 1)      : 0x%08h (expected 0xD3A00001)", u_dut.u_soc.u_dmem.mem[1]);
                    $display("  DMEM[2] (Pattern 2)      : 0x%08h (expected 0xD3A00002)", u_dut.u_soc.u_dmem.mem[2]);
                    $display("  DMEM[3] (Pattern 3)      : 0x%08h (expected 0xD3A00003)", u_dut.u_soc.u_dmem.mem[3]);
                    $display("  DMEM[4] (Pattern 4)      : 0x%08h (expected 0xD3A00004)", u_dut.u_soc.u_dmem.mem[4]);
                    $display("  Current PC               : 0x%08h", trace_rv_i_address_ip);
                    $display("  Retired Instructions     : %0d", retire_count);
                    $display("  Exceptions Encountered   : %0d", exception_count);
                    $display("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n");
                    $finish;
                end
            end
        join_any
        disable fork;

        // ---------------------------------------------------------------------
        // Independent Testbench Verification Checks
        // ---------------------------------------------------------------------
        $display("\n----------------------------------------------------------------");
        $display("INDEPENDENT TESTBENCH MEMORY CROSS-CHECKS");
        $display("----------------------------------------------------------------");

        // Verify Pattern 4 final buffer contents in DMEM directly
        // SRC_BUF is at word offset 64 (0x0001_0100)
        // COMP_BUF is at word offset 192 (0x0001_0300)
        // DECOMP_BUF is at word offset 320 (0x0001_0500)
        mem_match = 1'b1;

        // 1. Verify that Decompressed Buffer exactly matches Source Buffer
        for (int w = 0; w < 8; w++) begin
            if (u_dut.u_soc.u_dmem.mem[64 + w] !== u_dut.u_soc.u_dmem.mem[320 + w]) begin
                $display("  [TB ERROR] Word %0d mismatch! SRC=0x%08h, DECOMP=0x%08h",
                         w, u_dut.u_soc.u_dmem.mem[64 + w], u_dut.u_soc.u_dmem.mem[320 + w]);
                mem_match = 1'b0;
            end
        end

        // 2. Verify that Compressed Buffer matches expected RLE tokens:
        //    Word 0: 0x2008_1008 (run 8 of 0x10, run 8 of 0x20)
        //    Word 1: 0x4008_3008 (run 8 of 0x30, run 8 of 0x40)
        if (u_dut.u_soc.u_dmem.mem[192] !== 32'h2008_1008 ||
            u_dut.u_soc.u_dmem.mem[193] !== 32'h4008_3008) begin
            $display("  [TB ERROR] Pattern 4 Compressed Buffer mismatch! Word0=0x%08h (exp 0x20081008), Word1=0x%08h (exp 0x40083008)",
                     u_dut.u_soc.u_dmem.mem[192], u_dut.u_soc.u_dmem.mem[193]);
            mem_match = 1'b0;
        end

        if (mem_match) begin
            $display("  [TB PASS] Decompressed buffer perfectly matches Source buffer!");
            $display("  [TB PASS] Compressed RLE tokens match expected encoding!");
        end else begin
            $display("  [TB FAIL] Independent memory check detected discrepancies!");
            $finish;
        end

        // ---------------------------------------------------------------------
        // Final Summary Report
        // ---------------------------------------------------------------------
        $display("\n================================================================");
        $display("FINAL VERIFICATION SUMMARY: VeeR CPU + DMA + RLE + CRC32");
        $display("================================================================");
        $display("Total Simulated Cycles   : %0d", cycle_count);
        $display("Total Retired Insns      : %0d", retire_count);
        $display("Core Exceptions          : %0d", exception_count);
        $display("Total DMA Transfers      : %0d (Starts: %0d, Completions: %0d)",
                 dma_done_count, dma_start_count, dma_done_count);
        $display("----------------------------------------------------------------");
        $display("  Pattern 1 (Short 8B)     : %s (DMEM[1]=0x%08h)", pat1_passed ? "PASSED" : "FAILED", u_dut.u_soc.u_dmem.mem[1]);
        $display("  Pattern 2 (Repeated 16B) : %s (DMEM[2]=0x%08h)", pat2_passed ? "PASSED" : "FAILED", u_dut.u_soc.u_dmem.mem[2]);
        $display("  Pattern 3 (Mixed 14B)    : %s (DMEM[3]=0x%08h)", pat3_passed ? "PASSED" : "FAILED", u_dut.u_soc.u_dmem.mem[3]);
        $display("  Pattern 4 (Boundary 32B) : %s (DMEM[4]=0x%08h)", pat4_passed ? "PASSED" : "FAILED", u_dut.u_soc.u_dmem.mem[4]);
        $display("----------------------------------------------------------------");
        $display("OVERALL COMPLETION STATUS: %s (Signature 0xCAFE_D00D)",
                 all_passed ? ">>> ALL TESTS PASSED <<<" : ">>> FAILED <<<");
        $display("================================================================\n");

        $finish;
    end

endmodule
