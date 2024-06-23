# 

.text
.global _start
.type _start, @function

#.equ    STACK_TOP, 0x200000       # 2MB total memory
.equ    STACK_TOP, 0x100000       # 1MB total memory

_start:
    li  sp,STACK_TOP    # load stack pointer

# zero-init bss section
    la a0, _sbss
    la a1, _ebss
    bge a0, a1, end_init_bss
loop_init_bss:
    sw zero, 0(a0)
    addi a0, a0, 4
    blt a0, a1, loop_init_bss

end_init_bss:
    call main
    # tail exit
