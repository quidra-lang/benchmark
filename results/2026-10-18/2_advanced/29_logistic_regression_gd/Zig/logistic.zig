const d = @import("dataset.zig");
pub fn score(weights: []const f64, row: []const f64) f64 {
    var total: f64 = 0;
    for (weights, row[0..weights.len]) |weight, value| total += weight * value;
    return total;
}
pub fn sigmoid(value: f64) f64 {
    if (value >= 0) return 1 / (1 + @exp(-value));
    const e = @exp(value);
    return e / (1 + e);
}
pub fn loss(value: f64, target: usize) f64 {
    return @max(value, 0) - d.f(target) * value + @log(1 + @exp(-@abs(value)));
}
pub fn probabilities(weights: []const f64, data: d.Matrix) []f64 {
    const result = d.alloc(f64, data.len);
    for (data, result) |row, *value| value.* = sigmoid(score(weights, row));
    return result;
}
pub fn averageLoss(weights: []const f64, data: d.Matrix, targets: []const usize) f64 {
    var total: f64 = 0;
    for (data, targets) |row, target| total += loss(score(weights, row), target);
    return total / d.f(data.len);
}
pub fn objective(weights: []const f64, data: d.Matrix, targets: []const usize, lambda: f64) f64 {
    var penalty: f64 = 0;
    for (weights[1..]) |value| penalty += value * value;
    return averageLoss(weights, data, targets) + lambda * penalty / 2;
}
pub fn gradient(weights: []const f64, data: d.Matrix, targets: []const usize, lambda: f64) []f64 {
    const result = d.zeros(weights.len);
    const errors = d.alloc(f64, data.len);
    for (data, targets, errors) |row, target, *value| value.* = sigmoid(score(weights, row)) - d.f(target);
    for (result, 0..) |*value, j| {
        var total: f64 = 0;
        for (data, errors) |row, delta| total += delta * row[j];
        value.* = total / d.f(data.len);
        if (j > 0) value.* += lambda * weights[j];
    }
    return result;
}
pub fn hessian(weights: []const f64, data: d.Matrix, lambda: f64) d.Matrix {
    const probabilities_ = probabilities(weights, data);
    const variance = d.alloc(f64, data.len);
    for (probabilities_, variance) |pi, *value| value.* = pi * (1 - pi);
    const result = d.matrix(weights.len, weights.len);
    for (0..weights.len) |j| for (0..j + 1) |k| {
        var total: f64 = 0;
        for (data, variance) |row, value| total += value * row[j] * row[k];
        result[j][k] = total / d.f(data.len);
        if (j == k and j > 0) result[j][k] += lambda;
        result[k][j] = result[j][k];
    };
    return result;
}
pub fn length(values: []const f64) f64 {
    var total: f64 = 0;
    for (values) |value| total += value * value;
    return @sqrt(total);
}
