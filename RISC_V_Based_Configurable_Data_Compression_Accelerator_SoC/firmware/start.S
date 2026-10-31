.section .text.init
.globl _start

_start:

    /* Initialize stack pointer */
    la sp, __stack_top

    /* Call C main function */
    call main

halt:
    j halt
