// =============================================================================
// tb_soc_core_boot.sv — Minimal Boot Verification Testbench for VeeR EL2 SoC
//
// Verification Objective:
//   1. Reset release with VeeR EL2 reset vector at 0x8000_0000.
//   2. IFU fetch from IMEM alias at 0x8000_0000 through axi64_to_32_bridge and interconnect.
//   3. Core execution of 5 instructions:
//        0x8000_0000: lui  x1, 0x00010      (DMEM base address = 0x0001_0000)
//        0x8000_0004: lui  x2, 0xCAFEC
//        0x8000_0008: addi x2, x2, 0xABE    (x2 = 0xCAFE_BABE)
//        0x8000_000C: sw   x2, 0(x1)        (Store 0xCAFE_BABE to DMEM[0])
//        0x8000_0010: j    loop             (Infinite loop at 0x8000_0010)
//   4. LSU write of 0xCAFE_BABE through LSU axi64_to_32_bridge to DMEM at 0x0001_0000.
//   5. Assert that DMEM word 0 contains 0xCAFE_BABE upon retirement.
// =============================================================================

`timescale 1ns/1ps

module tb_soc_core_boot;

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

    // Monitoring counters
    integer cycle_count;
    integer fetch_count;
    integer store_count;
    integer retire_count;
    logic   boot_success;

    // Real-time bus & execution monitor
    always @(posedge clk) begin
        if (rst_n) begin
            cycle_count <= cycle_count + 1;

            // Monitor IFU fetch requests
            if (u_dut.ifu_axi_arvalid && u_dut.ifu_axi_arready) begin
                fetch_count <= fetch_count + 1;
                $display("[%0t ns] [CYC %0d] IFU FETCH REQ  : Addr=0x%08h, Len=%0d, Size=%0d",
                         $time, cycle_count, u_dut.ifu_axi_araddr, u_dut.ifu_axi_arlen, u_dut.ifu_axi_arsize);
            end

            // Monitor IFU fetch responses
            if (u_dut.ifu_axi_rvalid && u_dut.ifu_axi_rready) begin
                $display("[%0t ns] [CYC %0d] IFU FETCH RESP : Data=0x%016h, Last=%0b, Resp=%0b",
                         $time, cycle_count, u_dut.ifu_axi_rdata, u_dut.ifu_axi_rlast, u_dut.ifu_axi_rresp);
            end

            // Monitor LSU write address & data
            if (u_dut.lsu_axi_awvalid && u_dut.lsu_axi_awready) begin
                $display("[%0t ns] [CYC %0d] LSU WRITE REQ  : Addr=0x%08h, Len=%0d, Size=%0d",
                         $time, cycle_count, u_dut.lsu_axi_awaddr, u_dut.lsu_axi_awlen, u_dut.lsu_axi_awsize);
            end

            if (u_dut.lsu_axi_wvalid && u_dut.lsu_axi_wready) begin
                store_count <= store_count + 1;
                $display("[%0t ns] [CYC %0d] LSU WRITE DATA : Data=0x%016h, Strb=0x%02h, Last=%0b",
                         $time, cycle_count, u_dut.lsu_axi_wdata, u_dut.lsu_axi_wstrb, u_dut.lsu_axi_wlast);
            end

            if (u_dut.lsu_axi_bvalid && u_dut.lsu_axi_bready) begin
                $display("[%0t ns] [CYC %0d] LSU WRITE RESP : Resp=%0b",
                         $time, cycle_count, u_dut.lsu_axi_bresp);
            end

            // Monitor Instruction Retirements
            if (trace_rv_i_valid_ip) begin
                retire_count <= retire_count + 1;
                $display("[%0t ns] [CYC %0d] CORE RETIRE #%0d: PC=0x%08h, Insn=0x%08h",
                         $time, cycle_count, retire_count + 1, trace_rv_i_address_ip, trace_rv_i_insn_ip);
            end

            // Check if DMEM[0] has received 0xCAFE_BABE
            if (!boot_success && u_dut.u_soc.u_dmem.mem[0] == 32'hCAFE_BABE) begin
                boot_success = 1'b1;
                $display("");
                $display("************************************************************");
                $display("[%0t ns] [CYC %0d] SUCCESS: DMEM[0x0001_0000] contains 0xCAFEBABE!",
                         $time, cycle_count);
                $display("************************************************************");
            end
        end
    end

    // Test Sequence
    initial begin
        $display("================================================================");
        $display("Starting VeeR EL2 SoC Minimal Boot Testbench");
        $display("================================================================");

        cycle_count  = 0;
        fetch_count  = 0;
        store_count  = 0;
        retire_count = 0;
        boot_success = 1'b0;

        uart_rx = 1'b1;
        gpio_i  = 32'h0;
        rst_n   = 1'b0;

        // Clear target memory
        u_dut.u_soc.u_dmem.mem[0] = 32'h0000_0000;

        // Load minimal boot program into IMEM (executing from 0x8000_0000)
        // Word 0 (0x8000_0000): lui  x1, 0x00010      -> x1 = 0x0001_0000 (DMEM base)
        u_dut.u_soc.u_imem.mem[0] = 32'h000100b7;
        // Word 1 (0x8000_0004): lui  x2, 0xCAFEC      -> x2 upper 20 bits
        u_dut.u_soc.u_imem.mem[1] = 32'hcafec137;
        // Word 2 (0x8000_0008): addi x2, x2, 0xABE    -> x2 = 0xCAFE_BABE
        u_dut.u_soc.u_imem.mem[2] = 32'habe10113;
        // Word 3 (0x8000_000C): sw   x2, 0(x1)        -> DMEM[0] = 0xCAFE_BABE
        u_dut.u_soc.u_imem.mem[3] = 32'h0020a023;
        // Word 4 (0x8000_0010): j    loop             -> infinite loop
        u_dut.u_soc.u_imem.mem[4] = 32'h0000006f;

        $display("IMEM pre-loaded with boot instructions at 0x8000_0000:");
        $display("  [0x8000_0000] = 0x%08h (lui  x1, 0x00010)",   u_dut.u_soc.u_imem.mem[0]);
        $display("  [0x8000_0004] = 0x%08h (lui  x2, 0xCAFEC)",   u_dut.u_soc.u_imem.mem[1]);
        $display("  [0x8000_0008] = 0x%08h (addi x2, x2, 0xABE)",   u_dut.u_soc.u_imem.mem[2]);
        $display("  [0x8000_000C] = 0x%08h (sw   x2, 0(x1))",       u_dut.u_soc.u_imem.mem[3]);
        $display("  [0x8000_0010] = 0x%08h (j    loop)",            u_dut.u_soc.u_imem.mem[4]);
        $display("Initial DMEM[0x0001_0000] = 0x%08h", u_dut.u_soc.u_dmem.mem[0]);

        // Hold reset for 30 cycles
        repeat (30) @(posedge clk);
        #1;
        $display("[%0t ns] Releasing reset (rst_n = 1)...", $time);
        rst_n = 1'b1;

        // Run simulation until boot success or timeout (1200 cycles)
        fork
            begin : wait_for_success
                wait (boot_success == 1'b1);
                // Allow a few more cycles to observe the loop branch
                repeat (20) @(posedge clk);
            end
            begin : timeout_watchdog
                repeat (1200) @(posedge clk);
                if (!boot_success) begin
                    $display("");
                    $display("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
                    $display("[%0t ns] TIMEOUT: Boot test did not write 0xCAFEBABE to DMEM within 1200 cycles!", $time);
                    $display("Final DMEM[0x0001_0000] = 0x%08h", u_dut.u_soc.u_dmem.mem[0]);
                    $display("Total fetches: %0d, Total stores: %0d, Total retires: %0d",
                             fetch_count, store_count, retire_count);
                    $display("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
                end
            end
        join_any
        disable fork;

        // Final verification summary
        $display("");
        $display("================================================================");
        $display("BOOT TEST REPORT SUMMARY");
        $display("================================================================");
        $display("Total Simulated Cycles : %0d", cycle_count);
        $display("IFU Fetch Beats        : %0d", fetch_count);
        $display("LSU Store Beats        : %0d", store_count);
        $display("Retired Instructions   : %0d", retire_count);
        $display("DMEM[0x0001_0000] Value: 0x%08h", u_dut.u_soc.u_dmem.mem[0]);

        if (u_dut.u_soc.u_dmem.mem[0] == 32'hCAFE_BABE) begin
            $display("TEST RESULT            : >>> PASSED <<<");
            $display("VeeR EL2 processor successfully booted, fetched from 0x8000_0000,");
            $display("executed instructions, and wrote signature 0xCAFEBABE to DMEM!");
        end else begin
            $display("TEST RESULT            : >>> FAILED <<<");
            $display("DMEM[0x0001_0000] did not match expected 0xCAFEBABE.");
        end
        $display("================================================================");

        $finish;
    end

endmodule
