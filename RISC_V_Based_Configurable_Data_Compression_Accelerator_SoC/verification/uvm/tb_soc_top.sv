// =============================================================================
// tb_soc_top.sv — Top-Level Testbench for VeeR EL2 SoC UVM Verification
// Instantiates SoC DUT, connects physical VIP interfaces (Reset, UART, GPIO, IRQ),
// loads firmware into instruction memory, registers virtual interfaces in
// uvm_config_db, and kicks off UVM test execution.
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
  // Physical VIP Interface Instantiations
  // ---------------------------------------------------------------------------
  // Reset interface generates synchronous rst_n and active-high rst
  reset_if reset_vif (.clk(clk));

  // Peripheral interfaces driven with synchronous reset from reset_vif
  uart_if  uart_vif  (.clk(clk), .rst_n(reset_vif.rst_n));
  gpio_if  gpio_vif  (.clk(clk), .rst_n(reset_vif.rst_n));
  irq_if   irq_vif   (.clk(clk), .rst_n(reset_vif.rst_n));

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
    .IMEM_DEPTH(65536),
    .DMEM_DEPTH(65536)
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
  // Firmware Initialization
  // Note: Firmware start.S programmatically configures CSR 0x7C0 (MRAC = 0x5555555A)
  // on boot, establishing Region 1 as side-effect MMIO.
  // ---------------------------------------------------------------------------
  string fw_file;
  initial begin
    int i;
    // Pre-initialize IMEM with NOP instructions (0x00000013) to prevent uninitialized X fetches
    for (i = 0; i < 65536; i = i + 1) begin
      u_dut.u_soc.u_imem.mem[i] = 32'h00000013;
      u_dut.u_soc.u_dmem.mem[i] = 32'h00000000;
    end
    // Preload compiled C firmware instructions into IMEM
    if ($value$plusargs("FIRMWARE=%s", fw_file)) begin
      $readmemh(fw_file, u_dut.u_soc.u_imem.mem);
      `uvm_info("TB_SOC_TOP", $sformatf("Loaded firmware hex from +FIRMWARE=%s into IMEM", fw_file), UVM_LOW)
    end else begin
      int fd;
      fd = $fopen("firmware/images/uart_test_word.hex", "r");
      if (fd != 0) begin
        $fclose(fd);
        $readmemh("firmware/images/uart_test_word.hex", u_dut.u_soc.u_imem.mem);
        `uvm_info("TB_SOC_TOP", "Loaded firmware hex from firmware/images/uart_test_word.hex into IMEM", UVM_LOW)
      end else begin
        fd = $fopen("../firmware/images/uart_test_word.hex", "r");
        if (fd != 0) begin
          $fclose(fd);
          $readmemh("../firmware/images/uart_test_word.hex", u_dut.u_soc.u_imem.mem);
          `uvm_info("TB_SOC_TOP", "Loaded firmware hex from ../firmware/images/uart_test_word.hex into IMEM", UVM_LOW)
        end else begin
          $readmemh("../../firmware/images/uart_test_word.hex", u_dut.u_soc.u_imem.mem);
          `uvm_info("TB_SOC_TOP", "Loaded firmware hex from ../../firmware/images/uart_test_word.hex into IMEM", UVM_LOW)
        end
      end
    end
  end

  // Monitor core exceptions directly from DUT trace output ports
  always @(posedge clk) begin
    if (reset_vif.rst_n) begin
      if (trace_rv_i_valid_ip && trace_rv_i_exception_ip) begin
        `uvm_error("CORE_EXCEPTION",
                   $sformatf("[%0t ps] VeeR EL2 Core Exception: PC=0x%08h ecause=%0d",
                             $time, trace_rv_i_address_ip, trace_rv_i_ecause_ip))
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Physical DUT Signal Connectivity Reporting & Verification
  // ---------------------------------------------------------------------------
  initial begin
    `uvm_info("SOC_CONNECT", "==========================================================", UVM_LOW)
    `uvm_info("SOC_CONNECT", "      ESTABLISHING SOC TOP-LEVEL VIP CONNECTIONS          ", UVM_LOW)
    `uvm_info("SOC_CONNECT", "==========================================================", UVM_LOW)
    `uvm_info("SOC_CONNECT", "Reset VIP Interface -> DUT Connections:", UVM_LOW)
    `uvm_info("SOC_CONNECT", "  reset_vif.clk   <--> DUT clk (100 MHz Master System Clock)", UVM_LOW)
    `uvm_info("SOC_CONNECT", "  reset_vif.rst_n <--> DUT rst_n (Active-low System Reset)", UVM_LOW)
    `uvm_info("SOC_CONNECT", "UART VIP Interface -> DUT Connections:", UVM_LOW)
    `uvm_info("SOC_CONNECT", "  uart_vif.clk     <--> DUT clk", UVM_LOW)
    `uvm_info("SOC_CONNECT", "  uart_vif.rst_n   <--> reset_vif.rst_n", UVM_LOW)
    `uvm_info("SOC_CONNECT", "  uart_vif.uart_rx <--> DUT uart_rx (Driven into SoC)", UVM_LOW)
    `uvm_info("SOC_CONNECT", "  uart_vif.uart_tx <--> DUT uart_tx (Driven by SoC UART transmitter)", UVM_LOW)
    `uvm_info("SOC_CONNECT", "GPIO VIP Interface -> DUT Connections:", UVM_LOW)
    `uvm_info("SOC_CONNECT", "  gpio_vif.clk     <--> DUT clk", UVM_LOW)
    `uvm_info("SOC_CONNECT", "  gpio_vif.rst_n   <--> reset_vif.rst_n", UVM_LOW)
    `uvm_info("SOC_CONNECT", "  gpio_vif.gpio_i  <--> DUT gpio_i[31:0] (External input vector to SoC)", UVM_LOW)
    `uvm_info("SOC_CONNECT", "  gpio_vif.gpio_o  <--> DUT gpio_o[31:0] (32-bit output vector from SoC)", UVM_LOW)
    `uvm_info("SOC_CONNECT", "  gpio_vif.gpio_oe <--> DUT gpio_oe[31:0] (32-bit output enables from SoC)", UVM_LOW)
    `uvm_info("SOC_CONNECT", "IRQ VIP Interface -> DUT Connections:", UVM_LOW)
    `uvm_info("SOC_CONNECT", "  irq_vif.clk       <--> DUT clk", UVM_LOW)
    `uvm_info("SOC_CONNECT", "  irq_vif.rst_n     <--> reset_vif.rst_n", UVM_LOW)
    `uvm_info("SOC_CONNECT", "  irq_vif.gpio_irq  <--> DUT gpio_irq (GPIO combined interrupt)", UVM_LOW)
    `uvm_info("SOC_CONNECT", "  irq_vif.timer_irq <--> DUT timer_irq (Timer peripheral interrupt)", UVM_LOW)
    `uvm_info("SOC_CONNECT", "  irq_vif.rle_irq   <--> DUT rle_irq (RLE accelerator interrupt)", UVM_LOW)
    `uvm_info("SOC_CONNECT", "  irq_vif.dma_irq   <--> DUT dma_irq (DMA controller interrupt)", UVM_LOW)
    `uvm_info("SOC_CONNECT", "==========================================================", UVM_LOW)
  end

  // Optional VCD waveform dump
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
      $display("[SOC_CONNECT] Waveform dumping enabled via plusarg (+DUMP_WAVE / +DUMP_VCD) -> %s", wave_file);
      $dumpfile(wave_file);
      $dumpvars(0, tb_soc_top);
    end
  end

  // ---------------------------------------------------------------------------
  // UVM Virtual Interface Registration & Test Kickoff
  // ---------------------------------------------------------------------------
  initial begin
    // Register the four physical interfaces into uvm_config_db
    uvm_config_db#(virtual reset_if)::set(null, "*", "vif", reset_vif);
    `uvm_info("SOC_CONNECT", "[SOC_CONNECT] Top: Registered virtual interface 'vif' into uvm_config_db for reset_vif", UVM_LOW)

    uvm_config_db#(virtual uart_if)::set(null, "*", "vif", uart_vif);
    `uvm_info("SOC_CONNECT", "[SOC_CONNECT] Top: Registered virtual interface 'vif' into uvm_config_db for uart_vif", UVM_LOW)

    uvm_config_db#(virtual gpio_if)::set(null, "*", "vif", gpio_vif);
    `uvm_info("SOC_CONNECT", "[SOC_CONNECT] Top: Registered virtual interface 'vif' into uvm_config_db for gpio_vif", UVM_LOW)

    uvm_config_db#(virtual irq_if)::set(null, "*", "vif", irq_vif);
    `uvm_info("SOC_CONNECT", "[SOC_CONNECT] Top: Registered virtual interface 'vif' into uvm_config_db for irq_vif", UVM_LOW)

    run_test();
  end

endmodule : tb_soc_top
