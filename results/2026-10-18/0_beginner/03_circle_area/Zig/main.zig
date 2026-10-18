const std = @import("std");

fn writeFixed(out: *std.Io.Writer, value: f64) !void {
    const thousandths: u64 = @intFromFloat(@floor(value * 1000.0 + 0.5));
    try out.print("{d}.{d:0>3}", .{ thousandths / 1000, thousandths % 1000 });
}

pub fn main(init: std.process.Init) !void {
    const radii = [_]u32{ 3, 7, 12, 25, 41 };
    const pi: f64 = 3.141592653589793;
    var buffer: [512]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    const out = &writer.interface;
    for (radii) |radius| {
        const r: f64 = @floatFromInt(radius);
        const area = (pi * r) * r;
        const circumference = (2.0 * pi) * r;
        try out.print("r={d} area=", .{radius});
        try writeFixed(out, area);
        try out.writeAll(" circumference=");
        try writeFixed(out, circumference);
        try out.writeByte('\n');
    }
    try out.flush();
}
