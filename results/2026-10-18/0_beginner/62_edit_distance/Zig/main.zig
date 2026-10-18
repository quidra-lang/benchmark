const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const pairs = [_][2][]const u8{
        .{ "kitten", "sitting" },
        .{ "flaw", "lawn" },
        .{ "listen", "silent" },
        .{ "intention", "execution" },
        .{ "algorithm", "altruistic" }
    };
    for (pairs) |p| {
        const a = p[0];
        const b = p[1];
        var dp: [11][11]usize = undefined;
        for (0..a.len + 1) |i|
            dp[i][0] = i;
        for (0..b.len + 1) |j|
            dp[0][j] = j;
        for (1..a.len + 1) |i| {
            for (1..b.len + 1) |j| {
                const cost: usize = if (a[i - 1] == b[j - 1]) 0 else 1;
                dp[i][j] = @min(dp[i - 1][j] + 1, dp[i][j - 1] + 1, dp[i - 1][j - 1] + cost);
            }
        }
        try out.print("{s} -> {s}: {d}\n", .{ a, b, dp[a.len][b.len] });
    }
    try out.flush();
}
