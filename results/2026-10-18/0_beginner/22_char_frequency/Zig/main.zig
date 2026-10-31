const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const text = "Peter Piper picked a peck of pickled peppers!";
    var counts: [26]u32 = @splat(0);
    for (text) |c| {
        const lower = std.ascii.toLower(c);
        if (lower >= 'a' and lower <= 'z')
            counts[lower - 'a'] += 1;
    }
    for (counts, 0..) |count, i| {
        if (count > 0)
            try out.print("{c}: {d}\n", .{ @as(u8, @intCast(i)) + 'a', count });
    }
    try out.flush();
}
