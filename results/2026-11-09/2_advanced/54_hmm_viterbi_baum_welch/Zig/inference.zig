const c = @import("model_io.zig");
pub const FB = struct { forward: []c.StateValues, backward: []c.StateValues, posterior: []c.StateValues,
     emissions: []c.StateValues, scales: []f64, loglik: f64 = 0 };
pub const Viterbi = struct { path: c.Path, logprob: f64 };
pub const Decoding = struct { fb: FB, viterbi: Viterbi, posterior: c.Path, confidence: []const f64 };
pub fn maximum(values: []const f64) usize {
    var chosen: usize = 0;
    for (values[1..], 1..) |value, i| if (value > values[chosen]) {
        chosen = i;
    };
    return chosen;
}
pub fn emission(model: c.Model, observation: i64, state: usize) f64 {
    return if (observation < 0) 1 else model.emission[state][c.u(observation)];
}
pub fn forwardBackward(model: c.Model, observation: c.Observation) FB {
    const length = observation.len;
    const k = model.k();
    var out: FB = .{ .forward = c.alloc(c.StateValues, length), .backward = c.alloc(c.StateValues,
         length), .posterior = c.alloc(c.StateValues, length), .emissions = c.alloc(c.StateValues,
         length), .scales = c.alloc(f64, length) };
    @memset(out.forward, .{ 0, 0, 0, 0 });
    @memset(out.backward, .{ 0, 0, 0, 0 });
    @memset(out.posterior, .{ 0, 0, 0, 0 });
    @memset(out.emissions, .{ 0, 0, 0, 0 });
    @memset(out.scales, 0);
    for (observation, 0..) |symbol, t| {
        for (0..k) |j| {
            out.emissions[t][j] = emission(model, symbol, j);
            var value = model.initial[j];
            if (t > 0) {
                value = 0;
                for (0..k) |i| value += out.forward[t - 1][i] * model.transition[i][j];
            }
            out.forward[t][j] = value * out.emissions[t][j];
            out.scales[t] += out.forward[t][j];
        }
        for (0..k) |j| out.forward[t][j] /= out.scales[t];
        out.loglik += @log(out.scales[t]);
    }
    for (0..k) |i| out.backward[length - 1][i] = 1;
    var remaining = length - 1;
    while (remaining > 0) {
        remaining -= 1;
        const t = remaining;
        for (0..k) |i| {
            var sum: f64 = 0;
            for (0..k) |j| sum += model.transition[i][j] * out.emissions[t + 1][j] * out.backward[t + 1][j];
            out.backward[t][i] = sum / out.scales[t + 1];
        }
    }
    for (0..length) |t| for (0..k) |i| {
        out.posterior[t][i] = out.forward[t][i] * out.backward[t][i];
    };
    return out;
}
pub fn transitionPosterior(model: c.Model, fb: FB, t: usize, i: usize, j: usize) f64 {
    return fb.forward[t][i] * model.transition[i][j] * fb.emissions[t + 1][j] * fb.backward[t + 1][j] / fb.scales[t + 1];
}
pub fn viterbi(model: c.Model, observation: c.Observation) Viterbi {
    const k = model.k();
    const length = observation.len;
    var transitions: c.Matrix = undefined;
    for (0..k) |i| for (0..k) |j| {
        transitions[i][j] = @log(model.transition[i][j]);
    };
    var predecessors: [300][4]usize = undefined;
    var scores: c.StateValues = .{ 0, 0, 0, 0 };
    for (0..k) |j| scores[j] = @log(model.initial[j]) + (if (observation[0] < 0) 0 else @log(model.emission[j][c.u(observation[0])]));
    for (observation[1..], 1..) |symbol, t| {
        var next: c.StateValues = .{ 0, 0, 0, 0 };
        for (0..k) |j| {
            var candidates: c.StateValues = undefined;
            for (0..k) |i| candidates[i] = scores[i] + transitions[i][j];
            const previous = maximum(candidates[0..k]);
            predecessors[t][j] = previous;
            next[j] = candidates[previous] + (if (symbol < 0) 0 else @log(model.emission[j][c.u(symbol)]));
        }
        scores = next;
    }
    const path = c.alloc(usize, length);
    path[length - 1] = maximum(scores[0..k]);
    const logprob = scores[path[length - 1]];
    var remaining = length - 1;
    while (remaining > 0) {
        path[remaining - 1] = predecessors[remaining][path[remaining]];
        remaining -= 1;
    }
    return .{ .path = path, .logprob = logprob };
}
pub fn decode(model: c.Model, observation: c.Observation) Decoding {
    const fb = forwardBackward(model, observation);
    const path = viterbi(model, observation);
    const posterior = c.alloc(usize, observation.len);
    const confidence = c.alloc(f64, observation.len);
    for (fb.posterior, posterior, confidence) |row, *state, *value| {
        state.* = maximum(row[0..model.k()]);
        value.* = row[state.*];
    }
    return .{ .fb = fb, .viterbi = path, .posterior = posterior, .confidence = confidence };
}
