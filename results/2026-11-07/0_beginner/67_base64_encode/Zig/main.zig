const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    for ([_][]const u8{ "Man", "Hello, World!", "", "<b>bold</b>", "a+b=c?" }) |s| {
        var encoded: [128]u8 = undefined;
        var len: usize = 0;
        var i: usize = 0;
        while (i < s.len) : (i += 3) {
            const remaining = s.len - i;
            const b0: u32 = s[i];
            const b1: u32 = if (remaining > 1) s[i + 1] else 0;
            const b2: u32 = if (remaining > 2) s[i + 2] else 0;
            const value = (b0 << 16) | (b1 << 8) | b2;
            encoded[len] = alphabet[(value >> 18) & 63];
            len += 1;
            encoded[len] = alphabet[(value >> 12) & 63];
            len += 1;
            encoded[len] = if (remaining > 1) alphabet[(value >> 6) & 63] else '=';
            len += 1;
            encoded[len] = if (remaining > 2) alphabet[value & 63] else '=';
            len += 1;
        }
        try out.print("\"{s}\" -> \"{s}\"\n", .{ s, encoded[0..len] });
    }
    try out.flush();
}
