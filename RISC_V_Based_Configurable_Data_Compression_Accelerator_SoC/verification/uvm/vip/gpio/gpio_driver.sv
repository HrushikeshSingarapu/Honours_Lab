// =============================================================================
// gpio_driver.sv — Active Driver for GPIO VIP
// =============================================================================
`timescale 1ns/1ps

class gpio_driver extends uvm_driver #(gpio_seq_item);
  `uvm_component_utils(gpio_driver)

  virtual gpio_if vif;
  gpio_cfg        cfg;

  function new(string name = "gpio_driver", uvm_component parent = null);
    super.new(name, parent);
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
    reset_signals();
    forever begin
      seq_item_port.get_next_item(req);
      drive_item(req);
      seq_item_port.item_done();
    end
  endtask : run_phase

  virtual task reset_signals();
    vif.gpio_i <= 32'h0000_0000;
  endtask : reset_signals

  virtual task drive_item(gpio_seq_item item);
    `uvm_info("GPIO_DRV", $sformatf("[GPIO_DRV] Driving GPIO input vector 0x%08h into DUT gpio_i", item.gpio_val), UVM_LOW)
    wait(vif.rst_n === 1'b1);
    @(posedge vif.clk);
    case (item.op)
      gpio_seq_item::GPIO_DRIVE_ALL: begin
        vif.gpio_i <= item.gpio_val;
      end
      gpio_seq_item::GPIO_DRIVE_MASK: begin
        vif.gpio_i <= (vif.gpio_i & ~item.gpio_mask) | (item.gpio_val & item.gpio_mask);
      end
      gpio_seq_item::GPIO_PULSE_PIN: begin
        vif.gpio_i[item.pulse_pin_idx] <= ~vif.gpio_i[item.pulse_pin_idx];
        repeat (item.pulse_cycles) @(posedge vif.clk);
        vif.gpio_i[item.pulse_pin_idx] <= ~vif.gpio_i[item.pulse_pin_idx];
      end
      default: ;
    endcase
  endtask : drive_item
endclass : gpio_driver
