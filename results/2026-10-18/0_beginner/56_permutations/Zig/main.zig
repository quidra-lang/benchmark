const std = @import("std");

fn permutations(out: *std.Io.Writer, depth: usize, used: *[4]bool, word: *[4]u8, count: *u32) std.Io.Writer.Error!void {
    if (depth == 4) {
        count.* += 1;
        try out.print("{d}: {s}\n", .{ count.*, word });
        return;
    }
    for (0..4) |i| {
        if (!used[i]) {
            used[i] = true;
            word[depth] = "ABCD"[i];
            try permutations(out, depth + 1, used, word, count);
            used[i] = false;
        }
    }
}

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    var used = [_]bool{ false } ** 4;
    var word: [4]u8 = undefined;
    var count: u32 = 0;
    try permutations(out, 0, &used, &word, &count);
    try out.flush();
}
