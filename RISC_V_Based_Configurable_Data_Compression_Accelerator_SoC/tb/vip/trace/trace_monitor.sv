// =============================================================================
// trace_monitor.sv — VeeR EL2 Execution & Retirement Monitor VIP
// =============================================================================
`timescale 1ns/1ps

module trace_monitor #(
    parameter bit VERBOSE = 1'b0,
    parameter int STALL_LOOP_THRESHOLD = 50000
)(
    trace_if.monitor_mp vif
);
    import trace_pkg::*;

    int total_cycles = 0;
    int retired_instructions = 0;
    int exception_count = 0;
    int interrupt_trap_count = 0;

    logic [31:0] prev_pc = 32'h0;
    int repeat_pc_count  = 0;
    bit loop_logged      = 1'b0;

    always @(posedge vif.clk or negedge vif.rst_n) begin
        if (!vif.rst_n) begin
            total_cycles         <= 0;
            retired_instructions <= 0;
            exception_count      <= 0;
            interrupt_trap_count <= 0;
            prev_pc              <= 32'h0;
            repeat_pc_count      <= 0;
            loop_logged          <= 1'b0;
        end else begin
            total_cycles <= total_cycles + 1;

            if (vif.trace_rv_i_valid_ip) begin
                retired_instructions <= retired_instructions + 1;

                // Loop / Stall Detection
                if (vif.trace_rv_i_address_ip == prev_pc) begin
                    repeat_pc_count <= repeat_pc_count + 1;
                    if (repeat_pc_count == 2 && !loop_logged) begin
                        loop_logged <= 1'b1;
                        if (VERBOSE) begin
                            $display("[%0t ns] [TRACE VIP] CPU entered steady loop at PC=0x%08h (%s)",
                                     $time, vif.trace_rv_i_address_ip, disasm_rv32(vif.trace_rv_i_insn_ip));
                        end
                    end
                end else begin
                    prev_pc         <= vif.trace_rv_i_address_ip;
                    repeat_pc_count <= 0;
                    loop_logged     <= 1'b0;
                end

                // Exception Tracking
                if (vif.trace_rv_i_exception_ip) begin
                    exception_count <= exception_count + 1;
                    $display("[%0t ns] [TRACE VIP ERROR] *** CORE EXCEPTION *** PC=0x%08h | Cause=%0d (%s) | Tval=0x%08h",
                             $time, vif.trace_rv_i_address_ip, vif.trace_rv_i_ecause_ip,
                             decode_ecause(vif.trace_rv_i_ecause_ip), vif.trace_rv_i_tval_ip);
                end

                // Interrupt Trap Tracking
                if (vif.trace_rv_i_interrupt_ip) begin
                    interrupt_trap_count <= interrupt_trap_count + 1;
                    $display("[%0t ns] [TRACE VIP] *** INTERRUPT TRAP ENTERED *** PC=0x%08h",
                             $time, vif.trace_rv_i_address_ip);
                end

                // Verbose Instruction Log
                if (VERBOSE && !loop_logged && !vif.trace_rv_i_exception_ip) begin
                    $display("[%0t ns] [TRACE #%0d] PC=0x%08h | Insn=0x%08h | %-20s",
                             $time, retired_instructions + 1,
                             vif.trace_rv_i_address_ip,
                             vif.trace_rv_i_insn_ip,
                             disasm_rv32(vif.trace_rv_i_insn_ip));
                end
            end
        end
    end

    function int get_retired_count();
        return retired_instructions;
    endfunction

    function int get_cycle_count();
        return total_cycles;
    endfunction

    function real get_cpi();
        if (retired_instructions > 0)
            return (real'(total_cycles) / real'(retired_instructions));
        else
            return 0.0;
    endfunction

    task print_summary();
        real cpi;
        cpi = (retired_instructions > 0) ? (real'(total_cycles) / real'(retired_instructions)) : 0.0;
        $display("\n========================================================");
        $display("             PROCESSOR TRACE VIP SUMMARY                ");
        $display("========================================================");
        $display("Total simulation cycles      : %0d", total_cycles);
        $display("Total retired instructions   : %0d", retired_instructions);
        $display("Core exceptions encountered  : %0d", exception_count);
        $display("Interrupt traps taken        : %0d", interrupt_trap_count);
        $display("Cycles Per Instruction (CPI) : %0.2f", cpi);
        $display("========================================================\n");
    endtask

endmodule: trace_monitor

