const std = @import("std");
const layer_ops = @import("layers.zig");
pub const Network = struct {
    name: []const u8,
    inputs: usize,
    classes: usize = 0,
    weight_count: usize = 0,
    param_count: usize = 0,
    layer_count: usize = 0,
    layers: [3]layer_ops.Layer = undefined,
    initial: [1066]f64 = [_]f64{0} ** 1066,
    is_weight: [1066]bool = [_]bool{false} ** 1066,
    pub fn addLayer(self: *Network, units: usize, function: layer_ops.Function, is_output: bool) void {
        const inputs = if (self.layer_count == 0) self.inputs else self.layers[self.layer_count - 1].units;
        const weights = self.param_count;
        const biases = weights + units * inputs;
        self.layers[self.layer_count] = .{ .inputs = inputs, .units = units, .function = function,
             .weights = weights, .biases = biases, .output = is_output };
        self.layer_count += 1;
        self.param_count = biases + units;
        for (weights..biases) |p| self.is_weight[p] = true;
        self.weight_count += units * inputs;
        if (is_output) self.classes = units;
    }
};
pub const Forward = struct { z: [3][12]f64 = undefined, activations: [4][64]f64 = undefined,
     scores: [10]f64, delta: [10]f64, loss: f64 };
pub fn forward(network: *const Network, weights: []const f64, input: []const f64, label: usize) Forward {
    var out: Forward = undefined;
    @memcpy(out.activations[0][0..network.inputs], input[0..network.inputs]);
    for (network.layers[0..network.layer_count], 0..) |layer, l| {
        layer_ops.preactivation(weights, out.activations[l][0..layer.inputs], layer, out.z[l][0..layer.units]);
        if (layer.output) {
            const result = layer_ops.output(layer.function, out.z[l][0..layer.units], label);
            out.scores = result.scores;
            out.delta = result.delta;
            out.loss = result.loss;
            @memcpy(out.activations[l + 1][0..layer.units], result.scores[0..layer.units]);
        } else for (0..layer.units) |j| {
            out.activations[l + 1][j] = layer_ops.activation(layer.function, out.z[l][j]);
        };
    }
    return out;
}
pub const Backward = struct { parameters: [1066]f64 = undefined, input: [64]f64 = undefined };
pub fn backward(network: *const Network, weights: []const f64, record: *const Forward) Backward {
    var errors: [3][12]f64 = undefined;
    var carried: [64]f64 = undefined;
    const last = network.layer_count - 1;
    @memcpy(errors[last][0..network.classes], record.delta[0..network.classes]);
    var l = last;
    while (l > 0) {
        l -= 1;
        const layer = network.layers[l];
        const next = network.layers[l + 1];
        layer_ops.propagate(weights, next, errors[l + 1][0..next.units], carried[0..next.inputs]);
        for (0..layer.units) |j| errors[l][j] = carried[j] * layer_ops.derivative(layer.function,
             record.z[l][j], record.activations[l + 1][j]);
    }
    var out: Backward = .{};
    layer_ops.propagate(weights, network.layers[0], errors[0][0..network.layers[0].units],
         out.input[0..network.inputs]);
    for (network.layers[0..network.layer_count], 0..) |layer, index| for (0..layer.units) |j| {
        for (0..layer.inputs) |i| out.parameters[layer.weights + j * layer.inputs + i] = errors[index][j] * record.activations[index][i];
        out.parameters[layer.biases + j] = errors[index][j];
    };
    return out;
}
