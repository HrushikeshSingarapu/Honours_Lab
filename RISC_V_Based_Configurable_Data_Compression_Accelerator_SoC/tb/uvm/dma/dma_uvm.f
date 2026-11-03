// =============================================================================
// dma_uvm.f — Filelist for DMA UVM 1.2 Verification Environment
// =============================================================================
+incdir+C:/intelFPGA/20.1/modelsim_ase/verilog_src/uvm-1.2/src
+incdir+../rtl
+incdir+../../Reliable_Data_Transport_System/rtl/ip/rle
+incdir+./uvm/dma

// RLE Accelerator Sources (Target IP for DMA)
../../Reliable_Data_Transport_System/rtl/ip/rle/rle_controller.v
../../Reliable_Data_Transport_System/rtl/ip/rle/rle_encoder.v
../../Reliable_Data_Transport_System/rtl/ip/rle/rle_decoder.v
../../Reliable_Data_Transport_System/rtl/ip/rle/rle_reg_block.v
../../Reliable_Data_Transport_System/rtl/ip/rle/rle_top.v

// DMA IP RTL Sources
../rtl/dma_master_engine.v
../rtl/dma_reg_file.v
../rtl/dma_sequencer.v
../rtl/dma_top.v

// DMA UVM TB Sources
./uvm/dma/dma_axi_if.sv
./uvm/dma/dma_uvm_pkg.sv
./uvm/dma/tb_dma_uvm.sv

