const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const strings = [_][]const u8{
        "AAABBBCCCD",
        "WWWWWWWWWWWWBWWWWWWWWWWWWBBB",
        "ALGORITHM",
        "MISSISSIPPI",
        "XXXXXXXXXXYYYYYYYYYYYYYYYYYYYYYZ"
    };
    for (strings) |s| {
        var encoded: [256]u8 = undefined;
        var elen: usize = 0;
        var i: usize = 0;
        while (i < s.len) {
            var end = i + 1;
            while (end < s.len and s[end] == s[i])
                end += 1;
            const part = try std.fmt.bufPrint(encoded[elen..], "{d}{c}", .{ end - i, s[i] });
            elen += part.len;
            i = end;
        }
        var decoded: [256]u8 = undefined;
        var dlen: usize = 0;
        i = 0;
        while (i < elen) {
            var count: usize = 0;
            while (i < elen and std.ascii.isDigit(encoded[i])) : (i += 1)
                count = count * 10 + encoded[i] - '0';
            const c = encoded[i];
            i += 1;
            @memset(decoded[dlen..][0..count], c);
            dlen += count;
        }
        try out.print("{s} -> {s} -> {s}\n", .{ s, encoded[0..elen], decoded[0..dlen] });
    }
    try out.flush();
}
