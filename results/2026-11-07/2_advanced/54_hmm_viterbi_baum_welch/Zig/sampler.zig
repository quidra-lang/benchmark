const c = @import("model_io.zig");
const inference = @import("inference.zig");
pub const Generator = struct {
    state: i64,
    pub fn uniform(self: *Generator) f64 {
        self.state = @mod(48271 * self.state, 2147483647);
        return c.f(self.state) / 2147483647;
    }
};
pub fn draw(weights: []const f64, generator: *Generator) usize {
    var total: f64 = 0;
    for (weights) |weight| total += weight;
    const threshold = generator.uniform() * total;
    var cumulative: f64 = 0;
    for (weights, 0..) |weight, i| {
        cumulative += weight;
        if (threshold < cumulative) return i;
    }
    return weights.len - 1;
}
pub fn synthetic(model: c.Model, length: usize, generator: *Generator) c.Pair {
    const path = c.alloc(usize, length);
    const observation = c.alloc(i64, length);
    for (0..length) |t| {
        const weights = if (t == 0) model.initial[0..model.k()] else model.transition[path[t - 1]][0..model.k()];
        const state = draw(weights, generator);
        const symbol = draw(model.emission[state][0..model.m()], generator);
        path[t] = state;
        observation[t] = c.n(symbol);
    }
    return .{ .path = path, .observation = observation };
}
pub fn posteriorSample(model: c.Model, fb: inference.FB, generator: *Generator) c.Path {
    const path = c.alloc(usize, fb.forward.len);
    path[path.len - 1] = draw(fb.forward[path.len - 1][0..model.k()], generator);
    var remaining = path.len - 1;
    while (remaining > 0) {
        remaining -= 1;
        const t = remaining;
        var weights: c.StateValues = undefined;
        for (0..model.k()) |i| weights[i] = fb.forward[t][i] * model.transition[i][path[t + 1]];
        path[t] = draw(weights[0..model.k()], generator);
    }
    return path;
}
