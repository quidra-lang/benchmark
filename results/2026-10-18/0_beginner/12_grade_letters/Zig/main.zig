const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    var counts = [_]u32{ 0 } ** 5;
    const letters = "ABCDF";
    for ([_]u32{ 78, 90, 100, 59, 80, 85, 89, 70, 45, 93 }) |score| {
        const grade: usize = if (score >= 90) 0 else if (score >= 80) 1 else if (score >= 70) 2 else if (score >= 60) 3 else 4;
        counts[grade] += 1;
        try out.print("{d}: {c}\n", .{ score, letters[grade] });
    }
    for (counts, 0..) |count, i|
        try out.print("{c}: {d}\n", .{ letters[i], count });
    try out.flush();
}
