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

const terminal = @import("terminal.zig");
const multiboot = @import("multiboot.zig");

pub fn panic(msg: []const u8, error_return_trace: ?*@import("std").builtin.StackTrace, ret_addr: ?usize) noreturn {
    @setCold(true);
    @import("panic.zig").panic(msg, error_return_trace, ret_addr);
}

export fn kernel_main(info: *const multiboot.Info) void {
    terminal.init();
    const writer = terminal.writer();

    print_hello();

    // terminal.write("multiboot.Info:\n");
    // inline for (@typeInfo(multiboot.Info).Struct.fields) |field| {
    //     writer.print("{s}: {}\n", .{ field.name, @field(info.*, field.name) }) catch unreachable;
    // }

    if (!info.flags.mem_map) @panic("Missing memory map!\n");

    const num_mmap_entries = info.mmap_length / @sizeOf(multiboot.MemoryMapEntry);
    const mem_map = @intToPtr([*]multiboot.MemoryMapEntry, info.mmap_addr)[0..num_mmap_entries];

    for (mem_map) |entry| {
        for (0..10_000) |_| {}

        writer.print("address 0x{x}[0..0x{x}] is {s}\n", .{
            entry.base_addr,
            entry.length,
            if (@enumToInt(entry.mem_type) <= @enumToInt(multiboot.MemoryMapEntry.MemoryType.badram)) @tagName(entry.mem_type) else "reserved",
        }) catch unreachable;
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

    const defualt_color = terminal.VGA.color(.light_grey, .black);
    const border_color = terminal.VGA.color(.light_green, .black);

    for (hello_msg) |c| {
        terminal.color = if (c == '#') border_color else defualt_color;
        terminal.put_char(c);
    }
}
