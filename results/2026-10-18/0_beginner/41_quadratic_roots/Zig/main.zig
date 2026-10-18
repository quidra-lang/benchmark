const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const sets = [_][3]i32{
        .{ 1, -3, -10 },
        .{ -2, 5, 4 },
        .{ 3, 1, -2 },
        .{ 4, -12, 9 },
        .{ 1, 2, 5 },
        .{ -2, 3, -4 }
    };
    for (sets) |s| {
        const a = s[0];
        const b = s[1];
        const c = s[2];
        const disc = b * b - 4 * a * c;
        const numerator = -@as(f64, @floatFromInt(b));
        const denominator = 2.0 * @as(f64, @floatFromInt(a));
        try out.print("{d} {d} {d}: ", .{ a, b, c });
        if (disc > 0) {
            const root = @sqrt(@as(f64, @floatFromInt(disc)));
            const r1 = (numerator + root) / denominator;
            const r2 = (numerator - root) / denominator;
            try out.print("x1 = {d:.4}, x2 = {d:.4}", .{ @max(r1, r2), @min(r1, r2) });
        } else if (disc == 0) {
            try out.print("x = {d:.4}", .{numerator / denominator});
        } else {
            const p = numerator / denominator;
            const q = @sqrt(@as(f64, @floatFromInt(-disc))) / (2.0 * @as(f64, @floatFromInt(@abs(a))));
            try out.print("x = {d:.4} + {d:.4}i, {d:.4} - {d:.4}i", .{ p, q, p, q });
        }
        try out.writeByte('\n');
    }
    try out.flush();
}
