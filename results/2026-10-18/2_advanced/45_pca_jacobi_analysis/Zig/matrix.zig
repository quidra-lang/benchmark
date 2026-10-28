const c = @import("dataset.zig");
pub fn identity(size: usize) c.Matrix {
    const out = c.matrix(size, size);
    for (0..size) |i| out[i][i] = 1;
    return out;
}
pub fn copy(source: c.Matrix) c.Matrix {
    const out = c.alloc(c.Vector, source.len);
    for (source, out) |row, *destination| destination.* = c.dupe(f64, row);
    return out;
}
pub fn column(source: c.Matrix, index: usize) c.Vector {
    const out = c.vector(source.len);
    for (source, out) |row, *value| value.* = row[index];
    return out;
}
pub fn dot(a: []const f64, b: []const f64) f64 {
    var out: f64 = 0;
    for (a, b) |x, y| out += x * y;
    return out;
}
pub fn multiply(source: c.Matrix, values: []const f64) c.Vector {
    const out = c.vector(source.len);
    for (source, out) |row, *value| value.* = dot(row, values);
    return out;
}
pub fn normalize(values: c.Vector) c.Vector {
    const length = @sqrt(dot(values, values));
    for (values) |*value| value.* = value.* / length;
    return values;
}
pub fn orient(values: c.Vector) c.Vector {
    var largest: usize = 0;
    for (values[1..], 1..) |value, j| if (@abs(value) > @abs(values[largest])) {
        largest = j;
    };
    if (values[largest] < 0) for (values) |*value| {
        value.* = -value.*;
    };
    return values;
}
pub fn difference(a: []const f64, b: []const f64) f64 {
    var out: f64 = 0;
    for (a, b) |x, y| out = @max(out, @abs(x - y));
    return out;
}
pub fn deflate(source: c.Matrix, value: f64, values: []const f64) void {
    for (source, 0..) |row, i| for (row, 0..) |*entry, j| {
        entry.* = entry.* - value * values[i] * values[j];
    };
}
pub const Inverse = struct { inverse: c.Matrix, determinant: f64 };
pub fn inverseDeterminant(source: c.Matrix) Inverse {
    const n = source.len;
    const work = c.matrix(n, 2 * n);
    for (source, 0..) |row, i| {
        @memcpy(work[i][0..n], row);
        work[i][n + i] = 1;
    }
    var determinant: f64 = 1;
    for (0..n) |k| {
        const pivot = work[k][k];
        determinant *= pivot;
        for (work[k]) |*value| value.* = value.* / pivot;
        for (0..n) |i| if (i != k) {
            const gamma = work[i][k];
            for (0..2 * n) |h| work[i][h] = work[i][h] - gamma * work[k][h];
        };
    }
    const out = c.matrix(n, n);
    for (out, 0..) |row, i| @memcpy(row, work[i][n..]);
    return .{ .inverse = out, .determinant = determinant };
}
