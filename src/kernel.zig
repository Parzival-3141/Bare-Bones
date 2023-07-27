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
const terminal = @import("terminal.zig");
const multiboot = @import("multiboot.zig");
const gdt = @import("gdt.zig");

pub fn panic(msg: []const u8, error_return_trace: ?*@import("std").builtin.StackTrace, ret_addr: ?usize) noreturn {
    @setCold(true);
    @import("panic.zig").panic(msg, error_return_trace, ret_addr);
}

export fn kernel_main(info: *const multiboot.Info) void {
    @import("gdt.zig").load();

    terminal.init();
    const writer = terminal.writer();

    print_hello();

    if (!info.flags.mem_map) @panic("Missing memory map!\n");

    const num_mmap_entries = info.mmap_length / @sizeOf(multiboot.MemoryMapEntry);
    const mem_map = @as([*]multiboot.MemoryMapEntry, @ptrFromInt(info.mmap_addr))[0..num_mmap_entries];

    terminal.write("Memory Map:\n");
    for (mem_map) |entry| {
        writer.print("addr 0x{x:0>8} -> 0x{x:0>8} {s}\n", .{
            entry.base_addr,
            entry.base_addr + entry.length,
            if (@intFromEnum(entry.mem_type) <= @intFromEnum(multiboot.MemoryMapEntry.MemoryType.badram)) @tagName(entry.mem_type) else "reserved",
        }) catch unreachable;
    }

    terminal.write("\n");

    const gdt_ptr = gdt.get_loaded();
    terminal.write("GDT:\n");
    writer.print("GDT_Ptr{{ .size = 0x{x}, .address = 0x{x} }}\n", .{ gdt_ptr.size, gdt_ptr.address }) catch unreachable;

    const gdt_memory = @as([*]u8, @ptrFromInt(gdt_ptr.address))[0 .. gdt_ptr.size + 1];
    const descriptors = std.mem.bytesAsSlice(gdt.Descriptor, gdt_memory);

    writer.print("Index BaseAddress Size     Info\n", .{}) catch unreachable;
    for (descriptors, 0..) |d, i| {
        writer.print("{d: ^5} 0x{x: <9} 0x{x: <6} ", .{
            i,
            (d.base_low | @as(u32, d.base_high) << 24),
            (d.limit_low | @as(u20, d.limit_high) << 16),
        }) catch unreachable;

        if (d.access.present) {
            terminal.write(if (d.flags.is_64bit) "64-bit" else "32-bit");
            terminal.write(" ");
            terminal.write(if (d.access.executable) "code" else "data");
        } else {
            terminal.write("invalid");
        }
        terminal.write("\n");
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
