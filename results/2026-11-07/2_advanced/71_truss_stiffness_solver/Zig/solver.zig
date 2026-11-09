const d = @import("model_io.zig");
const a = @import("assembly.zig");
pub const Cholesky = struct { lower: a.Matrix, unstable: ?usize = null };
pub fn cholesky(matrix: a.Matrix, free: []const usize) Cholesky {
    var out: Cholesky = .{ .lower = a.matrix(matrix.len) };
    for (0..matrix.len) |i| for (0..i + 1) |j| {
        var value = matrix[i][j];
        for (0..j) |h| value -= out.lower[i][h] * out.lower[j][h];
        if (j < i) out.lower[i][j] = value / out.lower[j][j] else {
            if (value <= 0.000000001 * matrix[i][i]) {
                out.unstable = free[i];
                return out;
            }
            out.lower[i][i] = @sqrt(value);
        }
    };
    return out;
}
pub fn solve(lower: a.Matrix, right: []const f64) []f64 {
    const intermediate = d.alloc(f64, right.len);
    const out = d.alloc(f64, right.len);
    for (right, 0..) |entry, i| {
        var value = entry;
        for (0..i) |h| value -= lower[i][h] * intermediate[h];
        intermediate[i] = value / lower[i][i];
    }
    var i = right.len;
    while (i > 0) {
        i -= 1;
        var value = intermediate[i];
        for (i + 1..right.len) |h| value -= lower[h][i] * out[h];
        out[i] = value / lower[i][i];
    }
    return out;
}
