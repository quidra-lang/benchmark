const std = @import("std");
const c = @import("mesh.zig");
pub fn gValue(system: *const c.System, field: []const f64, point: usize) f64 {
    var out: f64 = 0;
    for (system.faces[point]) |face| {
        if (face.neighbor) |neighbor| out += face.g * field[neighbor] else if (face.theta) |theta| out += face.g * theta;
    }
    return out + system.source_all[point];
}
pub const Iteration = struct { method: []const u8, field: []f64, changes: []const f64, omega: f64,
     converged: bool = false };
pub fn iterate(system: *const c.System, initial: f64, tolerance: f64, maximum: usize, method: []const u8,
     omega: f64) Iteration {
    const field = c.alloc(f64, system.mesh.count);
    @memset(field, initial);
    var previous: [1000]f64 = undefined;
    var changes: std.ArrayList(f64) = .empty;
    var converged = false;
    for (0..maximum) |_| {
        @memcpy(previous[0..field.len], field);
        const jacobi = c.eq(method, "jacobi");
        const seidel = c.eq(method, "gauss_seidel");
        for (field, 0..) |*value, point| {
            const next = gValue(system, if (jacobi) previous[0..field.len] else field, point) / system.diagonal[point];
            value.* = if (jacobi or seidel) next else value.* + omega * (next - value.*);
        }
        var change: f64 = 0;
        for (field, previous[0..field.len]) |after, before| change = @max(change, @abs(after - before));
        c.append(f64, &changes, change);
        if (change < tolerance) {
            converged = true;
            break;
        }
    }
    return .{ .method = method, .field = field, .changes = changes.items, .omega = omega, .converged = converged };
}
const Matrix = struct {
    data: []f64,
    width: usize,
    fn at(self: Matrix, row: usize, column: usize) *f64 {
        return &self.data[row * (2 * self.width + 1) + column + self.width - row];
    }
};
pub fn direct(system: *const c.System, right_hand_sides: []const []const f64) [][]f64 {
    const n = system.mesh.count;
    const w = system.mesh.width;
    const matrix: Matrix = .{ .data = c.alloc(f64, n * (2 * w + 1)), .width = w };
    @memset(matrix.data, 0);
    const rhs = c.alloc([]f64, right_hand_sides.len);
    for (right_hand_sides, rhs) |values, *out| out.* = c.dupe(f64, values);
    for (system.faces, 0..) |faces, point| {
        matrix.at(point, point).* = system.diagonal[point];
        for (faces) |face| if (face.neighbor) |neighbor| {
            matrix.at(point, neighbor).* = -face.g;
        };
    }
    for (0..n) |k| {
        const stop = @min(n, k + w + 1);
        for (k + 1..stop) |i| {
            const factor = matrix.at(i, k).* / matrix.at(k, k).*;
            matrix.at(i, k).* = 0;
            for (k + 1..stop) |j| matrix.at(i, j).* = matrix.at(i, j).* - factor * matrix.at(k, j).*;
            for (rhs) |values| values[i] = values[i] - factor * values[k];
        }
    }
    const solutions = c.alloc([]f64, rhs.len);
    for (rhs, solutions) |values, *solution| {
        const field = c.alloc(f64, n);
        @memset(field, 0);
        var i = n;
        while (i > 0) {
            i -= 1;
            var value = values[i];
            for (i + 1..@min(n, i + w + 1)) |j| value = value - matrix.at(i, j).* * field[j];
            field[i] = value / matrix.at(i, i).*;
        }
        solution.* = field;
    }
    return solutions;
}
pub fn residual(system: *const c.System, field: []const f64, rhs: []const f64) f64 {
    var maximum: f64 = 0;
    for (system.faces, 0..) |faces, point| {
        var value = rhs[point];
        for (faces) |face| if (face.neighbor) |neighbor| {
            value += face.g * field[neighbor];
        };
        value -= system.diagonal[point] * field[point];
        maximum = @max(maximum, @abs(value));
    }
    return maximum;
}
