// =============================================================================
// soc_coverage.sv — Functional Coverage Subscriber for SoC UVM Verification
// Dual-mode collector:
//   1. Portable concrete functional bin counters (runs natively in ModelSim
//      Starter Edition AND commercial simulators, reporting hit/uncovered bins).
//   2. Native SV `covergroup` guarded under `ifdef ENABLE_SV_COVERGROUP for
//      Questa/VCS native UCDB/vdb functional coverage closure.
// =============================================================================
`timescale 1ns/1ps

`ifndef SOC_COVERAGE_SV
`define SOC_COVERAGE_SV

class soc_coverage extends uvm_subscriber #(uart_seq_item);
  `uvm_component_utils(soc_coverage)

  uart_seq_item      curr_item;
  soc_env_cfg        cfg;
  virtual soc_obs_if obs_vif;
  bit                has_obs_vif = 1'b0;

  // Address Map Coverage Bins
  int cov_imem_base      = 0; // 0x0000_xxxx
  int cov_imem_alias     = 0; // 0x8000_xxxx
  int cov_dmem_lo        = 0; // 0x0001_xxxx
  int cov_dmem_hi        = 0; // 0x0002_xxxx
  int cov_uart_mmio      = 0; // 0x0003_xxxx
  int cov_timer_mmio     = 0; // 0x0005_xxxx
  int cov_gpio_mmio      = 0; // 0x0006_xxxx
  int cov_crc_mmio       = 0; // 0x000A_xxxx
  int cov_dma_mmio       = 0; // 0x000B_xxxx
  int cov_rle_mmio       = 0; // 0x000D_xxxx

  // AXI Response & Error Bins
  int cov_axi_okay       = 0;
  int cov_axi_decerr     = 0;

  // Feature & Milestone Bins
  int cov_dma_compress   = 0;
  int cov_dma_decompress = 0;
  int cov_dma_err        = 0;
  int cov_rle_direct     = 0;
  int cov_crc_result_rd  = 0;
  int cov_uart_tx        = 0;
  int cov_uart_echo_rxtx = 0;
  int cov_irq_timer      = 0;
  int cov_irq_gpio       = 0;
  int cov_irq_rle        = 0;
  int cov_irq_dma        = 0;
  int cov_reset_asserted = 0;
  int cov_warm_reset     = 0;

`ifdef ENABLE_SV_COVERGROUP
  covergroup cg_uart;
    option.per_instance = 1;
    option.name = "soc_uart_coverage";

    cp_data: coverpoint curr_item.data {
      bins char_H       = {8'h48};
      bins char_I       = {8'h49};
      bins char_A       = {8'h41};
      bins char_B       = {8'h42};
      bins char_C       = {8'h43};
      bins char_K       = {8'h4B};
      bins char_P       = {8'h50};
      bins ascii_print  = {[8'h20 : 8'h7E]};
      bins others       = default;
    }

    cp_framing: coverpoint curr_item.framing_err {
      bins no_err  = {1'b0};
      bins has_err = {1'b1};
    }

    cross_data_framing: cross cp_data, cp_framing;
  endgroup : cg_uart
`endif

  function new(string name = "soc_coverage", uvm_component parent = null);
    super.new(name, parent);
`ifdef ENABLE_SV_COVERGROUP
    cg_uart = new();
`endif
  endfunction : new

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    void'(uvm_config_db#(soc_env_cfg)::get(this, "", "cfg", cfg));
    has_obs_vif = uvm_config_db#(virtual soc_obs_if)::get(this, "", "obs_vif", obs_vif);
  endfunction : build_phase

  virtual function void write(uart_seq_item t);
    curr_item = t;
    cov_uart_tx++;
    if (t.data == 8'h4B || t.data == 8'h41 || t.data == 8'h42 || t.data == 8'h43) begin
      cov_uart_echo_rxtx++;
    end
