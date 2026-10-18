const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const vertices = [_][2]i32{
        .{ 1, 1 },
        .{ 11, 2 },
        .{ 13, 9 },
        .{ 9, 7 },
        .{ 7, 12 },
        .{ 5, 6 },
        .{ 2, 10 },
        .{ 3, 5 }
    };
    for ([_][2]i32{
        .{ 4, 8 },
        .{ 6, 4 },
        .{ 10, 8 },
        .{ 7, 11 },
        .{ 14, 3 },
        .{ 12, 8 }
    }) |p| {
        var inside = false;
        for (vertices, 0..) |a, i| {
            const b = vertices[(i + 1) % vertices.len];
            if ((a[1] > p[1]) != (b[1] > p[1])) {
                const x = @as(f64, @floatFromInt(a[0])) + @as(f64, @floatFromInt((b[0] - a[0]) * (p[1] - a[1]))) / @as(f64,
                    @floatFromInt(b[1] - a[1]));
                if (x > @as(f64, @floatFromInt(p[0])))
                    inside = !inside;
            }
        }
        try out.print("({d}, {d}): {s}\n", .{ p[0], p[1], if (inside) @as([]const u8, "inside") else "outside" });
    }
    try out.flush();
}
