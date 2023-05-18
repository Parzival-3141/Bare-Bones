comptime {
    const builtin = @import("builtin");
    const tgt = builtin.target;

    // if (tgt.os.tag != .freestanding or tgt.cpu.arch != .x86) {
    //     @compileError("Target must be x86-freestanding (-target x86-freestanding)");
    // }

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

// const boot = @import("boot.zig");
const terminal = @import("terminal.zig");

export fn kernel_main() void {
    terminal.terminal_init();
    terminal.terminal_write("Hello Kernel!\n");
}
