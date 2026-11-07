// =============================================================================
// axi_agent.sv — Passive AXI Verification Agent
// Encapsulates passive AXI monitor and manages virtual interface retrieval.
// =============================================================================
`ifndef AXI_AGENT_SV
`define AXI_AGENT_SV

class axi_agent extends uvm_agent;
  `uvm_component_utils(axi_agent)

  axi_cfg     cfg;
  axi_monitor mon;

  function new(string name = "axi_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction : new

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(axi_cfg)::get(this, "", "cfg", cfg)) begin
      cfg = axi_cfg::type_id::create("cfg");
      cfg.port_name = get_name();
      `uvm_info("SOC_CONNECT",
                $sformatf("[SOC_CONNECT] Agent: %s using newly created default configuration object (port_name=%s)",
                          get_full_name(), cfg.port_name),
                UVM_LOW)
    end else begin
      `uvm_info("SOC_CONNECT",
                $sformatf("[SOC_CONNECT] Agent: %s successfully retrieved configuration 'cfg' via uvm_config_db::get() (port_name=%s)",
                          get_full_name(), cfg.port_name),
                UVM_LOW)
    end

    // Build passive monitor
    mon = axi_monitor::type_id::create("mon", this);
    mon.cfg = cfg;
  endfunction : build_phase

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    if (!uvm_config_db#(virtual axi_monitor_if)::get(this, "", "vif", mon.vif)) begin
      `uvm_fatal("AXI_AGENT",
                 $sformatf("[%s] Failed to get virtual interface 'vif' from uvm_config_db!", get_full_name()))
    end else begin
      `uvm_info("SOC_CONNECT",
                $sformatf("[SOC_CONNECT] Agent: %s successfully retrieved virtual axi_monitor_if via uvm_config_db::get() (Port: %s)",
                          get_full_name(), cfg.port_name),
                UVM_LOW)
    end
  endfunction : connect_phase

endclass : axi_agent

`endif // AXI_AGENT_SV
