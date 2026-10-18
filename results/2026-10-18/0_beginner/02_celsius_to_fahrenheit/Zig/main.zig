const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const temperatures = [_]i32{ -40, -15, -3, 0, 22, 37, 100 };
    var buffer: [512]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    const out = &writer.interface;
    for (temperatures) |celsius| {
        const fahrenheit = @as(f64, @floatFromInt(celsius)) * 9.0 / 5.0 + 32.0;
        const tenths: u64 = @intFromFloat(@floor(@abs(fahrenheit) * 10.0 + 0.5));
        const sign: []const u8 = if (fahrenheit < 0.0) "-" else "";
        try out.print("{d} C = {s}{d}.{d} F\n", .{ celsius, sign, tenths / 10, tenths % 10 });
    }
    try out.flush();
}
