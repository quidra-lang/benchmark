const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const denominations = [_]u32{ 10000, 5000, 1000, 500, 100, 50, 10, 5, 1 };
    for ([_]u32{ 3780, 15420, 99999, 506, 48263 }) |amount| {
        var remaining = amount;
        var total: u32 = 0;
        try out.print("{d} yen:", .{amount});
        for (denominations) |denom| {
            const count = remaining / denom;
            remaining %= denom;
            total += count;
            if (count > 0)
                try out.print(" {d}x{d}", .{ denom, count });
        }
        try out.print(" ({d} pieces)\n", .{total});
    }
    try out.flush();
}
