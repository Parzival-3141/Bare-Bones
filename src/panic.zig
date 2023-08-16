const std = @import("std");
const terminal = @import("terminal.zig");

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    @setCold(true);

    asm volatile ("cli");

    const writer = terminal.writer();
    terminal.put_char('\n');
    // terminal.init();

    terminal.color = terminal.VGA.color(.light_red, .black);
    terminal.write("KERNEL_PANIC");

    terminal.color = terminal.VGA.DEFAULT_COLOR;
    writer.print(": {s}\n", .{msg}) catch unreachable;

    if (ret_addr) |addr| writer.print("return address: 0x{x}\n", .{addr}) catch unreachable;
    if (error_return_trace) |trace| {
        terminal.write("error trace:\n");
        // @Note: silent compile error when error is ignored.
        trace.format("", .{}, writer) catch {
            writer.write("Unable to print trace\n") catch unreachable;
        };
    }

    while (true) {
        asm volatile ("hlt");
    }
}
