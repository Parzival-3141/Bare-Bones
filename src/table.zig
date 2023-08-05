const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn Table(comptime column_titles: []const []const u8) type {
    return struct {
        /// internal data
        columns: [column_titles.len]Column,
        max_column_widths: [column_titles.len]u16,
        backing_writer: AllocatingWriter,

        const Self = @This();
        const Column = std.ArrayList([]const u8);

        pub fn init(allocator: Allocator) Self {
            return .{
                .columns = [_]Column{Column.init(allocator)} ** column_titles.len,
                .backing_writer = AllocatingWriter{ .allocator = allocator },
                .max_column_widths = comptime blk: {
                    var widths = [_]u16{0} ** column_titles.len;
                    for (&widths, column_titles) |*w, title| {
                        w.* = @intCast(title.len);
                    }
                    break :blk widths;
                },
            };
        }

        pub fn deinit(self: *Self) void {
            for (self.columns) |col| {
                for (col.items) |str| {
                    self.backing_writer.allocator.free(str);
                }
                col.deinit();
            }
        }

        pub fn entry(self: *Self, column_idx: usize, comptime fmt: []const u8, args: anytype) !void {
            // using a BufferedWriter since format() can write multiple times
            // per call, cutting AllocatingWriter.last_allocated_slice short.
            var bw = std.io.bufferedWriter(self.backing_writer.writer());
            const writer = bw.writer();

            try writer.print(fmt, args);
            try bw.flush();

            const fmted_entry = self.backing_writer.last_allocated_slice.?;
            try self.columns[column_idx].append(fmted_entry);

            self.max_column_widths[column_idx] = @max(
                @as(u16, @intCast(fmted_entry.len)),
                self.max_column_widths[column_idx],
            );
        }

        pub fn print_out(self: *Self, writer: anytype) !void {
            inline for (column_titles, 0..) |title, i| {
                try writer.writeAll(title);
                try writer.writeByteNTimes(' ', 1 + self.max_column_widths[i] - title.len);
            }

            try writer.writeAll("\n");

            const tallest_column_len = blk: {
                var max_len: usize = 0;
                for (self.columns) |col| {
                    max_len = @max(max_len, col.items.len);
                }
                break :blk max_len;
            };

            var row: usize = 0;
            while (row < tallest_column_len) : (row += 1) {
                for (self.columns, 0..) |col, i| {
                    const str = if (col.items.len > row) col.items[row] else "";
                    try writer.writeAll(str);
                    try writer.writeByteNTimes(' ', 1 + self.max_column_widths[i] - str.len);
                }
                try writer.writeAll("\n");
            }
        }
    };
}

pub const AllocatingWriter = struct {
    allocator: Allocator,
    last_allocated_slice: ?[]const u8 = null,

    pub const WriteError = Allocator.Error;
    pub const Writer = std.io.Writer(*Self, WriteError, write);

    const Self = @This();

    pub fn write(self: *Self, bytes: []const u8) WriteError!usize {
        var data = try self.allocator.alloc(u8, bytes.len);

        @memcpy(data, bytes);

        self.last_allocated_slice = data;
        return bytes.len;
    }

    pub fn writer(self: *Self) Writer {
        return .{ .context = self };
    }
};
