// =============================================================================
// uart_driver.sv — Active Driver for UART VIP
// =============================================================================
`timescale 1ns/1ps

class uart_driver extends uvm_driver #(uart_seq_item);
  `uvm_component_utils(uart_driver)

  virtual uart_if vif;
  uart_cfg        cfg;

  function new(string name = "uart_driver", uvm_component parent = null);
    super.new(name, parent);
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
    reset_signals();
    forever begin
      seq_item_port.get_next_item(req);
      drive_item(req);
      seq_item_port.item_done();
    end
  endtask : run_phase

  virtual task reset_signals();
    vif.uart_rx <= 1'b1; // UART idle level is HIGH
  endtask : reset_signals

  virtual task drive_item(uart_seq_item item);
    int bit_cycles = (cfg != null) ? cfg.get_cycles_per_bit() : 434; // default ~115200 at 50MHz
    int s_bits     = (item.stop_bits > 0) ? item.stop_bits : 1;
    bit par_bit;
    `uvm_info("UART_DRV", $sformatf("[UART_DRV] Driving serial byte 0x%02h ('%c') onto DUT uart_rx line", item.data, item.data), UVM_LOW)
    wait(vif.rst_n === 1'b1);

    // 1. Start bit (Low)
    @(posedge vif.clk);
    vif.uart_rx <= 1'b0;
    repeat (bit_cycles) @(posedge vif.clk);

    // 2. Data bits (LSB first)
    for (int b = 0; b < 8; b++) begin
      vif.uart_rx <= item.data[b];
      repeat (bit_cycles) @(posedge vif.clk);
    end

    // 3. Parity bit (optional)
    if (item.parity != uart_seq_item::PARITY_NONE) begin
      par_bit = (item.parity == uart_seq_item::PARITY_ODD) ? ~(^item.data) : (^item.data);
      if (item.inject_parity_err) par_bit = ~par_bit;
      vif.uart_rx <= par_bit;
      repeat (bit_cycles) @(posedge vif.clk);
    end

    // 4. Stop bit(s) (High)
    vif.uart_rx <= item.inject_framing_err ? 1'b0 : 1'b1;
    repeat (bit_cycles * s_bits) @(posedge vif.clk);
    vif.uart_rx <= 1'b1;
  endtask : drive_item
endclass : uart_driver
