const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const matrix = [_][5]u32{
        .{ 125, 340, 78, 912, 456 },
        .{ 603, 27, 819, 150, 384 },
        .{ 0, 765, 231, 498, 62 },
        .{ 947, 113, 586, 39, 720 }
    };
    var columns = [_]u32{ 0 } ** 5;
    var total: u32 = 0;
    for (matrix) |row| {
        var sum: u32 = 0;
        for (row, 0..) |v, j| {
            sum += v;
            columns[j] += v;
            try out.print("{d:>6}", .{ v });
        }
        total += sum;
        try out.print("{d:>6}\n", .{ sum });
    }
    for (columns) |v|
        try out.print("{d:>6}", .{ v });
    try out.print("{d:>6}\n", .{ total });
    try out.flush();
}
