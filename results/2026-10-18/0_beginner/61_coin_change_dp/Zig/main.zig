const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const coins = [_]usize{ 1, 5, 6, 9 };
    var minimum = [_]u32{ 1000 } ** 41;
    minimum[0] = 0;
    for (1..41) |amount| {
        for (coins) |coin| {
            if (coin <= amount)
                minimum[amount] = @min(minimum[amount], minimum[amount - coin] + 1);
        }
    }
    var ways = [_]u64{ 0 } ** 41;
    ways[0] = 1;
    for (coins) |coin| {
        for (coin..41) |amount|
            ways[amount] += ways[amount - coin];
    }
    for ([_]usize{ 8, 11, 15, 22, 33, 40 }) |target| {
        var remaining = target;
        var greedy: usize = 0;
        var descending = std.mem.reverseIterator(&coins);
        while (descending.next()) |coin| {
            greedy += remaining / coin;
            remaining %= coin;
        }
        try out.print("{d}: min={d} greedy={d} ways={d}\n", .{ target, minimum[target], greedy, ways[target] });
    }
    try out.flush();
}
