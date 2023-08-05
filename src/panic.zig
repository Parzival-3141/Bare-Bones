const std = @import("std");
const terminal = @import("terminal.zig");

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    @setCold(true);

    asm volatile ("cli");

    const writer = terminal.writer();
    terminal.put_char('\n');
    // terminal.init();

    writer.print("KERNEL_PANIC: {s}\n", .{msg}) catch unreachable;

    if (ret_addr) |addr| writer.print("return address: {x}\n", .{addr}) catch unreachable;
    if (error_return_trace) |trace| {
        terminal.write("error trace:\n");
        trace.format("", .{}, writer) catch unreachable;
    }

    while (true) {
        asm volatile ("hlt");
    }
}