`ifdef ENABLE_SV_COVERGROUP
    cg_uart.sample();
`endif
  endfunction : write

  function automatic void sample_addr(input logic [31:0] a);
    if      (a >= 32'h0000_0000 && a <= 32'h0000_FFFF) cov_imem_base++;
    else if (a >= 32'h8000_0000 && a <= 32'h8000_FFFF) cov_imem_alias++;
    else if (a >= 32'h0001_0000 && a <= 32'h0001_FFFF) cov_dmem_lo++;
    else if (a >= 32'h0002_0000 && a <= 32'h0002_FFFF) cov_dmem_hi++;
    else if (a >= 32'h0003_0000 && a <= 32'h0003_0FFF) cov_uart_mmio++;
    else if (a >= 32'h0005_0000 && a <= 32'h0005_0FFF) cov_timer_mmio++;
    else if (a >= 32'h0006_0000 && a <= 32'h0006_0FFF) cov_gpio_mmio++;
    else if (a >= 32'h000A_0000 && a <= 32'h000A_0FFF) cov_crc_mmio++;
    else if (a >= 32'h000B_0000 && a <= 32'h000B_FFFF) cov_dma_mmio++;
    else if (a >= 32'h000D_0000 && a <= 32'h000D_0FFF) cov_rle_mmio++;
  endfunction : sample_addr

  virtual task run_phase(uvm_phase phase);
    if (!has_obs_vif) return;
    fork
      sample_obs_bus();
    join_none
  endtask : run_phase

  virtual task sample_obs_bus();
    bit          seen_first_release = 1'b0;
    bit          was_reset_low = 1'b0;
    logic [31:0] aw_q[$];
    logic [31:0] wd_q[$];
    logic [31:0] ar_q[$];

    forever begin
      @(posedge obs_vif.clk);
      if (!obs_vif.rst_n) begin
        if (!was_reset_low) begin
          cov_reset_asserted++;
          if (seen_first_release) cov_warm_reset++;
          was_reset_low = 1'b1;
        end
        aw_q.delete();
        wd_q.delete();
        ar_q.delete();
        continue;
      end
      seen_first_release = 1'b1;
      was_reset_low      = 1'b0;

      if (obs_vif.ifu32_arvalid && obs_vif.ifu32_arready) sample_addr(obs_vif.ifu32_araddr);
      if (obs_vif.m01_awvalid   && obs_vif.m01_awready)   sample_addr(obs_vif.m01_awaddr);
      if (obs_vif.m01_arvalid   && obs_vif.m01_arready)   sample_addr(obs_vif.m01_araddr);
      if (obs_vif.dma_awvalid   && obs_vif.dma_awready)   sample_addr(obs_vif.dma_awaddr);
      if (obs_vif.dma_arvalid   && obs_vif.dma_arready)   sample_addr(obs_vif.dma_araddr);

      if (obs_vif.lsu32_awvalid && obs_vif.lsu32_awready) begin
        sample_addr(obs_vif.lsu32_awaddr);
        aw_q.push_back(obs_vif.lsu32_awaddr);
      end
      if (obs_vif.lsu32_wvalid && obs_vif.lsu32_wready) begin
        wd_q.push_back(obs_vif.lsu32_wdata);
      end
      while (aw_q.size() > 0 && wd_q.size() > 0) begin
        automatic logic [31:0] wa = aw_q.pop_front();
        automatic logic [31:0] wd = wd_q.pop_front();
        if (wa == 32'h000D_0000 && wd[0]) cov_rle_direct++;
        if (wa == 32'h000B_0000 && wd[0]) begin
          if (wd[1]) cov_dma_decompress++;
          else       cov_dma_compress++;
        end
      end

      if (obs_vif.lsu32_arvalid && obs_vif.lsu32_arready) begin
        sample_addr(obs_vif.lsu32_araddr);
        ar_q.push_back(obs_vif.lsu32_araddr);
      end
      if (obs_vif.lsu32_rvalid && obs_vif.lsu32_rready) begin
        automatic logic [31:0] ra = (ar_q.size() > 0) ? ar_q.pop_front() : 32'hFFFF_FFFF;
        if (obs_vif.lsu32_rresp == 2'b00) cov_axi_okay++;
        if (obs_vif.lsu32_rresp == 2'b11) cov_axi_decerr++;
        if (ra == 32'h000A_0004) cov_crc_result_rd++;
        if (ra == 32'h000B_0004 && obs_vif.lsu32_rdata[2]) cov_dma_err++;
      end
      if (obs_vif.lsu32_bvalid && obs_vif.lsu32_bready) begin
        if (obs_vif.lsu32_bresp == 2'b00) cov_axi_okay++;
        if (obs_vif.lsu32_bresp == 2'b11) cov_axi_decerr++;
      end

      if (obs_vif.timer_irq) cov_irq_timer++;
      if (obs_vif.gpio_irq)  cov_irq_gpio++;
      if (obs_vif.rle_irq)   cov_irq_rle++;
      if (obs_vif.dma_irq)   cov_irq_dma++;
    end
  endtask : sample_obs_bus

  // Print bin line helper
  function void print_bin(input string label, input int hits, inout int total_bins, inout int hit_bins);
    total_bins++;
    if (hits > 0) hit_bins++;
    `uvm_info("SOC_COV", $sformatf("  %-28s : %6d hits  [%s]", label, hits, (hits > 0) ? "HIT" : "UNCOVERED"), UVM_LOW)
  endfunction : print_bin

  virtual function void report_phase(uvm_phase phase);
    int total_bins = 0;
    int hit_bins   = 0;
    super.report_phase(phase);

    `uvm_info("SOC_COV", "==========================================================", UVM_LOW)
    `uvm_info("SOC_COV", "            INTEGRATED SOC FUNCTIONAL COVERAGE            ", UVM_LOW)
    `uvm_info("SOC_COV", "==========================================================", UVM_LOW)
    print_bin("IMEM Base (0x0000_xxxx)",     cov_imem_base,      total_bins, hit_bins);
    print_bin("IMEM Alias (0x8000_xxxx)",    cov_imem_alias,     total_bins, hit_bins);
    print_bin("DMEM Lower (0x0001_xxxx)",    cov_dmem_lo,        total_bins, hit_bins);
    print_bin("DMEM Upper (0x0002_xxxx)",    cov_dmem_hi,        total_bins, hit_bins);
    print_bin("UART MMIO (0x0003_xxxx)",     cov_uart_mmio,      total_bins, hit_bins);
    print_bin("Timer MMIO (0x0005_xxxx)",    cov_timer_mmio,     total_bins, hit_bins);
    print_bin("GPIO MMIO (0x0006_xxxx)",     cov_gpio_mmio,      total_bins, hit_bins);
    print_bin("CRC-32 MMIO (0x000A_xxxx)",   cov_crc_mmio,       total_bins, hit_bins);
    print_bin("DMA MMIO (0x000B_xxxx)",      cov_dma_mmio,       total_bins, hit_bins);
    print_bin("RLE MMIO (0x000D_xxxx)",      cov_rle_mmio,       total_bins, hit_bins);
    print_bin("AXI OKAY Response",           cov_axi_okay,       total_bins, hit_bins);
    print_bin("AXI DECERR Reserved Access",  cov_axi_decerr,     total_bins, hit_bins);
    print_bin("DMA Compress Flow",           cov_dma_compress,   total_bins, hit_bins);
    print_bin("DMA Decompress Flow",         cov_dma_decompress, total_bins, hit_bins);
    print_bin("DMA Error / Exception Path",  cov_dma_err,        total_bins, hit_bins);
    print_bin("Direct RLE Accelerator Op",   cov_rle_direct,     total_bins, hit_bins);
    print_bin("CRC-32 Verification Flow",    cov_crc_result_rd,  total_bins, hit_bins);
    print_bin("UART TX Transmission",        cov_uart_tx,        total_bins, hit_bins);
    print_bin("UART RX->TX Interactive",     cov_uart_echo_rxtx, total_bins, hit_bins);
    print_bin("IRQ: Timer",                  cov_irq_timer,      total_bins, hit_bins);
    print_bin("IRQ: GPIO",                   cov_irq_gpio,       total_bins, hit_bins);
    print_bin("IRQ: RLE",                    cov_irq_rle,        total_bins, hit_bins);
    print_bin("IRQ: DMA",                    cov_irq_dma,        total_bins, hit_bins);
    print_bin("Reset Assertions (Cold/All)", cov_reset_asserted, total_bins, hit_bins);
    print_bin("Reset Recovery (Warm)",       cov_warm_reset,     total_bins, hit_bins);
    `uvm_info("SOC_COV", $sformatf("  TOTAL SOC COVERAGE BINS : %0d / %0d (%0.1f%%)",
              hit_bins, total_bins, (real'(hit_bins) / real'(total_bins)) * 100.0), UVM_LOW)
    `uvm_info("SOC_COV", "==========================================================", UVM_LOW)
`ifdef ENABLE_SV_COVERGROUP
    `uvm_info("SOC_COV", $sformatf("SV Covergroup UART Coverage: %0.2f%%", cg_uart.get_inst_coverage()), UVM_LOW)
`endif
  endfunction : report_phase

endclass : soc_coverage

`endif // SOC_COVERAGE_SV
