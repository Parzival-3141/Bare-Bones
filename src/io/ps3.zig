const data_port = 0x60; // Read/Write
const status_register = 0x64; // Read only
const cmd_register = 0x64; // Write only

const Status = packed struct(u8) {
    /// must be true before attempting to read data from data_port
    output_full: bool,
    /// must be false before attempting to write data to data_port or cmd_register
    input_full: bool,
    /// Meant to be cleared on reset and set by firmware
    /// (via. PS/2 Controller Configuration Byte) if the system passes self tests (POST)
    sys_flag: bool,
    /// Is data written to input buffer for a PS/2 device or the PS/2 controller?
    input_type: enum(u1) { device = 0, controller = 1 },

    _chipset_specific: u2,
    time_out_err: bool,
    parity_err: bool,
};

const Config = packed struct(u8) {
    port_1_interrupt_enabled: bool,
    /// Only if controller supports 2 PS/2 ports
    port_2_interrupt_enabled: bool,
    sys_flag: bool,
    _zero1: u1 = 0,
    port_1_clock_disabled: bool,
    /// Only if controller supports 2 PS/2 ports
    port_2_clock_disabled: bool,
    /// Enables scancode translation to set 1 by the controller
    port_1_translation_enabled: bool,
    _zero2: u1 = 0,
};

pub const CmdError = error{TimedOut};

pub fn init() CmdError!void {
    asm volatile ("xchgw %bx, %bx");
    // @Todo: init USB controllers
    // @Todo: determine if PS/2 controller exists

    try sendCmd(0xAD, null); // disable port1
    try sendCmd(0xA7, null); // disable port2 (ignored if single port only)

    _ = io.inb(data_port); // flush output

    try sendCmd(0x20, null); // request config
    var config: Config = @bitCast(try readResp());
    const has_port_2 = config.port_2_clock_disabled;
    if (has_port_2) io.terminal.write("PS/2 port 2 is supported\n");

    config.port_1_interrupt_enabled = false;
    config.port_2_interrupt_enabled = false;
    config.port_1_translation_enabled = false;

    try sendCmd(0x60, @bitCast(config)); // write updated config

    try sendCmd(0xAA, null); // perform controller self test
    if (try readResp() != 0x55)
        @panic("PS/2 controller self test failed");

    // Self test may reset the controller on some hardware.
    // Setting the config again here to support such hardware.
    try sendCmd(0x60, @bitCast(config)); // write config

    try sendCmd(0xAB, null); // test port 1
    if (try readResp() != 0)
        @panic("PS/2 interface test failed on port 1");

    if (has_port_2) {
        try sendCmd(0xA9, null); // test port 2
        if (try readResp() != 0)
            @panic("PS/2 interface test failed on port 2");
    }

    try sendCmd(0xAE, null); // enable port 1
    if (has_port_2) try sendCmd(0xA8, null); // enable port 2

    config.port_1_interrupt_enabled = true;
    if (has_port_2) config.port_2_interrupt_enabled = true;

    try sendCmd(0x60, @bitCast(config)); // write config
}

fn sendCmd(cmd: u8, data: ?u8) CmdError!void {
    try write(cmd_register, cmd);
    if (data) |d| try write(data_port, d);
}

fn write(port: u16, value: u8) CmdError!void {
    const expired: bool = for (0..16) |_| {
        const s: Status = @bitCast(io.inb(status_register));
        io.wait();
        if (!s.input_full) break false;
    } else true;
    if (expired) return error.TimedOut;

    io.outb(port, value);
    io.wait();
}

fn readResp() CmdError!u8 {
    const expired: bool = for (0..16) |_| {
        const s: Status = @bitCast(io.inb(status_register));
        io.wait();
        if (s.output_full) break false;
    } else true;
    if (expired) return error.TimedOut;

    const res = io.inb(data_port);
    io.wait();
    return res;
}

const io = @import("../io.zig");

// fn init2() void {
//     // @Todo: init USB controllers
//     // @Todo: determine if PS/2 controller exists

//     io.outb(cmd_register, 0xAD); // disable port1
//     io.outb(cmd_register, 0xA7); // disable port2 (ignored if single port only)

//     _ = io.inb(data_port); // flush output

//     io.outb(cmd_register, 0x20); // request config
//     var config: Config = @bitCast(io.inb(data_port));
//     const has_port_2 = config.port_2_clock_enabled;

//     config.port_1_interrupt_enabled = false;
//     config.port_2_interrupt_enabled = false;
//     config.port_1_translation_enabled = false;

//     io.outb(cmd_register, 0x60); // write updated config
//     io.outb(data_port, @bitCast(config));

//     io.outb(cmd_register, 0xAA); // perform controller self test
//     if (io.inb(data_port) != 0x55)
//         @panic("PS/2 controller self test failed");

//     // Self test may reset the controller on some hardware.
//     // Setting the config again here to support such hardware.
//     io.outb(cmd_register, 0x60); // write config
//     io.outb(data_port, @bitCast(config));

//     io.outb(cmd_register, 0xAB); // test port 1
//     if (io.inb(data_port) != 0)
//         @panic("PS/2 interface test failed on port 1");

//     if (has_port_2) {
//         io.outb(cmd_register, 0xA9); // test port 2
//         if (io.inb(data_port) != 0)
//             @panic("PS/2 interface test failed on port 2");
//     }

//     io.outb(cmd_register, 0xAE); // enable port 1
//     if (has_port_2) io.outb(cmd_register, 0xA8); // enable port 2

//     config.port_1_interrupt_enabled = true;
//     if (has_port_2) config.port_2_interrupt_enabled = true;

//     io.outb(cmd_register, 0x60); // write config
//     io.outb(data_port, @bitCast(config));
// }
