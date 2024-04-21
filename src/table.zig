// Inspired by https://github.com/Sobeston/table-helper/blob/master/table-helper.zig

const std = @import("std");

pub fn Table(comptime headers: []const []const u8) type {
    return struct {
        rows: []Row,

        pub const Row = [headers.len][]const u8;

        pub fn format(
            self: @This(),
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = fmt;
            _ = options;

            var max_column_widths: [headers.len]usize = comptime blk: {
                var widths: [headers.len]usize = undefined;
                for (headers, 0..) |header, i| widths[i] = header.len;
                break :blk widths;
            };

            for (self.rows) |row| {
                for (row, 0..) |column, i| {
                    max_column_widths[i] = @max(max_column_widths[i], column.len);
                }
            }

            try writeRow(headers[0..headers.len].*, max_column_widths, writer);
            try writer.writeByte('\n');

            for (self.rows, 0..) |row, i| {
                try writeRow(row, max_column_widths, writer);
                if (i < self.rows.len - 1) try writer.writeByte('\n');
            }
        }

        fn writeRow(row: Row, max_column_widths: [headers.len]usize, writer: anytype) !void {
            // ABC  DEF GHI
            // 1234 56  789
            for (row, 0..) |column, i| {
                try writer.writeAll(column);
                try writer.writeByteNTimes(' ', 1 + (max_column_widths[i] -| column.len));
                // @Todo: print seperators?
            }
        }
    };
}

// @Todo: helper functions to init/deinit allocated rows
// Use cases:
// - runtime known number of rows
// - print formatting each cell (especially combined with the above case)
