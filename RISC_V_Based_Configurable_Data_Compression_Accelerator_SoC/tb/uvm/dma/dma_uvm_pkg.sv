// =============================================================================
// dma_uvm_pkg.sv — Complete UVM 1.2 Verification Environment for DMA IP
// =============================================================================
`timescale 1ns/1ps

package dma_uvm_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `uvm_analysis_imp_decl(_master)
    `uvm_analysis_imp_decl(_transfer)

    // DMA Register Offsets
    localparam bit [31:0] REG_DMA_CONTROL    = 32'h000B_0000;
    localparam bit [31:0] REG_DMA_STATUS     = 32'h000B_0004;
    localparam bit [31:0] REG_DMA_SRC_ADDR   = 32'h000B_0008;
    localparam bit [31:0] REG_DMA_DST_ADDR   = 32'h000B_000C;
    localparam bit [31:0] REG_DMA_INPUT_LEN  = 32'h000B_0010;
    localparam bit [31:0] REG_DMA_OUTPUT_LEN = 32'h000B_0014;
    localparam bit [31:0] REG_DMA_IRQ_ENABLE = 32'h000B_0018;
    localparam bit [31:0] REG_DMA_IRQ_STATUS = 32'h000B_001C;
    localparam bit [31:0] REG_DMA_ERROR_CODE = 32'h000B_0020;

    typedef enum bit {
        DMA_MODE_COMPRESS   = 1'b0,
        DMA_MODE_DECOMPRESS = 1'b1
    } dma_mode_e;

    // =========================================================================
    // 1. Transaction Items
    // =========================================================================

    // Master AXI Beat Item (Observed by Passive Monitor)
    class dma_master_beat_item extends uvm_sequence_item;
        bit        is_write;
        bit [31:0] addr;
        bit [31:0] data;
        bit [3:0]  strb;
        bit [1:0]  resp;
        bit        last;

        `uvm_object_utils_begin(dma_master_beat_item)
            `uvm_field_int(is_write, UVM_ALL_ON)
            `uvm_field_int(addr, UVM_ALL_ON)
            `uvm_field_int(data, UVM_ALL_ON)
            `uvm_field_int(strb, UVM_ALL_ON)
            `uvm_field_int(resp, UVM_ALL_ON)
            `uvm_field_int(last, UVM_ALL_ON)
        `uvm_object_utils_end

        function new(string name = "dma_master_beat_item");
            super.new(name);
        endfunction
    endclass: dma_master_beat_item

    // High-Level DMA Transfer Item
    class dma_seq_item extends uvm_sequence_item;
        logic [31:0] src_addr;
        logic [31:0] dst_addr;
        int          length;
        dma_mode_e   mode;
        bit          expected_error;
        bit          actual_error;
        logic [7:0]  actual_err_code;
        int          actual_out_len;
        bit          inject_aw_backpressure;

        `uvm_object_utils_begin(dma_seq_item)
            `uvm_field_int(src_addr, UVM_ALL_ON)
            `uvm_field_int(dst_addr, UVM_ALL_ON)
            `uvm_field_int(length, UVM_ALL_ON)
            `uvm_field_enum(dma_mode_e, mode, UVM_ALL_ON)
            `uvm_field_int(expected_error, UVM_ALL_ON)
            `uvm_field_int(actual_error, UVM_ALL_ON)
            `uvm_field_int(actual_err_code, UVM_ALL_ON)
            `uvm_field_int(actual_out_len, UVM_ALL_ON)
            `uvm_field_int(inject_aw_backpressure, UVM_ALL_ON)
        `uvm_object_utils_end

        function new(string name = "dma_seq_item");
            super.new(name);
            mode                   = DMA_MODE_COMPRESS;
            expected_error         = 1'b0;
            actual_error           = 1'b0;
            inject_aw_backpressure = 1'b0;
        endfunction

        function void set_transfer(logic [31:0] s, logic [31:0] d, int len, dma_mode_e m);
            src_addr = s;
            dst_addr = d;
            length   = len;
            mode     = m;
        endfunction
    endclass: dma_seq_item

    // =========================================================================
    // 2. Independent Golden Reference Model (Compression & Decompression)
    // =========================================================================
    class dma_ref_model extends uvm_object;
        `uvm_object_utils(dma_ref_model)

        function new(string name = "dma_ref_model");
            super.new(name);
        endfunction

        function void predict(
            input  dma_mode_e  mode,
            input  logic [7:0] in_payload [],
            input  int         in_length,
            output logic [7:0] gold_out [],
            output int         gold_len,
            output bit         gold_err
        );
            gold_err = 1'b0;

            if (mode == DMA_MODE_COMPRESS) begin
                int idx;
                logic [7:0] token_q [$];
                idx = 0;

                while (idx < in_length) begin
                    logic [7:0] cur_byte;
                    int run_len;
                    cur_byte = in_payload[idx];
                    run_len  = 1;
                    idx++;

                    while (idx < in_length && in_payload[idx] == cur_byte && run_len < 255) begin
                        run_len++;
                        idx++;
                    end

                    token_q.push_back(run_len[7:0]);
                    token_q.push_back(cur_byte);
                end

                gold_len = token_q.size();
                gold_out = new[gold_len];
                for (int i = 0; i < gold_len; i++) gold_out[i] = token_q[i];

            end else begin
                // Decompression
                logic [7:0] expand_q [$];

                if (in_length % 2 != 0) begin
                    gold_err = 1'b1;
                    gold_len = 0;
                    gold_out = new[0];
                    return;
                end

                for (int i = 0; i < in_length; i += 2) begin
                    int count;
                    logic [7:0] val;
                    count = in_payload[i];
                    val   = in_payload[i+1];

                    if (count == 0) begin
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
    endclass: dma_ref_model

    // =========================================================================
    // 3. Functional Coverage Tracker
    // =========================================================================
    class dma_coverage extends uvm_component;
        `uvm_component_utils(dma_coverage)

        uvm_analysis_imp #(dma_seq_item, dma_coverage) analysis_export;

        int cov_byte_len_1_hits   = 0;
        int cov_byte_len_2_hits   = 0;
        int cov_byte_len_3_hits   = 0;
        int cov_byte_len_4_hits   = 0;
        int cov_multi_word_hits   = 0;
        int cov_max_buf_hits      = 0;
        int cov_compress_hits     = 0;
        int cov_decompress_hits   = 0;
        int cov_error_case_hits   = 0;
        int cov_bad_addr_hits     = 0;
        int cov_rle_err_hits      = 0;
        int cov_256b_out_hits     = 0;
        int total_samples         = 0;

        function new(string name = "dma_coverage", uvm_component parent = null);
            super.new(name, parent);
            analysis_export = new("analysis_export", this);
        endfunction

        virtual function void write(dma_seq_item t);
            sample(t);
        endfunction

        function void sample(dma_seq_item item);
            total_samples++;

            if (item.length == 1) cov_byte_len_1_hits++;
            if (item.length == 2) cov_byte_len_2_hits++;
            if (item.length == 3) cov_byte_len_3_hits++;
            if (item.length == 4) cov_byte_len_4_hits++;
            if (item.length > 4 && item.length < 256) cov_multi_word_hits++;
            if (item.length == 256) cov_max_buf_hits++;

            if (item.mode == DMA_MODE_COMPRESS) cov_compress_hits++;
            else cov_decompress_hits++;

            if (item.expected_error || item.actual_error) cov_error_case_hits++;
            if (item.actual_error && (item.actual_err_code == 8'h01 || item.actual_err_code == 8'h02)) cov_bad_addr_hits++;
            if (item.actual_error && item.actual_err_code == 8'h06) cov_rle_err_hits++;
            if (!item.actual_error && item.actual_out_len == 256) cov_256b_out_hits++;
        endfunction

        function void report_phase(uvm_phase phase);
            real cov_pct;
            int covered_bins;
            covered_bins = (cov_byte_len_1_hits > 0) +
                           (cov_byte_len_2_hits > 0) +
                           (cov_byte_len_3_hits > 0) +
                           (cov_byte_len_4_hits > 0) +
                           (cov_multi_word_hits > 0) +
                           (cov_max_buf_hits > 0) +
                           (cov_compress_hits > 0) +
                           (cov_decompress_hits > 0) +
                           (cov_error_case_hits > 0) +
                           (cov_bad_addr_hits > 0) +
                           (cov_rle_err_hits > 0) +
                           (cov_256b_out_hits > 0);
            cov_pct = (real'(covered_bins) / 12.0) * 100.0;

            `uvm_info("DMA_COV", "========================================================", UVM_LOW)
            `uvm_info("DMA_COV", "            DMA FUNCTIONAL COVERAGE REPORT             ", UVM_LOW)
            `uvm_info("DMA_COV", "========================================================", UVM_LOW)
            `uvm_info("DMA_COV", $sformatf("  1-Byte Transfer Bin          : %0d hits", cov_byte_len_1_hits), UVM_LOW)
            `uvm_info("DMA_COV", $sformatf("  2-Byte Transfer Bin          : %0d hits", cov_byte_len_2_hits), UVM_LOW)
            `uvm_info("DMA_COV", $sformatf("  3-Byte Transfer Bin          : %0d hits", cov_byte_len_3_hits), UVM_LOW)
            `uvm_info("DMA_COV", $sformatf("  4-Byte (1-Word) Transfer Bin : %0d hits", cov_byte_len_4_hits), UVM_LOW)
            `uvm_info("DMA_COV", $sformatf("  Multi-Word Burst Bin         : %0d hits", cov_multi_word_hits), UVM_LOW)
            `uvm_info("DMA_COV", $sformatf("  Maximum Capacity (256B In)   : %0d hits", cov_max_buf_hits), UVM_LOW)
            `uvm_info("DMA_COV", $sformatf("  Maximum Capacity (256B Out)  : %0d hits", cov_256b_out_hits), UVM_LOW)
            `uvm_info("DMA_COV", $sformatf("  Compression Mode Bin         : %0d hits", cov_compress_hits), UVM_LOW)
            `uvm_info("DMA_COV", $sformatf("  Decompression Mode Bin       : %0d hits", cov_decompress_hits), UVM_LOW)
            `uvm_info("DMA_COV", $sformatf("  Parameter Error Bin (Len)    : %0d hits", cov_error_case_hits), UVM_LOW)
            `uvm_info("DMA_COV", $sformatf("  Bad Src/Dst Boundary Err Bin : %0d hits", cov_bad_addr_hits), UVM_LOW)
            `uvm_info("DMA_COV", $sformatf("  RLE Protocol/Odd-Len Err Bin : %0d hits", cov_rle_err_hits), UVM_LOW)
            `uvm_info("DMA_COV", $sformatf("  Overall Covered Functional Bins : %0d / 12 (%0.1f%%)", covered_bins, cov_pct), UVM_LOW)
            `uvm_info("DMA_COV", "========================================================", UVM_LOW)
        endfunction
    endclass: dma_coverage

    // =========================================================================
    // 4. Sequencer
    // =========================================================================
    typedef uvm_sequencer #(dma_seq_item) dma_sequencer;

    // =========================================================================
    // 5. Driver (Active Stimulus Generation on Slave Interface Only)
    // =========================================================================
    class dma_driver extends uvm_driver #(dma_seq_item);
        `uvm_component_utils(dma_driver)

        virtual dma_axi_if vif;

        function new(string name = "dma_driver", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual dma_axi_if)::get(this, "", "vif", vif)) begin
                `uvm_fatal("DMA_DRV", "Failed to retrieve virtual interface 'vif' from config_db!")
            end
        endfunction

        // AXI4-Lite Write Task for CPU Slave Interface
        task cpu_write(input bit [31:0] addr, input bit [31:0] data, input bit [3:0] strb = 4'b1111);
            @(posedge vif.clk);
            vif.s_axi_awid    <= 8'h10;
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

        // AXI4-Lite Read Task for CPU Slave Interface
        task cpu_read(input bit [31:0] addr, output bit [31:0] data, output bit [1:0] resp);
            @(posedge vif.clk);
            vif.s_axi_arid    <= 8'h20;
            vif.s_axi_araddr  <= addr;
            vif.s_axi_arprot  <= 3'b000;
            vif.s_axi_arvalid <= 1'b1;
            vif.s_axi_rready  <= 1'b1;

            while (!vif.s_axi_arready) @(posedge vif.clk);
            @(posedge vif.clk);
            vif.s_axi_arvalid <= 1'b0;

            while (!vif.s_axi_rvalid) @(posedge vif.clk);
            data = vif.s_axi_rdata;
            resp = vif.s_axi_rresp;
            @(posedge vif.clk);
            vif.s_axi_rready <= 1'b0;
        endtask

        task run_phase(uvm_phase phase);
            // Default idle state on slave interface
            vif.s_axi_awvalid <= 1'b0;
            vif.s_axi_wvalid  <= 1'b0;
            vif.s_axi_bready  <= 1'b0;
            vif.s_axi_arvalid <= 1'b0;
            vif.s_axi_rready  <= 1'b0;

            while (!vif.rst_n) @(posedge vif.clk);

            forever begin
                dma_seq_item item;
                bit [31:0] status_val;
                bit [31:0] out_len_val;
                bit [31:0] err_val;
                bit [1:0]  resp;
                int timeout_cnt;

                seq_item_port.get_next_item(item);

                vif.inject_aw_backpressure <= item.inject_aw_backpressure;

                // 1. Program Source Address
                cpu_write(REG_DMA_SRC_ADDR, item.src_addr);

                // 2. Program Destination Address
                cpu_write(REG_DMA_DST_ADDR, item.dst_addr);

                // 3. Program Input Length
                cpu_write(REG_DMA_INPUT_LEN, item.length);

                // 4. Enable Interrupts
                cpu_write(REG_DMA_IRQ_ENABLE, 32'h0000_0003);

                // 5. Trigger DMA Start
                cpu_write(REG_DMA_CONTROL, {30'd0, item.mode, 1'b1});

                // 6. Poll Status Register for Completion or Error
                timeout_cnt = 0;
                forever begin
                    cpu_read(REG_DMA_STATUS, status_val, resp);
                    // Bit 0 = BUSY
                    if (!status_val[0] || timeout_cnt > 30000) break;
                    timeout_cnt++;
                    repeat (5) @(posedge vif.clk);
                end

                // 7. Read Output Length
                cpu_read(REG_DMA_OUTPUT_LEN, out_len_val, resp);

                // 8. Read Error Code
                cpu_read(REG_DMA_ERROR_CODE, err_val, resp);

                // 9. Acknowledge and Clear IRQ via W1C
                cpu_write(REG_DMA_IRQ_STATUS, 32'h0000_0003);

                vif.inject_aw_backpressure <= 1'b0;

                seq_item_port.item_done();
            end
        endtask
    endclass: dma_driver

    // =========================================================================
    // 6. Passive Monitor (Monitors Both Slave Config & Master Interconnect AXI)
    // =========================================================================
    class dma_monitor extends uvm_monitor;
        `uvm_component_utils(dma_monitor)

        virtual dma_axi_if vif;
        uvm_analysis_port #(dma_master_beat_item) master_ap;
        uvm_analysis_port #(dma_seq_item)        transfer_ap;

        function new(string name = "dma_monitor", uvm_component parent = null);
            super.new(name, parent);
            master_ap   = new("master_ap", this);
            transfer_ap = new("transfer_ap", this);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual dma_axi_if)::get(this, "", "vif", vif)) begin
                `uvm_fatal("DMA_MON", "Failed to retrieve virtual interface 'vif' from config_db!")
            end
        endfunction

        task run_phase(uvm_phase phase);
            // Slave Interface Tracking Variables
            bit [31:0] s_awaddr;
            bit [31:0] s_wdata;
            bit [3:0]  s_wstrb;
            bit        saw_s_aw;
            bit        saw_s_w;
            bit [31:0] s_araddr;
            bit        saw_s_ar;

            bit [31:0] cur_src;
            bit [31:0] cur_dst;
            int        cur_len;
            dma_mode_e cur_mode;
            bit        cur_error;
            bit [7:0]  cur_err_code;
            int        cur_out_len;
            bit        xfer_active;

            // Master Interface Tracking Variables
            bit [31:0]           m_awaddr;
            bit                  saw_m_aw;
            bit [31:0]           m_araddr;
            bit                  saw_m_ar;
            dma_master_beat_item pending_wr_beats [$];

            s_awaddr     = 32'h0;
            s_wdata      = 32'h0;
            s_wstrb      = 4'h0;
            saw_s_aw     = 1'b0;
            saw_s_w      = 1'b0;
            s_araddr     = 32'h0;
            saw_s_ar     = 1'b0;

            cur_src      = 32'h0;
            cur_dst      = 32'h0;
            cur_len      = 0;
            cur_mode     = DMA_MODE_COMPRESS;
            cur_error    = 1'b0;
            cur_err_code = 8'h0;
            cur_out_len  = 0;
            xfer_active  = 1'b0;

            m_awaddr     = 32'h0;
            saw_m_aw     = 1'b0;
            m_araddr     = 32'h0;
            saw_m_ar     = 1'b0;

            forever begin
                @(posedge vif.clk);

                if (!vif.rst_n) begin
                    saw_s_aw    = 1'b0;
                    saw_s_w     = 1'b0;
                    saw_s_ar    = 1'b0;
                    saw_m_aw    = 1'b0;
                    saw_m_ar    = 1'b0;
                    xfer_active = 1'b0;
                    pending_wr_beats.delete();
                    continue;
                end

                // -------------------------------------------------------------
                // A. Slave Interface (CPU Configuration) Monitoring
                // -------------------------------------------------------------
                if (vif.s_axi_awvalid && vif.s_axi_awready) begin
                    s_awaddr = vif.s_axi_awaddr;
                    saw_s_aw = 1'b1;
                end

                if (vif.s_axi_wvalid && vif.s_axi_wready) begin
                    s_wdata  = vif.s_axi_wdata;
                    s_wstrb  = vif.s_axi_wstrb;
                    saw_s_w  = 1'b1;
                end

                if (saw_s_aw && saw_s_w && vif.s_axi_bvalid && vif.s_axi_bready) begin
                    case (s_awaddr)
                        REG_DMA_SRC_ADDR:   cur_src = s_wdata;
                        REG_DMA_DST_ADDR:   cur_dst = s_wdata;
                        REG_DMA_INPUT_LEN:  cur_len = s_wdata[15:0];
                        REG_DMA_CONTROL: begin
                            cur_mode = (s_wdata[1] == 1'b1) ? DMA_MODE_DECOMPRESS : DMA_MODE_COMPRESS;
                            if (s_wdata[0]) begin
                                xfer_active  = 1'b1;
                                cur_error    = 1'b0;
                                cur_err_code = 8'h0;
                                cur_out_len  = 0;
                            end
                        end
                        REG_DMA_IRQ_STATUS: begin
                            // W1C IRQ clear signals end of software transaction flow
                            if (xfer_active) begin
                                dma_seq_item item;
                                item = dma_seq_item::type_id::create("obs_dma_xfer");
                                item.src_addr        = cur_src;
                                item.dst_addr        = cur_dst;
                                item.length          = cur_len;
                                item.mode            = cur_mode;
                                item.actual_error    = cur_error;
                                item.actual_err_code = cur_err_code;
                                item.actual_out_len  = cur_out_len;
                                transfer_ap.write(item);
                                xfer_active = 1'b0;
                            end
                        end
                        default: begin end
                    endcase
                    saw_s_aw = 1'b0;
                    saw_s_w  = 1'b0;
                end

                if (vif.s_axi_arvalid && vif.s_axi_arready) begin
                    s_araddr = vif.s_axi_araddr;
                    saw_s_ar = 1'b1;
                end

                if (saw_s_ar && vif.s_axi_rvalid && vif.s_axi_rready) begin
                    case (s_araddr)
                        REG_DMA_STATUS: begin
                            // Bit 2 = ERROR, Bit 1 = DONE
                            if (vif.s_axi_rdata[2])      cur_error = 1'b1;
                            else if (vif.s_axi_rdata[1]) cur_error = 1'b0;
                        end
                        REG_DMA_OUTPUT_LEN: begin
                            cur_out_len = vif.s_axi_rdata[15:0];
                        end
                        REG_DMA_ERROR_CODE: begin
                            cur_err_code = vif.s_axi_rdata[7:0];
                        end
                        default: begin end
                    endcase
                    saw_s_ar = 1'b0;
                end

                // -------------------------------------------------------------
                // B. Master Interface (Interconnect & Memory) Monitoring
                // -------------------------------------------------------------
                // Master Write Address Channel (Independent AW Handshake)
                if (vif.m_axi_awvalid && vif.m_axi_awready) begin
                    m_awaddr = vif.m_axi_awaddr;
                    saw_m_aw = 1'b1;
                    // Drain any write beats that were accepted before AW completed
                    while (pending_wr_beats.size() > 0) begin
                        dma_master_beat_item pb = pending_wr_beats.pop_front();
                        pb.addr = m_awaddr;
                        master_ap.write(pb);
                        m_awaddr = m_awaddr + 4;
                    end
                end

                // Master Write Data Channel (Independent W Handshake)
                if (vif.m_axi_wvalid && vif.m_axi_wready) begin
                    dma_master_beat_item beat;
                    beat = dma_master_beat_item::type_id::create("m_wr_beat");
                    beat.is_write = 1'b1;
                    beat.data     = vif.m_axi_wdata;
                    beat.strb     = vif.m_axi_wstrb;
                    beat.last     = vif.m_axi_wlast;
                    beat.resp     = 2'b00;

                    if (saw_m_aw) begin
                        beat.addr = m_awaddr;
                        master_ap.write(beat);
                        m_awaddr = m_awaddr + 4; // Advance address for INCR burst beats
                    end else begin
                        // W beat accepted before AW completed; buffer until AW handshake
                        pending_wr_beats.push_back(beat);
                    end
                end

                if (vif.m_axi_bvalid && vif.m_axi_bready) begin
                    saw_m_aw = 1'b0;
                end

                // Master Read Address Channel
                if (vif.m_axi_arvalid && vif.m_axi_arready) begin
                    m_araddr = vif.m_axi_araddr;
                    saw_m_ar = 1'b1;
                end

                // Master Read Data Channel
                if (vif.m_axi_rvalid && vif.m_axi_rready) begin
                    dma_master_beat_item beat;
                    beat = dma_master_beat_item::type_id::create("m_rd_beat");
                    beat.is_write = 1'b0;
                    beat.addr     = m_araddr;
                    beat.data     = vif.m_axi_rdata;
                    beat.strb     = 4'b0000;
                    beat.last     = vif.m_axi_rlast;
                    beat.resp     = vif.m_axi_rresp;
                    master_ap.write(beat);
                    m_araddr = m_araddr + 4; // Advance address for INCR burst beats
                    if (vif.m_axi_rlast) begin
                        saw_m_ar = 1'b0;
                    end
                end
            end
        endtask
    endclass: dma_monitor

    // =========================================================================
    // 7. Scoreboard (Memory-Level Data & Protocol Verification)
    // =========================================================================
    class dma_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(dma_scoreboard)

        uvm_analysis_imp_master   #(dma_master_beat_item, dma_scoreboard) master_export;
        uvm_analysis_imp_transfer #(dma_seq_item, dma_scoreboard)        transfer_export;

        dma_ref_model ref_model;

        // Golden memory model for source data
        logic [7:0] ref_dmem [logic [31:0]];

        // Reconstructed destination memory from observed master writes
        logic [7:0] reconstructed_dst_mem [logic [31:0]];
        bit   [31:0] written_addrs [$];

        int total_checks = 0;
        int pass_checks  = 0;
        int fail_checks  = 0;

        function new(string name = "dma_scoreboard", uvm_component parent = null);
            super.new(name, parent);
            master_export   = new("master_export", this);
            transfer_export = new("transfer_export", this);
            ref_model       = dma_ref_model::type_id::create("ref_model");
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            // Populate full 128 KB reference DMEM matching initial testbench state
            for (int i = 0; i < 131072; i++) begin
                ref_dmem[32'h0001_0000 + i] = 8'hAA;
            end
            // Decompression tokens at 0x0002_0000: [10, 0x41], [6, 0x42]
            ref_dmem[32'h0002_0000 + 0] = 8'd10;
            ref_dmem[32'h0002_0000 + 1] = 8'h41;
            ref_dmem[32'h0002_0000 + 2] = 8'd6;
            ref_dmem[32'h0002_0000 + 3] = 8'h42;
        endfunction

        // Track observed master AXI beats
        function void write_master(dma_master_beat_item beat);
            if (beat.is_write) begin
                // Check if write is targeting destination Data Memory (0x0001_0000 .. 0x0002_FFFF)
                if (beat.addr >= 32'h0001_0000 && beat.addr <= 32'h0002_FFFF) begin
                    written_addrs.push_back(beat.addr);
                    if (beat.strb[0]) reconstructed_dst_mem[beat.addr + 0] = beat.data[7:0];
                    if (beat.strb[1]) reconstructed_dst_mem[beat.addr + 1] = beat.data[15:8];
                    if (beat.strb[2]) reconstructed_dst_mem[beat.addr + 2] = beat.data[23:16];
                    if (beat.strb[3]) reconstructed_dst_mem[beat.addr + 3] = beat.data[31:24];
                end
            end
        endfunction

        // Verify high-level completed transfer
        function void write_transfer(dma_seq_item item);
            bit   pass;
            bit   exp_err;
            logic [7:0] exp_err_code;
            logic [7:0] src_payload [];
            logic [7:0] gold_out [];
            int         gold_len;
            bit         gold_err;

            total_checks++;
            pass         = 1'b1;
            exp_err      = 1'b0;
            exp_err_code = 8'h00;

            if (item.length == 0 || item.length > 256) begin
                exp_err      = 1'b1;
                exp_err_code = 8'h03; // ERR_BAD_LEN
            end else if (item.src_addr < 32'h0001_0000 || item.src_addr > 32'h0002_FFFF ||
                         ((longint'(item.src_addr) + longint'(item.length) - 1) > 64'h0002_FFFF)) begin
                exp_err      = 1'b1;
                exp_err_code = 8'h01; // ERR_BAD_SRC
            end else if (item.dst_addr < 32'h0001_0000 || item.dst_addr > 32'h0002_FFFF) begin
                exp_err      = 1'b1;
                exp_err_code = 8'h02; // ERR_BAD_DST
            end else begin
                src_payload = new[item.length];
                for (int i = 0; i < item.length; i++) begin
                    src_payload[i] = ref_dmem.exists(item.src_addr + i) ? ref_dmem[item.src_addr + i] : 8'h00;
                end
                ref_model.predict(item.mode, src_payload, item.length, gold_out, gold_len, gold_err);
                if (gold_err || gold_len > 256) begin
                    exp_err      = 1'b1;
                    exp_err_code = 8'h06; // ERR_RLE_ERR
                end else if (gold_len > 0 && ((longint'(item.dst_addr) + longint'(gold_len) - 1) > 64'h0002_FFFF)) begin
                    exp_err      = 1'b1;
                    exp_err_code = 8'h02; // ERR_BAD_DST (spillover)
                end
            end

            if (exp_err) begin
                if (item.actual_error && item.actual_err_code == exp_err_code && written_addrs.size() == 0) begin
                    pass_checks++;
                    `uvm_info("DMA_SCB", $sformatf(">>> [PASS] DMA Expected Error Correctly Raised! (ErrCode=0x%02h)",
                              item.actual_err_code), UVM_LOW)
                end else begin
                    fail_checks++;
                    `uvm_error("DMA_SCB", $sformatf("Expected DMA error ErrCode=0x%02h with 0 writes! ActErr=%b, ActCode=0x%02h, WrCount=%0d",
                               exp_err_code, item.actual_error, item.actual_err_code, written_addrs.size()))
                end
                reconstructed_dst_mem.delete();
                written_addrs.delete();
                return;
            end

            // Scenario: Normal Compression / Decompression Transfer
            if (item.actual_error) begin
                `uvm_error("DMA_SCB", $sformatf("Unexpected DMA Error! ErrCode=0x%02h", item.actual_err_code))
                pass = 1'b0;
            end else begin
                // 2. Verify Output Length
                if (item.actual_out_len !== gold_len) begin
                    `uvm_error("DMA_SCB", $sformatf("Output Length Mismatch! Hardware=%0d, Golden Ref=%0d",
                               item.actual_out_len, gold_len))
                    pass = 1'b0;
                end

                // 3. Verify Reconstructed Destination Memory Byte-by-Byte
                for (int i = 0; i < gold_len; i++) begin
                    logic [31:0] target_addr;
                    target_addr = item.dst_addr + i;

                    if (!reconstructed_dst_mem.exists(target_addr)) begin
                        `uvm_error("DMA_SCB", $sformatf("Missing destination byte at 0x%08h (index %0d)! Expected=0x%02h",
                                   target_addr, i, gold_out[i]))
                        pass = 1'b0;
                    end else if (reconstructed_dst_mem[target_addr] !== gold_out[i]) begin
                        `uvm_error("DMA_SCB", $sformatf("Byte mismatch at 0x%08h (index %0d)! Actual=0x%02h, Expected=0x%02h",
                                   target_addr, i, reconstructed_dst_mem[target_addr], gold_out[i]))
                        pass = 1'b0;
                    end
                end

                // 4. Verify No Unexpected Writes Outside Expected Destination Range
                foreach (reconstructed_dst_mem[addr]) begin
                    if (addr < item.dst_addr || addr >= item.dst_addr + gold_len) begin
                        `uvm_error("DMA_SCB", $sformatf("Unexpected destination write outside range! Addr=0x%08h, Range=[0x%08h..0x%08h]",
                                   addr, item.dst_addr, item.dst_addr + gold_len - 1))
                        pass = 1'b0;
                    end
                end

                // 5. Verify Transfer Ordering (Strictly Monotonic Non-Decreasing Addresses)
                for (int w = 1; w < written_addrs.size(); w++) begin
                    if (written_addrs[w] <= written_addrs[w-1]) begin
                        `uvm_error("DMA_SCB", $sformatf("Write out-of-order or duplicate at index %0d: 0x%08h <= 0x%08h",
                                   w, written_addrs[w], written_addrs[w-1]))
                        pass = 1'b0;
                    end
                end

                // 6. Update reference memory with written output
                for (int i = 0; i < gold_len; i++) begin
                    ref_dmem[item.dst_addr + i] = gold_out[i];
                end
            end

            if (pass) begin
                pass_checks++;
                `uvm_info("DMA_SCB", $sformatf(">>> [PASS] DMA Transfer Verified Byte-for-Byte! (Src:0x%08h -> Dst:0x%08h, %0d -> %0d bytes, Error=0)",
                          item.src_addr, item.dst_addr, item.length, item.actual_out_len), UVM_LOW)
            end else begin
                fail_checks++;
            end

            reconstructed_dst_mem.delete();
            written_addrs.delete();
        endfunction

        function void report_phase(uvm_phase phase);
            `uvm_info("DMA_SCB", "========================================================", UVM_LOW)
            `uvm_info("DMA_SCB", "               DMA SCOREBOARD SUMMARY                   ", UVM_LOW)
            `uvm_info("DMA_SCB", "========================================================", UVM_LOW)
            `uvm_info("DMA_SCB", $sformatf("  Total DMA Transfers Checked : %0d", total_checks), UVM_LOW)
            `uvm_info("DMA_SCB", $sformatf("  Passed Transfers            : %0d", pass_checks), UVM_LOW)
            `uvm_info("DMA_SCB", $sformatf("  Failed Transfers            : %0d", fail_checks), UVM_LOW)
            if (fail_checks == 0 && total_checks > 0)
                `uvm_info("DMA_SCB", "  OVERALL SCOREBOARD VERDICT  : [ALL CHECKS PASSED]", UVM_LOW)
            else
                `uvm_error("DMA_SCB", "  OVERALL SCOREBOARD VERDICT  : [FAILURES DETECTED]")
            `uvm_info("DMA_SCB", "========================================================", UVM_LOW)
        endfunction
    endclass: dma_scoreboard

    // =========================================================================
    // 8. Agent
    // =========================================================================
    class dma_agent extends uvm_agent;
        `uvm_component_utils(dma_agent)

        dma_driver    driver;
        dma_sequencer sequencer;
        dma_monitor   monitor;

        function new(string name = "dma_agent", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            driver    = dma_driver::type_id::create("driver", this);
            sequencer = dma_sequencer::type_id::create("sequencer", this);
            monitor   = dma_monitor::type_id::create("monitor", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            driver.seq_item_port.connect(sequencer.seq_item_export);
        endfunction
    endclass: dma_agent

    // =========================================================================
    // 9. Environment
    // =========================================================================
    class dma_env extends uvm_env;
        `uvm_component_utils(dma_env)

        dma_agent      agent;
        dma_scoreboard scoreboard;
        dma_coverage   coverage;

        function new(string name = "dma_env", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agent      = dma_agent::type_id::create("agent", this);
            scoreboard = dma_scoreboard::type_id::create("scoreboard", this);
            coverage   = dma_coverage::type_id::create("coverage", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            // Passive monitor feeds scoreboard and coverage collector
            agent.monitor.transfer_ap.connect(scoreboard.transfer_export);
            agent.monitor.master_ap.connect(scoreboard.master_export);
            agent.monitor.transfer_ap.connect(coverage.analysis_export);
        endfunction
    endclass: dma_env

    // =========================================================================
    // 10. Master Sequence (Decoupled Stimulus Generation Only)
    // =========================================================================
    class dma_master_sequence extends uvm_sequence #(dma_seq_item);
        `uvm_object_utils(dma_master_sequence)

        function new(string name = "dma_master_sequence");
            super.new(name);
        endfunction

        task body();
            dma_seq_item item;

            // -----------------------------------------------------------------
            // Scenario 1: Single-byte transfer (1 byte)
            // -----------------------------------------------------------------
            `uvm_info("DMA_SEQ", ">>> Executing Scenario 1: Single-byte transfer (1 byte)", UVM_LOW)
            item = dma_seq_item::type_id::create("item_1b");
            start_item(item);
            item.set_transfer(32'h0001_0000, 32'h0002_1000, 1, DMA_MODE_COMPRESS);
            finish_item(item);

            // -----------------------------------------------------------------
            // Scenario 2: Two-byte transfer (2 bytes)
            // -----------------------------------------------------------------
            `uvm_info("DMA_SEQ", ">>> Executing Scenario 2: Two-byte transfer (2 bytes)", UVM_LOW)
            item = dma_seq_item::type_id::create("item_2b");
            start_item(item);
            item.set_transfer(32'h0001_0000, 32'h0002_2000, 2, DMA_MODE_COMPRESS);
            finish_item(item);

            // -----------------------------------------------------------------
            // Scenario 3: Three-byte transfer (3 bytes)
            // -----------------------------------------------------------------
            `uvm_info("DMA_SEQ", ">>> Executing Scenario 3: Three-byte transfer (3 bytes)", UVM_LOW)
            item = dma_seq_item::type_id::create("item_3b");
            start_item(item);
            item.set_transfer(32'h0001_0000, 32'h0002_3000, 3, DMA_MODE_COMPRESS);
            finish_item(item);

            // -----------------------------------------------------------------
            // Scenario 4: Four-byte (Full Word) transfer
            // -----------------------------------------------------------------
            `uvm_info("DMA_SEQ", ">>> Executing Scenario 4: Four-byte (1-Word) transfer", UVM_LOW)
            item = dma_seq_item::type_id::create("item_4b");
            start_item(item);
            item.set_transfer(32'h0001_0000, 32'h0002_4000, 4, DMA_MODE_COMPRESS);
            finish_item(item);

            // -----------------------------------------------------------------
            // Scenario 5: Full Run-Length Compression Flow (16 bytes)
            // -----------------------------------------------------------------
            `uvm_info("DMA_SEQ", ">>> Executing Scenario 5: Compression Flow (16 bytes)", UVM_LOW)
            item = dma_seq_item::type_id::create("item_16b");
            start_item(item);
            item.set_transfer(32'h0001_0000, 32'h0002_5000, 16, DMA_MODE_COMPRESS);
            finish_item(item);

            // -----------------------------------------------------------------
            // Scenario 6: Full Lossless Decompression Flow (4 bytes tokens -> 16 bytes)
            // -----------------------------------------------------------------
            `uvm_info("DMA_SEQ", ">>> Executing Scenario 6: Decompression Flow (4 bytes tokens)", UVM_LOW)
            item = dma_seq_item::type_id::create("item_decomp");
            start_item(item);
            item.set_transfer(32'h0002_0000, 32'h0002_6000, 4, DMA_MODE_DECOMPRESS);
            finish_item(item);

            // -----------------------------------------------------------------
            // Scenario 7: Multi-Word Burst Transfer (64 bytes)
            // -----------------------------------------------------------------
            `uvm_info("DMA_SEQ", ">>> Executing Scenario 7: Multi-word burst transfer (64 bytes)", UVM_LOW)
            item = dma_seq_item::type_id::create("item_64b");
            start_item(item);
            item.set_transfer(32'h0001_0000, 32'h0002_7000, 64, DMA_MODE_COMPRESS);
            finish_item(item);

            // -----------------------------------------------------------------
            // Scenario 8: Maximum Buffer Capacity Transfer (256 bytes)
            // -----------------------------------------------------------------
            `uvm_info("DMA_SEQ", ">>> Executing Scenario 8: Maximum Buffer Capacity (256 bytes)", UVM_LOW)
            item = dma_seq_item::type_id::create("item_256b");
            start_item(item);
            item.set_transfer(32'h0001_0000, 32'h0002_8000, 256, DMA_MODE_COMPRESS);
            finish_item(item);

            // -----------------------------------------------------------------
            // Scenario 9: Parameter Error Detection (Zero Length)
            // -----------------------------------------------------------------
            `uvm_info("DMA_SEQ", ">>> Executing Scenario 9: Parameter Error Detection (Zero Length)", UVM_LOW)
            item = dma_seq_item::type_id::create("item_err");
            start_item(item);
            item.set_transfer(32'h0001_0000, 32'h0002_9000, 0, DMA_MODE_COMPRESS);
            item.expected_error = 1'b1;
            finish_item(item);

            // -----------------------------------------------------------------
            // Scenario 10: W-before-AW Acceptance Under AW Backpressure (16 bytes)
            // -----------------------------------------------------------------
            `uvm_info("DMA_SEQ", ">>> Executing Scenario 10: W-before-AW Acceptance Under Backpressure", UVM_LOW)
            item = dma_seq_item::type_id::create("item_w_before_aw");
            start_item(item);
            item.set_transfer(32'h0001_0000, 32'h0002_A000, 16, DMA_MODE_COMPRESS);
            item.inject_aw_backpressure = 1'b1;
            finish_item(item);

            // -----------------------------------------------------------------
            // Scenario 11: Back-to-Back 256B Roundtrip Decompression Ending @ 0x0002_FFFF
            // Uses compressed output produced at 0x0002_8000 (4 bytes -> 256 bytes)
            // -----------------------------------------------------------------
            `uvm_info("DMA_SEQ", ">>> Executing Scenario 11: Full 256B Decompression to 0x0002_FF00..0x0002_FFFF", UVM_LOW)
            item = dma_seq_item::type_id::create("item_decomp_256b");
            start_item(item);
            item.set_transfer(32'h0002_8000, 32'h0002_FF00, 4, DMA_MODE_DECOMPRESS);
            finish_item(item);

            // -----------------------------------------------------------------
            // Scenario 12: Parameter Error (Destination Outside DMEM -> ERR_BAD_DST)
            // -----------------------------------------------------------------
            `uvm_info("DMA_SEQ", ">>> Executing Scenario 12: Invalid DST_ADDR (0x0003_0000) -> ERR_BAD_DST", UVM_LOW)
            item = dma_seq_item::type_id::create("item_bad_dst");
            start_item(item);
            item.set_transfer(32'h0001_0000, 32'h0003_0000, 4, DMA_MODE_COMPRESS);
            item.expected_error = 1'b1;
            finish_item(item);

            // -----------------------------------------------------------------
            // Scenario 13: Source End-of-DMEM Overflow (0x0002_FFFC len=8 -> ERR_BAD_SRC)
            // -----------------------------------------------------------------
            `uvm_info("DMA_SEQ", ">>> Executing Scenario 13: SRC End-of-DMEM Spillover -> ERR_BAD_SRC", UVM_LOW)
            item = dma_seq_item::type_id::create("item_src_spill");
            start_item(item);
            item.set_transfer(32'h0002_FFFC, 32'h0002_B000, 8, DMA_MODE_COMPRESS);
            item.expected_error = 1'b1;
            finish_item(item);

            // -----------------------------------------------------------------
            // Scenario 14: RLE Decompression Protocol Error (Odd Length -> ERR_RLE_ERR)
            // -----------------------------------------------------------------
            `uvm_info("DMA_SEQ", ">>> Executing Scenario 14: Odd Decomp Input Length -> ERR_RLE_ERR", UVM_LOW)
            item = dma_seq_item::type_id::create("item_rle_err");
            start_item(item);
            item.set_transfer(32'h0002_0000, 32'h0002_B000, 3, DMA_MODE_DECOMPRESS);
            item.expected_error = 1'b1;
            finish_item(item);

            // -----------------------------------------------------------------
            // Scenario 15: Post-RLE Destination End-of-DMEM Spillover -> ERR_BAD_DST
            // 4 bytes [10,'A',6,'B'] -> 16 bytes @ 0x0002_FFF8 would overflow 0x0002_FFFF
            // -----------------------------------------------------------------
            `uvm_info("DMA_SEQ", ">>> Executing Scenario 15: Post-RLE DST Spillover -> ERR_BAD_DST", UVM_LOW)
            item = dma_seq_item::type_id::create("item_dst_spill");
            start_item(item);
            item.set_transfer(32'h0002_0000, 32'h0002_FFF8, 4, DMA_MODE_DECOMPRESS);
            item.expected_error = 1'b1;
            finish_item(item);
        endtask
    endclass: dma_master_sequence

    // =========================================================================
    // 11. UVM Test
    // =========================================================================
    class dma_test extends uvm_test;
        `uvm_component_utils(dma_test)

        dma_env env;

        function new(string name = "dma_test", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = dma_env::type_id::create("env", this);
        endfunction

        task run_phase(uvm_phase phase);
            dma_master_sequence seq;
            phase.raise_objection(this);

            seq = dma_master_sequence::type_id::create("seq");

            `uvm_info("DMA_TEST", "========================================================", UVM_LOW)
            `uvm_info("DMA_TEST", "       STARTING UVM 1.2 REGRESSION: DMA IP CORE         ", UVM_LOW)
            `uvm_info("DMA_TEST", "========================================================", UVM_LOW)

            seq.start(env.agent.sequencer);

            `uvm_info("DMA_TEST", "DMA Master Sequence Completed All Scenarios.", UVM_LOW)
            phase.drop_objection(this);
        endtask
    endclass: dma_test

endpackage: dma_uvm_pkg
