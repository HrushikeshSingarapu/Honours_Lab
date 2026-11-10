// =============================================================================
// soc_env_cfg.sv — Unified SoC Environment Configuration Object
// Preserves all 4 VIP configurations (UART, GPIO, Reset, IRQ) plus passive
// scoreboard and coverage verification controls.
// =============================================================================
`timescale 1ns/1ps

`ifndef SOC_ENV_CFG_SV
`define SOC_ENV_CFG_SV

class soc_env_cfg extends uvm_object;
  `uvm_object_utils(soc_env_cfg)

  // Sub-VIP configurations (Exact 4 Active Agents: UART, GPIO, Reset, IRQ)
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
  int    clock_freq_hz            = 100_000_000; // 100 MHz SoC system clock
  int    baud_rate                = 115200;
  string expected_uart_string     = "HI";

  // Scoreboard / Passive Check Configuration Knobs
  bit          enable_uart_str_check    = 1'b1;
  bit          enable_bus_ref_check     = 1'b1;
  bit          clear_uart_on_warm_reset = 1'b0;
  bit          allow_expected_decerr    = 1'b0;
  bit [31:0]   expected_decerr_addr     = 32'h0007_0000;
  bit          allow_expected_cpu_fault = 1'b0;
  bit [4:0]    expected_cpu_ecause      = 5'd5;

  // Expected system milestones (verified in scoreboard check_phase when > 0 / 1)
  bit          expect_timer_irq         = 1'b0;
  bit          expect_gpio_irq          = 1'b0;
  bit          expect_rle_irq           = 1'b0;
  bit          expect_dma_irq           = 1'b0;
  bit          expect_gpio_pin_check    = 1'b0;
  int          min_expected_dma_xfers   = 0;
  int          min_expected_rle_ops     = 0;
  int          min_expected_crc_checks  = 0;
  int          min_expected_decerr_hits = 0;

  function new(string name = "soc_env_cfg");
    super.new(name);
    uart_c  = uart_cfg::type_id::create("uart_c");
    gpio_c  = gpio_cfg::type_id::create("gpio_c");
    reset_c = reset_cfg::type_id::create("reset_c");
    irq_c   = irq_cfg::type_id::create("irq_c");

    // Default 100 MHz UART baud timing for SoC
    uart_c.clock_freq_hz = clock_freq_hz;
    uart_c.baud_rate     = baud_rate;
    uart_c.data_bits     = 8;
    uart_c.stop_bits     = 1;
    uart_c.is_active     = UVM_PASSIVE;

    gpio_c.is_active     = UVM_PASSIVE;
    reset_c.is_active    = UVM_ACTIVE;
    irq_c.is_active      = UVM_PASSIVE;
  endfunction : new

  function void apply_uart_timing(int clk_hz, int baud);
    clock_freq_hz        = clk_hz;
    baud_rate            = baud;
    uart_c.clock_freq_hz = clk_hz;
    uart_c.baud_rate     = baud;
  endfunction : apply_uart_timing

endclass : soc_env_cfg

`endif // SOC_ENV_CFG_SV
