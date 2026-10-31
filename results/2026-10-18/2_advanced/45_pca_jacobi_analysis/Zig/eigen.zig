const std = @import("std");
const c = @import("dataset.zig");
const m = @import("matrix.zig");
pub const Eigen = struct { values: c.Vector, vectors: c.Matrix, sweeps: usize };
pub const Power = struct { value: f64, vector: c.Vector, agreement: ?usize };
fn off(a: c.Matrix) f64 {
    var out: f64 = 0;
    for (0..a.len - 1) |p| for (p + 1..a.len) |q| {
        out += a[p][q] * a[p][q];
    };
    return out;
}
fn rotate(a: c.Matrix, v: c.Matrix, p: usize, q: usize) void {
    if (a[p][q] == 0) return;
    const theta = (a[q][q] - a[p][p]) / (2 * a[p][q]);
    var t = 1 / (@abs(theta) + @sqrt(theta * theta + 1));
    if (theta < 0) t = -t;
    const cosine = 1 / @sqrt(t * t + 1);
    const sine = t * cosine;
    for (0..a.len) |r| if (r != p and r != q) {
        const x = a[r][p];
        const y = a[r][q];
        a[r][p] = cosine * x - sine * y;
        a[p][r] = a[r][p];
        a[r][q] = sine * x + cosine * y;
        a[q][r] = a[r][q];
    };
    const apq = a[p][q];
    a[p][p] = a[p][p] - t * apq;
    a[q][q] = a[q][q] + t * apq;
    a[p][q] = 0;
    a[q][p] = 0;
    for (v) |row| {
        const x = row[p];
        const y = row[q];
        row[p] = cosine * x - sine * y;
        row[q] = sine * x + cosine * y;
    }
}
fn eigenLess(a: c.Matrix, x: usize, y: usize) bool {
    return if (a[x][x] != a[y][y]) a[x][x] > a[y][y] else x < y;
}
pub fn jacobi(source: c.Matrix) Eigen {
    const a = m.copy(source);
    const v = m.identity(source.len);
    const initial = off(a);
    var sweeps: usize = 0;
    if (initial > 0) for (1..101) |step| {
        for (0..a.len - 1) |p| for (p + 1..a.len) |q| {
            rotate(a, v, p, q);
        };
        const remaining = off(a);
        if (sweeps == 0 and remaining < 1e-16 * initial) sweeps = step;
        if (remaining < 1e-22 * initial) break;
    };
    const order = c.alloc(usize, a.len);
    for (order, 0..) |*value, i| value.* = i;
    std.mem.sort(usize, order, a, eigenLess);
    const values = c.vector(a.len);
    const vectors = c.alloc(c.Vector, a.len);
    for (order, 0..) |index, k| {
        values[k] = a[index][index];
        vectors[k] = m.orient(m.normalize(m.column(v, index)));
    }
    return .{ .values = values, .vectors = vectors, .sweeps = sweeps };
}
pub fn powerIteration(source: c.Matrix, references: c.Matrix) []const Power {
    const b = m.copy(source);
    const out = c.alloc(Power, references.len);
    for (references, out) |reference, *result| {
        const opposite = c.dupe(f64, reference);
        for (opposite) |*value| value.* = -value.*;
        var x = c.vector(source.len);
        @memset(x, 1);
        var agreement: ?usize = null;
        for (1..1001) |step| {
            x = m.normalize(m.multiply(b, x));
            if (agreement == null and @min(m.difference(x, reference), m.difference(x, opposite)) < 0.000001) agreement = step;
        }
        const value = m.dot(x, m.multiply(b, x));
        const values = m.orient(m.normalize(x));
        m.deflate(b, value, values);
        result.* = .{ .value = value, .vector = values, .agreement = agreement };
    }
    return out;
}
