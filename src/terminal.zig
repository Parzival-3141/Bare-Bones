// @Todo: technically should be u7, as the highest bit actually controls blinking,
// but this makes things easier.
const VGA_Color = enum(u8) {
    black = 0,
    blue = 1,
    green = 2,
    cyan = 3,
    red = 4,
    magenta = 5,
    brown = 6,
    light_grey = 7,
    dark_grey = 8,
    light_blue = 9,
    light_green = 10,
    light_cyan = 11,
    light_red = 12,
    light_magenta = 13,
    light_brown = 14,
    white = 15,
};

pub const VGA_WIDTH = 80;
pub const VGA_HEIGHT = 25;

pub inline fn vga_entry_color(foreground: VGA_Color, background: VGA_Color) u8 {
    return @enumToInt(foreground) | (@enumToInt(background) << 4);
}

pub inline fn vga_entry(char: u8, col: u8) u16 {
    return char | (@as(u16, col) << 8);
}

// @Todo: refactor all this into idiomatic Zig
// const Terminal = struct {
//     x: usize = 0,
//     y: usize = 0,
//     color: VGA_Color = vga_entry_color(.light_grey, .black),
//     buffer: []u16 = .{ .ptr = @intToPtr(u16, 0xB8000), .len = VGA_HEIGHT * VGA_WIDTH },
// };

var row: usize = 0;
var column: usize = 0;
var color = vga_entry_color(.light_grey, .black);
var buffer = @intToPtr([*]volatile u16, 0xB8000);

pub fn init() void {
    for (0..VGA_HEIGHT) |y| {
        for (0..VGA_WIDTH) |x| {
            put_entry_at(' ', color, x, y);
        }
    }
}

pub fn put_entry_at(c: u8, col: u8, x: usize, y: usize) void {
    const index = y * VGA_WIDTH + x;
    buffer[index] = vga_entry(c, col);
}

pub fn put_cursor_at(x: usize, y: usize) void {
    column = x % VGA_WIDTH;
    row = y % VGA_HEIGHT;
}

pub fn put_char(c: u8) void {
    if (c == '\n') {
        column = 0;
        row = (row + 1) % VGA_HEIGHT;
        return;
    }

    put_entry_at(c, color, column, row);
    column += 1;
    if (column == VGA_WIDTH) {
        column = 0;
        row = (row + 1) % VGA_HEIGHT;
    }
}

pub fn write(str: []const u8) void {
    for (str) |c| {
        put_char(c);
    }
}
