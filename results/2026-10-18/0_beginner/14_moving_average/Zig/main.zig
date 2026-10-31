const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const sales = [_]u32{ 120, 135, 98, 143, 160, 152, 171, 149, 188, 176 };
    for (2..sales.len) |i| {
        const average = @as(f64, @floatFromInt(sales[i - 2] + sales[i - 1] + sales[i])) / 3.0;
        try out.print("day {d}: {d:.2}\n", .{ i + 1, average });
    }
    try out.flush();
}
