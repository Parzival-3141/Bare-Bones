const io = @import("../io.zig");

var scan_code_buf: [256]u8 linksection(".bss") = undefined;
var read_idx: u8 = 0;
var write_idx: u8 = 0;

pub fn getKey() ?u8 {
    // Prevent an interrupt from modifying
    // the indices while we're comparing them.
    asm volatile ("cli");
    defer asm volatile ("sti");
    if (read_idx == write_idx) return null;

    read_idx +%= 1;
    const code = scan_code_buf[read_idx];
    if (code > 0x58) return null; // is release key
    return scan_set_1_to_ascii[code];
}

pub fn putScanCode(sc: u8) void {
    // io.terminal.put_char(sc);
    write_idx +%= 1;
    scan_code_buf[write_idx] = sc;
}

const scan_set_1_to_ascii =
    "??1234567890-=??" ++ // 00-0F
    "qwertyuiop[]??as" ++ // 10-1F
    "dfghjkl;'`?\\zxcv" ++ //20-2F
    "bnm,./?*? ??????" ++ // 30-3F
    "????????????????" ++ // 40-4F
    "????????????????" ++ // 50-5F
    "????????????????" ++ // 60-6F
    "????????????????" ++ // 70-7F
    "????????????????" ++ // 80-8F
    "????????????????" ++ // 90-9F
    "????????????????" ++ // A0-AF
    "????????????????" ++ // B0-BF
    "????????????????" ++ // C0-CF
    "????????????????" ++ // D0-DF
    "????????????????" ++ // E0-EF
    "????????????????" //    F0-FF
;

/// Keyboard Commands
/// Some commands require sending an additional data byte
pub const Command = union(Tag) {
    set_LEDs: packed struct(u8) {
        scroll_lock: bool,
        number_lock: bool,
        caps_lock: bool,
        _reserved: u5, // used by some international keyboards
    },

    echo,

    access_scancode_set: enum(u8) {
        get_current = 0,
        set_1 = 1,
        set_2 = 2,
        set_3 = 3,
    },

    identify_kbd,

    set_typematic: packed struct(u8) {
        /// 0x0=30Hz...0x1F=2Hz
        repeat_rate: u5,
        delay_before_repeat: enum(u2) {
            @"250ms" = 0,
            @"500ms" = 1,
            @"750ms" = 2,
            @"1000ms" = 3,
        },
        _zero: u1 = 0,
    },

    enable_scanning,
    disable_scanning,
    set_defaults,
    resend_last,
    reset_and_test,

    pub const Tag = enum(u8) {
        set_LEDs = 0xED,
        echo = 0xEE,
        access_scancode_set = 0xF0,
        identify_kbd = 0xF2,
        set_typematic = 0xF3,
        enable_scanning = 0xF4,
        disable_scanning = 0xF5,
        set_defaults = 0xF6,

        // @Todo: handle scancode set 3 commands

        resend_last = 0xFE,
        reset_and_test = 0xFF,
        _,
    };
};

pub const Response = enum(u8) {
    err1 = 0x0,
    test_pass = 0xAA,
    echo = 0xEE,
    ack = 0xFA,
    test_fail1 = 0xFC,
    test_fail2 = 0xFD,
    resend = 0xFE,
    err2 = 0xFF,
    _,
};

const Status = packed struct(u8) {
    output_full: bool,
    input_full: bool,
    sys_flag: bool,
    input_type: enum(u1) { device = 0, command = 1 },
    _chipset_specific: u2,
    time_out_err: bool,
    parity_err: bool,
};

pub const DATA_PORT = 0x60;
pub const STATUS_REG = 0x64;
pub const CMD_REG = 0x64;

const Queue = @import("std").fifo.LinearFifo(Command, .{ .Static = 8 });
var queue = Queue.init();

pub fn sendCommand(cmd: Command) void {
    asm volatile ("cli");
    defer asm volatile ("sti");
    queue.writeItem(cmd) catch @panic("PS/2 command queue OOM");
    if (queue.readableLength() > 1) return;
    sendCmd(cmd);
}

fn sendCmd(cmd: Command) void {
    io.outb(DATA_PORT, @intFromEnum(cmd));
    io.wait();
    switch (cmd) {
        .set_LEDs => |data| io.outb(DATA_PORT, @bitCast(data)),
        .access_scancode_set => |data| io.outb(DATA_PORT, @intFromEnum(data)),
        .set_typematic => |data| io.outb(DATA_PORT, @bitCast(data)),
        else => {},
    }
}

var retries: u8 = 0;

/// Should only be called from within an interrupt
pub fn handleData(d: u8) void {
    if (queue.readableLength() == 0) return putScanCode(d);
    switch (@as(Response, @enumFromInt(d))) {
        .resend => {
            if (retries > 3) @import("std").debug.panic("ps2 command 0x{x} ran out of retries!", .{@intFromEnum(queue.peekItem(0))});
            retries += 1;
            sendCmd(queue.peekItem(0));
        },
        .echo, .ack => {
            retries = 0;
            io.terminal.write("ack ");
            queue.discard(1);

            if (queue.readableLength() > 0) {
                io.wait();
                sendCmd(queue.peekItem(0));
            }
        },
        else => unreachable,
    }
}
