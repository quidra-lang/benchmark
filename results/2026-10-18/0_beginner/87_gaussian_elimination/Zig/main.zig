const std = @import("std");

fn solve(out: *std.Io.Writer, comptime n: usize, system: usize, matrix: [n][n + 1]f64) !void {
    var a = matrix;
    for (0..n) |k| {
        var pivot = k;
        for (k..n) |i| {
            if (@abs(a[i][k]) > @abs(a[pivot][k]))
                pivot = i;
        }
        if (pivot != k) {
            std.mem.swap([n + 1]f64, &a[k], &a[pivot]);
        }
        for (k + 1..n) |i| {
            const f = a[i][k] / a[k][k];
            for (k..n + 1) |j|
                a[i][j] = a[i][j] - f * a[k][j];
        }
    }
    var x: [n]f64 = undefined;
    var i = n;
    while (i > 0) {
        i -= 1;
        var s = a[i][n];
        for (i + 1..n) |j|
            s = s - a[i][j] * x[j];
        x[i] = s / a[i][i];
    }
    try out.print("system {d}:\n", .{system});
    for (x, 0..) |value, j|
        try out.print("x{d} = {d:.4}\n", .{ j + 1, value });
}

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    try solve(out, 3, 1, .{
        .{ 2, -1, 3, 7 },
        .{ 4, 1, -2, 3 },
        .{ -3, 5, 1, -4 },
    });
    try solve(out, 4, 2, .{
        .{ 1, 3, -2, 4, 6 },
        .{ 5, -2, 1, 3, -7 },
        .{ -2, 4, 6, -1, 9 },
        .{ 3, 1, -4, 2, 5 },
    });
    try out.flush();
}
