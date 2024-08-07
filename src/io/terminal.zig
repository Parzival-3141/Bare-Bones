var row: usize = 0;
var column: usize = 0;

pub var color: u8 = VGA.DEFAULT_COLOR;

var buffer = @as([*]volatile u16, @ptrFromInt(0xB8000));

pub fn init() void {
    clear();
    put_cursor_at(0, 0);
}

pub fn clear() void {
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
    buffer[index] = VGA.entry(@as(u8, @truncate(buffer[index])), new_color);
}

pub fn put_cursor_at(x: usize, y: usize) void {
    column = x % VGA.WIDTH;
    row = y % VGA.HEIGHT;
    update_visual_cursor();
}

pub fn update_visual_cursor() void {
    const outb = @import("../io.zig").outb;
    const pos: u16 = @intCast(row * VGA.WIDTH + column);
    outb(0x3D4, 0xF);
    outb(0x3D5, @truncate(pos));
    outb(0x3D4, 0xE);
    outb(0x3D5, @truncate(pos >> 8));
}

pub fn get_cursor_pos() struct { x: usize, y: usize } {
    return .{ .x = column, .y = row };
}

pub fn put_char(c: u8) void {
    if (c != '\n') put_entry_at(column, row, c, color);

    column += 1;
    if (column >= VGA.WIDTH or c == '\n') {
        column = 0;

        if (row + 1 >= VGA.HEIGHT) {
            // scroll terminal
            for (0..VGA.HEIGHT) |y| {
                if (y == 0) continue;

                for (0..VGA.WIDTH) |x| {
                    buffer[(y - 1) * VGA.WIDTH + x] = buffer[y * VGA.WIDTH + x];
                }

                if (y == VGA.HEIGHT - 1) {
                    for (0..VGA.WIDTH) |x| {
                        buffer[y * VGA.WIDTH + x] = ' ';
                    }
                }
            }
        } else {
            row += 1;
        }
    }
}

pub fn backspace() void {
    column, const overflow = @subWithOverflow(column, 1);
    if (overflow != 0) {
        column = VGA.WIDTH - 1;
        row -|= 1;
    }
    put_entry_at(column, row, ' ', color);
}

pub fn write(str: []const u8) void {
    for (str) |c| {
        put_char(c);
    }
}

pub const Writer = @import("std").io.Writer(void, error{}, _write);

fn _write(_: void, bytes: []const u8) !usize {
    write(bytes);
    return bytes.len;
}

pub fn writer() Writer {
    return .{ .context = {} };
}

pub const VGA = struct {
    pub const WIDTH = 80;
    pub const HEIGHT = 25;
    pub const DEFAULT_COLOR = VGA.color(.light_grey, .black);

    pub inline fn color(foreground: Color, background: Color) u8 {
        return @intFromEnum(foreground) | (@as(u8, @intFromEnum(background)) << 4);
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
