const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const a = [_][4]i32{ .{ 3, -2, 5, 1 }, .{ -4, 7, 0, 6 }, .{ 2, 9, -8, -3 } };
    const b = [_][2]i32{ .{ 1, 4 }, .{ -5, 2 }, .{ 6, -1 }, .{ 0, 7 } };
    for (a) |row| {
        for (0..2) |j| {
            var value: i32 = 0;
            for (0..4) |k|
                value += row[k] * b[k][j];
            if (value < 0) {
                try out.print("{d:>5}", .{ value });
            } else {
                try out.print("{d:>5}", .{ @as(u32, @intCast(value)) });
            }
        }
        try out.writeByte('\n');
    }
    try out.flush();
}
