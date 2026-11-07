// =============================================================================
// gpio_monitor.sv — Passive Monitor for GPIO VIP
// =============================================================================
`timescale 1ns/1ps

class gpio_monitor extends uvm_monitor;
  `uvm_component_utils(gpio_monitor)

  virtual gpio_if                  vif;
  gpio_cfg                         cfg;
  uvm_analysis_port #(gpio_seq_item) ap;

  function new(string name = "gpio_monitor", uvm_component parent = null);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction : new

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (vif == null) begin
      if (!uvm_config_db#(virtual gpio_if)::get(this, "", "vif", vif)) begin
        if (!uvm_config_db#(gpio_cfg)::get(this, "", "cfg", cfg) || cfg.vif == null) begin
          `uvm_fatal("NOVIF", $sformatf("Virtual interface gpio_if not found for %s", get_full_name()))
        end else begin
          vif = cfg.vif;
        end
      end
    end
    `uvm_info("SOC_CONNECT", $sformatf("%s: Initialized with virtual interface gpio_if", get_full_name()), UVM_LOW)
  endfunction : build_phase

  virtual task run_phase(uvm_phase phase);
    collect_transactions();
  endtask : run_phase

  virtual task collect_transactions();
    gpio_seq_item item;
    logic [31:0] prev_o  = '0;
    logic [31:0] prev_oe = '0;
    forever begin
      @(posedge vif.clk);
      if (vif.rst_n) begin
        if (vif.gpio_o !== prev_o || vif.gpio_oe !== prev_oe) begin
          item = gpio_seq_item::type_id::create("item");
          item.gpio_o    = vif.gpio_o;
          item.gpio_oe   = vif.gpio_oe;
          item.gpio_val  = vif.gpio_i;
          item.timestamp = $time;
          prev_o         = vif.gpio_o;
          prev_oe        = vif.gpio_oe;
          `uvm_info("GPIO_MON", $sformatf("[GPIO_MON] Sampled DUT GPIO pin activity: gpio_o=0x%08h, gpio_oe=0x%08h at %0t ps", item.gpio_o, item.gpio_oe, item.timestamp), UVM_LOW)
          ap.write(item);
        end
      end
    end
  endtask : collect_transactions
endclass : gpio_monitor
