// =============================================================================
// dma_uvm.f — Filelist for DMA UVM 1.2 Verification Environment
// Run from: <repo_root>/tb/
// =============================================================================
// Include Directories (UVM source incdir passed by runner CLI)
+incdir+../rtl/accelerators/dma
+incdir+../rtl/accelerators/rle
+incdir+./uvm/dma
+incdir+../verification/assertions

// RLE Accelerator Sources (Target IP for DMA)
../rtl/accelerators/rle/rle_controller.v
../rtl/accelerators/rle/rle_encoder.v
../rtl/accelerators/rle/rle_decoder.v
../rtl/accelerators/rle/rle_reg_block.v
../rtl/accelerators/rle/rle_top.v

// DMA IP RTL Sources
../rtl/accelerators/dma/dma_master_engine.v
../rtl/accelerators/dma/dma_reg_file.v
../rtl/accelerators/dma/dma_sequencer.v
../rtl/accelerators/dma/dma_top.v

// Protocol Assertions
../verification/assertions/axi_protocol_assertions.sv
../verification/assertions/dma_protocol_assertions.sv
../verification/assertions/rle_protocol_assertions.sv

// DMA UVM TB Sources
./uvm/dma/dma_axi_if.sv
./uvm/dma/dma_uvm_pkg.sv
./uvm/dma/tb_dma_uvm.sv
