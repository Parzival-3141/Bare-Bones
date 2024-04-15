const std = @import("std");
const gdt = @import("gdt.zig");

pub fn init() void {
    PIC.remap(IRQ_0, IRQ_0 + 8);
    PIC.maskIrq(0, true);
    loadIDT();
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

// IDT ranges
const EXCEPTION_0 = 0;
const EXCEPTION_31 = EXCEPTION_0 + 31;
const IRQ_0 = 32;
const IRQ_15 = IRQ_0 + 15;

export fn mainInterruptHandler(frame: IsrStack) void {
    switch (frame.interrupt) {
        // @Todo: handle exceptions
        EXCEPTION_0...EXCEPTION_31 => std.debug.panic("Unhandled exception: {d}", .{frame.interrupt}),

        IRQ_0...IRQ_15 => {
            const irq: u8 = @intCast(frame.interrupt - IRQ_0);
            if (PIC.handleSpuriousIRQ(irq)) return;

            // @Todo: handle IRQs
            switch (irq) {
                1 => {
                    // print out scancodes
                    @import("terminal.zig").put_char(inb(0x60));
                },
                else => std.debug.panic("Unhandled IRQ: {d} (interrupt={d})", .{ irq, frame.interrupt }),
            }

            PIC.sendEOI(irq);
        },
        else => std.debug.panic("Unhandled interrupt: {d}", .{frame.interrupt}),
    }
}

/// Interrupt Descriptor Table
var idt: [256]Descriptor align(8) linksection(".bss") = undefined;
var idt_ptr = gdt.DescTablePtr{
    .size = @sizeOf(@TypeOf(idt)) - 1,
    .address = undefined,
};

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

fn loadIDT() void {
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
          // : "memory"
    );
}

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

/// Programmable Interrupt Controller
const PIC = struct {
    const master_command = 0x20;
    const master_data = 0x21;

    const slave_command = 0xA0;
    const slave_data = 0xA1;

    const end_of_interrupt = 0x20;

    pub fn remap(master_offset: u8, slave_offset: u8) void {
        // Initialization Command Words (ICW)
        const ICW1_INIT = 0x10; // Initialization - required!
        const ICW1_ICW4 = 0x01; // Indicates that ICW4 will be present
        const ICW4_8086 = 0x01; // 8086/88 (MCS-80/85) mode

        const mask1 = inb(master_data);
        const mask2 = inb(slave_data);

        outb(master_command, ICW1_INIT | ICW1_ICW4); // starts the initialization sequence (in cascade mode)
        io_wait();
        outb(slave_command, ICW1_INIT | ICW1_ICW4);
        io_wait();
        outb(master_data, master_offset); // ICW2: Master PIC vector offset
        io_wait();
        outb(slave_data, slave_offset); // ICW2: Slave PIC vector offset
        io_wait();
        outb(master_data, 4); // ICW3: tell Master PIC that there is a slave PIC at IRQ2 (0000 0100)
        io_wait();
        outb(slave_data, 2); // ICW3: tell Slave PIC its cascade identity (0000 0010)
        io_wait();

        outb(master_data, ICW4_8086); // ICW4: have the PICs use 8086 mode (and not 8080 mode)
        io_wait();
        outb(slave_data, ICW4_8086);
        io_wait();

        outb(master_data, mask1); // restore saved masks.
        outb(slave_data, mask2);
    }

    pub fn disable() void {
        outb(master_data, 0xFF);
        outb(slave_data, 0xFF);
    }

    pub fn sendEOI(irq: u8) void {
        if (irq >= 8) outb(slave_command, end_of_interrupt);
        outb(master_command, end_of_interrupt);
    }

    pub fn maskIrq(irq: u8, mask: bool) void {
        const port: u16 = if (irq < 8) master_data else slave_data;
        const shift: u3 = @intCast(irq % 8);
        if (mask)
            outb(port, inb(port) | (@as(u8, 1) << shift))
        else
            outb(port, inb(port) & ~(@as(u8, 1) << shift));
    }

    pub const StatusRegister = enum(u8) {
        /// Interrupt Request Register
        irr = 0x0A,
        /// In-Service Register
        isr = 0x0B,
    };

    /// Returns the combined value of the cascaded PICs from the given register.
    /// Low 8 bits are date from the Master PIC, high 8 are the Slave.
    pub fn getReg(sr: StatusRegister) u16 {
        // Operation Command Word (OCW)
        // OCW3 to PIC CMD to get the register values.  Slave is chained, and
        // represents IRQs 8-15.  Master is IRQs 0-7, with 2 being the chain.
        const ocw3 = @intFromEnum(sr);
        outb(master_command, ocw3);
        outb(slave_command, ocw3);
        return (@as(u16, inb(slave_command)) << 8) | inb(master_command);
    }

    /// Returns true if the IRQ is spurious and should be ignored.
    /// Handles sending EOI in the true case.
    pub fn handleSpuriousIRQ(irq: u8) bool {
        switch (irq) {
            7 => {
                const master_isr: u8 = @truncate(getReg(.isr));
                return (master_isr & (1 << 7)) == 0;
            },
            15 => {
                const slave_isr: u8 = @truncate(getReg(.isr) >> 8);
                if ((slave_isr & (1 << 7)) == 0) {
                    // Send EOI to Master PIC since it doesn't know
                    // this was a spurious IRQ from the Slave.
                    outb(master_command, end_of_interrupt);
                    return true;
                } else return false;
            },
            else => return false,
        }
    }
};

inline fn inb(port: u16) u8 {
    return asm volatile (
        \\inb %[port], %[ret]
        : [ret] "={al}" (-> u8),
        : [port] "N{dx}" (port),
        : "memory"
    );
}

inline fn outb(port: u16, val: u8) void {
    asm volatile (
        \\outb %[val], %[port]
        :
        : [val] "{al}" (val),
          [port] "N{dx}" (port),
        : "memory"
    );
}

/// Wait a very small amount of time (1 to 4 microseconds, generally).
inline fn io_wait() void {
    // You can do an IO operation on any unused port: the Linux kernel by
    // default uses port 0x80, which is often used during POST to log
    // information on the motherboard's hex display but almost always unused
    // after boot.
    outb(0x80, 0);
}
