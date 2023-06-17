var row: usize = 0;
var column: usize = 0;

pub var color = VGA.color(.light_grey, .black);

var buffer = @intToPtr([*]volatile u16, 0xB8000);

pub fn init() void {
    for (0..VGA.HEIGHT) |y| {
        for (0..VGA.WIDTH) |x| {
            put_entry_at(x, y, ' ', color);
        }
    }
}

pub fn put_entry_at(x: usize, y: usize, c: u8, new_color: u8) void {
    const index = (y % VGA.HEIGHT) * VGA.WIDTH + (x % VGA.WIDTH);
    buffer[index] = VGA.entry(c, new_color);
}

pub fn put_color_at(x: usize, y: usize, new_color: u8) void {
    const index = (y % VGA.HEIGHT) * VGA.WIDTH + (x % VGA.WIDTH);
    buffer[index] = VGA.entry(@truncate(u8, buffer[index]), new_color);
}

pub fn put_cursor_at(x: usize, y: usize) void {
    column = x % VGA.WIDTH;
    row = y % VGA.HEIGHT;
}

pub fn put_char(c: u8) void {
    if (c == '\n') {
        put_cursor_at(0, row + 1);
        return;
    }

    put_entry_at(column, row, c, color);
    column += 1;
    if (column == VGA.WIDTH) {
        column = 0;
        row = (row + 1) % VGA.HEIGHT;
    }
}

pub fn write(str: []const u8) void {
    for (str) |c| {
        put_char(c);
    }
}

pub const Writer = @import("std").io.Writer(void, error{}, zwrite);

fn zwrite(_: void, bytes: []const u8) !usize {
    write(bytes);
    return bytes.len;
}

pub fn writer() Writer {
    return .{ .context = {} };
}

pub const VGA = struct {
    pub const WIDTH = 80;
    pub const HEIGHT = 25;

    pub inline fn color(foreground: Color, background: Color) u8 {
        return @enumToInt(foreground) | (@as(u8, @enumToInt(background)) << 4);
    }

    pub inline fn entry(char: u8, colour: u8) u16 {
        return char | (@as(u16, colour) << 8);
    }

    pub const Color = enum(u4) {
        black = 0,
        blue = 1,
        green = 2,
        cyan = 3,
        red = 4,
        magenta = 5,
        brown = 6,
        light_grey = 7,

        // Foreground only, depending on VGA mode
        dark_grey = 8,
        light_blue = 9,
        light_green = 10,
        light_cyan = 11,
        light_red = 12,
        light_magenta = 13,
        light_brown = 14,
        white = 15,
    };
};
