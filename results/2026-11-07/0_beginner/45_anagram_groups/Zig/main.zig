const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const words = [_][]const u8{
        "listen", "stone", "night", "silent", "notes", "apple", "thing", "enlist", "earth", "onset",
        "heart",  "tones",
    };
    var keys: [12][26]u32 = undefined;
    for (words, 0..) |word, i| {
        keys[i] = @splat(0);
        for (word) |c|
            keys[i][c - 'a'] += 1;
    }
    var groups: [12][12]usize = undefined;
    var lengths: [12]usize = @splat(0);
    var count: usize = 0;
    for (words, 0..) |_, i| {
        var g: usize = 0;
        while (g < count and !std.mem.eql(u32, &keys[i], &keys[groups[g][0]])) : (g += 1) {}
        if (g == count) count += 1;
        groups[g][lengths[g]] = i;
        lengths[g] += 1;
    }
    for (0..count) |g| {
        for (groups[g][0..lengths[g]], 0..) |i, j| {
            if (j > 0) try out.writeByte(' ');
            try out.writeAll(words[i]);
        }
        try out.writeByte('\n');
    }
    try out.flush();
}
