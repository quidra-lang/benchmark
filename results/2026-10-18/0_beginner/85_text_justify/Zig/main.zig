const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const paragraph = "Good software is written for people first and for machines second. A clear program explains its purpose through careful names, small functions and honest tests. When a team agrees on shared rules for internationalization, documentation and code review, every newcomer can read the code quickly, change it safely and ship new improvements with confidence instead of fear, week after week.";
    var words: [100][]const u8 = undefined;
    var count: usize = 0;
    var tokens = std.mem.splitScalar(u8, paragraph, ' ');
    while (tokens.next()) |word| {
        words[count] = word;
        count += 1;
    }
    var start: usize = 0;
    while (start < count) {
        var end = start;
        var letters: usize = 0;
        while (end < count and letters + words[end].len + (end - start) <= 30) {
            letters += words[end].len;
            end += 1;
        }
        const n = end - start;
        try out.writeByte('|');
        if (end == count or n == 1) {
            for (words[start..end], 0..) |word, i| {
                if (i > 0)
                    try out.writeByte(' ');
                try out.writeAll(word);
            }
            for (0..30 - (letters + n - 1)) |_|
                try out.writeByte(' ');
        } else {
            const spaces = 30 - letters;
            const gaps = n - 1;
            for (words[start..end], 0..) |word, i| {
                try out.writeAll(word);
                if (i < gaps) {
                    const width = spaces / gaps + @as(usize, if (i < spaces % gaps) 1 else 0);
                    for (0..width) |_|
                        try out.writeByte(' ');
                }
            }
        }
        try out.writeAll("|\n");
        start = end;
    }
    try out.flush();
}
