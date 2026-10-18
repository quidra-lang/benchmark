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

fn less(_: void, a: [2]i32, b: [2]i32) bool {
    return if (a[0] != b[0]) a[0] < b[0]else a[1] < b[1];
}

fn cross(o: [2]i32, a: [2]i32, b: [2]i32) i32 {
    return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]);
}

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    var points = [_][2]i32{
        .{ 3, 2 },
        .{ -6, 1 },
        .{ 8, 4 },
        .{ 0, 0 },
        .{ -3, 7 },
        .{ 4, -3 },
        .{ 1, -5 },
        .{ -2, 1 },
        .{ 5, 6 },
        .{ -6, -2 },
        .{ 2, -2 },
        .{ 7, -1 },
        .{ -3, 4 },
        .{ 2, 8 },
        .{ -6, 3 }
    };
    std.mem.sort([2]i32, &points, {}, less);
    var lower: [15][2]i32 = undefined;
    var upper: [15][2]i32 = undefined;
    var llen: usize = 0;
    var ulen: usize = 0;
    for (points) |p| {
        while (llen >= 2 and cross(lower[llen - 2], lower[llen - 1], p) <= 0)
            llen -= 1;
        lower[llen] = p;
        llen += 1;
    }
    var i = points.len;
    while (i > 0) {
        i -= 1;
        const p = points[i];
        while (ulen >= 2 and cross(upper[ulen - 2], upper[ulen - 1], p) <= 0)
            ulen -= 1;
        upper[ulen] = p;
        ulen += 1;
    }
    var hull: [30][2]i32 = undefined;
    var len: usize = 0;
    for (lower[0..llen - 1]) |p| {
        hull[len] = p;
        len += 1;
    }
    for (upper[0..ulen - 1]) |p| {
        hull[len] = p;
        len += 1;
    }
    try out.print("hull: {d} points\n", .{ len });
    var twice: i32 = 0;
    for (hull[0..len], 0..) |p, k| {
        try out.print("({d}, {d})\n", .{ p[0], p[1] });
        const q = hull[(k + 1) % len];
        twice += p[0] * q[1] - q[0] * p[1];
    }
    try out.writeAll("area: ");
    try fixed(out, @as(f64, @floatFromInt(twice)) / 2.0, 1);
    try out.writeByte('\n');
    try out.flush();
}
