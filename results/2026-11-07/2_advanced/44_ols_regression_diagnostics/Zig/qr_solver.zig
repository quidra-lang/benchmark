const std = @import("std");
const c = @import("dataframe.zig");
pub const Fit = struct { rank: usize = 0, accepted: []const usize, alias: []bool, coefficients: c.Vector,
     effects: c.Vector, variance: c.Vector, fitted: c.Vector, residuals: c.Vector, weighted_residuals: c.Vector,
     leverage: c.Vector, triangular: c.Matrix, inverse: c.Matrix, u: c.Matrix, g: c.Matrix, rss: f64 = 0 };
pub fn fit(x: c.Matrix, y: []const f64, weights: []const f64, tolerance: f64) Fit {
    const n = x.len;
    const p = x[0].len;
    const aliases = c.alloc(bool, p);
    @memset(aliases, true);
    const coefficients = c.vector(p);
    const triangular = c.matrix(p, p);
    const inverse = c.matrix(p, p);
    const z = c.matrix(n, p);
    const working = c.matrix(n, p);
    const right = c.vector(n);
    const lengths = c.vector(p);
    for (x, y, weights, 0..) |row, response, weight, i| {
        const a = @sqrt(weight);
        right[i] = a * response;
        for (row, 0..) |value, j| z[i][j] = a * value;
        @memcpy(working[i], z[i]);
    }
    for (0..p) |j| {
        var sum: f64 = 0;
        for (0..n) |i| sum += z[i][j] * z[i][j];
        lengths[j] = @sqrt(sum);
    }
    var accepted: std.ArrayList(usize) = .empty;
    for (0..p) |j| {
        const k = accepted.items.len;
        var squares: f64 = 0;
        for (k..n) |i| squares += working[i][j] * working[i][j];
        const eta = @sqrt(squares);
        if (eta <= tolerance * lengths[j]) continue;
        c.append(usize, &accepted, j);
        aliases[j] = false;
        const alpha = if (working[k][j] >= 0) -eta else eta;
        const v = c.vector(n);
        v[k] = working[k][j] - alpha;
        for (k + 1..n) |i| v[i] = working[i][j];
        var norm: f64 = 0;
        for (v[k..]) |value| norm += value * value;
        for (0..k) |l| triangular[l][k] = working[l][j];
        triangular[k][k] = alpha;
        for (j + 1..p) |column| {
            var sum: f64 = 0;
            for (k..n) |i| sum += v[i] * working[i][column];
            const delta = 2 * sum / norm;
            for (k..n) |i| working[i][column] = working[i][column] - delta * v[i];
        }
        var sum: f64 = 0;
        for (k..n) |i| sum += v[i] * right[i];
        const delta = 2 * sum / norm;
        for (k..n) |i| right[i] = right[i] - delta * v[i];
    }
    const r = accepted.items.len;
    const effects = c.dupe(f64, right[0..r]);
    var remaining = r;
    while (remaining > 0) {
        remaining -= 1;
        const k = remaining;
        var sum: f64 = 0;
        for (k + 1..r) |l| sum += triangular[k][l] * coefficients[accepted.items[l]];
        coefficients[accepted.items[k]] = (effects[k] - sum) / triangular[k][k];
    }
    for (0..r) |m| {
        remaining = r;
        while (remaining > 0) {
            remaining -= 1;
            const l = remaining;
            var sum: f64 = 0;
            for (l + 1..r) |q| sum += triangular[l][q] * inverse[q][m];
            inverse[l][m] = ((if (l == m) @as(f64, 1) else 0) - sum) / triangular[l][l];
        }
    }
    const variance = c.vector(r);
    for (0..r) |k| for (0..r) |m| {
        variance[k] += inverse[k][m] * inverse[k][m];
    };
    var out: Fit = .{ .rank = r, .accepted = accepted.items, .alias = aliases, .coefficients = coefficients,
         .effects = effects, .variance = variance, .fitted = c.vector(n), .residuals = c.vector(n),
         .weighted_residuals = c.vector(n), .leverage = c.vector(n), .triangular = triangular, .inverse = inverse,
         .u = c.matrix(n, r), .g = c.matrix(n, r) };
    for (0..n) |i| {
        for (0..r) |k| {
            var sum: f64 = 0;
            for (0..r) |m| sum += z[i][accepted.items[m]] * inverse[m][k];
            out.u[i][k] = sum;
            out.leverage[i] += sum * sum;
        }
        for (0..r) |k| {
            var sum: f64 = 0;
            for (0..r) |m| sum += inverse[k][m] * out.u[i][m];
            out.g[i][k] = sum;
        }
        var prediction: f64 = 0;
        for (0..r) |k| prediction += x[i][accepted.items[k]] * coefficients[accepted.items[k]];
        out.fitted[i] = prediction;
        out.residuals[i] = y[i] - prediction;
        out.weighted_residuals[i] = @sqrt(weights[i]) * out.residuals[i];
        out.rss += out.weighted_residuals[i] * out.weighted_residuals[i];
    }
    return out;
}
