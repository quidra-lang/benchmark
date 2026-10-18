const std = @import("std");

fn fixed(out: *std.Io.Writer, value: f64, places: usize) !void {
    var scale: u64 = 1;
    for (0..places) |_|
        scale *= 10;
    const scaled: u64 = @intFromFloat(@floor(@abs(value) * @as(f64, @floatFromInt(scale)) + 0.5));
    if (value < 0)
        try out.writeByte('-');
    try out.print("{d}", .{ scaled / scale });
    if (places > 0)
        try out.writeByte('.');
    var divisor = scale / 10;
    while (divisor > 0) : (divisor /= 10) {
        try out.writeByte('0' + @as(u8, @intCast((scaled / divisor) % 10)));
    }
}

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const originals = [2][4][5]f64{
        .{
            .{ 2, -1, 3, 7, 0 },
            .{ 4, 1, -2, 3, 0 },
            .{ -3, 5, 1, -4, 0 },
            .{ 0, 0, 0, 0, 0 }
        },
        .{
            .{ 1, 3, -2, 4, 6 },
            .{ 5, -2, 1, 3, -7 },
            .{ -2, 4, 6, -1, 9 },
            .{ 3, 1, -4, 2, 5 }
        }
    };
    for (originals, 0..) |original, system| {
        var a = original;
        const n: usize = system + 3;
        for (0..n) |k| {
            var pivot = k;
            for (k..n) |i| {
                if (@abs(a[i][k]) > @abs(a[pivot][k]))
                    pivot = i;
            }
            if (pivot != k) {
                const temp = a[k];
                a[k] = a[pivot];
                a[pivot] = temp;
            }
            for (k + 1..n) |i| {
                const f = a[i][k] / a[k][k];
                for (k..n + 1) |j|
                    a[i][j] = a[i][j] - f * a[k][j];
            }
        }
        var x: [4]f64 = undefined;
        var i = n;
        while (i > 0) {
            i -= 1;
            var s = a[i][n];
            for (i + 1..n) |j|
                s = s - a[i][j] * x[j];
            x[i] = s / a[i][i];
        }
        try out.print("system {d}:\n", .{ system + 1 });
        for (x[0..n], 0..) |value, j| {
            try out.print("x{d} = ", .{ j + 1 });
            try fixed(out, value, 4);
            try out.writeByte('\n');
        }
    }
    try out.flush();
}
