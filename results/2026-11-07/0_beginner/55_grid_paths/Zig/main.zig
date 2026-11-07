const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const grid = [_][]const u8{ ".......", "..#....", "....#..", ".#.....", "...#.#.", "......." };
    for (0..2) |mode| {
        var dp: [6][7]u64 = @splat(@splat(0));
        for (0..6) |r| {
            for (0..7) |c| {
                if (mode == 1 and grid[r][c] == '#')
                    continue;
                if (r == 0 and c == 0) {
                    dp[r][c] = 1;
                    continue;
                }
                if (r > 0)
                    dp[r][c] += dp[r - 1][c];
                if (c > 0)
                    dp[r][c] += dp[r][c - 1];
            }
        }
        const label: []const u8 = if (mode == 0) "without" else "with";
        try out.print("{s} obstacles: {d}\n", .{ label, dp[5][6] });
    }
    try out.flush();
}
