//! Boot Zig script
const multiboot = @import("multiboot.zig");

// Declare a multiboot header that marks the program as a kernel. These are magic
// values that are documented in the multiboot standard. The bootloader will
// search for this signature in the first 8 KiB of the kernel file, aligned at a
// 32-bit boundary. The signature is in its own section so the header can be
// forced to be within the first 8 KiB of the kernel file.

export const mb_header align(4) linksection(".multiboot") =
    multiboot.Header.init(.{ .@"align" = true, .mem_info = true });

// The multiboot standard does not define the value of the stack pointer register
// (esp) and it is up to the kernel to provide a stack. This allocates room for a
// small stack by creating a symbol at the bottom of it, then allocating 16384
// bytes for it, and finally creating a symbol at the top. The stack grows
// downwards on x86. The stack is in its own section so it can be marked nobits,
// which means the kernel file is smaller because it does not contain an
// uninitialized stack. The stack on x86 must be 16-byte aligned according to the
// System V ABI standard and de-facto extensions. The compiler will assume the
// stack is properly aligned and failure to align the stack will result in
// undefined behavior.

export var stack: [16 * 1024]u8 align(16) linksection(".bss") = undefined;
const stack_top = stack[0..].ptr + stack.len;

// The linker script specifies _start as the entry point to the kernel and the
// bootloader will jump to this position once the kernel has been loaded. It
// doesn't make sense to return from this function as the bootloader is gone.

export fn _start() callconv(.Naked) noreturn {
    // asm volatile ("xchgw %bx, %bx"); // bochs breakpoint

    // The bootloader has loaded us into 32-bit protected mode on a x86
    // machine. Interrupts are disabled. Paging is disabled. The processor
    // state is as defined in the multiboot standard. The kernel has full
    // control of the CPU. The kernel can only make use of hardware features
    // and any code it provides as part of itself. There's no printf
    // function, unless the kernel provides its own <stdio.h> header and a
    // printf implementation. There are no security restrictions, no
    // safeguards, no debugging mechanisms, only what the kernel provides
    // itself. It has absolute and complete power over the
    // machine.

    // To set up a stack, we set the esp register to point to the top of our
    // stack (as it grows downwards on x86 systems). This is necessarily done
    // in assembly as languages such as C cannot function without a stack.

    asm volatile (
        \\mov %[stack_top], %%esp
        :
        : [stack_top] "i" (stack_top),
        : "esp"
    );

    // jump to kernel
    // Note on the ':P' https://llvm.org/docs/LangRef.html#asm-template-argument-modifiers
    asm volatile (
        \\call %[kernel_init:P]
        :
        : [kernel_init] "X" (&kernel_init),
    );
}

extern fn kernel_init() noreturn;
