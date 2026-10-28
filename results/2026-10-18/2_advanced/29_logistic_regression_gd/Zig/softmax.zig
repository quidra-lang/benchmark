const std = @import("std");
const d = @import("dataset.zig");
const l = @import("logistic.zig");
pub const Point = struct { probabilities: []f64, loss: f64, predicted: usize };
pub fn point(weights: d.Matrix, row: []const f64, label: usize) Point {
    const scores = d.alloc(f64, weights.len);
    var maximum: f64 = -std.math.inf(f64);
    for (weights, scores) |vector, *value| {
        value.* = l.score(vector, row);
        maximum = @max(maximum, value.*);
    }
    const exponents = d.alloc(f64, weights.len);
    var total: f64 = 0;
    for (scores, exponents) |value, *e| {
        e.* = @exp(value - maximum);
        total += e.*;
    }
    const probabilities_ = d.alloc(f64, weights.len);
    var predicted: usize = 0;
    for (exponents, probabilities_, 0..) |e, *value, index| {
        value.* = e / total;
        if (value.* > probabilities_[predicted]) predicted = index;
    }
    return .{ .probabilities = probabilities_, .loss = @log(total) - (scores[label] - maximum), .predicted = predicted };
}
pub fn loss(weights: d.Matrix, data: d.Matrix, labels: []const usize) f64 {
    var total: f64 = 0;
    for (data, labels) |row, label| total += point(weights, row, label).loss;
    return total / d.f(data.len);
}
pub fn objective(weights: d.Matrix, data: d.Matrix, labels: []const usize, lambda: f64) f64 {
    var penalty: f64 = 0;
    for (weights) |vector| for (vector[1..]) |value| {
        penalty += value * value;
    };
    return loss(weights, data, labels) + lambda * penalty / 2;
}
pub fn gradient(weights: d.Matrix, data: d.Matrix, labels: []const usize, lambda: f64) d.Matrix {
    const probabilities_ = d.alloc([]f64, data.len);
    for (data, labels, probabilities_) |row, label, *values| values.* = point(weights, row, label).probabilities;
    const result = d.matrix(weights.len, weights[0].len);
    for (weights, 0..) |vector, k| for (vector, 0..) |_, j| {
        var total: f64 = 0;
        for (data, labels, probabilities_) |row, label, values| total += (values[k] - @as(f64, if (label == k) 1 else 0)) * row[j];
        result[k][j] = total / d.f(data.len);
        if (j > 0) result[k][j] += lambda * weights[k][j];
    };
    return result;
}
pub const Checkpoint = struct { iteration: usize, weights: d.Matrix };
fn copy(weights: d.Matrix) d.Matrix {
    const result = d.alloc([]f64, weights.len);
    for (weights, result) |vector, *target| target.* = d.dupe(f64, vector);
    return result;
}
pub fn train(data: d.Matrix, labels: []const usize, classes: usize, params: d.Params) []Checkpoint {
    const weights = d.matrix(classes, data[0].len);
    var result: std.ArrayList(Checkpoint) = .empty;
    d.append(Checkpoint, &result, .{ .iteration = 0, .weights = copy(weights) });
    for (1..params.softmax_iterations + 1) |iteration| {
        const delta = gradient(weights, data, labels, params.softmax_lambda);
        for (weights, delta) |vector, changes| for (vector, changes) |*value, change| {
            value.* -= params.softmax_rate * change;
        };
        if (iteration % 100 == 0) d.append(Checkpoint, &result, .{ .iteration = iteration, .weights = copy(weights) });
    }
    return result.items;
}
