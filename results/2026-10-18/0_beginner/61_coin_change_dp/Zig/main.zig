const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const coins = [_]usize{ 1, 5, 6, 9 };
    for ([_]usize{ 8, 11, 15, 22, 33, 40 }) |target| {
        var minimum = [_]u32{ 1000 } ** 41;
        minimum[0] = 0;
        for (1..target + 1) |amount| {
            for (coins) |coin| {
                if (coin <= amount)
                    minimum[amount] = @min(minimum[amount], minimum[amount - coin] + 1);
            }
        }
        var ways = [_]u64{ 0 } ** 41;
        ways[0] = 1;
        for (coins) |coin| {
            if (coin <= target) {
                for (coin..target + 1) |amount|
                    ways[amount] += ways[amount - coin];
            }
        }
        var remaining = target;
        var greedy: usize = 0;
        var i = coins.len;
        while (i > 0) {
            i -= 1;
            greedy += remaining / coins[i];
            remaining %= coins[i];
        }
        try out.print("{d}: min={d} greedy={d} ways={d}\n", .{ target, minimum[target], greedy, ways[target] });
    }
    try out.flush();
}
