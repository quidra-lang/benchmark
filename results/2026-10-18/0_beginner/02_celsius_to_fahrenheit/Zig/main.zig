const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const temperatures = [_]i32{ -40, -15, -3, 0, 22, 37, 100 };
    var buffer: [512]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    const out = &writer.interface;
    for (temperatures) |celsius| {
        const fahrenheit = @as(f64, @floatFromInt(celsius)) * 9.0 / 5.0 + 32.0;
        try out.print("{d} C = {d:.1} F\n", .{ celsius, fahrenheit });
    }
    try out.flush();
}
