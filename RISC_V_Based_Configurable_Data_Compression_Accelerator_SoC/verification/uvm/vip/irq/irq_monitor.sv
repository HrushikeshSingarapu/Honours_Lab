// =============================================================================
// irq_monitor.sv — Passive Monitor for IRQ VIP
// =============================================================================
`timescale 1ns/1ps

class irq_monitor extends uvm_monitor;
  `uvm_component_utils(irq_monitor)

  virtual irq_if                  vif;
  irq_cfg                         cfg;
  uvm_analysis_port #(irq_seq_item) ap;

  function new(string name = "irq_monitor", uvm_component parent = null);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction : new

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (vif == null) begin
      if (!uvm_config_db#(virtual irq_if)::get(this, "", "vif", vif)) begin
        if (!uvm_config_db#(irq_cfg)::get(this, "", "cfg", cfg) || cfg.vif == null) begin
          `uvm_fatal("NOVIF", $sformatf("Virtual interface irq_if not found for %s", get_full_name()))
        end else begin
          vif = cfg.vif;
        end
      end
    end
    `uvm_info("SOC_CONNECT", $sformatf("%s: Initialized with virtual interface irq_if", get_full_name()), UVM_LOW)
  endfunction : build_phase

  virtual task run_phase(uvm_phase phase);
    collect_transactions();
  endtask : run_phase

  virtual task collect_transactions();
    irq_seq_item item;
    logic [3:0] prev_irqs = 4'b0000;
    logic [3:0] cur_irqs;
    forever begin
      @(posedge vif.clk);
      cur_irqs = {vif.dma_irq, vif.rle_irq, vif.timer_irq, vif.gpio_irq};
      if (vif.rst_n) begin
        for (int ch = 0; ch < 4; ch++) begin
          if (cur_irqs[ch] !== prev_irqs[ch]) begin
            item = irq_seq_item::type_id::create("item");
            item.irq_channel  = ch;
            item.is_assertion = cur_irqs[ch];
            item.irq_status   = cur_irqs;
            item.gpio_irq     = vif.gpio_irq;
            item.timer_irq    = vif.timer_irq;
            item.rle_irq      = vif.rle_irq;
            item.dma_irq      = vif.dma_irq;
            item.timestamp    = $time;
            `uvm_info("IRQ_MON", $sformatf("[IRQ_MON] Sampled DUT interrupt transition Ch %0d -> %b (gpio=%0b, timer=%0b, rle=%0b, dma=%0b) at %0t ps", ch, cur_irqs[ch], vif.gpio_irq, vif.timer_irq, vif.rle_irq, vif.dma_irq, item.timestamp), UVM_LOW)
            ap.write(item);
          end
        end
        prev_irqs = cur_irqs;
      end else begin
        prev_irqs = 4'b0000;
      end
    end
  endtask : collect_transactions
endclass : irq_monitor
