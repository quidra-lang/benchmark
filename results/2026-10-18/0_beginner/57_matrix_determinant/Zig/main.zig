const std = @import("std");

fn det(comptime n: usize, matrix: [n][n]i64) i64 {
    if (n == 1) {
        return matrix[0][0];
    } else {
        var result: i64 = 0;
        for (0..n) |j| {
            var minor: [n - 1][n - 1]i64 = undefined;
            for (1..n) |r| {
                var col: usize = 0;
                for (0..n) |c| {
                    if (c != j) {
                        minor[r - 1][col] = matrix[r][c];
                        col += 1;
                    }
                }
            }
            const term = matrix[0][j] * det(n - 1, minor);
            result += if (j % 2 == 0) term else -term;
        }
        return result;
    }
}

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const matrix3 = [3][3]i64{
        .{ 2, -3, 1 },
        .{ 5, 4, -2 },
        .{ -1, 6, 3 },
    };
    const matrix4 = [4][4]i64{
        .{ 3, 0, -2, 5 },
        .{ 1, 4, 7, -3 },
        .{ -6, 2, 1, 8 },
        .{ 9, -5, 3, 2 },
    };
    const matrix5 = [5][5]i64{
        .{ 4, -1, 7, 0, -3 },
        .{ 2, 8, -5, 6, 1 },
        .{ -9, 3, 2, -4, 5 },
        .{ 6, 0, -7, 3, -2 },
        .{ 1, -6, 4, 9, 8 },
    };
    try out.print("det(3x3) = {d}\ndet(4x4) = {d}\ndet(5x5) = {d}\n", .{
        det(3, matrix3),
        det(4, matrix4),
        det(5, matrix5),
    });
    try out.flush();
}
