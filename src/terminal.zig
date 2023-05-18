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

const VGA_WIDTH = 80;
const VGA_HEIGHT = 25;

pub inline fn vga_entry_color(foreground: VGA_Color, background: VGA_Color) u8 {
    return @enumToInt(foreground) | (@enumToInt(background) << 4);
}

pub inline fn vga_entry(char: u8, color: u8) u16 {
    return char | (@as(u16, color) << 8);
}

// @Todo: refactor all this into idiomatic Zig
// const Terminal = struct {
//     x: usize = 0,
//     y: usize = 0,
//     color: VGA_Color = vga_entry_color(.light_grey, .black),
//     buffer: []u16 = .{ .ptr = @intToPtr(u16, 0xB8000), .len = VGA_HEIGHT * VGA_WIDTH },
// };

var terminal_row: usize = 0;
var terminal_column: usize = 0;
var terminal_color = vga_entry_color(.light_grey, .black);
var terminal_buffer = @intToPtr([*]volatile u16, 0xB8000);

pub fn terminal_init() void {
    for (0..VGA_HEIGHT) |y| {
        for (0..VGA_WIDTH) |x| {
            terminal_put_entry_at(' ', terminal_color, x, y);
        }
    }
}

pub fn terminal_put_entry_at(c: u8, color: u8, x: usize, y: usize) void {
    const index = y * VGA_WIDTH + x;
    terminal_buffer[index] = vga_entry(c, color);
}

pub fn terminal_put_char(c: u8) void {
    terminal_put_entry_at(c, terminal_color, terminal_column, terminal_row);
    terminal_column += 1;
    if (terminal_column == VGA_WIDTH) {
        terminal_column = 0;
        terminal_row += 1;
        if (terminal_row == VGA_HEIGHT)
            terminal_row = 0;
    }
}

pub fn terminal_write(str: []const u8) void {
    for (str) |c| {
        terminal_put_char(c);
    }
}
