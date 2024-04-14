const std = @import("std");
const gdt = @import("gdt.zig");

var idt: [256]Descriptor align(8) linksection(".bss") = undefined;

comptime {
    for (0..idt.len) |i| {
        const int_fmt: []const u8 = switch (i) {
            // interrupt (with error code)
            8, 10...14, 17, 21, 29, 30 =>
            \\.global isr_err{0d}
            \\.align 4
            \\.type isr_err{0d}, @function;
            \\isr_err{0d}:
            \\                 # cpu pushes an error code to the stack
            \\  push ${0d}     # interrupt number 
            \\  jmp isr_common
            ,

            // interrupt (no error code)
            else =>
            \\.global isr{0d}
            \\.align 4
            \\.type isr{0d}, @function;
            \\isr{0d}:
            \\  push $0        # dummy error code 
            \\  push ${0d}     # interrupt number 
            \\  jmp isr_common
            ,
        };

        asm (std.fmt.comptimePrint(int_fmt, .{i}));
    }

    asm (
        \\isr_common:
        \\  pusha
        \\  call mainInterruptHandler
        \\  popa
        \\  add $8, %esp # clean up interrupt number and error code from the stack 
        \\  iret
    );
}

const IsrStack = extern struct {
    pusha_registers: Registers,

    interrupt: u32,
    err_code: u32,

    eip: u32,
    cs: u32,
    eflags: u32,
};

const Registers = extern struct {
    edi: u32,
    esi: u32,
    ebp: u32,
    esp: u32,
    ebx: u32,
    edx: u32,
    ecx: u32,
    eax: u32,
};

export fn mainInterruptHandler(frame: IsrStack) void {
    switch (frame.interrupt) {
        else => unhandled(@intCast(frame.interrupt)),
    }
}

fn unhandled(interrupt: u8) noreturn {
    if (interrupt < 32)
        std.debug.panic("Unhandled exception: {d}", .{interrupt})
    else
        std.debug.panic("Unhandled interrupt: {d}", .{interrupt});
}

pub fn load() void {
    inline for (&idt, 0..) |*desc, i| {
        const isr_name = switch (i) {
            // interrupt (with error code)
            8, 10...14, 17, 21, 29, 30 => "isr_err{d}",
            // interrupt (no error code)
            else => "isr{d}",
        };

        const isr_ptr: u32 = @intFromPtr(
            @extern(
                *const fn () callconv(.Naked) void,
                .{ .name = std.fmt.comptimePrint(isr_name, .{i}) },
            ),
        );

        desc.offset_low = @truncate(isr_ptr);
        desc.offset_high = @truncate(isr_ptr >> 16);
        desc.selector = gdt.KERNEL_CODE_SELECTOR;
        desc.flags = .{
            .gate_type = if (i < 32) .trap_32bit else .interrupt_32bit,
            .privilege = .ring0,
        };
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

const Descriptor = packed struct(u64) {
    offset_low: u16,
    selector: gdt.Selector,
    _reserved: u8 = 0,

    flags: Flags,

    offset_high: u16,

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
