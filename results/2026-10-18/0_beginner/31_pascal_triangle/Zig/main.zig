const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    var previous = [_]u32{ 0 } ** 12;
    previous[0] = 1;
    for (0..12) |n| {
        var row = [_]u32{ 0 } ** 12;
        row[0] = 1;
        row[n] = 1;
        if (n > 1) {
            for (1..n) |k|
                row[k] = previous[k - 1] + previous[k];
        }
        for (row[0..n + 1], 0..) |v, k| {
            if (k > 0)
                try out.writeByte(' ');
            try out.print("{d}", .{ v });
        }
        try out.writeByte('\n');
        previous = row;
    }
    try out.flush();
}
