const std = @import("std");
const gdt = @import("gdt.zig");

// @Todo: set all 256 gate entries
var idt: [32]Descriptor = undefined;

comptime {
    // const no_err_fmt =
    //     \\.global isr_no_err{0d}
    //     \\.type isr_no_err{0d}, @function;
    //     \\isr_no_err{0d}:
    //     \\  pushad
    //     \\  cld
    //     \\  call mainInterruptHandler
    //     \\  popad
    //     \\  iret
    // ;
    // asm (std.fmt.comptimePrint(no_err_fmt, .{1}));

    asm (
        \\.global isr_no_err
        \\.align 4
        \\.type isr_no_err, @function;
        \\isr_no_err:
        // \\  pushad
        \\cli
        \\  cld
        \\  call exceptionHandler
        // \\  popad
        \\sti
        \\  iret
    );
}

pub fn load() void {
    // @Todo: handle both Interrupt and Trap (exception) Gates.
    // Some exceptions push an error code onto the stack.
    const isr_ptr: u32 = @intFromPtr(@extern(*const fn () callconv(.Naked) void, .{ .name = "isr_no_err" }));
    for (&idt) |*desc| {
        desc.isr_lo = @truncate(isr_ptr);
        desc.selector = gdt.KERNEL_CODE_SELECTOR;
        desc.flags = .{ .gate_type = .trap_32bit, .privilege = .ring0 };
        desc.isr_hi = @truncate(isr_ptr >> 16);
    }

    idt_ptr.address = @intFromPtr(&idt);

    asm volatile (
        \\lidt %[idt_ptr]
        \\sti
        :
        : [idt_ptr] "p" (&idt_ptr),
    );
}

var idt_ptr = gdt.DescTablePtr{
    .size = @sizeOf(@TypeOf(idt)) - 1,
    .address = undefined,
};

export fn exceptionHandler() void {
    @panic("Unhandled Exception!");
}

const Descriptor = packed struct(u64) {
    isr_lo: u16,
    selector: gdt.Selector,
    _reserved: u8 = 0,

    flags: Flags,

    isr_hi: u16,

    pub const Flags = packed struct(u8) {
        gate_type: enum(u4) {
            /// In this case the Offset value is unused and should be set to zero.
            task = 0x5,
            interrupt_16bit = 0x6,
            trap_16bit = 0x7,
            interrupt_32bit = 0xE,
            trap_32bit = 0xF,
            _,
        },
        _zero: u1 = 0,
        /// Defines the CPU Privilege Levels which are allowed to access this
        /// interrupt via the INT instruction. Hardware interrupts ignore this mechanism.
        privilege: gdt.PrivilegeLevel,
        present: u1 = 1,
    };
};
