const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    var a: u32 = 1;
    var b: u32 = 1;
    var sum: u32 = 0;
    for (0..30) |i| {
        if (i > 0)
            try out.writeByte(' ');
        try out.print("{d}", .{ a });
        sum += a;
        const next = a + b;
        a = b;
        b = next;
    }
    try out.print("\nsum: {d}\n", .{ sum });
    try out.flush();
}
