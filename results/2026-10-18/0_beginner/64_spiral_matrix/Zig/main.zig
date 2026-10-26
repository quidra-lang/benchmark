const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    var matrix: [5][6]u32 = @splat(@splat(0));
    const directions = [_][2]i32{ .{ 0, 1 }, .{ 1, 0 }, .{ 0, -1 }, .{ -1, 0 } };
    var r: i32 = 0;
    var c: i32 = 0;
    var d: usize = 0;
    for (1..31) |value| {
        matrix[@intCast(r)][@intCast(c)] = @intCast(value);
        if (value == 30)
            break;
        var nr = r + directions[d][0];
        var nc = c + directions[d][1];
        if (nr < 0 or nr >= 5 or nc < 0 or nc >= 6 or matrix[@intCast(nr)][@intCast(nc)] != 0) {
            d = (d + 1) % 4;
            nr = r + directions[d][0];
            nc = c + directions[d][1];
        }
        r = nr;
        c = nc;
    }
    for (matrix) |row| {
        for (row) |v|
            try out.print("{d:>3}", .{v});
        try out.writeByte('\n');
    }
    try out.flush();
}
