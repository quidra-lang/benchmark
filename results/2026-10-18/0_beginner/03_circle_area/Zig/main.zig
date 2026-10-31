const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const radii = [_]u32{ 3, 7, 12, 25, 41 };
    const pi: f64 = 3.141592653589793;
    var buffer: [512]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    const out = &writer.interface;
    for (radii) |radius| {
        const r: f64 = @floatFromInt(radius);
        const area = pi * r * r;
        const circumference = 2.0 * pi * r;
        try out.print("r={d} area={d:.3} circumference={d:.3}\n", .{ radius, area, circumference });
    }
    try out.flush();
}
