const std = @import("std");
const d = @import("dataset.zig");
fn realLess(_: void, a: f64, b: f64) bool {
    return a < b;
}
pub fn median(values: []const f64) f64 {
    const sorted = d.alloc(f64, values.len);
    @memcpy(sorted, values);
    std.mem.sort(f64, sorted, {}, realLess);
    const n = sorted.len;
    return if (n % 2 == 1) sorted[n / 2] else (sorted[n / 2 - 1] + sorted[n / 2]) / 2;
}
fn solve(lower: [3][3]f64, rhs: [3]f64, count: usize) [3]f64 {
    var eta = std.mem.zeroes([3]f64);
    var result = std.mem.zeroes([3]f64);
    for (0..count) |k| {
        var value = rhs[k];
        for (0..k) |j| value -= lower[k][j] * eta[j];
        eta[k] = value / lower[k][k];
    }
    var k = count;
    while (k > 0) {
        k -= 1;
        var value = eta[k];
        for (k + 1..count) |j| value -= lower[j][k] * result[j];
        result[k] = value / lower[k][k];
    }
    return result;
}
pub const Local = struct { value: f64, zeta: f64, weights: []f64 };
const Context = struct { x: []const i64, position: i64 };
fn neighborLess(context: Context, a: usize, b: usize) bool {
    const first = @abs(context.x[a] - context.position);
    const second = @abs(context.x[b] - context.position);
    return if (first != second) first < second else a < b;
}
pub fn localFit(data: d.Data, position: i64, span: i64, degree: usize, rho: []const f64) Local {
    const n = data.x.len;
    const q = d.u(@divTrunc(span * d.n(n), 100));
    const order = d.alloc(usize, n);
    for (order, 0..) |*value, i| value.* = i;
    std.mem.sort(usize, order, Context{ .x = data.x, .position = position }, neighborLess);
    const radius = @abs(data.x[order[q - 1]] - position);
    const used = d.zero(bool, n);
    for (order[0..q]) |j| used[j] = true;
    const v = d.zero(f64, n);
    const basis = d.zero([3]f64, n);
    const x0 = d.f(position) / 100;
    for (used, 0..) |selected, j| if (selected) {
        const a = d.f(@abs(data.x[j] - position)) / d.f(radius);
        const s = 1 - a * a * a;
        const w = s * s * s;
        const distance = data.real_x[j] - x0;
        v[j] = w * rho[j];
        basis[j][0] = 1;
        basis[j][1] = distance;
        if (degree == 2) basis[j][2] = distance * distance;
    };
    var matrix = std.mem.zeroes([3][3]f64);
    var lower = std.mem.zeroes([3][3]f64);
    var rhs = std.mem.zeroes([3]f64);
    for (0..degree + 1) |k| {
        for (0..degree + 1) |l| for (used, 0..) |selected, j| {
            if (selected) matrix[k][l] += v[j] * basis[j][k] * basis[j][l];
        };
        for (used, 0..) |selected, j| if (selected) {
            rhs[k] += v[j] * basis[j][k] * data.real_y[j];
        };
    }
    for (0..degree + 1) |k| for (0..k + 1) |l| {
        var sigma = matrix[k][l];
        for (0..l) |j| sigma -= lower[k][j] * lower[l][j];
        lower[k][l] = if (k == l) @sqrt(sigma) else sigma / lower[l][l];
    };
    const beta = solve(lower, rhs, degree + 1);
    const zeta = solve(lower, .{ 1, 0, 0 }, degree + 1);
    const weights = d.zero(f64, n);
    for (used, 0..) |selected, j| if (selected) {
        var sum: f64 = 0;
        for (0..degree + 1) |k| sum += zeta[k] * basis[j][k];
        weights[j] = v[j] * sum;
    };
    return .{ .value = beta[0], .zeta = zeta[0], .weights = weights };
}
pub const Robust = struct { scale: f64, zero: usize, change: f64 };
pub const Fit = struct { fitted: []f64, leverage: []f64, rho: []f64, edf: f64, iterations: []Robust };
pub fn fit(data: d.Data, span: i64, degree: usize, iterations: usize) Fit {
    const n = data.x.len;
    const rho = d.alloc(f64, n);
    @memset(rho, 1);
    var fitted = d.alloc(f64, n);
    for (fitted, data.x) |*value, x| value.* = localFit(data, x, span, degree, rho).value;
    var records: std.ArrayList(Robust) = .empty;
    for (0..iterations) |_| {
        const residuals = d.alloc(f64, n);
        const magnitudes = d.alloc(f64, n);
        for (data.real_y, fitted, residuals, magnitudes) |y, value, *residual, *magnitude| {
            residual.* = y - value;
            magnitude.* = @abs(residual.*);
        }
        const scale = median(magnitudes);
        var zero: usize = 0;
        for (residuals, rho) |residual, *weight| {
            const u = residual / (6 * scale);
            if (@abs(u) < 1) {
                const nu = 1 - u * u;
                weight.* = nu * nu;
            } else {
                weight.* = 0;
                zero += 1;
            }
        }
        const next = d.alloc(f64, n);
        var change: f64 = 0;
        for (next, data.x, fitted) |*value, x, old| {
            value.* = localFit(data, x, span, degree, rho).value;
            change = @max(change, @abs(value.* - old));
        }
        fitted = next;
        d.append(Robust, &records, .{ .scale = scale, .zero = zero, .change = change });
    }
    const leverage = d.alloc(f64, n);
    var edf: f64 = 0;
    for (data.x, rho, leverage) |x, weight, *value| {
        value.* = weight * localFit(data, x, span, degree, rho).zeta;
        edf += value.*;
    }
    return .{ .fitted = fitted, .leverage = leverage, .rho = rho, .edf = edf, .iterations = records.items };
}
