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
const stack_top = (&stack).ptr + stack.len;

// The linker script specifies _start as the entry point to the kernel and the
// bootloader will jump to this position once the kernel has been loaded. It
// doesn't make sense to return from this function as the bootloader is gone.

extern fn kernel_main(info: *const multiboot.Info) void;

export fn _start() callconv(.Naked) noreturn {
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

    asm volatile (""
        :
        : [stack_top] "{esp}" (stack_top),
    );

    // This is a good place to initialize crucial processor state before the
    // high-level kernel is entered. It's best to minimize the early
    // environment where crucial features are offline. Note that the
    // processor is not fully initialized yet: Features such as floating
    // point instructions and instruction set extensions are not initialized
    // yet. The GDT should be loaded here. Paging should be enabled here.
    // C++ features such as global constructors and exceptions will require
    // runtime support to work as well.

    // Enter the high-level kernel. The ABI requires the stack is 16-byte
    // aligned at the time of the call instruction (which afterwards pushes
    // the return pointer of size 4 bytes). The stack was originally 16-byte
    // aligned above and we've since pushed a multiple of 16 bytes to the
    // stack since (pushed 0 bytes so far) and the alignment is thus
    // preserved and the call is well defined.

    const mbinfo_addr: usize align(16) =
        asm volatile (""
        : [ret] "={ebx}" (-> usize),
    );
    kernel_main(@intToPtr(*const multiboot.Info, mbinfo_addr));

    // Can call kernel_main and setup stack at the same time, though you might want
    // to setup the stack before configuring processor state.
    // They removed this feature in 0.11.0-dev, even though async isn't ready yet
    // https://github.com/ziglang/zig/pull/13907
    // @call(.{ .stack = stack_slice }, @import("kernel.zig").kernel_main, .{});

    // If the system has nothing more to do, put the computer into an
    // infinite loop. To do that:
    // 1) Disable interrupts with cli (clear interrupt enable in eflags).
    //    They are already disabled by the bootloader, so this is not needed.
    //    Mind that you might later enable interrupts and return from
    //    kernel_main (which is sort of nonsensical to do).
    // 2) Wait for the next interrupt to arrive with hlt (halt instruction).
    //    Since they are disabled, this will lock up the computer.
    // 3) Jump to the hlt instruction if it ever wakes up due to a
    //    non-maskable interrupt occurring or due to system management mode.
    while (true) {}
}
