const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const n: usize = 5;
    for (0..2 * n - 1) |row| {
        const i = if (row < n) row + 1 else 2 * n - 1 - row;
        try out.splatByteAll(' ', n - i);
        try out.splatByteAll('*', 2 * i - 1);
        try out.writeByte('\n');
    }
    try out.flush();
}
