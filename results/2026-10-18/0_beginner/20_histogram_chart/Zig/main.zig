const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const names = [_][]const u8{ "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" };
    const counts = [_]u32{ 7, 12, 4, 15, 9, 18, 11 };
    for (names, counts) |name, count| {
        try out.print("{s} | ", .{ name });
        try out.splatByteAll('*', count);
        try out.print(" {d}\n", .{ count });
    }
    try out.flush();
}
