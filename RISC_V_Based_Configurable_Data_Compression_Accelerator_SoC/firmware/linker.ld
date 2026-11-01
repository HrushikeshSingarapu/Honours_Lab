OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    IMEM (rx)  : ORIGIN = 0x80000000, LENGTH = 256K
    DCCM (rwx) : ORIGIN = 0xF0040000, LENGTH = 64K
    DMEM (rwx) : ORIGIN = 0x00040000, LENGTH = 256K
}

SECTIONS
{
    .text :
    {
        KEEP(*(.text.init))
        *(.text*)
        *(.rodata*)
        . = ALIGN(4);
    } > IMEM

    .data :
    {
        *(.data*)
        . = ALIGN(4);
    } > DCCM

    .bss :
    {
        *(.bss*)
        *(COMMON)
        . = ALIGN(4);
    } > DCCM

    __stack_top = ORIGIN(DCCM) + LENGTH(DCCM) - 16;

    /DISCARD/ :
    {
        *(.note*)
        *(.comment)
        *(.riscv.attributes)
    }
}