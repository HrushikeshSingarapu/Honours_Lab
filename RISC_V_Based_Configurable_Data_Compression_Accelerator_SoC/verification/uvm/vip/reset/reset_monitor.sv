// =============================================================================
// reset_monitor.sv — Passive Monitor for RESET VIP
// =============================================================================
`timescale 1ns/1ps

class reset_monitor extends uvm_monitor;
  `uvm_component_utils(reset_monitor)

  virtual reset_if                  vif;
  reset_cfg                         cfg;
  uvm_analysis_port #(reset_seq_item) ap;

  function new(string name = "reset_monitor", uvm_component parent = null);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction : new

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (vif == null) begin
      if (!uvm_config_db#(virtual reset_if)::get(this, "", "vif", vif)) begin
        if (!uvm_config_db#(reset_cfg)::get(this, "", "cfg", cfg) || cfg.vif == null) begin
          `uvm_fatal("NOVIF", $sformatf("Virtual interface reset_if not found for %s", get_full_name()))
        end else begin
          vif = cfg.vif;
        end
      end
    end
    `uvm_info("SOC_CONNECT", $sformatf("%s: Initialized with virtual interface reset_if", get_full_name()), UVM_LOW)
  endfunction : build_phase

  virtual task run_phase(uvm_phase phase);
    collect_transactions();
  endtask : run_phase

  virtual task collect_transactions();
    reset_seq_item item;
    bit prev_rst_n = 1'b1;
    int cycles = 0;
    forever begin
      @(posedge vif.clk);
      if (!vif.rst_n) begin
        if (prev_rst_n) begin
          `uvm_info("RST_MON", "[RST_MON] Detected DUT reset assertion (rst_n == 0)", UVM_LOW)
        end
        cycles++;
        prev_rst_n = 1'b0;
      end else if (vif.rst_n && !prev_rst_n) begin
        item = reset_seq_item::type_id::create("item");
        item.duration_cycles = cycles;
        item.timestamp       = $time;
        `uvm_info("RST_MON", $sformatf("[RST_MON] Sampled DUT reset release (rst_n == 1), measured duration = %0d cycles at %0t ps", item.duration_cycles, item.timestamp), UVM_LOW)
        cycles               = 0;
        prev_rst_n           = 1'b1;
        ap.write(item);
      end
    end
  endtask : collect_transactions
endclass : reset_monitor
