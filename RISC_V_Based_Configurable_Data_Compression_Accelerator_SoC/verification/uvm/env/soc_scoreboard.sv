// =============================================================================
// soc_scoreboard.sv — Unified Scoreboard for SoC UVM Verification
// Cross-checks transactions from UART, GPIO, Reset, and IRQ VIP monitors.
// Validates end-to-end SoC dataflow and firmware execution.
// =============================================================================
`timescale 1ns/1ps

`ifndef SOC_SCOREBOARD_SV
`define SOC_SCOREBOARD_SV

`uvm_analysis_imp_decl(_uart)
`uvm_analysis_imp_decl(_gpio)
`uvm_analysis_imp_decl(_reset)
`uvm_analysis_imp_decl(_irq)

class soc_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(soc_scoreboard)

  // Analysis implementation exports for each VIP (UART, GPIO, Reset, IRQ)
  uvm_analysis_imp_uart  #(uart_seq_item,  soc_scoreboard) uart_export;
  uvm_analysis_imp_gpio  #(gpio_seq_item,  soc_scoreboard) gpio_export;
  uvm_analysis_imp_reset #(reset_seq_item, soc_scoreboard) reset_export;
  uvm_analysis_imp_irq   #(irq_seq_item,   soc_scoreboard) irq_export;

  soc_env_cfg cfg;

  // UART Verification tracking state
  string expected_str       = "HI";
  string received_str       = "";
  int    uart_chars_matched = 0;
  int    uart_frame_errors  = 0;
  int    total_uart_rx      = 0;
  bit    uart_test_passed   = 1'b0;

  // Peripheral transition counters
  int    gpio_transitions   = 0;
  int    reset_assertions   = 0;
  int    irq_events         = 0;

  function new(string name = "soc_scoreboard", uvm_component parent = null);
    super.new(name, parent);
    uart_export  = new("uart_export", this);
    gpio_export  = new("gpio_export", this);
    reset_export = new("reset_export", this);
    irq_export   = new("irq_export", this);
  endfunction : new

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (uvm_config_db#(soc_env_cfg)::get(this, "", "cfg", cfg)) begin
      expected_str = cfg.expected_uart_string;
      `uvm_info("SOC_SCB", $sformatf("Configured expected_str = \"%s\" from soc_env_cfg", expected_str), UVM_LOW)
    end
  endfunction : build_phase

  function void set_expected_string(string s);
    expected_str = s;
  endfunction : set_expected_string

  // ---------------------------------------------------------------------------
  // UART Analysis Port Implementation
  // ---------------------------------------------------------------------------
  virtual function void write_uart(uart_seq_item item);
    byte ch = item.data;
    total_uart_rx++;

    if (item.framing_err || item.parity_err) begin
      uart_frame_errors++;
      `uvm_error("UART_SCB",
                 $sformatf("[UART_SCB] Protocol frame error detected on char #%0d! framing_err=%0b, parity_err=%0b",
                           total_uart_rx, item.framing_err, item.parity_err))
      return;
    end

    received_str = {received_str, string'(ch)};
    `uvm_info("UART_SCB",
              $sformatf("[UART_SCB] Received character #%0d: '%c' (0x%02h) [Cumulative: \"%s\"] at %0t ps",
                        total_uart_rx, ch, ch, received_str, $time),
              UVM_LOW)

    // Check against expected sequence
    if (total_uart_rx <= expected_str.len()) begin
      byte exp_ch = expected_str[total_uart_rx - 1];
      if (ch == exp_ch) begin
        uart_chars_matched++;
        `uvm_info("UART_SCB",
                  $sformatf("[UART_SCB] Character match #%0d PASS: expected '%c', got '%c'",
                            total_uart_rx, exp_ch, ch),
                  UVM_LOW)
      end else begin
        `uvm_error("UART_SCB",
                   $sformatf("[UART_SCB] Character mismatch at pos #%0d: expected '%c' (0x%02h), got '%c' (0x%02h) - Check: FAIL",
                             total_uart_rx, exp_ch, exp_ch, ch, ch))
      end
    end else begin
      `uvm_warning("UART_SCB",
                   $sformatf("[UART_SCB] Received character beyond expected length (%0d): '%c'",
                             expected_str.len(), ch))
    end

    if (total_uart_rx == expected_str.len() && uart_chars_matched == expected_str.len()) begin
      uart_test_passed = 1'b1;
      `uvm_info("UART_SCB",
                $sformatf("[UART_SCB] COMPLETE MATCH! Fully received expected string \"%s\" with 0 errors.",
                          expected_str),
                UVM_NONE)
    end
  endfunction : write_uart

  // ---------------------------------------------------------------------------
  // GPIO Analysis Port Implementation
  // ---------------------------------------------------------------------------
  virtual function void write_gpio(gpio_seq_item item);
    gpio_transitions++;
    `uvm_info("GPIO_SCB",
              $sformatf("[GPIO_SCB] Observation #%0d: gpio_o=0x%08h, gpio_oe=0x%08h at %0t ps",
                        gpio_transitions, item.gpio_o, item.gpio_oe, item.timestamp),
              UVM_MEDIUM)
  endfunction : write_gpio

  // ---------------------------------------------------------------------------
  // Reset Analysis Port Implementation
  // ---------------------------------------------------------------------------
  virtual function void write_reset(reset_seq_item item);
    reset_assertions++;
    `uvm_info("RST_SCB",
              $sformatf("[RST_SCB] Reset event #%0d: duration=%0d cycles, release at %0t ps",
                        reset_assertions, item.duration_cycles, item.timestamp),
              UVM_LOW)
  endfunction : write_reset

  // ---------------------------------------------------------------------------
  // IRQ Analysis Port Implementation
  // ---------------------------------------------------------------------------
  virtual function void write_irq(irq_seq_item item);
    irq_events++;
    `uvm_info("IRQ_SCB",
              $sformatf("[IRQ_SCB] Interrupt event #%0d: channel=%0d, asserted=%0b, irq_status=4'b%04b at %0t ps",
                        irq_events, item.irq_channel, item.is_assertion, item.irq_status, item.timestamp),
              UVM_MEDIUM)
  endfunction : write_irq

  // ---------------------------------------------------------------------------
  // Final Evaluation and Checks
  // ---------------------------------------------------------------------------
  virtual function void check_phase(uvm_phase phase);
    super.check_phase(phase);

    `uvm_info("SCB_FINAL", "==========================================================", UVM_NONE)
    `uvm_info("SCB_FINAL", "           SOC SCOREBOARD FINAL SUMMARY REPORT            ", UVM_NONE)
    `uvm_info("SCB_FINAL", "==========================================================", UVM_NONE)
    `uvm_info("SCB_FINAL", $sformatf(" Expected UART String                 : \"%s\"", expected_str), UVM_NONE)
    `uvm_info("SCB_FINAL", $sformatf(" Received UART String                 : \"%s\"", received_str), UVM_NONE)
    `uvm_info("SCB_FINAL", $sformatf(" Total UART Characters Received       : %0d", total_uart_rx), UVM_NONE)
    `uvm_info("SCB_FINAL", $sformatf(" Matching Characters                  : %0d / %0d", uart_chars_matched, expected_str.len()), UVM_NONE)
    `uvm_info("SCB_FINAL", $sformatf(" UART Protocol Framing Errors         : %0d", uart_frame_errors), UVM_NONE)
    `uvm_info("SCB_FINAL", $sformatf(" System Reset Assertions Observed     : %0d", reset_assertions), UVM_NONE)
    `uvm_info("SCB_FINAL", $sformatf(" GPIO Pin Transitions Monitored       : %0d", gpio_transitions), UVM_NONE)
    `uvm_info("SCB_FINAL", $sformatf(" Peripheral Interrupt Events Captured : %0d", irq_events), UVM_NONE)
    `uvm_info("SCB_FINAL", "==========================================================", UVM_NONE)

    // Evaluate final assertions
    if (uart_chars_matched != expected_str.len() || total_uart_rx != expected_str.len() || uart_frame_errors != 0) begin
      `uvm_error("UART_SCB",
                 $sformatf("[UART_SCB] Scoreboard check failed! Expected \"%s\" (len=%0d) with 0 errors, received \"%s\" (total_rx=%0d) with %0d errors - Check: FAIL",
                           expected_str, expected_str.len(), received_str, total_uart_rx, uart_frame_errors))
    end else begin
      `uvm_info("UART_SCB",
                "[UART_SCB] Scoreboard check PASSED! All expected characters matched with zero errors - Check: PASS", UVM_NONE)
    end
  endfunction : check_phase

endclass : soc_scoreboard

`endif // SOC_SCOREBOARD_SV
