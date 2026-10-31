// =============================================================================
// soc_dma_integration.f — VCS Filelist for SoC DMA Integration Verification
// =============================================================================

// Include Directories
+incdir+../rtl
+incdir+../../Reliable_Data_Transport_System/rtl/ip/uart
+incdir+../../Reliable_Data_Transport_System/rtl/ip/rle
+incdir+../../Reliable_Data_Transport_System/rtl/ip/timer
+incdir+../../Reliable_Data_Transport_System/rtl/ip/gpio
+incdir+../../Reliable_Data_Transport_System/rtl/ip/crc

// Peripheral IP RTLs
../../Reliable_Data_Transport_System/rtl/ip/uart/axi_uart_top.v
../../Reliable_Data_Transport_System/rtl/ip/uart/axi_internal_fifo.v
../../Reliable_Data_Transport_System/rtl/ip/uart/uart_controller.v
../../Reliable_Data_Transport_System/rtl/ip/uart/uart_parity_bit_compute.v
../../Reliable_Data_Transport_System/rtl/ip/uart/uart_receiver.v
../../Reliable_Data_Transport_System/rtl/ip/uart/uart_transmitter.v
../../Reliable_Data_Transport_System/rtl/ip/timer/timer_top.v
../../Reliable_Data_Transport_System/rtl/ip/gpio/gpio_top.v
../../Reliable_Data_Transport_System/rtl/ip/crc/crc32_top.v
../../Reliable_Data_Transport_System/rtl/ip/rle/rle_top.v
../../Reliable_Data_Transport_System/rtl/ip/rle/rle_controller.v
../../Reliable_Data_Transport_System/rtl/ip/rle/rle_decoder.v
../../Reliable_Data_Transport_System/rtl/ip/rle/rle_encoder.v
../../Reliable_Data_Transport_System/rtl/ip/rle/rle_reg_block.v

// DMA Controller IP RTLs
../rtl/dma_reg_file.v
../rtl/dma_master_engine.v
../rtl/dma_sequencer.v
../rtl/dma_top.v

// SoC Interconnect & Top RTLs
../rtl/priority_encoder.v
../rtl/arbiter.v
../rtl/axi_interconnect.v
../rtl/axi_interconnect_wrap_4x8.v
../rtl/axi64_to_32_bridge.v
../rtl/soc_top.v

// Testbench
tb_soc_dma_integration.sv
