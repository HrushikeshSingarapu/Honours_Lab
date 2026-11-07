// =============================================================================
// axi_monitor.sv — Passive Monitor for AXI4 Bus Interconnect Verification
// Non-intrusively samples AXI channel handshakes on posedge clk, reconstructs
// complete burst transactions, detects handshake stalls, and broadcasts
// transactions via analysis port to the scoreboard.
// =============================================================================
`ifndef AXI_MONITOR_SV
`define AXI_MONITOR_SV

class axi_monitor extends uvm_monitor;
  `uvm_component_utils(axi_monitor)

  virtual axi_monitor_if           vif;
  axi_cfg                          cfg;
  uvm_analysis_port #(axi_seq_item) ap;

  // Internal transaction queues for in-flight request/response matching
  protected axi_seq_item pending_reads[bit [7:0]][$];
  protected axi_seq_item pending_writes_aw[$];
  protected axi_seq_item pending_b_resp[bit [7:0]][$];

  // Stall counters
  protected int aw_stall_cnt = 0;
  protected int w_stall_cnt  = 0;
  protected int ar_stall_cnt = 0;

  function new(string name = "axi_monitor", uvm_component parent = null);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction : new

  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);

    if (vif == null) begin
      `uvm_fatal("AXI_MON", $sformatf("[%s] Virtual interface vif handle is NULL!", get_full_name()))
    end else begin
      `uvm_info("AXI_MON",
                $sformatf("[AXI_MON] Monitor: %s verified virtual interface handle is NON-NULL (active on port %s)",
                          get_full_name(), cfg.port_name),
                UVM_LOW)
    end

    fork
      monitor_read_channel();
      monitor_write_channel();
      monitor_stalls();
    join
  endtask : run_phase

  // ---------------------------------------------------------------------------
  // Read Channel Monitor: Samples AR & R channels and matches by ARID/RID
  // ---------------------------------------------------------------------------
  virtual task monitor_read_channel();
    forever begin
      @(posedge vif.clk);
      if (!vif.rst_n) begin
        pending_reads.delete();
      end else begin
        // 1. Sample Address Read (AR) handshake
        if (vif.arvalid && vif.arready) begin
          axi_seq_item item = axi_seq_item::type_id::create("rd_item");
          item.port_name  = cfg.port_name;
          item.xact_type  = AXI_READ;
          item.addr       = vif.araddr;
          item.id         = vif.arid;
          item.len        = vif.arlen;
          item.size       = vif.arsize;
          item.burst      = vif.arburst;
          item.lock       = vif.arlock;
          item.cache      = vif.arcache;
          item.prot       = vif.arprot;
          item.qos        = vif.arqos;
          item.region     = vif.arregion;
          item.user       = vif.aruser;
          item.start_time = $time;
          item.num_beats  = 0;
          pending_reads[item.id].push_back(item);

          // Detailed handshake log for LSU and MMIO interfaces
          if (cfg.port_name == "S01_LSU" || cfg.port_name == "M02_UART") begin
            `uvm_info("AXI_MON",
                      $sformatf("[AXI_MON] AR Handshake observed on %s: ARADDR=0x%08h, ARVALID=%0b, ARREADY=%0b, ARID=0x%02h, ARLEN=%0d at %0t ps",
                                cfg.port_name, vif.araddr, vif.arvalid, vif.arready, vif.arid, vif.arlen, $time),
                      UVM_LOW)
          end
        end

        // 2. Sample Read Data (R) handshake
        if (vif.rvalid && vif.rready) begin
          bit [7:0] rid = vif.rid;
          if (pending_reads.exists(rid) && pending_reads[rid].size() > 0) begin
            axi_seq_item curr_item = pending_reads[rid][0];
            // Accumulate beat data
            curr_item.data = new[curr_item.data.size() + 1](curr_item.data);
            curr_item.data[curr_item.data.size() - 1] = vif.rdata;

            curr_item.resp = new[curr_item.resp.size() + 1](curr_item.resp);
            curr_item.resp[curr_item.resp.size() - 1] = vif.rresp;

            if (vif.rresp != 2'b00) curr_item.has_error = 1'b1;
            curr_item.num_beats++;

            if (cfg.port_name == "S01_LSU" || cfg.port_name == "M02_UART") begin
              `uvm_info("AXI_MON",
                        $sformatf("[AXI_MON] R Handshake observed on %s: RDATA=0x%08h, RRESP=%0b, RLAST=%0b, RVALID=%0b, RREADY=%0b at %0t ps",
                                  cfg.port_name, vif.rdata, vif.rresp, vif.rlast, vif.rvalid, vif.rready, $time),
                        UVM_LOW)
            end

            // Check if burst is finished (rlast asserted or beat count reached)
            if (vif.rlast || (curr_item.num_beats == int'(curr_item.len) + 1)) begin
              curr_item.end_time  = $time;
              curr_item.completed = 1'b1;
              void'(pending_reads[rid].pop_front());
              if (pending_reads[rid].size() == 0) pending_reads.delete(rid);

              `uvm_info("AXI_MON",
                        $sformatf("[AXI_MON] Read completed on %s: Addr=0x%08h, ID=0x%02h, Len=%0d, Size=%0d, Resp=%0b, Beats=%0d, Data[0]=0x%08h at %0t ps",
                                  curr_item.port_name, curr_item.addr, curr_item.id, curr_item.len, curr_item.size,
                                  curr_item.resp[0], curr_item.num_beats, curr_item.data[0], curr_item.end_time),
                        UVM_LOW)
              ap.write(curr_item);
            end
          end else begin
            if (cfg.enable_checks) begin
              `uvm_error("AXI_MON",
                         $sformatf("[AXI_MON] Read data beat observed on %s with RID=0x%02h, Data=0x%08h but no pending AR request found!",
                                   cfg.port_name, rid, vif.rdata))
            end
          end
        end
      end
    end
  endtask : monitor_read_channel

  // ---------------------------------------------------------------------------
  // Write Channel Monitor: Samples AW, W, & B channels and matches responses
  // ---------------------------------------------------------------------------
  virtual task monitor_write_channel();
    forever begin
      @(posedge vif.clk);
      if (!vif.rst_n) begin
        pending_writes_aw.delete();
        pending_b_resp.delete();
      end else begin
        // 1. Sample Write Address (AW) handshake
        if (vif.awvalid && vif.awready) begin
          axi_seq_item item = axi_seq_item::type_id::create("wr_item");
          item.port_name  = cfg.port_name;
          item.xact_type  = AXI_WRITE;
          item.addr       = vif.awaddr;
          item.id         = vif.awid;
          item.len        = vif.awlen;
          item.size       = vif.awsize;
          item.burst      = vif.awburst;
          item.lock       = vif.awlock;
          item.cache      = vif.awcache;
          item.prot       = vif.awprot;
          item.qos        = vif.awqos;
          item.region     = vif.awregion;
          item.user       = vif.awuser;
          item.start_time = $time;
          item.num_beats  = 0;
          pending_writes_aw.push_back(item);

          // Detailed handshake log
          if (cfg.port_name == "S01_LSU" || cfg.port_name == "M02_UART") begin
            `uvm_info("AXI_MON",
                      $sformatf("[AXI_MON] AW Handshake observed on %s: AWADDR=0x%08h, AWVALID=%0b, AWREADY=%0b, AWID=0x%02h, AWLEN=%0d at %0t ps",
                                cfg.port_name, vif.awaddr, vif.awvalid, vif.awready, vif.awid, vif.awlen, $time),
                      UVM_LOW)
          end
        end

        // 2. Sample Write Data (W) handshake
        if (vif.wvalid && vif.wready) begin
          if (pending_writes_aw.size() > 0) begin
            axi_seq_item curr_item = pending_writes_aw[0];
            curr_item.data = new[curr_item.data.size() + 1](curr_item.data);
            curr_item.data[curr_item.data.size() - 1] = vif.wdata;

            curr_item.strb = new[curr_item.strb.size() + 1](curr_item.strb);
            curr_item.strb[curr_item.strb.size() - 1] = vif.wstrb;
            curr_item.num_beats++;

            if (cfg.port_name == "S01_LSU" || cfg.port_name == "M02_UART") begin
              `uvm_info("AXI_MON",
                        $sformatf("[AXI_MON] W Handshake observed on %s: WDATA=0x%08h, WSTRB=0x%1h, WVALID=%0b, WREADY=%0b, WLAST=%0b at %0t ps",
                                  cfg.port_name, vif.wdata, vif.wstrb, vif.wvalid, vif.wready, vif.wlast, $time),
                        UVM_LOW)
            end

            if (vif.wlast || (curr_item.num_beats == int'(curr_item.len) + 1)) begin
              // Write data burst completed; queue for B response matching
              pending_b_resp[curr_item.id].push_back(curr_item);
              void'(pending_writes_aw.pop_front());
            end
          end else begin
            if (cfg.enable_checks) begin
              `uvm_warning("AXI_MON",
                           $sformatf("[AXI_MON] W handshake observed on %s with WDATA=0x%08h before AW handshake was registered",
                                     cfg.port_name, vif.wdata))
            end
          end
        end

        // 3. Sample Write Response (B) handshake
        if (vif.bvalid && vif.bready) begin
          bit [7:0] bid = vif.bid;
          if (pending_b_resp.exists(bid) && pending_b_resp[bid].size() > 0) begin
            axi_seq_item done_item = pending_b_resp[bid].pop_front();
            done_item.bresp     = vif.bresp;
            done_item.bid       = vif.bid;
            done_item.end_time  = $time;
            done_item.completed = 1'b1;
            if (vif.bresp != 2'b00) done_item.has_error = 1'b1;

            if (pending_b_resp[bid].size() == 0) pending_b_resp.delete(bid);

            if (cfg.port_name == "S01_LSU" || cfg.port_name == "M02_UART") begin
              `uvm_info("AXI_MON",
                        $sformatf("[AXI_MON] B Handshake observed on %s: BRESP=%0b (%s), BVALID=%0b, BREADY=%0b, BID=0x%02h at %0t ps",
                                  cfg.port_name, vif.bresp, (vif.bresp == 2'b00 ? "OKAY" : "ERR"), vif.bvalid, vif.bready, vif.bid, $time),
                        UVM_LOW)
            end

            `uvm_info("AXI_MON",
                      $sformatf("[AXI_MON] Write completed on %s: Addr=0x%08h, ID=0x%02h, Len=%0d, Size=%0d, BResp=%0b, Beats=%0d, WData[0]=0x%08h, WStrb[0]=0x%1h at %0t ps",
                                done_item.port_name, done_item.addr, done_item.id, done_item.len, done_item.size,
                                done_item.bresp, done_item.num_beats, done_item.data[0], done_item.strb[0], done_item.end_time),
                      UVM_LOW)
            ap.write(done_item);
          end else begin
            if (cfg.enable_checks) begin
              `uvm_error("AXI_MON",
                         $sformatf("[AXI_MON] Write response observed on %s with BID=0x%02h, BRESP=%0b but no matching write item found!",
                                   cfg.port_name, bid, vif.bresp))
            end
          end
        end
      end
    end
  endtask : monitor_write_channel

  // ---------------------------------------------------------------------------
  // Stall Checking: Detects persistent valid asserted without ready
  // ---------------------------------------------------------------------------
  virtual task monitor_stalls();
    forever begin
      @(posedge vif.clk);
      if (!vif.rst_n) begin
        aw_stall_cnt = 0;
        w_stall_cnt  = 0;
        ar_stall_cnt = 0;
      end else begin
        // AW Stall check
        if (vif.awvalid && !vif.awready) begin
          aw_stall_cnt++;
          if (aw_stall_cnt == cfg.stall_timeout_cycles) begin
            `uvm_warning("AXI_MON",
                         $sformatf("[AXI_MON] AW handshake stall detected on %s: awvalid asserted without awready for %0d cycles (Addr=0x%08h)",
                                   cfg.port_name, aw_stall_cnt, vif.awaddr))
          end
        end else begin
          aw_stall_cnt = 0;
        end

        // W Stall check
        if (vif.wvalid && !vif.wready) begin
          w_stall_cnt++;
          if (w_stall_cnt == cfg.stall_timeout_cycles) begin
            `uvm_warning("AXI_MON",
                         $sformatf("[AXI_MON] W handshake stall detected on %s: wvalid asserted without wready for %0d cycles",
                                   cfg.port_name, w_stall_cnt))
          end
        end else begin
          w_stall_cnt = 0;
        end

        // AR Stall check
        if (vif.arvalid && !vif.arready) begin
          ar_stall_cnt++;
          if (ar_stall_cnt == cfg.stall_timeout_cycles) begin
            `uvm_warning("AXI_MON",
                         $sformatf("[AXI_MON] AR handshake stall detected on %s: arvalid asserted without arready for %0d cycles (Addr=0x%08h)",
                                   cfg.port_name, ar_stall_cnt, vif.araddr))
          end
        end else begin
          ar_stall_cnt = 0;
        end
      end
    end
  endtask : monitor_stalls

endclass : axi_monitor

`endif // AXI_MONITOR_SV
