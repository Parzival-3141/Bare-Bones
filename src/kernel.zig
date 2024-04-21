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
const kalloc = @import("kalloc.zig");
const Table = @import("table.zig").Table;

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

    kernel_main(@ptrFromInt(mbinfo_addr)) catch |err| @panic(@errorName(err));

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
    @panic("Kernel exited unexpectedly. Halting system.");
}

fn kernel_main(info: *const multiboot.Info) !void {
    terminal.init();
    const writer = terminal.writer();

    print_hello();

    kalloc.init();
    const kallocator = kalloc.allocator();

    if (!info.flags.mem_map) @panic("Missing memory map!\n");

    const num_mmap_entries = info.mmap_length / @sizeOf(multiboot.MemoryMapEntry);
    const mem_map = @as([*]multiboot.MemoryMapEntry, @ptrFromInt(info.mmap_addr))[0..num_mmap_entries];

    terminal.write("Memory Map:\n");
    {
        const T = Table(&.{ "Address", "Size", "Info" });
        var table: T = .{ .rows = try kallocator.alloc(T.Row, mem_map.len) };
        defer {
            for (table.rows) |row| {
                for (row) |col| kallocator.free(col);
            }
            kallocator.free(table.rows);
        }

        for (mem_map, 0..) |entry, i| {
            table.rows[i] = .{
                try std.fmt.allocPrint(kallocator, "0x{x}", .{entry.base_addr}),
                try std.fmt.allocPrint(kallocator, "{d} (0x{x})", .{ entry.length, entry.length }),
                try std.fmt.allocPrint(kallocator, "{s}", .{
                    if (entry.mem_type.isReserved()) "reserved" else @tagName(entry.mem_type),
                }),
            };
        }

        writer.print("{}\n", .{table}) catch unreachable;
    }

    const gdt_ptr = gdt.get_loaded();
    const gdt_memory = @as([*]u8, @ptrFromInt(gdt_ptr.address))[0 .. gdt_ptr.size + 1];
    const descriptors = std.mem.bytesAsSlice(gdt.Descriptor, gdt_memory);

    terminal.write("\nGDT:\n");
    writer.print("GDT_Ptr{{ .size = 0x{x}, .address = 0x{x} }}\n", .{ gdt_ptr.size, gdt_ptr.address }) catch unreachable;
    {
        const T = Table(&.{ "Index", "BaseAddress", "Size", "Info" });
        var table: T = .{ .rows = try kallocator.alloc(T.Row, descriptors.len) };
        defer {
            for (table.rows) |row| {
                for (row) |col| kallocator.free(col);
            }
            kallocator.free(table.rows);
        }

        for (descriptors, 0..) |d, i| {
            table.rows[i] = .{
                try std.fmt.allocPrint(kallocator, "{d}", .{i}),
                try std.fmt.allocPrint(kallocator, "0x{x}", .{(d.base_low | @as(u32, d.base_high) << 24)}),
                try std.fmt.allocPrint(kallocator, "0x{x}", .{(d.limit_low | @as(u20, d.limit_high) << 16)}),

                if (d.access.present)
                    try std.fmt.allocPrint(kallocator, "{s} {s} {s}", .{
                        if (d.flags.is_64bit) "64-bit" else "32-bit",
                        if (d.access.executable) "code" else "data",
                        @tagName(d.access.privilege),
                    })
                else
                    try std.fmt.allocPrint(kallocator, "invalid", .{}),
            };
        }

        writer.print("{}\n\n", .{table}) catch unreachable;
    }

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
