// =============================================================================
// uart_monitor.sv — Passive Monitor for UART VIP
// =============================================================================
`timescale 1ns/1ps

class uart_monitor extends uvm_monitor;
  `uvm_component_utils(uart_monitor)

  virtual uart_if                  vif;
  uart_cfg                         cfg;
  uvm_analysis_port #(uart_seq_item) ap;

  function new(string name = "uart_monitor", uvm_component parent = null);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction : new

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (cfg == null) begin
      void'(uvm_config_db#(uart_cfg)::get(this, "", "cfg", cfg));
    end
    if (vif == null) begin
      if (!uvm_config_db#(virtual uart_if)::get(this, "", "vif", vif)) begin
        if (cfg == null || cfg.vif == null) begin
          `uvm_fatal("NOVIF", $sformatf("Virtual interface uart_if not found for %s", get_full_name()))
        end else begin
          vif = cfg.vif;
        end
      end
    end
    `uvm_info("SOC_CONNECT", $sformatf("%s: Initialized with virtual interface uart_if", get_full_name()), UVM_LOW)
  endfunction : build_phase

  virtual task run_phase(uvm_phase phase);
    collect_transactions();
  endtask : run_phase

  virtual task collect_transactions();
    int bit_cycles = (cfg != null) ? cfg.get_cycles_per_bit() : 434;
    uart_seq_item item;
    logic [7:0] rx_byte;
    bit rx_stop;
    forever begin
      wait(vif.rst_n === 1'b1);
      // Ensure line is idle (HIGH) before awaiting falling edge
      wait(vif.uart_tx === 1'b1);
      // Detect falling edge of start bit on uart_tx (transmitted by DUT)
      @(negedge vif.uart_tx);
      `uvm_info("UART_MON", $sformatf("[UART_MON] Detected UART start bit falling edge on DUT uart_tx line at %0t ps", $time), UVM_LOW)
      // Sample mid-way through start bit to verify
      repeat (bit_cycles / 2) @(posedge vif.clk);
      if (vif.uart_tx !== 1'b0) continue; // Glitch filter

      // Sample 8 data bits at center of bit period
      for (int b = 0; b < 8; b++) begin
        repeat (bit_cycles) @(posedge vif.clk);
        rx_byte[b] = vif.uart_tx;
      end

      // Sample stop bit
      repeat (bit_cycles) @(posedge vif.clk);
      rx_stop = vif.uart_tx;

      item = uart_seq_item::type_id::create("item");
      item.data        = rx_byte;
      item.framing_err = (rx_stop !== 1'b1);
      item.timestamp   = $time;
      `uvm_info("UART_MON", $sformatf("[UART_MON] Sampled complete UART frame from DUT uart_tx: data=0x%02h ('%c'), stop_bit=%0b, framing_err=%0b at %0t ps", item.data, item.data, rx_stop, item.framing_err, item.timestamp), UVM_LOW)
      ap.write(item);
    end
  endtask : collect_transactions
endclass : uart_monitor
