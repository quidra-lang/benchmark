const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const years = [_]u32{ 1900, 1988, 2000, 2019, 2024, 2026, 2032, 2100 };
    var buffer: [512]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    const out = &writer.interface;
    for (years) |year| {
        const leap = year % 4 == 0 and (year % 100 != 0 or year % 400 == 0);
        const result: []const u8 = if (leap) "leap year" else "common year";
        try out.print("{d}: {s}\n", .{ year, result });
    }
    try out.flush();
}
