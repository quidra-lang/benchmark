const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const names = [_][]const u8{ "tent", "stove", "lantern", "rope", "camera", "blanket", "water" };
    const weights = [_]usize{ 10, 3, 2, 3, 5, 5, 6 };
    const values = [_]u32{ 120, 65, 45, 20, 90, 85, 100 };
    var dp = [_][21]u32{ [_]u32{ 0 } ** 21 } ** 8;
    for (1..8) |i| {
        for (0..21) |capacity| {
            dp[i][capacity] = dp[i - 1][capacity];
            if (weights[i - 1] <= capacity)
                dp[i][capacity] = @max(dp[i][capacity], dp[i - 1][capacity - weights[i - 1]] + values[i - 1]);
        }
    }
    var chosen = [_]bool{ false } ** 7;
    var capacity: usize = 20;
    var i: usize = 7;
    var weight: usize = 0;
    while (i > 0) : (i -= 1) {
        if (dp[i][capacity] != dp[i - 1][capacity]) {
            chosen[i - 1] = true;
            capacity -= weights[i - 1];
            weight += weights[i - 1];
        }
    }
    try out.print("max value: {d}\ntotal weight: {d}\nitems:", .{ dp[7][20], weight });
    for (names, chosen) |name, yes| {
        if (yes)
            try out.print(" {s}", .{ name });
    }
    try out.writeByte('\n');
    try out.flush();
}
