const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const values = [_]i32{ 17, -8, 42, 5, -23, 36, 5, 0, -11, 29 };
    var total: i32 = 0;
    for (values) |value|
        total += value;
    const minimum, const maximum = std.mem.minMax(i32, &values);
    var buffer: [256]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    try writer.interface.print("sum: {d}\nmax: {d}\nmin: {d}\n", .{ total, maximum, minimum });
    try writer.interface.flush();
}
