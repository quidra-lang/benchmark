const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    var a: [26]bool = @splat(false);
    var b = a;
    for ([_]usize{ 12, 5, 8, 21, 5, 17, 3, 12, 9 }) |v|
        a[v] = true;
    for ([_]usize{ 8, 14, 21, 6, 14, 3, 25, 6 }) |v|
        b[v] = true;
    const labels = [_][]const u8{ "union:", "intersection:", "difference:", "symmetric difference:" };
    for (labels, 0..) |label, k| {
        try out.writeAll(label);
        for (0..26) |v| {
            const include = switch (k) {
                0 => a[v] or b[v],
                1 => a[v] and b[v],
                2 => a[v] and !b[v],
                else => a[v] != b[v],
            };
            if (include)
                try out.print(" {d}", .{v});
        }
        try out.writeByte('\n');
    }
    try out.flush();
}
