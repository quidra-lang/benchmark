const std = @import("std");
const c = @import("dataset.zig");
pub fn cholesky(matrix: c.Matrix, size: usize) c.Matrix {
    var lower = std.mem.zeroes(c.Matrix);
    for (0..size) |i| for (0..i + 1) |j| {
        var sum: f64 = 0;
        for (0..j) |k| sum += lower[i][k] * lower[j][k];
        const value = matrix[i][j] - sum;
        lower[i][j] = if (i == j) @sqrt(value) else value / lower[j][j];
    };
    return lower;
}
pub fn forward(lower: c.Matrix, right: c.Vector, size: usize) c.Vector {
    var out = std.mem.zeroes(c.Vector);
    for (0..size) |i| {
        var sum: f64 = 0;
        for (0..i) |k| sum += lower[i][k] * out[k];
        out[i] = (right[i] - sum) / lower[i][i];
    }
    return out;
}
pub fn backward(lower: c.Matrix, right: c.Vector, size: usize) c.Vector {
    var out = std.mem.zeroes(c.Vector);
    var remaining = size;
    while (remaining > 0) {
        remaining -= 1;
        const i = remaining;
        var sum: f64 = 0;
        for (i + 1..size) |k| sum += lower[k][i] * out[k];
        out[i] = (right[i] - sum) / lower[i][i];
    }
    return out;
}
pub fn logDeterminant(lower: c.Matrix, size: usize) f64 {
    var sum: f64 = 0;
    for (0..size) |i| sum += @log(lower[i][i]);
    return 2 * sum;
}
pub fn quadratic(lower: c.Matrix, right: c.Vector, size: usize) f64 {
    const values = forward(lower, right, size);
    var sum: f64 = 0;
    for (values[0..size]) |value| sum += value * value;
    return sum;
}
pub const Eigen = struct { values: c.Vector = std.mem.zeroes(c.Vector), vectors: c.Matrix = std.mem.zeroes(c.Matrix),
     sweeps: usize = 0 };
pub fn jacobi(matrix: c.Matrix, size: usize) Eigen {
    var out: Eigen = .{};
    var current = matrix;
    for (0..size) |i| out.vectors[i][i] = 1;
    while (true) {
        var squares: f64 = 0;
        for (0..size - 1) |a| for (a + 1..size) |b| {
            squares += current[a][b] * current[a][b];
        };
        if (@sqrt(squares) < 1e-12 or out.sweeps == 50) break;
        for (0..size - 1) |a| for (a + 1..size) |b| {
            if (current[a][b] == 0) continue;
            const theta = (current[b][b] - current[a][a]) / (2 * current[a][b]);
            const sign: f64 = if (theta >= 0) 1 else -1;
            const t = sign / (@abs(theta) + @sqrt(theta * theta + 1));
            const co = 1 / @sqrt(t * t + 1);
            const si = t * co;
            for (0..size) |k| if (k != a and k != b) {
                const x = current[k][a];
                const y = current[k][b];
                current[k][a] = co * x - si * y;
                current[a][k] = current[k][a];
                current[k][b] = si * x + co * y;
                current[b][k] = current[k][b];
            };
            const w = current[a][b];
            current[a][a] = current[a][a] - t * w;
            current[b][b] = current[b][b] + t * w;
            current[a][b] = 0;
            current[b][a] = 0;
            for (0..size) |k| {
                const x = out.vectors[k][a];
                const y = out.vectors[k][b];
                out.vectors[k][a] = co * x - si * y;
                out.vectors[k][b] = si * x + co * y;
            }
        };
        out.sweeps += 1;
    }
    for (0..size) |i| out.values[i] = current[i][i];
    return out;
}
