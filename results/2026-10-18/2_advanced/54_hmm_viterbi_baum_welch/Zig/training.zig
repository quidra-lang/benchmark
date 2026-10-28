const std = @import("std");
const c = @import("model_io.zig");
const inference = @import("inference.zig");
fn smoothed(original: c.Model, source_initial: c.StateValues, source_transition: c.Matrix, source_emissions: c.Emissions,
     alpha: f64, name: []const u8) c.Model {
    var out = original;
    out.name = name;
    out.initial = source_initial;
    out.transition = source_transition;
    out.emission = source_emissions;
    for (0..out.k()) |i| {
        out.initial[i] += alpha;
        for (0..out.k()) |j| out.transition[i][j] += alpha;
        for (0..out.m()) |j| out.emission[i][j] += alpha;
        c.normalize(out.transition[i][0..out.k()]);
        c.normalize(out.emission[i][0..out.m()]);
    }
    c.normalize(out.initial[0..out.k()]);
    return out;
}
pub fn baumWelch(model: c.Model, observations: []const c.Observation, alpha: f64) c.Model {
    var initial: c.StateValues = .{ 0, 0, 0, 0 };
    var transition: c.Matrix = [_][4]f64{.{ 0, 0, 0, 0 }} ** 4;
    var emissions: c.Emissions = [_][8]f64{.{ 0, 0, 0, 0, 0, 0, 0, 0 }} ** 4;
    for (observations) |observation| {
        var scratch = std.heap.ArenaAllocator.init(c.backing_allocator);
        const permanent = c.allocator;
        c.allocator = scratch.allocator();
        const fb = inference.forwardBackward(model, observation);
        for (0..model.k()) |i| initial[i] += fb.posterior[0][i];
        for (observation, 0..) |symbol, t| for (0..model.k()) |i| {
            if (symbol >= 0) emissions[i][c.u(symbol)] += fb.posterior[t][i];
            if (t + 1 < observation.len) for (0..model.k()) |j| {
                transition[i][j] += inference.transitionPosterior(model, fb, t, i, j);
            };
        };
        c.allocator = permanent;
        scratch.deinit();
    }
    return smoothed(model, initial, transition, emissions, alpha, "BAUM_WELCH");
}
pub fn counting(model: c.Model, pairs: []const c.Pair, alpha: f64, name: []const u8) c.Model {
    var initial: c.StateValues = .{ 0, 0, 0, 0 };
    var transition: c.Matrix = [_][4]f64{.{ 0, 0, 0, 0 }} ** 4;
    var emissions: c.Emissions = [_][8]f64{.{ 0, 0, 0, 0, 0, 0, 0, 0 }} ** 4;
    for (pairs) |pair| {
        initial[pair.path[0]] += 1;
        for (pair.path, 0..) |state, t| {
            if (pair.observation[t] >= 0) emissions[state][c.u(pair.observation[t])] += 1;
            if (t + 1 < pair.path.len) transition[state][pair.path[t + 1]] += 1;
        }
    }
    return smoothed(model, initial, transition, emissions, alpha, name);
}
pub fn totalLoglik(model: c.Model, observations: []const c.Observation) f64 {
    var sum: f64 = 0;
    for (observations) |observation| {
        var scratch = std.heap.ArenaAllocator.init(c.backing_allocator);
        const permanent = c.allocator;
        c.allocator = scratch.allocator();
        sum += inference.forwardBackward(model, observation).loglik;
        c.allocator = permanent;
        scratch.deinit();
    }
    return sum;
}
