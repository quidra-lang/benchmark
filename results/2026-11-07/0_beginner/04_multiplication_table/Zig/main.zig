const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var buffer: [512]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    const out = &writer.interface;
    for (1..10) |row| {
        for (1..10) |column| {
            try out.print("{d:>3}", .{row * column});
        }
        try out.writeByte('\n');
    }
    try out.flush();
}
