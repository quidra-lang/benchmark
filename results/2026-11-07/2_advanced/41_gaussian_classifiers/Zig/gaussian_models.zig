const std = @import("std");
const c = @import("dataset.zig");
const linalg = @import("linalg.zig");
pub const Statistics = struct { count: usize, classes: usize, size: usize, counts: [5]usize = std.mem.zeroes([5]usize),
     means: [5]c.Vector = std.mem.zeroes([5]c.Vector), scatter: [5]c.Matrix = std.mem.zeroes([5]c.Matrix),
     center: c.Vector = std.mem.zeroes(c.Vector), variance: c.Vector = std.mem.zeroes(c.Vector), priors: [5]f64 = std.mem.zeroes([5]f64) };
pub fn statistics(rows: c.Rows, features: c.Features, classes: usize, empirical: bool) Statistics {
    var out: Statistics = .{ .count = rows.len, .classes = classes, .size = features.len };
    for (rows) |row| out.counts[row.label] += 1;
    for (0..classes) |k| {
        for (features, 0..) |feature, j| {
            var sum: f64 = 0;
            for (rows) |row| if (row.label == k) {
                sum += row.values[feature];
            };
            out.means[k][j] = sum / c.f(out.counts[k]);
        }
        for (features, 0..) |first, a| for (features, 0..) |second, b| {
            var sum: f64 = 0;
            for (rows) |row| if (row.label == k) {
                sum += (row.values[first] - out.means[k][a]) * (row.values[second] - out.means[k][b]);
            };
            out.scatter[k][a][b] = sum;
        };
        out.priors[k] = if (empirical) c.f(out.counts[k]) / c.f(rows.len) else 1 / c.f(classes);
    }
    for (features, 0..) |feature, j| {
        var sum: f64 = 0;
        for (rows) |row| sum += row.values[feature];
        out.center[j] = sum / c.f(rows.len);
        sum = 0;
        for (rows) |row| sum += (row.values[feature] - out.center[j]) * (row.values[feature] - out.center[j]);
        out.variance[j] = sum / c.f(rows.len);
    }
    return out;
}
pub const Model = struct { kind: usize, features: c.Features, stats: Statistics, covariance: [5]c.Matrix = std.mem.zeroes([5]c.Matrix),
     lower: [5]c.Matrix = std.mem.zeroes([5]c.Matrix), log_det: [5]f64 = std.mem.zeroes([5]f64), max_variance: f64 = 0,
     added: f64 = 0 };
pub fn train(rows: c.Rows, features: c.Features, classes: usize, kind: usize, empirical: bool, smoothing: f64, gamma: f64) Model {
    var out: Model = .{ .kind = kind, .features = features, .stats = statistics(rows, features, classes, empirical) };
    const size = features.len;
    out.max_variance = std.mem.max(f64, out.stats.variance[0..size]);
    out.added = smoothing * out.max_variance;
    for (0..classes) |k| {
        for (0..size) |a| for (0..size) |b| {
            var value: f64 = 0;
            if (kind == 0) {
                if (a == b) value = out.stats.scatter[k][a][a] / c.f(out.stats.counts[k]) + out.added;
            } else if (kind == 1) {
                var sum: f64 = 0;
                for (0..classes) |j| sum += out.stats.scatter[j][a][b];
                value = sum / c.f(rows.len - classes);
            } else {
                value = out.stats.scatter[k][a][b] / c.f(out.stats.counts[k] - 1);
                if (a != b) value = value * (1 - gamma);
            }
            out.covariance[k][a][b] = value;
        };
        out.lower[k] = linalg.cholesky(out.covariance[k], size);
        out.log_det[k] = linalg.logDeterminant(out.lower[k], size);
    }
    return out;
}
pub const Prediction = struct { predicted: usize = 0, decision: usize = 0, posterior: [5]f64 = std.mem.zeroes([5]f64),
     log_posterior: [5]f64 = std.mem.zeroes([5]f64), distance: [5]f64 = std.mem.zeroes([5]f64), confidence: f64 = 0 };
pub fn predict(model: Model, values: c.Vector, costs: [5][5]f64) Prediction {
    var out: Prediction = .{};
    const classes = model.stats.classes;
    const size = model.stats.size;
    var scores = std.mem.zeroes([5]f64);
    const h = c.f(size) * @log(2 * std.math.pi) / 2;
    for (0..classes) |k| {
        var difference = std.mem.zeroes(c.Vector);
        for (model.features, 0..) |feature, j| difference[j] = values[feature] - model.stats.means[k][j];
        out.distance[k] = linalg.quadratic(model.lower[k], difference, size);
        scores[k] = @log(model.stats.priors[k]) - h - model.log_det[k] / 2 - out.distance[k] / 2;
        if (scores[k] > scores[out.predicted]) out.predicted = k;
    }
    const maximum = scores[out.predicted];
    var sum: f64 = 0;
    for (0..classes) |k| {
        out.posterior[k] = @exp(scores[k] - maximum);
        sum += out.posterior[k];
    }
    for (0..classes) |k| {
        out.posterior[k] /= sum;
        out.log_posterior[k] = (scores[k] - maximum) - @log(sum);
    }
    out.confidence = out.posterior[out.predicted];
    var best: f64 = 0;
    for (0..classes) |b| {
        var risk: f64 = 0;
        for (0..classes) |k| risk += out.posterior[k] * costs[k][b];
        if (b == 0 or risk < best) {
            best = risk;
            out.decision = b;
        }
    }
    return out;
}
