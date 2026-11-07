// =============================================================================
// uart_agent.sv — Agent for UART VIP
// Retrieves UART virtual interface at agent level and distributes it to child
// driver and monitor components.
// =============================================================================
`timescale 1ns/1ps

class uart_agent extends uvm_agent;
  `uvm_component_utils(uart_agent)

  virtual uart_if vif;
  uart_cfg        cfg;
  uart_monitor    mon;
  uart_driver     drv;
  uart_sequencer  seqr;

  function new(string name = "uart_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction : new

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(uart_cfg)::get(this, "", "cfg", cfg)) begin
      `uvm_info("NOCFG", "No config specified for uart_agent, using default", UVM_HIGH)
      cfg = uart_cfg::type_id::create("cfg");
    end else begin
      is_active = cfg.is_active;
    end

    // Retrieve UART Virtual Interface at Agent level
    if (!uvm_config_db#(virtual uart_if)::get(this, "", "vif", vif)) begin
      `uvm_fatal("NOVIF", $sformatf("[SOC_CONNECT] %s: Failed to get virtual interface 'vif' from uvm_config_db", get_full_name()))
    end else begin
      `uvm_info("SOC_CONNECT", $sformatf("[SOC_CONNECT] %s: Successfully retrieved virtual interface 'vif' from uvm_config_db", get_full_name()), UVM_LOW)
    end

    // Always build passive monitor and distribute VIF
    mon = uart_monitor::type_id::create("mon", this);
    mon.cfg = cfg;
    mon.vif = vif;

    // Build active components only if configured active and distribute VIF
    if (get_is_active() == UVM_ACTIVE) begin
      drv  = uart_driver::type_id::create("drv", this);
      drv.cfg = cfg;
      drv.vif = vif;
      seqr = uart_sequencer::type_id::create("seqr", this);
    end
  endfunction : build_phase

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (get_is_active() == UVM_ACTIVE) begin
      drv.seq_item_port.connect(seqr.seq_item_export);
    end
  endfunction : connect_phase
endclass : uart_agent
