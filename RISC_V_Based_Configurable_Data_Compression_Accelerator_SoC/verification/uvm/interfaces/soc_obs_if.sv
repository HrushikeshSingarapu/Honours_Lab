// =============================================================================
// soc_obs_if.sv — Passive Read-Only SoC Bus & Telemetry Observation Interface
// Monitors internal SoC interconnect buses without altering the 4-agent UVM
// topology (UART, GPIO, Reset, IRQ remain the sole 4 agents).
// =============================================================================
`timescale 1ns/1ps

`ifndef SOC_OBS_IF_SV
`define SOC_OBS_IF_SV

interface soc_obs_if (
    input logic clk,
    input logic rst_n
);
    // IFU 32-bit post-bridge AXI Channel (M00 Instruction Fetches + Reset Alias)
    logic        ifu32_arvalid;
    logic        ifu32_arready;
    logic [31:0] ifu32_araddr;
    logic        ifu32_rvalid;
    logic        ifu32_rready;
    logic [ 1:0] ifu32_rresp;

    // LSU 32-bit post-bridge AXI Channel (CPU Data & MMIO Accesses)
    logic        lsu32_awvalid;
    logic        lsu32_awready;
    logic [31:0] lsu32_awaddr;
    logic        lsu32_wvalid;
    logic        lsu32_wready;
    logic [31:0] lsu32_wdata;
    logic [ 3:0] lsu32_wstrb;
    logic        lsu32_wlast;
    logic        lsu32_bvalid;
    logic        lsu32_bready;
    logic [ 1:0] lsu32_bresp;
    logic        lsu32_arvalid;
    logic        lsu32_arready;
    logic [31:0] lsu32_araddr;
    logic        lsu32_rvalid;
    logic        lsu32_rready;
    logic [31:0] lsu32_rdata;
    logic [ 1:0] lsu32_rresp;
    logic        lsu32_rlast;

    // DMA Master AXI Channel (S03)
    logic        dma_awvalid;
    logic        dma_awready;
    logic [31:0] dma_awaddr;
    logic        dma_wvalid;
    logic        dma_wready;
    logic [31:0] dma_wdata;
    logic [ 3:0] dma_wstrb;
    logic        dma_wlast;
    logic        dma_bvalid;
    logic        dma_bready;
    logic [ 1:0] dma_bresp;
    logic        dma_arvalid;
    logic        dma_arready;
    logic [31:0] dma_araddr;
    logic        dma_rvalid;
    logic        dma_rready;
    logic [31:0] dma_rdata;
    logic [ 1:0] dma_rresp;
    logic        dma_rlast;

    // DMEM Slave Channel (M01)
    logic        m01_awvalid;
    logic        m01_awready;
    logic [31:0] m01_awaddr;
    logic        m01_wvalid;
    logic        m01_wready;
    logic [31:0] m01_wdata;
    logic [ 3:0] m01_wstrb;
    logic        m01_wlast;
    logic        m01_bvalid;
    logic        m01_bready;
    logic [ 1:0] m01_bresp;
    logic        m01_arvalid;
    logic        m01_arready;
    logic [31:0] m01_araddr;

    // External Peripherals, IRQs & VeeR Trace
    logic        uart_tx;
    logic        uart_rx;
    logic [31:0] gpio_i;
    logic [31:0] gpio_o;
    logic [31:0] gpio_oe;
    logic        timer_irq;
    logic        gpio_irq;
    logic        rle_irq;
    logic        dma_irq;
    logic        trace_valid;
    logic        trace_exception;
    logic [ 4:0] trace_ecause;

    // Controlled fault exception allow flags (for intentional DECERR trap tests)
    bit          allow_expected_cpu_fault = 1'b0;
    bit [ 4:0]   expected_cpu_ecause      = 5'd5;
    int          expected_cpu_faults_seen = 0;

endinterface : soc_obs_if

`endif // SOC_OBS_IF_SV
