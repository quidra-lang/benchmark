const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const values = [_]i32{ 48, 73, 56, 91, 35, 62, 84 };
    var total: i32 = 0;
    for (values) |value|
        total += value;
    const mean = @as(f64, @floatFromInt(total)) / @as(f64, @floatFromInt(values.len));
    const hundredths: u64 = @intFromFloat(@floor(mean * 100.0 + 0.5));
    var buffer: [256]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    try writer.interface.print("{d}.{d:0>2}\n", .{ hundredths / 100, hundredths % 100 });
    try writer.interface.flush();
}
