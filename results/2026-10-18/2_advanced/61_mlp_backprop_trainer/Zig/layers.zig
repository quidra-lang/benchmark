const std = @import("std");
pub const Function = enum { TANH, SIGMOID, RELU, SOFTMAX };
pub const Layer = struct { inputs: usize, units: usize, function: Function, weights: usize,
     biases: usize, output: bool };
pub fn activation(function: Function, z: f64) f64 {
    return switch (function) {
        .TANH => std.math.tanh(z),
        .SIGMOID => 1 / (1 + @exp(-z)),
        .RELU => if (z > 0) z else 0,
        .SOFTMAX => unreachable,
    };
}
pub fn derivative(function: Function, z: f64, a: f64) f64 {
    return switch (function) {
        .TANH => 1 - a * a,
        .SIGMOID => a * (1 - a),
        .RELU => if (z > 0) @as(f64, 1) else 0,
        .SOFTMAX => unreachable,
    };
}
pub fn preactivation(weights: []const f64, input: []const f64, layer: Layer, out: []f64) void {
    for (0..layer.units) |j| {
        var sum: f64 = 0;
        for (0..layer.inputs) |i| sum += weights[layer.weights + j * layer.inputs + i] * input[i];
        out[j] = sum + weights[layer.biases + j];
    }
}
pub fn propagate(weights: []const f64, next: Layer, delta: []const f64, out: []f64) void {
    for (0..next.inputs) |j| {
        out[j] = 0;
        for (0..next.units) |k| out[j] += weights[next.weights + k * next.inputs + j] * delta[k];
    }
}
pub const Output = struct { scores: [10]f64 = [_]f64{0} ** 10, delta: [10]f64 = [_]f64{0} ** 10, loss: f64 = 0 };
pub fn output(function: Function, z: []const f64, label: usize) Output {
    var out: Output = .{};
    if (function == .SOFTMAX) {
        var maximum = z[0];
        for (z[1..]) |value| maximum = @max(maximum, value);
        var total: f64 = 0;
        for (z, 0..) |value, k| {
            out.scores[k] = @exp(value - maximum);
            total += out.scores[k];
        }
        for (0..z.len) |k| {
            out.scores[k] /= total;
            out.delta[k] = out.scores[k] - @as(f64, if (k == label) 1 else 0);
        }
        out.loss = @log(total) - (z[label] - maximum);
    } else {
        for (z, 0..) |value, k| {
            const score = 1 / (1 + @exp(-value));
            const difference = score - @as(f64, if (k == label) 1 else 0);
            out.scores[k] = score;
            out.loss += difference * difference;
            out.delta[k] = 2 * difference * score * (1 - score) / @as(f64, @floatFromInt(z.len));
        }
        out.loss /= @as(f64, @floatFromInt(z.len));
    }
    return out;
}
