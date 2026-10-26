const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    var black: [11][11]bool = @splat(@splat(false));
    const directions = [_][2]i32{ .{ -1, 0 }, .{ 0, 1 }, .{ 1, 0 }, .{ 0, -1 } };
    var r: i32 = 5;
    var c: i32 = 5;
    var d: usize = 0;
    for (0..300) |_| {
        const rr: usize = @intCast(r);
        const cc: usize = @intCast(c);
        d = (d + (if (black[rr][cc]) @as(usize, 3) else 1)) % 4;
        black[rr][cc] = !black[rr][cc];
        r = @mod(r + directions[d][0], 11);
        c = @mod(c + directions[d][1], 11);
    }
    var count: u32 = 0;
    for (black, 0..) |row, i| {
        for (row, 0..) |cell, j| {
            if (cell)
                count += 1;
            const ant = i == @as(usize, @intCast(r)) and j == @as(usize, @intCast(c));
            try out.writeByte(if (ant) 'A' else if (cell) '#' else '.');
        }
        try out.writeByte('\n');
    }
    try out.print("black: {d}\n", .{count});
    try out.flush();
}
