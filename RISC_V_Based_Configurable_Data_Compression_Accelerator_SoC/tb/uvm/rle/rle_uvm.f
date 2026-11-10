// =============================================================================
// rle_uvm.f — Filelist for RLE UVM 1.2 Verification Environment
// Run from: <repo_root>/tb/
// =============================================================================
// Include Directories (UVM source incdir passed by runner CLI)
+incdir+../rtl/accelerators/rle
+incdir+./uvm/rle
+incdir+../verification/assertions

// RTL Sources
../rtl/accelerators/rle/rle_controller.v
../rtl/accelerators/rle/rle_encoder.v
../rtl/accelerators/rle/rle_decoder.v
../rtl/accelerators/rle/rle_reg_block.v
../rtl/accelerators/rle/rle_top.v

// Protocol Assertions
../verification/assertions/axi_protocol_assertions.sv
../verification/assertions/rle_protocol_assertions.sv

// UVM TB Sources
./uvm/rle/rle_axi_if.sv
./uvm/rle/rle_uvm_pkg.sv
./uvm/rle/tb_rle_uvm.sv
