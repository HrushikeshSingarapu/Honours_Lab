// =============================================================================
// dma_firmware.f — Simulation Filelist for VeeR EL2 SoC DMA Firmware Test
// =============================================================================

// --- Compiler Defines ---
+define+RV_OPENSOURCE
+define+GTLSIM

// --- Include Directories ---
+incdir+../rtl
+incdir+../../Reliable_Data_Transport_System/rtl/ip/uart
+incdir+../../Reliable_Data_Transport_System/rtl/ip/rle
+incdir+../../Reliable_Data_Transport_System/rtl/ip/timer
+incdir+../../Reliable_Data_Transport_System/rtl/ip/gpio
+incdir+../../Reliable_Data_Transport_System/rtl/ip/crc
+incdir+../../Cores-VeeR-EL2/snapshots/soc_sim
+incdir+../../Cores-VeeR-EL2/design/include
+incdir+../../Cores-VeeR-EL2/design/lib
+incdir+../../Cores-VeeR-EL2/design/dmi

// --- VeeR Snapshot Global Defines ---
../../Cores-VeeR-EL2/snapshots/soc_sim/common_defines.vh

// --- VeeR Packages & Interfaces ---
../../Cores-VeeR-EL2/design/include/el2_def.sv
../../Cores-VeeR-EL2/design/lib/el2_assert.sv
../../Cores-VeeR-EL2/design/el2_mubi_pkg.sv
../../Cores-VeeR-EL2/design/el2_lockstep_pkg.sv
../../Cores-VeeR-EL2/design/lib/el2_mem_if.sv
../../Cores-VeeR-EL2/design/lib/el2_regfile_if.sv

// --- VeeR Core Infrastructure & DMI ---
../../Cores-VeeR-EL2/design/lib/el2_lib.sv
../../Cores-VeeR-EL2/design/lib/el2_prim_generic_buf.sv
../../Cores-VeeR-EL2/design/lib/el2_prim_buf.sv
../../Cores-VeeR-EL2/design/lib/ahb_to_axi4.sv
../../Cores-VeeR-EL2/design/lib/axi4_to_ahb.sv
../../Cores-VeeR-EL2/design/dmi/dmi_mux.v
../../Cores-VeeR-EL2/design/dmi/dmi_wrapper.v
../../Cores-VeeR-EL2/design/dmi/dmi_jtag_to_core_sync.v
../../Cores-VeeR-EL2/design/dmi/rvjtag_tap.v

// --- VeeR Subunits (IFU, DEC, EXU, LSU, DBG) ---
../../Cores-VeeR-EL2/design/ifu/el2_ifu_aln_ctl.sv
../../Cores-VeeR-EL2/design/ifu/el2_ifu_compress_ctl.sv
../../Cores-VeeR-EL2/design/ifu/el2_ifu_ifc_ctl.sv
../../Cores-VeeR-EL2/design/ifu/el2_ifu_bp_ctl.sv
../../Cores-VeeR-EL2/design/ifu/el2_ifu_ic_mem.sv
../../Cores-VeeR-EL2/design/ifu/el2_ifu_mem_ctl.sv
../../Cores-VeeR-EL2/design/ifu/el2_ifu_iccm_mem.sv
../../Cores-VeeR-EL2/design/ifu/el2_ifu.sv
../../Cores-VeeR-EL2/design/dec/el2_dec_decode_ctl.sv
../../Cores-VeeR-EL2/design/dec/el2_dec_gpr_ctl.sv
../../Cores-VeeR-EL2/design/dec/el2_dec_ib_ctl.sv
../../Cores-VeeR-EL2/design/dec/el2_dec_pmp_ctl.sv
../../Cores-VeeR-EL2/design/dec/el2_dec_tlu_ctl.sv
../../Cores-VeeR-EL2/design/dec/el2_dec_trigger.sv
../../Cores-VeeR-EL2/design/dec/el2_dec.sv
../../Cores-VeeR-EL2/design/exu/el2_exu_alu_ctl.sv
../../Cores-VeeR-EL2/design/exu/el2_exu_mul_ctl.sv
../../Cores-VeeR-EL2/design/exu/el2_exu_div_ctl.sv
../../Cores-VeeR-EL2/design/exu/el2_exu.sv
../../Cores-VeeR-EL2/design/lsu/el2_lsu.sv
../../Cores-VeeR-EL2/design/lsu/el2_lsu_clkdomain.sv
../../Cores-VeeR-EL2/design/lsu/el2_lsu_addrcheck.sv
../../Cores-VeeR-EL2/design/lsu/el2_lsu_lsc_ctl.sv
../../Cores-VeeR-EL2/design/lsu/el2_lsu_stbuf.sv
../../Cores-VeeR-EL2/design/lsu/el2_lsu_bus_buffer.sv
../../Cores-VeeR-EL2/design/lsu/el2_lsu_bus_intf.sv
../../Cores-VeeR-EL2/design/lsu/el2_lsu_ecc.sv
../../Cores-VeeR-EL2/design/lsu/el2_lsu_dccm_mem.sv
../../Cores-VeeR-EL2/design/lsu/el2_lsu_dccm_ctl.sv
../../Cores-VeeR-EL2/design/lsu/el2_lsu_trigger.sv
../../Cores-VeeR-EL2/design/dbg/el2_dbg.sv

// --- VeeR Core Top Level Modules ---
../../Cores-VeeR-EL2/design/el2_dma_ctrl.sv
../../Cores-VeeR-EL2/design/el2_pmp.sv
../../Cores-VeeR-EL2/design/el2_pic_ctrl.sv
../../Cores-VeeR-EL2/design/el2_mem.sv
../../Cores-VeeR-EL2/design/el2_veer.sv
../../Cores-VeeR-EL2/design/el2_veer_lockstep.sv
../../Cores-VeeR-EL2/design/el2_veer_wrapper.sv

// --- VeeR SRAM Models & Behavioral Flops ---
-v ../../Cores-VeeR-EL2/design/lib/beh_lib.sv
-v ../../Cores-VeeR-EL2/design/lib/mem_lib.sv
-y ../../Cores-VeeR-EL2/design/lib

// --- Peripheral RTLs ---
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

// --- SoC Interconnect & Wrapper RTLs ---
../rtl/priority_encoder.v
../rtl/arbiter.v
../rtl/axi_interconnect.v
../rtl/axi_interconnect_wrap_3x8.v
../rtl/axi_interconnect_wrap_4x8.v
../rtl/axi64_to_32_bridge.v
../rtl/dma_reg_file.v
../rtl/dma_master_engine.v
../rtl/dma_sequencer.v
../rtl/dma_top.v
../rtl/soc_top.v
../rtl/soc_core_top.sv

// --- Testbench ---
tb_soc_dma_firmware.sv

