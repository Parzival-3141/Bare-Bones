comptime {
    const builtin = @import("builtin");
    const tgt = builtin.target;

    // @Todo: Not sure if Abi.none is correct. IDK what System V ABI is in Zig
    if (tgt.os.tag != .freestanding or tgt.cpu.arch != .x86 or tgt.abi != .none) {
        @compileError("Target must be x86-freestanding-none (-target x86-freestanding-none)");
    }

    if (builtin.object_format != .elf) {
        @compileError("Object format must be ELF (-ofmt=elf)");
    }

    const model_name = "i686";
    if (tgt.cpu.model.name.len != model_name.len or for (tgt.cpu.model.name, 0..) |*c, i| {
        if (c.* != model_name[i]) break true;
    } else false) {
        @compileError("Target cpu must be i686 (-mcpu i686)");
    }
}

// Force boot.zig to be included in the build
comptime {
    _ = @import("boot.zig");
}

const std = @import("std");
const io = @import("io.zig");
const terminal = io.terminal;
const multiboot = @import("multiboot.zig");
const gdt = @import("gdt.zig");

pub fn panic(msg: []const u8, error_return_trace: ?*@import("std").builtin.StackTrace, ret_addr: ?usize) noreturn {
    @setCold(true);
    @import("panic.zig").panic(msg, error_return_trace, ret_addr);
}

pub fn kernel_init() noreturn {
    // Grab multiboot info before potentially overwriting it
    const mbinfo_addr: usize align(16) =
        asm volatile (""
        : [ret] "={ebx}" (-> usize),
    );

    // This is a good place to initialize crucial processor state before the
    // high-level kernel is entered. It's best to minimize the early
    // environment where crucial features are offline. Note that the
    // processor is not fully initialized yet: Features such as floating
    // point instructions and instruction set extensions are not initialized
    // yet. The GDT should be loaded here. Paging should be enabled here.
    // C++ features such as global constructors and exceptions will require
    // runtime support to work as well.

    gdt.load();
    @import("interrupts.zig").init();

    kernel_main(@ptrFromInt(mbinfo_addr));

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
    // asm volatile ("cli");
    while (true) {
        asm volatile ("hlt");
    }
}

fn kernel_main(info: *const multiboot.Info) void {
    _ = info;
    terminal.init();

    print_hello();

    while (true) {
        if (io.ps2.getKey()) |key| {
            terminal.put_char(key);
        }
    }
}

fn print_hello() void {
    const hello_msg =
        \\#################
        \\#               #
        \\# Hello Kernel! #
        \\#               #
        \\#################
        \\
        \\
    ;

    const default_color = terminal.VGA.color(.light_grey, .black);
    const border_color = terminal.VGA.color(.light_green, .black);

    for (hello_msg) |c| {
        terminal.color = if (c == '#') border_color else default_color;
        terminal.put_char(c);
    }
}
