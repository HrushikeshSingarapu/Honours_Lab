// =============================================================================
// tb_soc_top.sv — Top-Level Testbench for VeeR EL2 SoC UVM Verification
// Instantiates SoC DUT, connects the 4 physical VIP interfaces (Reset, UART,
// GPIO, IRQ) plus passive soc_obs_if and bound protocol assertions, loads
// firmware into IMEM (honoring +FIRMWARE= or +UVM_TESTNAME default mapping),
// registers virtual interfaces in uvm_config_db, and kicks off UVM tests.
// =============================================================================
`timescale 1ns/1ps

module tb_soc_top;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import reset_vip_pkg::*;
  import uart_vip_pkg::*;
  import gpio_vip_pkg::*;
  import irq_vip_pkg::*;
  import soc_uvm_pkg::*;

  // ---------------------------------------------------------------------------
  // 100 MHz SoC Master System Clock Generation
  // ---------------------------------------------------------------------------
  logic clk = 1'b0;
  always #5 clk = ~clk; // 100 MHz (10ns period)

  // ---------------------------------------------------------------------------
  // Physical VIP Interface Instantiations (Preserves exact 4 VIP interfaces)
  // ---------------------------------------------------------------------------
  reset_if reset_vif (.clk(clk));
  uart_if  uart_vif  (.clk(clk), .rst_n(reset_vif.rst_n));
  gpio_if  gpio_vif  (.clk(clk), .rst_n(reset_vif.rst_n));
  irq_if   irq_vif   (.clk(clk), .rst_n(reset_vif.rst_n));

  // Passive internal SoC telemetry interface (NO active driver)
  soc_obs_if obs_vif (.clk(clk), .rst_n(reset_vif.rst_n));

  // Core instruction trace signals exported from DUT boundary
  wire [31:0] trace_rv_i_insn_ip;
  wire [31:0] trace_rv_i_address_ip;
  wire        trace_rv_i_valid_ip;
  wire        trace_rv_i_exception_ip;
  wire [ 4:0] trace_rv_i_ecause_ip;
  wire        trace_rv_i_interrupt_ip;
  wire [31:0] trace_rv_i_tval_ip;

  // Initialize passive inputs to avoid X-propagation
  initial begin
    uart_vif.uart_rx = 1'b1;         // UART idle state is HIGH
    gpio_vif.gpio_i  = 32'h00000000; // External GPIO inputs grounded by default
  end

  // ---------------------------------------------------------------------------
  // SoC DUT Instantiation (soc_core_top)
  // ---------------------------------------------------------------------------
  soc_core_top #(
    .IMEM_DEPTH(16384),
    .DMEM_DEPTH(32768)
  ) u_dut (
    .clk                    (clk),
    .rst_n                  (reset_vif.rst_n),
    .uart_rx                (uart_vif.uart_rx),
    .uart_tx                (uart_vif.uart_tx),
    .gpio_i                 (gpio_vif.gpio_i),
    .gpio_o                 (gpio_vif.gpio_o),
    .gpio_oe                (gpio_vif.gpio_oe),
    .trace_rv_i_insn_ip     (trace_rv_i_insn_ip),
    .trace_rv_i_address_ip  (trace_rv_i_address_ip),
    .trace_rv_i_valid_ip    (trace_rv_i_valid_ip),
    .trace_rv_i_exception_ip(trace_rv_i_exception_ip),
    .trace_rv_i_ecause_ip   (trace_rv_i_ecause_ip),
    .trace_rv_i_interrupt_ip(trace_rv_i_interrupt_ip),
    .trace_rv_i_tval_ip     (trace_rv_i_tval_ip),
    .gpio_irq               (irq_vif.gpio_irq),
    .timer_irq              (irq_vif.timer_irq),
    .rle_irq                (irq_vif.rle_irq),
    .dma_irq                (irq_vif.dma_irq)
  );

  // ---------------------------------------------------------------------------
  // Passive Continuous Observation Assignments (Read-Only Taps into DUT)
  // ---------------------------------------------------------------------------
  assign obs_vif.ifu32_arvalid   = u_dut.u_soc.ifu32_arvalid;
  assign obs_vif.ifu32_arready   = u_dut.u_soc.ifu32_arready;
  assign obs_vif.ifu32_araddr    = u_dut.u_soc.ifu32_araddr;
  assign obs_vif.ifu32_rvalid    = u_dut.u_soc.ifu32_rvalid;
  assign obs_vif.ifu32_rready    = u_dut.u_soc.ifu32_rready;
  assign obs_vif.ifu32_rresp     = u_dut.u_soc.ifu32_rresp;

  assign obs_vif.lsu32_awvalid   = u_dut.u_soc.lsu32_awvalid;
  assign obs_vif.lsu32_awready   = u_dut.u_soc.lsu32_awready;
  assign obs_vif.lsu32_awaddr    = u_dut.u_soc.lsu32_awaddr;
  assign obs_vif.lsu32_wvalid    = u_dut.u_soc.lsu32_wvalid;
  assign obs_vif.lsu32_wready    = u_dut.u_soc.lsu32_wready;
  assign obs_vif.lsu32_wdata     = u_dut.u_soc.lsu32_wdata;
  assign obs_vif.lsu32_wstrb     = u_dut.u_soc.lsu32_wstrb;
  assign obs_vif.lsu32_wlast     = u_dut.u_soc.lsu32_wlast;
  assign obs_vif.lsu32_bvalid    = u_dut.u_soc.lsu32_bvalid;
  assign obs_vif.lsu32_bready    = u_dut.u_soc.lsu32_bready;
  assign obs_vif.lsu32_bresp     = u_dut.u_soc.lsu32_bresp;
  assign obs_vif.lsu32_arvalid   = u_dut.u_soc.lsu32_arvalid;
  assign obs_vif.lsu32_arready   = u_dut.u_soc.lsu32_arready;
  assign obs_vif.lsu32_araddr    = u_dut.u_soc.lsu32_araddr;
  assign obs_vif.lsu32_rvalid    = u_dut.u_soc.lsu32_rvalid;
  assign obs_vif.lsu32_rready    = u_dut.u_soc.lsu32_rready;
  assign obs_vif.lsu32_rdata     = u_dut.u_soc.lsu32_rdata;
  assign obs_vif.lsu32_rresp     = u_dut.u_soc.lsu32_rresp;
  assign obs_vif.lsu32_rlast     = u_dut.u_soc.lsu32_rlast;

  assign obs_vif.dma_awvalid     = u_dut.u_soc.dma_awvalid;
  assign obs_vif.dma_awready     = u_dut.u_soc.dma_awready;
  assign obs_vif.dma_awaddr      = u_dut.u_soc.dma_awaddr;
  assign obs_vif.dma_wvalid      = u_dut.u_soc.dma_wvalid;
  assign obs_vif.dma_wready      = u_dut.u_soc.dma_wready;
  assign obs_vif.dma_wdata       = u_dut.u_soc.dma_wdata;
  assign obs_vif.dma_wstrb       = u_dut.u_soc.dma_wstrb;
  assign obs_vif.dma_wlast       = u_dut.u_soc.dma_wlast;
  assign obs_vif.dma_bvalid      = u_dut.u_soc.dma_bvalid;
  assign obs_vif.dma_bready      = u_dut.u_soc.dma_bready;
  assign obs_vif.dma_bresp       = u_dut.u_soc.dma_bresp;
  assign obs_vif.dma_arvalid     = u_dut.u_soc.dma_arvalid;
  assign obs_vif.dma_arready     = u_dut.u_soc.dma_arready;
  assign obs_vif.dma_araddr      = u_dut.u_soc.dma_araddr;
  assign obs_vif.dma_rvalid      = u_dut.u_soc.dma_rvalid;
  assign obs_vif.dma_rready      = u_dut.u_soc.dma_rready;
  assign obs_vif.dma_rdata       = u_dut.u_soc.dma_rdata;
  assign obs_vif.dma_rresp       = u_dut.u_soc.dma_rresp;
  assign obs_vif.dma_rlast       = u_dut.u_soc.dma_rlast;

  assign obs_vif.m01_awvalid     = u_dut.u_soc.m01_awvalid;
  assign obs_vif.m01_awready     = u_dut.u_soc.m01_awready;
  assign obs_vif.m01_awaddr      = u_dut.u_soc.m01_awaddr;
  assign obs_vif.m01_wvalid      = u_dut.u_soc.m01_wvalid;
  assign obs_vif.m01_wready      = u_dut.u_soc.m01_wready;
  assign obs_vif.m01_wdata       = u_dut.u_soc.m01_wdata;
  assign obs_vif.m01_wstrb       = u_dut.u_soc.m01_wstrb;
  assign obs_vif.m01_wlast       = u_dut.u_soc.m01_wlast;
  assign obs_vif.m01_bvalid      = u_dut.u_soc.m01_bvalid;
  assign obs_vif.m01_bready      = u_dut.u_soc.m01_bready;
  assign obs_vif.m01_bresp       = u_dut.u_soc.m01_bresp;
  assign obs_vif.m01_arvalid     = u_dut.u_soc.m01_arvalid;
  assign obs_vif.m01_arready     = u_dut.u_soc.m01_arready;
  assign obs_vif.m01_araddr      = u_dut.u_soc.m01_araddr;

  assign obs_vif.uart_tx         = uart_vif.uart_tx;
  assign obs_vif.uart_rx         = uart_vif.uart_rx;
  assign obs_vif.gpio_i          = gpio_vif.gpio_i;
  assign obs_vif.gpio_o          = gpio_vif.gpio_o;
  assign obs_vif.gpio_oe         = gpio_vif.gpio_oe;
  assign obs_vif.timer_irq       = irq_vif.timer_irq;
  assign obs_vif.gpio_irq        = irq_vif.gpio_irq;
  assign obs_vif.rle_irq         = irq_vif.rle_irq;
  assign obs_vif.dma_irq         = irq_vif.dma_irq;
  assign obs_vif.trace_valid     = trace_rv_i_valid_ip;
  assign obs_vif.trace_exception = trace_rv_i_exception_ip;
  assign obs_vif.trace_ecause    = trace_rv_i_ecause_ip;

  // ---------------------------------------------------------------------------
  // Passive Bound Protocol Assertions
  // ---------------------------------------------------------------------------
  soc_protocol_assertions #(.NAME("SOC_TOP_ASSERT")) u_soc_asrt (
    .clk       (clk),
    .rst_n     (reset_vif.rst_n),
    .uart_tx   (uart_vif.uart_tx),
    .gpio_o    (gpio_vif.gpio_o),
    .gpio_oe   (gpio_vif.gpio_oe),
    .timer_irq (irq_vif.timer_irq),
    .gpio_irq  (irq_vif.gpio_irq),
    .rle_irq   (irq_vif.rle_irq),
    .dma_irq   (irq_vif.dma_irq)
  );

  axi4_full_protocol_assertions #(
    .NAME("SOC_LSU32_AXI4"), .DATA_WIDTH(32), .ID_WIDTH(8), .CHECK_ID(1), .CHECK_RST_MST(0)
  ) u_lsu32_asrt (
    .clk(clk), .rst_n(reset_vif.rst_n),
    .awvalid(u_dut.u_soc.lsu32_awvalid), .awready(u_dut.u_soc.lsu32_awready), .awid(u_dut.u_soc.lsu32_awid),
    .awaddr(u_dut.u_soc.lsu32_awaddr),   .awlen(u_dut.u_soc.lsu32_awlen),     .awsize(u_dut.u_soc.lsu32_awsize),
    .awburst(u_dut.u_soc.lsu32_awburst), .awprot(u_dut.u_soc.lsu32_awprot),
    .wvalid(u_dut.u_soc.lsu32_wvalid),   .wready(u_dut.u_soc.lsu32_wready),
    .wdata(u_dut.u_soc.lsu32_wdata),     .wstrb(u_dut.u_soc.lsu32_wstrb),     .wlast(u_dut.u_soc.lsu32_wlast),
    .bvalid(u_dut.u_soc.lsu32_bvalid),   .bready(u_dut.u_soc.lsu32_bready),
    .bid(u_dut.u_soc.lsu32_bid),         .bresp(u_dut.u_soc.lsu32_bresp),
    .arvalid(u_dut.u_soc.lsu32_arvalid), .arready(u_dut.u_soc.lsu32_arready), .arid(u_dut.u_soc.lsu32_arid),
    .araddr(u_dut.u_soc.lsu32_araddr),   .arlen(u_dut.u_soc.lsu32_arlen),     .arsize(u_dut.u_soc.lsu32_arsize),
    .arburst(u_dut.u_soc.lsu32_arburst), .arprot(u_dut.u_soc.lsu32_arprot),
    .rvalid(u_dut.u_soc.lsu32_rvalid),   .rready(u_dut.u_soc.lsu32_rready),
    .rid(u_dut.u_soc.lsu32_rid),         .rdata(u_dut.u_soc.lsu32_rdata),
    .rresp(u_dut.u_soc.lsu32_rresp),     .rlast(u_dut.u_soc.lsu32_rlast)
  );

  axi4_full_protocol_assertions #(
    .NAME("SOC_M01_DMEM_AXI4"), .DATA_WIDTH(32), .ID_WIDTH(8), .CHECK_ID(1), .CHECK_RST_MST(0)
  ) u_m01_asrt (
    .clk(clk), .rst_n(reset_vif.rst_n),
    .awvalid(u_dut.u_soc.m01_awvalid), .awready(u_dut.u_soc.m01_awready), .awid(u_dut.u_soc.m01_awid),
    .awaddr(u_dut.u_soc.m01_awaddr),   .awlen(u_dut.u_soc.m01_awlen),     .awsize(u_dut.u_soc.m01_awsize),
    .awburst(u_dut.u_soc.m01_awburst), .awprot(u_dut.u_soc.m01_awprot),
    .wvalid(u_dut.u_soc.m01_wvalid),   .wready(u_dut.u_soc.m01_wready),
    .wdata(u_dut.u_soc.m01_wdata),     .wstrb(u_dut.u_soc.m01_wstrb),     .wlast(u_dut.u_soc.m01_wlast),
    .bvalid(u_dut.u_soc.m01_bvalid),   .bready(u_dut.u_soc.m01_bready),
    .bid(u_dut.u_soc.m01_bid),         .bresp(u_dut.u_soc.m01_bresp),
    .arvalid(u_dut.u_soc.m01_arvalid), .arready(u_dut.u_soc.m01_arready), .arid(u_dut.u_soc.m01_arid),
    .araddr(u_dut.u_soc.m01_araddr),   .arlen(u_dut.u_soc.m01_arlen),     .arsize(u_dut.u_soc.m01_arsize),
    .arburst(u_dut.u_soc.m01_arburst), .arprot(u_dut.u_soc.m01_arprot),
    .rvalid(u_dut.u_soc.m01_rvalid),   .rready(u_dut.u_soc.m01_rready),
    .rid(u_dut.u_soc.m01_rid),         .rdata(u_dut.u_soc.m01_rdata),
    .rresp(u_dut.u_soc.m01_rresp),     .rlast(u_dut.u_soc.m01_rlast)
  );

  dma_protocol_assertions #(.NAME("SOC_DMA_MASTER")) u_dma_proto_asrt (
    .clk(clk), .rst_n(reset_vif.rst_n),
    .m_axi_awvalid(u_dut.u_soc.dma_awvalid), .m_axi_awready(u_dut.u_soc.dma_awready),
    .m_axi_awaddr(u_dut.u_soc.dma_awaddr),   .m_axi_awlen(u_dut.u_soc.dma_awlen),
    .m_axi_awsize(u_dut.u_soc.dma_awsize),   .m_axi_awburst(u_dut.u_soc.dma_awburst),
    .m_axi_wvalid(u_dut.u_soc.dma_wvalid),   .m_axi_wready(u_dut.u_soc.dma_wready),
    .m_axi_wdata(u_dut.u_soc.dma_wdata),     .m_axi_wstrb(u_dut.u_soc.dma_wstrb),
    .m_axi_wlast(u_dut.u_soc.dma_wlast),
    .m_axi_bvalid(u_dut.u_soc.dma_bvalid),   .m_axi_bready(u_dut.u_soc.dma_bready),
    .m_axi_bresp(u_dut.u_soc.dma_bresp),
    .m_axi_arvalid(u_dut.u_soc.dma_arvalid), .m_axi_arready(u_dut.u_soc.dma_arready),
    .m_axi_araddr(u_dut.u_soc.dma_araddr),   .m_axi_arlen(u_dut.u_soc.dma_arlen),
    .m_axi_arsize(u_dut.u_soc.dma_arsize),   .m_axi_arburst(u_dut.u_soc.dma_arburst),
    .m_axi_rvalid(u_dut.u_soc.dma_rvalid),   .m_axi_rready(u_dut.u_soc.dma_rready),
    .m_axi_rdata(u_dut.u_soc.dma_rdata),     .m_axi_rresp(u_dut.u_soc.dma_rresp),
    .m_axi_rlast(u_dut.u_soc.dma_rlast),     .irq_o(irq_vif.dma_irq)
  );

  rle_protocol_assertions #(.NAME("SOC_RLE_SLAVE"), .MAX_BUFFER_DEPTH(256)) u_rle_proto_asrt (
    .clk(clk), .rst(reset_vif.rst),
    .s_axi_awvalid(u_dut.u_soc.m05_awvalid), .s_axi_awready(u_dut.u_soc.m05_awready), .s_axi_awaddr(u_dut.u_soc.m05_awaddr),
    .s_axi_wvalid(u_dut.u_soc.m05_wvalid),   .s_axi_wready(u_dut.u_soc.m05_wready),   .s_axi_wdata(u_dut.u_soc.m05_wdata),
    .s_axi_wstrb(u_dut.u_soc.m05_wstrb),     .s_axi_bvalid(u_dut.u_soc.m05_bvalid),   .s_axi_bready(u_dut.u_soc.m05_bready),
    .s_axi_bresp(u_dut.u_soc.m05_bresp),     .s_axi_arvalid(u_dut.u_soc.m05_arvalid), .s_axi_arready(u_dut.u_soc.m05_arready),
    .s_axi_araddr(u_dut.u_soc.m05_araddr),   .s_axi_rvalid(u_dut.u_soc.m05_rvalid),   .s_axi_rready(u_dut.u_soc.m05_rready),
    .s_axi_rdata(u_dut.u_soc.m05_rdata),     .s_axi_rresp(u_dut.u_soc.m05_rresp),     .irq(irq_vif.rle_irq)
  );

  axi_protocol_assertions #(.NAME("SOC_CRC_AXI4LITE")) u_crc_axi_asrt (
    .clk(clk), .rst_n(reset_vif.rst_n),
    .awvalid(u_dut.u_soc.m07_awvalid), .awready(u_dut.u_soc.m07_awready), .awaddr(u_dut.u_soc.m07_awaddr), .awprot(u_dut.u_soc.m07_awprot),
    .wvalid(u_dut.u_soc.m07_wvalid),   .wready(u_dut.u_soc.m07_wready),   .wdata(u_dut.u_soc.m07_wdata),   .wstrb(u_dut.u_soc.m07_wstrb),
    .bvalid(u_dut.u_soc.m07_bvalid),   .bready(u_dut.u_soc.m07_bready),   .bresp(u_dut.u_soc.m07_bresp),
    .arvalid(u_dut.u_soc.m07_arvalid), .arready(u_dut.u_soc.m07_arready), .araddr(u_dut.u_soc.m07_araddr), .arprot(u_dut.u_soc.m07_arprot),
    .rvalid(u_dut.u_soc.m07_rvalid),   .rready(u_dut.u_soc.m07_rready),   .rdata(u_dut.u_soc.m07_rdata),   .rresp(u_dut.u_soc.m07_rresp)
  );

  // ---------------------------------------------------------------------------
  // Firmware Initialization (Honors +FIRMWARE= or auto-selects per +UVM_TESTNAME)
  // ---------------------------------------------------------------------------
  task automatic load_hex_into_imem(input string rel_path);
    int fd;
    string candidates[4];
    candidates[0] = rel_path;
    candidates[1] = {"../", rel_path};
    candidates[2] = {"../../", rel_path};
    candidates[3] = {"../../../", rel_path};
    for (int k = 0; k < 4; k++) begin
      fd = $fopen(candidates[k], "r");
      if (fd != 0) begin
        $fclose(fd);
        $readmemh(candidates[k], u_dut.u_soc.u_imem.mem);
        `uvm_info("TB_SOC_TOP", $sformatf("Loaded firmware hex from %s into IMEM", candidates[k]), UVM_LOW)
        return;
      end
    end
    `uvm_fatal("TB_SOC_TOP", $sformatf("Failed to locate firmware hex file: %s", rel_path))
  endtask : load_hex_into_imem

  string fw_file;
  string test_name;
  initial begin
    // Pre-initialize IMEM with NOP instructions (0x00000013) to prevent X fetches
    for (int i = 0; i < 16384; i++) begin
      u_dut.u_soc.u_imem.mem[i] = 32'h00000013;
    end
    for (int i = 0; i < 32768; i++) begin
      u_dut.u_soc.u_dmem.mem[i] = 32'h00000000;
    end

    if ($value$plusargs("FIRMWARE=%s", fw_file)) begin
      $readmemh(fw_file, u_dut.u_soc.u_imem.mem);
      `uvm_info("TB_SOC_TOP", $sformatf("Loaded firmware hex from +FIRMWARE=%s into IMEM", fw_file), UVM_LOW)
    end else begin
      if (!$value$plusargs("UVM_TESTNAME=%s", test_name)) test_name = "soc_smoke_test";
      if (test_name == "uart_echo_test") begin
        load_hex_into_imem("firmware/images/uart_echo.hex");
      end else if (test_name == "soc_e2e_flow_test" || test_name == "soc_reset_recovery_test") begin
        load_hex_into_imem("firmware/images/soc_e2e_uvm.hex");
      end else if (test_name == "soc_decerr_trap_test") begin
        load_hex_into_imem("firmware/images/soc_decerr_test.hex");
      end else begin
        load_hex_into_imem("firmware/images/uart_test_word.hex");
      end
    end
  end

  // Monitor core exceptions directly from DUT trace output ports
  always @(posedge clk) begin
    if (reset_vif.rst_n) begin
      if (trace_rv_i_valid_ip && trace_rv_i_exception_ip) begin
        if (obs_vif.allow_expected_cpu_fault &&
            ((trace_rv_i_ecause_ip === obs_vif.expected_cpu_ecause) ||
             (trace_rv_i_address_ip == 32'h1111_0000 && trace_rv_i_ecause_ip == 5'd1))) begin
          obs_vif.expected_cpu_faults_seen++;
          `uvm_info("EXPECTED_FAULT",
                    $sformatf("[%0t ps] Controlled VeeR EL2 Load/Bus Fault Trap Observed (PC=0x%08h ecause=%0d)",
                              $time, trace_rv_i_address_ip, trace_rv_i_ecause_ip),
                    UVM_LOW)
        end else begin
          `uvm_error("CORE_EXCEPTION",
                     $sformatf("[%0t ps] VeeR EL2 Core Exception: PC=0x%08h ecause=%0d",
                               $time, trace_rv_i_address_ip, trace_rv_i_ecause_ip))
        end
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Optional VCD waveform dump
  // ---------------------------------------------------------------------------
  string wave_file;
  initial begin
    if ($test$plusargs("DUMP_WAVE") || $test$plusargs("DUMP_VCD")) begin
      if (!$value$plusargs("VCD_FILE=%s", wave_file)) begin
        int fd;
        fd = $fopen("simulation/waveforms/soc_uvm.vcd", "w");
        if (fd != 0) begin
          $fclose(fd);
          wave_file = "simulation/waveforms/soc_uvm.vcd";
        end else begin
          wave_file = "soc_uvm.vcd";
        end
      end
      $display("[SOC_CONNECT] Waveform dumping enabled -> %s", wave_file);
      $dumpfile(wave_file);
      $dumpvars(0, tb_soc_top);
    end
  end

  // ---------------------------------------------------------------------------
  // UVM Virtual Interface Registration & Test Kickoff
  // ---------------------------------------------------------------------------
  initial begin
    uvm_config_db#(virtual reset_if)::set(null, "*", "vif", reset_vif);
    uvm_config_db#(virtual uart_if)::set(null, "*", "vif", uart_vif);
    uvm_config_db#(virtual gpio_if)::set(null, "*", "vif", gpio_vif);
    uvm_config_db#(virtual irq_if)::set(null, "*", "vif", irq_vif);
    uvm_config_db#(virtual soc_obs_if)::set(null, "*", "obs_vif", obs_vif);
    run_test();
  end

  final begin
    automatic int e_soc = u_soc_asrt.get_total_assertion_errors();
    automatic int e_lsu = u_lsu32_asrt.get_total_assertion_errors();
    automatic int e_m01 = u_m01_asrt.get_total_assertion_errors();
    automatic int e_dma = u_dma_proto_asrt.get_total_assertion_errors();
    automatic int e_rle = u_rle_proto_asrt.get_total_assertion_errors();
    automatic int e_crc = u_crc_axi_asrt.get_total_assertion_errors();
    automatic int tot   = e_soc + e_lsu + e_m01 + e_dma + e_rle + e_crc;
    $display("-----------------------------------------------------------------");
    $display("[SOC ASSERTION SUMMARY] SOC=%0d LSU32=%0d M01=%0d DMA=%0d RLE=%0d CRC=%0d (TOTAL=%0d)",
             e_soc, e_lsu, e_m01, e_dma, e_rle, e_crc, tot);
    if (tot == 0)
      $display("[SOC ASSERTION STATUS] ALL SOC PROTOCOL ASSERTIONS PASSED CLEANLY (0 Errors)");
    else
      $error("[SOC ASSERTION STATUS] FAIL: %0d assertion errors detected!", tot);
    $display("-----------------------------------------------------------------");
  end

endmodule : tb_soc_top
