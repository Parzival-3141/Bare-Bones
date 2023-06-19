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

export fn kernel_main() void {
    terminal.init();

    const msg = "Hello Kernel!";
    const border_color = terminal.VGA.color(.light_green, .black);

    for (0..msg.len + 3) |i| {
        terminal.put_entry_at(i, 0, '#', border_color);
        terminal.put_entry_at(i, 4, '#', border_color);
    }

    for (0..5) |i| {
        terminal.put_entry_at(0, i, '#', border_color);
        terminal.put_entry_at(msg.len + 3, i, '#', border_color);
    }

    terminal.put_cursor_at(2, 2);
    terminal.write(msg);
}
