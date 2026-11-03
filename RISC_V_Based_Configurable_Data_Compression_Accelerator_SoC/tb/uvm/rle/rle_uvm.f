// =============================================================================
// rle_uvm.f — Filelist for RLE UVM 1.2 Verification Environment
// =============================================================================
+incdir+C:/intelFPGA/20.1/modelsim_ase/verilog_src/uvm-1.2/src
+incdir+../../Reliable_Data_Transport_System/rtl/ip/rle
+incdir+./uvm/rle
+incdir+./assertions

// RTL Sources
../../Reliable_Data_Transport_System/rtl/ip/rle/rle_controller.v
../../Reliable_Data_Transport_System/rtl/ip/rle/rle_encoder.v
../../Reliable_Data_Transport_System/rtl/ip/rle/rle_decoder.v
../../Reliable_Data_Transport_System/rtl/ip/rle/rle_reg_block.v
../../Reliable_Data_Transport_System/rtl/ip/rle/rle_top.v

// Protocol Assertions
./assertions/axi_protocol_assertions.sv
./assertions/rle_protocol_assertions.sv

// UVM TB Sources
./uvm/rle/rle_axi_if.sv
./uvm/rle/rle_uvm_pkg.sv
./uvm/rle/tb_rle_uvm.sv
