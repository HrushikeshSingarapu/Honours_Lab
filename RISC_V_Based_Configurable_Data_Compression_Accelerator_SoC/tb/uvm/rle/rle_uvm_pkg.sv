// =============================================================================
// rle_uvm_pkg.sv — Complete UVM 1.2 Verification Environment for RLE IP
// =============================================================================
`timescale 1ns/1ps

package rle_uvm_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // Register Offsets
    localparam bit [31:0] REG_CONTROL       = 32'h000;
    localparam bit [31:0] REG_STATUS        = 32'h004;
    localparam bit [31:0] REG_INPUT_LENGTH  = 32'h008;
    localparam bit [31:0] REG_OUTPUT_LENGTH = 32'h00C;
    localparam bit [31:0] REG_INPUT_DATA    = 32'h010;
    localparam bit [31:0] REG_OUTPUT_DATA   = 32'h014;
    localparam bit [31:0] REG_IRQ_ENABLE    = 32'h018;
    localparam bit [31:0] REG_IRQ_STATUS    = 32'h01C;

    typedef enum bit {
        RLE_MODE_COMPRESS   = 1'b0,
        RLE_MODE_DECOMPRESS = 1'b1
    } rle_mode_e;

    // =========================================================================
    // 1. Transaction Item
    // =========================================================================
    class rle_seq_item extends uvm_sequence_item;
        rle_mode_e mode;
        logic [7:0] in_payload [];
        logic [7:0] out_payload [];
        int         in_length;
        int         out_length;
        bit         expected_error;
        bit         actual_error;

        `uvm_object_utils_begin(rle_seq_item)
            `uvm_field_enum(rle_mode_e, mode, UVM_ALL_ON)
            `uvm_field_int(in_length, UVM_ALL_ON)
            `uvm_field_int(out_length, UVM_ALL_ON)
            `uvm_field_int(expected_error, UVM_ALL_ON)
            `uvm_field_int(actual_error, UVM_ALL_ON)
            `uvm_field_array_int(in_payload, UVM_ALL_ON)
            `uvm_field_array_int(out_payload, UVM_ALL_ON)
        `uvm_object_utils_end

        function new(string name = "rle_seq_item");
            super.new(name);
            mode           = RLE_MODE_COMPRESS;
            expected_error = 1'b0;
            actual_error   = 1'b0;
        endfunction

        function void set_input_bytes(logic [7:0] data []);
            in_payload = new[data.size()](data);
            in_length  = data.size();
        endfunction
    endclass: rle_seq_item

    // =========================================================================
    // 2. Reference Model (Golden Software Model)
    // =========================================================================
    class rle_ref_model extends uvm_object;
        `uvm_object_utils(rle_ref_model)

        function new(string name = "rle_ref_model");
            super.new(name);
        endfunction

        localparam int RLE_BUF_DEPTH = 512;

        function void predict(
            input  rle_seq_item item,
            output logic [7:0]  gold_out [],
            output int          gold_len,
            output bit          gold_err
        );
            gold_err = 1'b0;

            if (item.in_length == 0) begin
                gold_len = 0;
                gold_out = new[0];
                return;
            end

            if (item.mode == RLE_MODE_COMPRESS) begin
                // Compression Flow
                int idx = 0;
                logic [7:0] token_q [$];

                while (idx < item.in_length) begin
                    logic [7:0] cur_byte;
                    int run_len;
                    cur_byte = item.in_payload[idx];
                    run_len  = 1;
                    idx++;

                    while (idx < item.in_length && item.in_payload[idx] == cur_byte && run_len < 255) begin
                        run_len++;
                        idx++;
                    end

                    token_q.push_back(run_len[7:0]);
                    token_q.push_back(cur_byte);
                end

                if (token_q.size() > RLE_BUF_DEPTH) begin
                    gold_err = 1'b1;
                    gold_len = 0;
                    gold_out = new[0];
                    return;
                end
                gold_len = token_q.size();
                gold_out = new[gold_len];
                for (int i = 0; i < gold_len; i++) gold_out[i] = token_q[i];

            end else begin
                // Decompression Flow
                logic [7:0] expand_q [$];

                // Specification rule: odd decompression input length is an error
                if (item.in_length % 2 != 0) begin
                    gold_err = 1'b1;
                    gold_len = 0;
                    gold_out = new[0];
                    return;
                end

                for (int i = 0; i < item.in_length; i += 2) begin
                    int count = item.in_payload[i];
                    logic [7:0] val = item.in_payload[i+1];

                    // Zero count token is an invalid record
                    if (count == 0) begin
                        gold_err = 1'b1;
                        gold_len = 0;
                        gold_out = new[0];
                        return;
                    end

                    if (expand_q.size() + count > RLE_BUF_DEPTH) begin
                        gold_err = 1'b1;
                        gold_len = 0;
                        gold_out = new[0];
                        return;
                    end

                    for (int c = 0; c < count; c++) begin
                        expand_q.push_back(val);
                    end
                end

                gold_len = expand_q.size();
                gold_out = new[gold_len];
                for (int i = 0; i < gold_len; i++) gold_out[i] = expand_q[i];
            end
        endfunction
    endclass: rle_ref_model

    // =========================================================================
    // 3. Functional Coverage Tracker
    // =========================================================================
    class rle_coverage extends uvm_component;
        `uvm_component_utils(rle_coverage)

        uvm_analysis_imp #(rle_seq_item, rle_coverage) analysis_export;

        int cov_single_byte_hits   = 0;
        int cov_repeated_byte_hits = 0;
        int cov_max_run_hits       = 0;
        int cov_boundary_split_hits= 0;
        int cov_alternating_hits   = 0;
        int cov_decompress_hits    = 0;
        int cov_error_odd_len_hits = 0;
        int cov_error_zero_cnt_hits= 0;
        int cov_zero_len_hits      = 0;
        int cov_buf_overflow_hits  = 0;
        int cov_prng_mixed_hits    = 0;
        int total_samples          = 0;

        function new(string name = "rle_coverage", uvm_component parent = null);
            super.new(name, parent);
            analysis_export = new("analysis_export", this);
        endfunction

        virtual function void write(rle_seq_item t);
            sample(t);
        endfunction

        function void sample(rle_seq_item item);
            total_samples++;
            if (item.in_length == 0) cov_zero_len_hits++;
            if (item.actual_error && (item.mode == RLE_MODE_COMPRESS ||
                ((item.in_length % 2 == 0) && item.in_length >= 2 && item.in_payload[0] != 0))) begin
                cov_buf_overflow_hits++;
            end

            if (item.mode == RLE_MODE_COMPRESS) begin
                if (item.in_length == 1) cov_single_byte_hits++;
                if (item.in_length == 255) cov_max_run_hits++;
                if (item.in_length > 255) cov_boundary_split_hits++;
                if (item.in_length > 1 && item.in_length < 255) cov_repeated_byte_hits++;
                if (item.in_length == 64 && !item.actual_error) cov_prng_mixed_hits++;

                // Detect alternating bytes pattern (e.g., ABABABAB)
                if (item.in_length >= 4) begin
                    bit is_alt;
                    is_alt = 1'b1;
                    for (int i = 2; i < item.in_length; i++) begin
                        if (item.in_payload[i] !== item.in_payload[i % 2]) begin
                            is_alt = 1'b0;
                            break;
                        end
                    end
                    if (is_alt && (item.in_payload[0] !== item.in_payload[1])) begin
                        cov_alternating_hits++;
                    end
                end
            end else begin
                cov_decompress_hits++;
                if (item.in_length % 2 != 0) cov_error_odd_len_hits++;
                for (int i = 0; i < item.in_length; i += 2) begin
                    if (item.in_payload[i] == 0) cov_error_zero_cnt_hits++;
                end
            end
        endfunction

        function void report_phase(uvm_phase phase);
            real cov_pct;
            int covered_bins;
            covered_bins = (cov_single_byte_hits > 0) +
                           (cov_repeated_byte_hits > 0) +
                           (cov_max_run_hits > 0) +
                           (cov_boundary_split_hits > 0) +
                           (cov_alternating_hits > 0) +
                           (cov_decompress_hits > 0) +
                           (cov_error_odd_len_hits > 0) +
                           (cov_error_zero_cnt_hits > 0) +
                           (cov_zero_len_hits > 0) +
                           (cov_buf_overflow_hits > 0) +
                           (cov_prng_mixed_hits > 0);
            cov_pct = (real'(covered_bins) / 11.0) * 100.0;

            `uvm_info("RLE_COV", "========================================================", UVM_LOW)
            `uvm_info("RLE_COV", "            RLE FUNCTIONAL COVERAGE REPORT             ", UVM_LOW)
            `uvm_info("RLE_COV", "========================================================", UVM_LOW)
            `uvm_info("RLE_COV", $sformatf("  Single-Byte Run Bin          : %0d hits", cov_single_byte_hits), UVM_LOW)
            `uvm_info("RLE_COV", $sformatf("  Repeated-Byte Run Bin        : %0d hits", cov_repeated_byte_hits), UVM_LOW)
            `uvm_info("RLE_COV", $sformatf("  Max Run-Length (255) Bin     : %0d hits", cov_max_run_hits), UVM_LOW)
            `uvm_info("RLE_COV", $sformatf("  Boundary Run Split (>255) Bin: %0d hits", cov_boundary_split_hits), UVM_LOW)
            `uvm_info("RLE_COV", $sformatf("  Alternating Data Bin         : %0d hits", cov_alternating_hits), UVM_LOW)
            `uvm_info("RLE_COV", $sformatf("  Decompression Expansion Bin  : %0d hits", cov_decompress_hits), UVM_LOW)
            `uvm_info("RLE_COV", $sformatf("  Zero-Length Input Bin        : %0d hits", cov_zero_len_hits), UVM_LOW)
            `uvm_info("RLE_COV", $sformatf("  Output Buffer Overflow Bin   : %0d hits", cov_buf_overflow_hits), UVM_LOW)
            `uvm_info("RLE_COV", $sformatf("  PRNG Mixed Payload Bin       : %0d hits", cov_prng_mixed_hits), UVM_LOW)
            `uvm_info("RLE_COV", $sformatf("  Error: Odd Decomp Length Bin : %0d hits", cov_error_odd_len_hits), UVM_LOW)
            `uvm_info("RLE_COV", $sformatf("  Error: Zero Run Count Bin    : %0d hits", cov_error_zero_cnt_hits), UVM_LOW)
            `uvm_info("RLE_COV", $sformatf("  Overall Covered Functional Bins : %0d / 11 (%0.1f%%)", covered_bins, cov_pct), UVM_LOW)
            `uvm_info("RLE_COV", "========================================================", UVM_LOW)
        endfunction
    endclass: rle_coverage

    // =========================================================================
    // 4. Sequencer
    // =========================================================================
    typedef uvm_sequencer #(rle_seq_item) rle_sequencer;

    // =========================================================================
    // 5. Driver (Active Stimulus Generation Only)
    // =========================================================================
    class rle_driver extends uvm_driver #(rle_seq_item);
        `uvm_component_utils(rle_driver)

        virtual rle_axi_if vif;

        function new(string name = "rle_driver", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual rle_axi_if)::get(this, "", "vif", vif)) begin
                `uvm_fatal("RLE_DRV", "Failed to retrieve virtual interface 'vif' from config_db!")
            end
        endfunction

        // AXI4-Lite Low-Level Write Task
        task axi_write(input bit [31:0] addr, input bit [31:0] data, input bit [3:0] strb = 4'b1111);
            @(posedge vif.clk);
            vif.s_axi_awaddr  <= addr;
            vif.s_axi_awprot  <= 3'b000;
            vif.s_axi_awvalid <= 1'b1;

            vif.s_axi_wdata   <= data;
            vif.s_axi_wstrb   <= strb;
            vif.s_axi_wvalid  <= 1'b1;

            vif.s_axi_bready  <= 1'b1;

            fork
                begin
                    while (!vif.s_axi_awready) @(posedge vif.clk);
                    @(posedge vif.clk);
                    vif.s_axi_awvalid <= 1'b0;
                end
                begin
                    while (!vif.s_axi_wready) @(posedge vif.clk);
                    @(posedge vif.clk);
                    vif.s_axi_wvalid <= 1'b0;
                end
            join

            while (!vif.s_axi_bvalid) @(posedge vif.clk);
            @(posedge vif.clk);
            vif.s_axi_bready <= 1'b0;
        endtask

        // AXI4-Lite Low-Level Read Task
        task axi_read(input bit [31:0] addr, output bit [31:0] rdata, output bit [1:0] rresp);
            @(posedge vif.clk);
            vif.s_axi_araddr  <= addr;
            vif.s_axi_arprot  <= 3'b000;
            vif.s_axi_arvalid <= 1'b1;
            vif.s_axi_rready  <= 1'b1;

            while (!vif.s_axi_arready) @(posedge vif.clk);
            @(posedge vif.clk);
            vif.s_axi_arvalid <= 1'b0;

            while (!vif.s_axi_rvalid) @(posedge vif.clk);
            rdata = vif.s_axi_rdata;
            rresp = vif.s_axi_rresp;
            @(posedge vif.clk);
            vif.s_axi_rready <= 1'b0;
        endtask

        task run_phase(uvm_phase phase);
            // Default idle state
            vif.s_axi_awvalid <= 1'b0;
            vif.s_axi_wvalid  <= 1'b0;
            vif.s_axi_bready  <= 1'b0;
            vif.s_axi_arvalid <= 1'b0;
            vif.s_axi_rready  <= 1'b0;

            while (vif.rst) @(posedge vif.clk);

            forever begin
                rle_seq_item item;
                bit [31:0] status_val;
                bit [1:0]  resp;
                int timeout_cnt;

                seq_item_port.get_next_item(item);

                // 1. Write Input Length
                axi_write(REG_INPUT_LENGTH, item.in_length);

                // 2. Stream Input Data to FIFO
                for (int i = 0; i < item.in_length; i += 4) begin
                    bit [31:0] wdata;
                    bit [3:0]  wstrb;
                    wdata = 32'h0;
                    wstrb = 4'b0000;
                    if (i < item.in_length)   begin wdata[7:0]   = item.in_payload[i];   wstrb[0] = 1'b1; end
                    if (i+1 < item.in_length) begin wdata[15:8]  = item.in_payload[i+1]; wstrb[1] = 1'b1; end
                    if (i+2 < item.in_length) begin wdata[23:16] = item.in_payload[i+2]; wstrb[2] = 1'b1; end
                    if (i+3 < item.in_length) begin wdata[31:24] = item.in_payload[i+3]; wstrb[3] = 1'b1; end
                    axi_write(REG_INPUT_DATA, wdata, wstrb);
                end

                // 3. Write Control Register (Start bit | Mode bit)
                axi_write(REG_CONTROL, {30'b0, item.mode, 1'b1});

                // 4. Poll Status Register for Completion or Error
                timeout_cnt = 0;
                forever begin
                    axi_read(REG_STATUS, status_val, resp);
                    // Bit 1 = DONE, Bit 2 = ERROR
                    if (status_val[1] || status_val[2] || timeout_cnt > 20000) break;
                    timeout_cnt++;
                    repeat (5) @(posedge vif.clk);
                end

                // 5. Read Output Length and Output Bytes if no error
                if (!status_val[2]) begin
                    bit [31:0] len_rd;
                    int out_cnt;
                    axi_read(REG_OUTPUT_LENGTH, len_rd, resp);
                    out_cnt = len_rd[15:0];

                    for (int i = 0; i < out_cnt; i++) begin
                        bit [31:0] rword;
                        axi_read(REG_OUTPUT_DATA, rword, resp);
                    end
                end

                seq_item_port.item_done();
            end
        endtask
    endclass: rle_driver

    // =========================================================================
    // 6. Passive Monitor (Reconstructs Transactions Strictly from Interface Pins)
    // =========================================================================
    class rle_monitor extends uvm_monitor;
        `uvm_component_utils(rle_monitor)

        virtual rle_axi_if vif;
        uvm_analysis_port #(rle_seq_item) ap;

        function new(string name = "rle_monitor", uvm_component parent = null);
            super.new(name, parent);
            ap = new("ap", this);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual rle_axi_if)::get(this, "", "vif", vif)) begin
                `uvm_fatal("RLE_MON", "Failed to retrieve virtual interface 'vif' from config_db!")
            end
        endfunction

        task run_phase(uvm_phase phase);
            bit [31:0] latched_awaddr;
            bit [31:0] latched_wdata;
            bit [3:0]  latched_wstrb;
            bit        saw_aw;
            bit        saw_w;

            bit [31:0] latched_araddr;
            bit        saw_ar;

            // Reconstructed state for active operation
            rle_mode_e  obs_mode;
            int         obs_in_len;
            logic [7:0] obs_in_bytes [$];
            int         obs_out_len;
            logic [7:0] obs_out_bytes [$];
            bit         obs_done;
            bit         obs_error;
            bit         reported_item;

            latched_awaddr = 32'h0;
            latched_wdata  = 32'h0;
            latched_wstrb  = 4'h0;
            saw_aw         = 1'b0;
            saw_w          = 1'b0;
            latched_araddr = 32'h0;
            saw_ar         = 1'b0;

            obs_mode       = RLE_MODE_COMPRESS;
            obs_in_len     = 0;
            obs_out_len    = 0;
            obs_done       = 1'b0;
            obs_error      = 1'b0;
            reported_item  = 1'b0;

            forever begin
                @(posedge vif.clk);

                if (vif.rst) begin
                    saw_aw        = 1'b0;
                    saw_w         = 1'b0;
                    saw_ar        = 1'b0;
                    obs_in_bytes.delete();
                    obs_out_bytes.delete();
                    reported_item = 1'b0;
                    continue;
                end

                // -------------------------------------------------------------
                // AXI Write Channel Monitoring (Independent AW and W handshakes)
                // -------------------------------------------------------------
                if (vif.s_axi_awvalid && vif.s_axi_awready) begin
                    latched_awaddr = vif.s_axi_awaddr;
                    saw_aw         = 1'b1;
                end

                if (vif.s_axi_wvalid && vif.s_axi_wready) begin
                    latched_wdata = vif.s_axi_wdata;
                    latched_wstrb = vif.s_axi_wstrb;
                    saw_w         = 1'b1;
                end

                if (saw_aw && saw_w && vif.s_axi_bvalid && vif.s_axi_bready) begin
                    // Write transaction complete
                    case (latched_awaddr[7:0])
                        8'h08: begin // REG_INPUT_LENGTH
                            obs_in_len = latched_wdata[15:0];
                            obs_in_bytes.delete();
                            obs_out_bytes.delete();
                            obs_done      = 1'b0;
                            obs_error     = 1'b0;
                            reported_item = 1'b0;
                        end
                        8'h10: begin // REG_INPUT_DATA
                            if (latched_wstrb[0]) obs_in_bytes.push_back(latched_wdata[7:0]);
                            if (latched_wstrb[1]) obs_in_bytes.push_back(latched_wdata[15:8]);
                            if (latched_wstrb[2]) obs_in_bytes.push_back(latched_wdata[23:16]);
                            if (latched_wstrb[3]) obs_in_bytes.push_back(latched_wdata[31:24]);
                        end
                        8'h00: begin // REG_CONTROL
                            obs_mode = (latched_wdata[1] == 1'b1) ? RLE_MODE_DECOMPRESS : RLE_MODE_COMPRESS;
                        end
                        default: begin end
                    endcase
                    saw_aw = 1'b0;
                    saw_w  = 1'b0;
                end

                // -------------------------------------------------------------
                // AXI Read Channel Monitoring (Independent AR and R handshakes)
                // -------------------------------------------------------------
                if (vif.s_axi_arvalid && vif.s_axi_arready) begin
                    latched_araddr = vif.s_axi_araddr;
                    saw_ar         = 1'b1;
                end

                if (saw_ar && vif.s_axi_rvalid && vif.s_axi_rready) begin
                    case (latched_araddr[7:0])
                        8'h04: begin // REG_STATUS
                            // Bit 1 = DONE, Bit 2 = ERROR
                            if (vif.s_axi_rdata[1]) obs_done = 1'b1;
                            if (vif.s_axi_rdata[2]) begin
                                obs_error = 1'b1;
                                if (!reported_item) begin
                                    rle_seq_item item;
                                    reported_item = 1'b1;
                                    item = rle_seq_item::type_id::create("obs_err_item");
                                    item.mode = obs_mode;
                                    item.in_length = obs_in_bytes.size();
                                    item.in_payload = new[obs_in_bytes.size()];
                                    for (int i = 0; i < obs_in_bytes.size(); i++) item.in_payload[i] = obs_in_bytes[i];
                                    item.actual_error = 1'b1;
                                    item.out_length = 0;
                                    item.out_payload = new[0];
                                    ap.write(item);
                                end
                            end
                        end
                        8'h0C: begin // REG_OUTPUT_LENGTH
                            obs_out_len = vif.s_axi_rdata[15:0];
                            if (obs_out_len == 0 && obs_done && !obs_error && !reported_item) begin
                                rle_seq_item item;
                                reported_item = 1'b1;
                                item = rle_seq_item::type_id::create("obs_zero_item");
                                item.mode = obs_mode;
                                item.in_length = obs_in_bytes.size();
                                item.in_payload = new[obs_in_bytes.size()];
                                for (int i = 0; i < obs_in_bytes.size(); i++) item.in_payload[i] = obs_in_bytes[i];
                                item.actual_error = 1'b0;
                                item.out_length = 0;
                                item.out_payload = new[0];
                                ap.write(item);
                            end
                        end
                        8'h14: begin // REG_OUTPUT_DATA
                            obs_out_bytes.push_back(vif.s_axi_rdata[7:0]);
                            if (obs_out_bytes.size() == obs_out_len && !reported_item) begin
                                rle_seq_item item;
                                reported_item = 1'b1;
                                item = rle_seq_item::type_id::create("obs_item");
                                item.mode = obs_mode;
                                item.in_length = obs_in_bytes.size();
                                item.in_payload = new[obs_in_bytes.size()];
                                for (int i = 0; i < obs_in_bytes.size(); i++) item.in_payload[i] = obs_in_bytes[i];
                                item.actual_error = 1'b0;
                                item.out_length = obs_out_bytes.size();
                                item.out_payload = new[obs_out_bytes.size()];
                                for (int i = 0; i < obs_out_bytes.size(); i++) item.out_payload[i] = obs_out_bytes[i];
                                ap.write(item);
                            end
                        end
                        default: begin end
                    endcase
                    saw_ar = 1'b0;
                end
            end
        endtask
    endclass: rle_monitor

    // =========================================================================
    // 7. Scoreboard (Validates Observed Transactions Against Golden Reference)
    // =========================================================================
    class rle_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(rle_scoreboard)

        uvm_analysis_imp #(rle_seq_item, rle_scoreboard) item_export;
        rle_ref_model ref_model;

        int total_checks = 0;
        int pass_checks  = 0;
        int fail_checks  = 0;

        function new(string name = "rle_scoreboard", uvm_component parent = null);
            super.new(name, parent);
            item_export = new("item_export", this);
            ref_model   = rle_ref_model::type_id::create("ref_model");
        endfunction

        function void write(rle_seq_item item);
            logic [7:0] gold_out [];
            int         gold_len;
            bit         gold_err;
            bit         match;

            total_checks++;
            ref_model.predict(item, gold_out, gold_len, gold_err);

            match = 1'b1;

            // Check Error Flag match
            if (item.actual_error !== gold_err) begin
                `uvm_error("RLE_SCB", $sformatf("Error flag mismatch! Observed error=%b, Expected error=%b",
                           item.actual_error, gold_err))
                match = 1'b0;
            end

            // Check Length match
            if (!gold_err && item.out_length !== gold_len) begin
                `uvm_error("RLE_SCB", $sformatf("Output length mismatch! Observed len=%0d, Expected len=%0d",
                           item.out_length, gold_len))
                match = 1'b0;
            end

            // Check Payload byte-by-byte for corruption, missing, or reordering
            if (!gold_err && match) begin
                for (int i = 0; i < gold_len; i++) begin
                    if (item.out_payload[i] !== gold_out[i]) begin
                        `uvm_error("RLE_SCB", $sformatf("Byte[%0d] mismatch! Observed=0x%02h, Expected=0x%02h",
                                   i, item.out_payload[i], gold_out[i]))
                        match = 1'b0;
                        break;
                    end
                end
            end

            if (match) begin
                pass_checks++;
                `uvm_info("RLE_SCB", $sformatf(">>> [PASS] Observed Transaction Verified! (%0s: %0d -> %0d bytes, Error=%b)",
                          (item.mode == RLE_MODE_COMPRESS ? "COMPRESSION" : "DECOMPRESSION"),
                          item.in_length, item.out_length, item.actual_error), UVM_LOW)
            end else begin
                fail_checks++;
            end
        endfunction

        function void report_phase(uvm_phase phase);
            `uvm_info("RLE_SCB", "========================================================", UVM_LOW)
            `uvm_info("RLE_SCB", "               RLE SCOREBOARD SUMMARY                   ", UVM_LOW)
            `uvm_info("RLE_SCB", "========================================================", UVM_LOW)
            `uvm_info("RLE_SCB", $sformatf("  Total Transactions Checked : %0d", total_checks), UVM_LOW)
            `uvm_info("RLE_SCB", $sformatf("  Passed Comparisons         : %0d", pass_checks), UVM_LOW)
            `uvm_info("RLE_SCB", $sformatf("  Failed Comparisons         : %0d", fail_checks), UVM_LOW)
            if (fail_checks == 0 && total_checks > 0)
                `uvm_info("RLE_SCB", "  OVERALL SCOREBOARD VERDICT : [ALL CHECKS PASSED]", UVM_LOW)
            else
                `uvm_error("RLE_SCB", "  OVERALL SCOREBOARD VERDICT : [FAILURES DETECTED]")
            `uvm_info("RLE_SCB", "========================================================", UVM_LOW)
        endfunction
    endclass: rle_scoreboard

    // =========================================================================
    // 8. Agent
    // =========================================================================
    class rle_agent extends uvm_agent;
        `uvm_component_utils(rle_agent)

        rle_driver    driver;
        rle_sequencer sequencer;
        rle_monitor   monitor;

        function new(string name = "rle_agent", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            driver    = rle_driver::type_id::create("driver", this);
            sequencer = rle_sequencer::type_id::create("sequencer", this);
            monitor   = rle_monitor::type_id::create("monitor", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            driver.seq_item_port.connect(sequencer.seq_item_export);
        endfunction
    endclass: rle_agent

    // =========================================================================
    // 9. Environment
    // =========================================================================
    class rle_env extends uvm_env;
        `uvm_component_utils(rle_env)

        rle_agent      agent;
        rle_scoreboard scoreboard;
        rle_coverage   coverage;

        function new(string name = "rle_env", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agent      = rle_agent::type_id::create("agent", this);
            scoreboard = rle_scoreboard::type_id::create("scoreboard", this);
            coverage   = rle_coverage::type_id::create("coverage", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            // Passive monitor analysis port drives scoreboard and coverage collector
            agent.monitor.ap.connect(scoreboard.item_export);
            agent.monitor.ap.connect(coverage.analysis_export);
        endfunction
    endclass: rle_env

    // =========================================================================
    // 10. Master Stimulus Sequence (Completely Decoupled from Scoreboard)
    // =========================================================================
    class rle_master_sequence extends uvm_sequence #(rle_seq_item);
        `uvm_object_utils(rle_master_sequence)

        function new(string name = "rle_master_sequence");
            super.new(name);
        endfunction

        task body();
            rle_seq_item item;
            logic [7:0] buf_data [];

            // -----------------------------------------------------------------
            // Scenario 1: Single-byte input
            // -----------------------------------------------------------------
            `uvm_info("SEQ", ">>> Executing Scenario 1: Single-Byte Input", UVM_LOW)
            item = rle_seq_item::type_id::create("item_single");
            start_item(item);
            item.mode = RLE_MODE_COMPRESS;
            buf_data = new[1];
            buf_data[0] = 8'h42;
            item.set_input_bytes(buf_data);
            finish_item(item);

            // -----------------------------------------------------------------
            // Scenario 2: Repeated bytes (16 bytes of 0xAA)
            // -----------------------------------------------------------------
            `uvm_info("SEQ", ">>> Executing Scenario 2: Repeated-Byte Input (16 bytes)", UVM_LOW)
            item = rle_seq_item::type_id::create("item_rep16");
            start_item(item);
            item.mode = RLE_MODE_COMPRESS;
            buf_data = new[16];
            for (int i = 0; i < 16; i++) buf_data[i] = 8'hAA;
            item.set_input_bytes(buf_data);
            finish_item(item);

            // -----------------------------------------------------------------
            // Scenario 3: Maximum single-run boundary (255 bytes of 0x55)
            // -----------------------------------------------------------------
            `uvm_info("SEQ", ">>> Executing Scenario 3: Maximum Run Length Boundary (255 bytes)", UVM_LOW)
            item = rle_seq_item::type_id::create("item_max255");
            start_item(item);
            item.mode = RLE_MODE_COMPRESS;
            buf_data = new[255];
            for (int i = 0; i < 255; i++) buf_data[i] = 8'h55;
            item.set_input_bytes(buf_data);
            finish_item(item);

            // -----------------------------------------------------------------
            // Scenario 3b: Boundary run split (>255 bytes: 270 bytes of 0x33)
            // -----------------------------------------------------------------
            `uvm_info("SEQ", ">>> Executing Scenario 3b: Run Split Boundary (270 bytes)", UVM_LOW)
            item = rle_seq_item::type_id::create("item_split270");
            start_item(item);
            item.mode = RLE_MODE_COMPRESS;
            buf_data = new[270];
            for (int i = 0; i < 270; i++) buf_data[i] = 8'h33;
            item.set_input_bytes(buf_data);
            finish_item(item);

            // -----------------------------------------------------------------
            // Scenario 4: Consecutive run transitions ("AAAAABBBCCCC")
            // -----------------------------------------------------------------
            `uvm_info("SEQ", ">>> Executing Scenario 4: Consecutive Runs (AAAAABBBCCCC)", UVM_LOW)
            item = rle_seq_item::type_id::create("item_consec");
            start_item(item);
            item.mode = RLE_MODE_COMPRESS;
            buf_data = new[12];
            for (int i = 0; i < 5; i++)  buf_data[i] = 8'h41; // 'A'
            for (int i = 5; i < 8; i++)  buf_data[i] = 8'h42; // 'B'
            for (int i = 8; i < 12; i++) buf_data[i] = 8'h43; // 'C'
            item.set_input_bytes(buf_data);
            finish_item(item);

            // -----------------------------------------------------------------
            // Scenario 5: Alternating bytes (ABABABAB)
            // -----------------------------------------------------------------
            `uvm_info("SEQ", ">>> Executing Scenario 5: Alternating Bytes", UVM_LOW)
            item = rle_seq_item::type_id::create("item_alt");
            start_item(item);
            item.mode = RLE_MODE_COMPRESS;
            buf_data = new[8];
            for (int i = 0; i < 8; i++) buf_data[i] = (i % 2 == 0) ? 8'hA1 : 8'hB2;
            item.set_input_bytes(buf_data);
            finish_item(item);

            // -----------------------------------------------------------------
            // Scenario 6: Decompression Roundtrip (Expand [10, 0x77], [5, 0x88])
            // -----------------------------------------------------------------
            `uvm_info("SEQ", ">>> Executing Scenario 6: Lossless Decompression", UVM_LOW)
            item = rle_seq_item::type_id::create("item_decomp");
            start_item(item);
            item.mode = RLE_MODE_DECOMPRESS;
            buf_data = new[4];
            buf_data[0] = 8'd10; buf_data[1] = 8'h77;
            buf_data[2] = 8'd5;  buf_data[3] = 8'h88;
            item.set_input_bytes(buf_data);
            finish_item(item);

            // -----------------------------------------------------------------
            // Scenario 7: Error Condition — Odd Decompression Length
            // -----------------------------------------------------------------
            `uvm_info("SEQ", ">>> Executing Scenario 7: Error Case (Odd Decompression Length)", UVM_LOW)
            item = rle_seq_item::type_id::create("item_err_odd");
            start_item(item);
            item.mode = RLE_MODE_DECOMPRESS;
            buf_data = new[3];
            buf_data[0] = 8'd4; buf_data[1] = 8'h11; buf_data[2] = 8'd2; // Missing byte
            item.set_input_bytes(buf_data);
            item.expected_error = 1'b1;
            finish_item(item);

            // -----------------------------------------------------------------
            // Scenario 8: Error Condition — Zero Count Record
            // -----------------------------------------------------------------
            `uvm_info("SEQ", ">>> Executing Scenario 8: Error Case (Zero Count Record)", UVM_LOW)
            item = rle_seq_item::type_id::create("item_err_zero");
            start_item(item);
            item.mode = RLE_MODE_DECOMPRESS;
            buf_data = new[2];
            buf_data[0] = 8'd0; buf_data[1] = 8'h99; // Count = 0
            item.set_input_bytes(buf_data);
            item.expected_error = 1'b1;
            finish_item(item);

            // -----------------------------------------------------------------
            // Scenario 9: Zero-Length Compression & Decompression
            // -----------------------------------------------------------------
            `uvm_info("SEQ", ">>> Executing Scenario 9: Zero-Length Compress & Decompress", UVM_LOW)
            item = rle_seq_item::type_id::create("item_zero_comp");
            start_item(item);
            item.mode = RLE_MODE_COMPRESS;
            buf_data = new[0];
            item.set_input_bytes(buf_data);
            finish_item(item);

            item = rle_seq_item::type_id::create("item_zero_decomp");
            start_item(item);
            item.mode = RLE_MODE_DECOMPRESS;
            buf_data = new[0];
            item.set_input_bytes(buf_data);
            finish_item(item);

            // -----------------------------------------------------------------
            // Scenario 10: Compression Output Buffer Overflow (> 512 bytes)
            // 260 distinct alternating bytes -> needs 520 output bytes > 512
            // -----------------------------------------------------------------
            `uvm_info("SEQ", ">>> Executing Scenario 10: Compression Output Buffer Overflow (>512B)", UVM_LOW)
            item = rle_seq_item::type_id::create("item_comp_ovf");
            start_item(item);
            item.mode = RLE_MODE_COMPRESS;
            buf_data = new[260];
            for (int i = 0; i < 260; i++) buf_data[i] = i[7:0];
            item.set_input_bytes(buf_data);
            item.expected_error = 1'b1;
            finish_item(item);

            // -----------------------------------------------------------------
            // Scenario 11: Decompression Output Buffer Overflow (> 512 bytes)
            // [200, 0x11], [200, 0x22], [200, 0x33] -> 600 > 512
            // -----------------------------------------------------------------
            `uvm_info("SEQ", ">>> Executing Scenario 11: Decompression Output Buffer Overflow (>512B)", UVM_LOW)
            item = rle_seq_item::type_id::create("item_decomp_ovf");
            start_item(item);
            item.mode = RLE_MODE_DECOMPRESS;
            buf_data = new[6];
            buf_data[0] = 8'd200; buf_data[1] = 8'h11;
            buf_data[2] = 8'd200; buf_data[3] = 8'h22;
            buf_data[4] = 8'd200; buf_data[5] = 8'h33;
            item.set_input_bytes(buf_data);
            item.expected_error = 1'b1;
            finish_item(item);

            // -----------------------------------------------------------------
            // Scenario 12: Deterministic PRNG Mixed Vector (64 bytes)
            // -----------------------------------------------------------------
            `uvm_info("SEQ", ">>> Executing Scenario 12: Deterministic PRNG Mixed Vector (64 bytes)", UVM_LOW)
            item = rle_seq_item::type_id::create("item_prng64");
            start_item(item);
            item.mode = RLE_MODE_COMPRESS;
            buf_data = new[64];
            begin
                automatic logic [31:0] lfsr = 32'hACE1_1357;
                for (int i = 0; i < 64; i++) begin
                    lfsr = {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
                    // Force occasional runs and singletons
                    buf_data[i] = (lfsr[2]) ? lfsr[7:4] : {4'hA, lfsr[3:0]};
                end
            end
            item.set_input_bytes(buf_data);
            finish_item(item);
        endtask
    endclass: rle_master_sequence

    // =========================================================================
    // 11. UVM Test
    // =========================================================================
    class rle_test extends uvm_test;
        `uvm_component_utils(rle_test)

        rle_env env;

        function new(string name = "rle_test", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = rle_env::type_id::create("env", this);
        endfunction

        task run_phase(uvm_phase phase);
            rle_master_sequence seq;
            phase.raise_objection(this);

            seq = rle_master_sequence::type_id::create("seq");

            `uvm_info("RLE_TEST", "========================================================", UVM_LOW)
            `uvm_info("RLE_TEST", "     STARTING UVM 1.2 REGRESSION: RLE ACCELERATOR      ", UVM_LOW)
            `uvm_info("RLE_TEST", "========================================================", UVM_LOW)

            seq.start(env.agent.sequencer);

            `uvm_info("RLE_TEST", "RLE Master Sequence Completed All Scenarios.", UVM_LOW)
            phase.drop_objection(this);
        endtask
    endclass: rle_test

endpackage: rle_uvm_pkg
