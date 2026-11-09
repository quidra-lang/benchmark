const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const sales = [_]u32{ 120, 135, 98, 143, 160, 152, 171, 149, 188, 176 };
    const window = 3;
    for (window - 1..sales.len) |i| {
        var sum: u32 = 0;
        for (sales[i + 1 - window .. i + 1]) |sale| sum += sale;
        const average = @as(f64, @floatFromInt(sum)) / @as(f64, @floatFromInt(window));
        try out.print("day {d}: {d:.2}\n", .{ i + 1, average });
    }
    try out.flush();
}
