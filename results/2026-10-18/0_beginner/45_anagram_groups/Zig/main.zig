const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const words = [_][]const u8{
        "listen",
        "stone",
        "night",
        "silent",
        "notes",
        "apple",
        "thing",
        "enlist",
        "earth",
        "onset",
        "heart",
        "tones"
    };
    var keys: [12][26]u32 = undefined;
    for (words, 0..) |word, i| {
        keys[i] = [_]u32{ 0 } ** 26;
        for (word) |c|
            keys[i][c - 'a'] += 1;
    }
    var used = [_]bool{ false } ** 12;
    for (words, 0..) |_, i| {
        if (used[i])
            continue;
        var first = true;
        for (i..words.len) |j| {
            if (std.mem.eql(u32, &keys[i], &keys[j])) {
                if (!first)
                    try out.writeByte(' ');
                try out.writeAll(words[j]);
                used[j] = true;
                first = false;
            }
        }
        try out.writeByte('\n');
    }
    try out.flush();
}
