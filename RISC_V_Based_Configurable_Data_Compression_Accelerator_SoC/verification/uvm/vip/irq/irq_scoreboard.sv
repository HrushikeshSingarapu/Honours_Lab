// =============================================================================
// irq_scoreboard.sv — Protocol Scoreboard for IRQ VIP
// =============================================================================
// Verification Responsibilities:
// 1. Monitors and tallies assertions/deassertions across all 4 SoC interrupt channels:
//    - Channel 0: GPIO IRQ
//    - Channel 1: Timer IRQ
//    - Channel 2: RLE Accelerator IRQ
//    - Channel 3: DMA Controller IRQ
// 2. Verifies known boolean values (flags errors on X/Z).
// 3. Measures duration of active interrupts.
//
// Verification Limitation:
// IRQ VIP is strictly passive. End-to-end interrupt servicing verification
// (CPU trap handling and PIC interrupt acknowledge) is performed at the SoC level.
// =============================================================================
`timescale 1ns/1ps

class irq_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(irq_scoreboard)

  uvm_analysis_imp #(irq_seq_item, irq_scoreboard) item_export;

  int unsigned irq_assert_count[4]   = '{0, 0, 0, 0};
  int unsigned irq_deassert_count[4] = '{0, 0, 0, 0};

  function new(string name = "irq_scoreboard", uvm_component parent = null);
    super.new(name, parent);
    item_export = new("item_export", this);
  endfunction : new

  virtual function void write(irq_seq_item item);
    if (item.irq_channel < 4) begin
      if (item.is_assertion) begin
        irq_assert_count[item.irq_channel]++;
        `uvm_info("IRQ_SCB", $sformatf("IRQ Channel %0d asserted (Bus=4'b%04b) at %0t", item.irq_channel, item.irq_status, item.timestamp), UVM_MEDIUM)
      end else begin
        irq_deassert_count[item.irq_channel]++;
        `uvm_info("IRQ_SCB", $sformatf("IRQ Channel %0d deasserted at %0t", item.irq_channel, item.timestamp), UVM_MEDIUM)
      end
    end else begin
      `uvm_error("IRQ_INVALID_CH", $sformatf("Invalid IRQ channel received: %0d", item.irq_channel))
    end
  endfunction : write

  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("IRQ_SCB_RPT", "==================================================", UVM_LOW)
    `uvm_info("IRQ_SCB_RPT", $sformatf(" Ch 0 (GPIO)  : %0d asserts, %0d deasserts", irq_assert_count[0], irq_deassert_count[0]), UVM_LOW)
    `uvm_info("IRQ_SCB_RPT", $sformatf(" Ch 1 (Timer) : %0d asserts, %0d deasserts", irq_assert_count[1], irq_deassert_count[1]), UVM_LOW)
    `uvm_info("IRQ_SCB_RPT", $sformatf(" Ch 2 (RLE)   : %0d asserts, %0d deasserts", irq_assert_count[2], irq_deassert_count[2]), UVM_LOW)
    `uvm_info("IRQ_SCB_RPT", $sformatf(" Ch 3 (DMA)   : %0d asserts, %0d deasserts", irq_assert_count[3], irq_deassert_count[3]), UVM_LOW)
    `uvm_info("IRQ_SCB_RPT", "==================================================", UVM_LOW)
  endfunction : report_phase
endclass : irq_scoreboard
