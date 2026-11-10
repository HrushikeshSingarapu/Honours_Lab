// =============================================================================
// uart_firmware.f — VCS Simulation Filelist for VeeR EL2 SoC UART Firmware Test
// Project Root: RISC_V_Based_Configurable_Data_Compression_Accelerator_SoC/
// =============================================================================

// --- Compiler Defines ---
+define+RV_OPENSOURCE
+define+GTLSIM

// --- Include Directories ---
+incdir+rtl/soc
+incdir+rtl/interconnect
+incdir+rtl/peripherals/uart
+incdir+rtl/peripherals/timer
+incdir+rtl/peripherals/gpio
+incdir+rtl/peripherals/crc
+incdir+rtl/accelerators/rle
+incdir+rtl/accelerators/dma
+incdir+third_party/RISC-V-VeeR-EL2/snapshots/soc_sim
+incdir+third_party/RISC-V-VeeR-EL2/design/include
+incdir+third_party/RISC-V-VeeR-EL2/design/lib
+incdir+third_party/RISC-V-VeeR-EL2/design/dmi
+incdir+verification/standalone/soc

// --- VeeR Snapshot Global Defines ---
third_party/RISC-V-VeeR-EL2/snapshots/soc_sim/common_defines.vh

// --- VeeR Packages & Interfaces ---
third_party/RISC-V-VeeR-EL2/design/include/el2_def.sv
third_party/RISC-V-VeeR-EL2/design/lib/el2_assert.sv
third_party/RISC-V-VeeR-EL2/design/el2_mubi_pkg.sv
third_party/RISC-V-VeeR-EL2/design/el2_lockstep_pkg.sv
third_party/RISC-V-VeeR-EL2/design/lib/el2_mem_if.sv
third_party/RISC-V-VeeR-EL2/design/lib/el2_regfile_if.sv

// --- VeeR Core Infrastructure & DMI ---
third_party/RISC-V-VeeR-EL2/design/lib/el2_lib.sv
third_party/RISC-V-VeeR-EL2/design/lib/el2_prim_generic_buf.sv
third_party/RISC-V-VeeR-EL2/design/lib/el2_prim_buf.sv
third_party/RISC-V-VeeR-EL2/design/lib/ahb_to_axi4.sv
third_party/RISC-V-VeeR-EL2/design/lib/axi4_to_ahb.sv
third_party/RISC-V-VeeR-EL2/design/dmi/dmi_mux.v
third_party/RISC-V-VeeR-EL2/design/dmi/dmi_wrapper.v
third_party/RISC-V-VeeR-EL2/design/dmi/dmi_jtag_to_core_sync.v
third_party/RISC-V-VeeR-EL2/design/dmi/rvjtag_tap.v

// --- VeeR Subunits (IFU, DEC, EXU, LSU, DBG) ---
third_party/RISC-V-VeeR-EL2/design/ifu/el2_ifu_aln_ctl.sv
third_party/RISC-V-VeeR-EL2/design/ifu/el2_ifu_compress_ctl.sv
third_party/RISC-V-VeeR-EL2/design/ifu/el2_ifu_ifc_ctl.sv
third_party/RISC-V-VeeR-EL2/design/ifu/el2_ifu_bp_ctl.sv
third_party/RISC-V-VeeR-EL2/design/ifu/el2_ifu_ic_mem.sv
third_party/RISC-V-VeeR-EL2/design/ifu/el2_ifu_mem_ctl.sv
third_party/RISC-V-VeeR-EL2/design/ifu/el2_ifu_iccm_mem.sv
third_party/RISC-V-VeeR-EL2/design/ifu/el2_ifu.sv
third_party/RISC-V-VeeR-EL2/design/dec/el2_dec_decode_ctl.sv
third_party/RISC-V-VeeR-EL2/design/dec/el2_dec_gpr_ctl.sv
third_party/RISC-V-VeeR-EL2/design/dec/el2_dec_ib_ctl.sv
third_party/RISC-V-VeeR-EL2/design/dec/el2_dec_pmp_ctl.sv
third_party/RISC-V-VeeR-EL2/design/dec/el2_dec_tlu_ctl.sv
third_party/RISC-V-VeeR-EL2/design/dec/el2_dec_trigger.sv
third_party/RISC-V-VeeR-EL2/design/dec/el2_dec.sv
third_party/RISC-V-VeeR-EL2/design/exu/el2_exu_alu_ctl.sv
third_party/RISC-V-VeeR-EL2/design/exu/el2_exu_mul_ctl.sv
third_party/RISC-V-VeeR-EL2/design/exu/el2_exu_div_ctl.sv
third_party/RISC-V-VeeR-EL2/design/exu/el2_exu.sv
third_party/RISC-V-VeeR-EL2/design/lsu/el2_lsu.sv
third_party/RISC-V-VeeR-EL2/design/lsu/el2_lsu_clkdomain.sv
third_party/RISC-V-VeeR-EL2/design/lsu/el2_lsu_addrcheck.sv
third_party/RISC-V-VeeR-EL2/design/lsu/el2_lsu_lsc_ctl.sv
third_party/RISC-V-VeeR-EL2/design/lsu/el2_lsu_stbuf.sv
third_party/RISC-V-VeeR-EL2/design/lsu/el2_lsu_bus_buffer.sv
third_party/RISC-V-VeeR-EL2/design/lsu/el2_lsu_bus_intf.sv
third_party/RISC-V-VeeR-EL2/design/lsu/el2_lsu_ecc.sv
third_party/RISC-V-VeeR-EL2/design/lsu/el2_lsu_dccm_mem.sv
third_party/RISC-V-VeeR-EL2/design/lsu/el2_lsu_dccm_ctl.sv
third_party/RISC-V-VeeR-EL2/design/lsu/el2_lsu_trigger.sv
third_party/RISC-V-VeeR-EL2/design/dbg/el2_dbg.sv

// --- VeeR Core Top Level Modules ---
third_party/RISC-V-VeeR-EL2/design/el2_dma_ctrl.sv
third_party/RISC-V-VeeR-EL2/design/el2_pmp.sv
third_party/RISC-V-VeeR-EL2/design/el2_pic_ctrl.sv
third_party/RISC-V-VeeR-EL2/design/el2_mem.sv
third_party/RISC-V-VeeR-EL2/design/el2_veer.sv
third_party/RISC-V-VeeR-EL2/design/el2_veer_lockstep.sv
third_party/RISC-V-VeeR-EL2/design/el2_veer_wrapper.sv

// --- VeeR SRAM Models & Behavioral Flops ---
-v third_party/RISC-V-VeeR-EL2/design/lib/beh_lib.sv
-v third_party/RISC-V-VeeR-EL2/design/lib/mem_lib.sv
-y third_party/RISC-V-VeeR-EL2/design/lib

// --- Peripheral RTLs ---
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

// --- SoC Interconnect & Wrapper RTLs ---
rtl/interconnect/priority_encoder.v
rtl/interconnect/arbiter.v
rtl/interconnect/axi_interconnect.v
rtl/interconnect/axi_interconnect_wrap_4x8.v
rtl/interconnect/axi64_to_32_bridge.v
rtl/accelerators/dma/dma_reg_file.v
rtl/accelerators/dma/dma_master_engine.v
rtl/accelerators/dma/dma_sequencer.v
rtl/accelerators/dma/dma_top.v
rtl/soc/soc_top.v
rtl/soc/soc_core_top.sv

// --- Testbench & Monitor ---
verification/standalone/soc/tb_soc_uart_firmware.sv
verification/standalone/soc/uart_tx_monitor.sv
