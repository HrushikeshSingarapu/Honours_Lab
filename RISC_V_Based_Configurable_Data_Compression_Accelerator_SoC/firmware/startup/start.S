.section .text.init
.globl _start

_start:
    /* 1. Set default trap vector */
    la t0, _trap_handler
    csrw mtvec, t0

    /* 2. Configure MRAC (CSR 0x7C0):
          Region 0 (0x0000_0000 - 0x0FFF_FFFF): IMEM alias, DMEM & MMIO peripherals -> side-effect, non-cacheable (2'b10, bits [1:0])
          Regions 1-15 (including Region 8 IMEM 0x8000_0000): cacheable, idempotent (2'b01)
          Full word = 0x55555556
    */
    li t0, 0x55555556
    csrw 0x7C0, t0
    fence
    fence.i

    /* 3. Initialize stack pointer in DCCM */
    la sp, __stack_top

    /* 4. Call main */
    call main

halt:
    j halt

.align 2
_trap_handler:
    j _trap_handler
