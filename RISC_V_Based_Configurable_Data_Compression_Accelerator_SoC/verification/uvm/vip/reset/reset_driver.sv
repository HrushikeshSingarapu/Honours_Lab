// =============================================================================
// reset_driver.sv — Active Driver for RESET VIP
// =============================================================================
`timescale 1ns/1ps

class reset_driver extends uvm_driver #(reset_seq_item);
  `uvm_component_utils(reset_driver)

  virtual reset_if vif;
  reset_cfg        cfg;

  function new(string name = "reset_driver", uvm_component parent = null);
    super.new(name, parent);
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
    reset_signals();
    forever begin
      seq_item_port.get_next_item(req);
      drive_item(req);
      seq_item_port.item_done();
    end
  endtask : run_phase

  virtual task reset_signals();
    vif.rst_n <= 1'b0;
  endtask : reset_signals

  virtual task drive_item(reset_seq_item item);
    vif.rst_n <= 1'b0;
    `uvm_info("RST_DRV", $sformatf("[RST_DRV] Driving system reset assertion (%s) for %0d cycles to DUT rst_n", item.kind.name(), item.duration_cycles), UVM_LOW)
    repeat (item.duration_cycles) @(posedge vif.clk);
    #1;
    vif.rst_n <= 1'b1;
    `uvm_info("RST_DRV", "[RST_DRV] Driving synchronous system reset release (rst_n = 1) to DUT", UVM_LOW)
  endtask : drive_item
endclass : reset_driver
