// =============================================================================
// irq_agent.sv — Agent for IRQ VIP
// Retrieves IRQ virtual interface at agent level and distributes it to child
// monitor component.
// =============================================================================
`timescale 1ns/1ps

class irq_agent extends uvm_agent;
  `uvm_component_utils(irq_agent)

  virtual irq_if vif;
  irq_cfg        cfg;
  irq_monitor    mon;

  function new(string name = "irq_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction : new

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(irq_cfg)::get(this, "", "cfg", cfg)) begin
      `uvm_info("NOCFG", "No config specified for irq_agent, using default", UVM_HIGH)
      cfg = irq_cfg::type_id::create("cfg");
    end else begin
      is_active = cfg.is_active;
    end

    // Retrieve IRQ Virtual Interface at Agent level
    if (!uvm_config_db#(virtual irq_if)::get(this, "", "vif", vif)) begin
      `uvm_fatal("NOVIF", $sformatf("[SOC_CONNECT] %s: Failed to get virtual interface 'vif' from uvm_config_db", get_full_name()))
    end else begin
      `uvm_info("SOC_CONNECT", $sformatf("[SOC_CONNECT] %s: Successfully retrieved virtual interface 'vif' from uvm_config_db", get_full_name()), UVM_LOW)
    end

    // Always build passive monitor and distribute VIF
    mon = irq_monitor::type_id::create("mon", this);
    mon.cfg = cfg;
    mon.vif = vif;
  endfunction : build_phase

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
  endfunction : connect_phase
endclass : irq_agent
