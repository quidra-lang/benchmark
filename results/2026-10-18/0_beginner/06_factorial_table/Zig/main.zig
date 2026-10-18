const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var buffer: [512]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    const out = &writer.interface;
    var factorial: u32 = 1;
    var n: u32 = 0;
    while (n <= 12) : (n += 1) {
        if (n > 0)
            factorial *= n;
        try out.print("{d}! = {d}\n", .{ n, factorial });
    }
    try out.flush();
}
