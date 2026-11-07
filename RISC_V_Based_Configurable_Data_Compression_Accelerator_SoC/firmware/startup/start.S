.section .text.init
.globl _start

_start:
    /* 1. Set default trap vector */
    la t0, _trap_handler
    csrw mtvec, t0

    /* 2. Configure MRAC (CSR 0x7C0):
          Region 1 (0x1000_0000 - 0x1FFF_FFFF): MMIO peripherals -> side-effect, non-cacheable (2'b10, bits [3:2])
          Region 0 (0x0000_0000 - 0x0FFF_FFFF): DMEM / IMEM alias -> non-cacheable / side-effect safe (2'b10, bits [1:0])
          Regions 2-15 (including Region 8 IMEM 0x8000_0000): cacheable, idempotent (2'b01)
          Full word = 0x5555555A
    */
    li t0, 0x5555555A
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
