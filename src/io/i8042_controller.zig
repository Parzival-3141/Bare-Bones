/// read/write
pub const data_port = 0x60;
/// read only
pub const status_port = 0x64;
/// write only
pub const command_port = 0x64;

const Command = enum(u8) {
    get_config = 0x20,
    set_config = 0x60,
    disable_ps2_port_2 = 0xA7,
    enable_ps2_port_2 = 0xA8,
    test_ps2_port_2 = 0xA9,
    test_controller = 0xAA,
    test_ps2_port_1 = 0xAB,
    disable_ps2_port_1 = 0xAD,
    enable_ps2_port_1 = 0xAE,
};

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
    ps2_port_1_interrupt_enabled: bool,
    /// Only if controller supports 2 PS/2 ports
    ps2_port_2_interrupt_enabled: bool,
    sys_flag: bool,
    _zero1: u1 = 0,
    ps2_port_1_clock_disabled: bool,
    /// Only if controller supports 2 PS/2 ports
    ps2_port_2_clock_disabled: bool,
    /// Enables scancode translation to set 1 by the controller
    ps2_port_1_translation_enabled: bool,
    _zero2: u1 = 0,
};

pub fn init() void {
    asm volatile ("xchgw %bx, %bx");
    // @Todo: init USB controllers
    // @Todo: determine if PS/2 controller exists

    sendCmd(.disable_ps2_port_1);
    sendCmd(.disable_ps2_port_2); // ignored if single port only

    _ = io.inb(data_port); // flush output

    sendCmd(.get_config);
    var config: Config = @bitCast(readResp());
    const has_ps2_port_2 = config.ps2_port_2_clock_disabled;
    if (has_ps2_port_2) io.terminal.write("PS/2 port 2 is supported\n");

    config.ps2_port_1_translation_enabled = false;
    config.ps2_port_1_interrupt_enabled = false;
    config.ps2_port_2_interrupt_enabled = false;

    sendCmdWithData(.set_config, @bitCast(config)); // write updated config

    sendCmd(.test_controller);
    if (readResp() != 0x55)
        @panic("PS/2 controller self test failed");

    // Self test may reset the controller on some hardware.
    // Setting the config again here to support such hardware.
    sendCmdWithData(.set_config, @bitCast(config));

    sendCmd(.test_ps2_port_1);
    if (readResp() != 0)
        @panic("PS/2 interface test failed on port 1");

    if (has_ps2_port_2) {
        sendCmd(.test_ps2_port_2);
        if (readResp() != 0)
            @panic("PS/2 interface test failed on port 2");
    }

    sendCmd(.enable_ps2_port_1);
    if (has_ps2_port_2) sendCmd(.enable_ps2_port_2);

    config.ps2_port_1_interrupt_enabled = true;
    if (has_ps2_port_2) config.ps2_port_2_interrupt_enabled = true;

    sendCmdWithData(.set_config, @bitCast(config));
}

fn sendCmd(cmd: Command) void {
    write(command_port, @intFromEnum(cmd));
}

fn sendCmdWithData(cmd: Command, data: u8) void {
    sendCmd(cmd);
    write(data_port, data);
}

fn write(port: u8, value: u8) void {
    for (0..16) |_| {
        const s: Status = @bitCast(io.inb(status_port));
        io.wait();
        if (!s.input_full) break;
    } else @panic("i8042 write expired");

    io.outb(port, value);
    io.wait();
}

fn readResp() u8 {
    for (0..16) |_| {
        const s: Status = @bitCast(io.inb(status_port));
        io.wait();
        if (s.output_full) break;
    } else @panic("i8042 read expired");

    const res = io.inb(data_port);
    io.wait();
    return res;
}

const io = @import("../io.zig");
