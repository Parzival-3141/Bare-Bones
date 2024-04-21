pub const ps2 = @import("io/ps2.zig");
pub const terminal = @import("io/terminal.zig");

pub inline fn inb(port: u16) u8 {
    return asm volatile (
        \\inb %[port], %[ret]
        : [ret] "={al}" (-> u8),
        : [port] "N{dx}" (port),
        : "memory"
    );
}

pub inline fn outb(port: u16, val: u8) void {
    asm volatile (
        \\outb %[val], %[port]
        :
        : [val] "{al}" (val),
          [port] "N{dx}" (port),
        : "memory"
    );
}

/// Wait a very small amount of time (1 to 4 microseconds, generally).
pub inline fn wait() void {
    // You can do an IO operation on any unused port: the Linux kernel by
    // default uses port 0x80, which is often used during POST to log
    // information on the motherboard's hex display but almost always unused
    // after boot.
    outb(0x80, 0);
}
