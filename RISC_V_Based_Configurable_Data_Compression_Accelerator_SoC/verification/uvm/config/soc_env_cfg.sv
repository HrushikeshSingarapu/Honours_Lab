// =============================================================================
// soc_env_cfg.sv — Unified SoC Environment Configuration Object
// =============================================================================
`timescale 1ns/1ps

`ifndef SOC_ENV_CFG_SV
`define SOC_ENV_CFG_SV

class soc_env_cfg extends uvm_object;
  `uvm_object_utils(soc_env_cfg)

  // Sub-VIP configurations (4 Agents: UART, GPIO, Reset, IRQ)
  uart_cfg  uart_c;
  gpio_cfg  gpio_c;
  reset_cfg reset_c;
  irq_cfg   irq_c;

  // Environment feature flags
  bit has_uart  = 1'b1;
  bit has_gpio  = 1'b1;
  bit has_reset = 1'b1;
  bit has_irq   = 1'b1;

  // SoC Timing & Verification parameters
  int    clock_freq_hz        = 100_000_000; // 100 MHz SoC system clock
  int    baud_rate            = 115200;
  string expected_uart_string = "HI";

  function new(string name = "soc_env_cfg");
    super.new(name);
    uart_c  = uart_cfg::type_id::create("uart_c");
    gpio_c  = gpio_cfg::type_id::create("gpio_c");
    reset_c = reset_cfg::type_id::create("reset_c");
    irq_c   = irq_cfg::type_id::create("irq_c");

    // Configure 100 MHz UART baud timing for SoC
    uart_c.clock_freq_hz = 100_000_000;
    uart_c.baud_rate     = 115200;
    uart_c.data_bits     = 8;
    uart_c.stop_bits     = 1;
    uart_c.is_active     = UVM_PASSIVE; // Passive monitor on SoC UART TX by default

    gpio_c.is_active     = UVM_PASSIVE;
    reset_c.is_active    = UVM_ACTIVE;
    irq_c.is_active      = UVM_PASSIVE;
  endfunction : new

endclass : soc_env_cfg

`endif // SOC_ENV_CFG_SV
