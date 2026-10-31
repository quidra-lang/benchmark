const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const values = [_]i32{ 48, 73, 56, 91, 35, 62, 84 };
    var total: i32 = 0;
    for (values) |value|
        total += value;
    const mean = @as(f64, @floatFromInt(total)) / @as(f64, @floatFromInt(values.len));
    var buffer: [256]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    try writer.interface.print("{d:.2}\n", .{mean});
    try writer.interface.flush();
}
