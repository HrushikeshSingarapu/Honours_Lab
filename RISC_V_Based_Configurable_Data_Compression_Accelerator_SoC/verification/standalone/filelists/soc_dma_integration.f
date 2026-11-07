// =============================================================================
// soc_dma_integration.f — VCS Filelist for SoC DMA Integration Verification
// Project Root: RISC_V_Based_Configurable_Data_Compression_Accelerator_SoC/
// =============================================================================

// Include Directories
+incdir+rtl/soc
+incdir+rtl/interconnect
+incdir+rtl/peripherals/uart
+incdir+rtl/peripherals/rle
+incdir+rtl/peripherals/timer
+incdir+rtl/peripherals/gpio
+incdir+rtl/peripherals/crc
+incdir+rtl/accelerators/rle
+incdir+rtl/accelerators/dma
+incdir+verification/standalone/soc

// Peripheral IP RTLs
rtl/peripherals/uart/axi_uart_top.v
rtl/peripherals/uart/axi_internal_fifo.v
rtl/peripherals/uart/uart_controller.v
rtl/peripherals/uart/uart_parity_bit_compute.v
rtl/peripherals/uart/uart_receiver.v
rtl/peripherals/uart/uart_transmitter.v
rtl/peripherals/timer/timer_top.v
rtl/peripherals/gpio/gpio_top.v
rtl/peripherals/crc/crc32_top.v
rtl/accelerators/rle/rle_top.v
rtl/accelerators/rle/rle_controller.v
rtl/accelerators/rle/rle_decoder.v
rtl/accelerators/rle/rle_encoder.v
rtl/accelerators/rle/rle_reg_block.v

// DMA Controller IP RTLs
rtl/accelerators/dma/dma_reg_file.v
rtl/accelerators/dma/dma_master_engine.v
rtl/accelerators/dma/dma_sequencer.v
rtl/accelerators/dma/dma_top.v

// SoC Interconnect & Top RTLs
rtl/interconnect/priority_encoder.v
rtl/interconnect/arbiter.v
rtl/interconnect/axi_interconnect.v
rtl/interconnect/axi_interconnect_wrap_4x8.v
rtl/interconnect/axi64_to_32_bridge.v
rtl/soc/soc_top.v

// Testbench
verification/standalone/soc/tb_soc_dma_integration.sv
