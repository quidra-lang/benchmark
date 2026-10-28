const std = @import("std");
const c = @import("dataset.zig");
const stumps = @import("stumps.zig");
const adaboost = @import("adaboost.zig");
fn sum(values: []const f64) f64 {
    var out: f64 = 0;
    for (values) |value| out += value;
    return out;
}
pub fn train(rows: []const c.Row, p: c.Params, variant: []const u8) adaboost.Model {
    if (c.eq(variant, "discrete")) return adaboost.discrete(rows, p, p.rounds, 1, null);
    const search = stumps.prepare(rows, if (c.eq(variant, "real")) p.bins else 0);
    const cuts = c.alloc([]const f64, search.features.len);
    for (search.features, cuts) |feature, *values| values.* = feature.cuts;
    const weights = c.vector(rows.len);
    @memset(weights, 1 / c.f(rows.len));
    const score = c.vector(rows.len);
    const probability = c.vector(rows.len);
    @memset(probability, 0.5);
    const targets = c.vector(rows.len);
    var bound: f64 = 1;
    var rounds: std.ArrayList(adaboost.Round) = .empty;
    var reason: []const u8 = "completed";
    for (0..p.rounds) |_| {
        var round: adaboost.Round = undefined;
        if (c.eq(variant, "real")) {
            const candidate = stumps.realStump(rows, search, weights, p.bins, p.smoothing);
            if (candidate.z >= 1 - p.convergence) {
                reason = "converged";
                break;
            }
            bound = bound * candidate.z;
            round = .{ .stump = candidate.stump, .z = candidate.z, .bound = bound, .weights = c.dupe(f64, weights) };
        } else {
            if (c.eq(variant, "gentle")) {
                for (rows, targets) |row, *target| target.* = c.f(row.label);
            } else {
                const q = c.vector(rows.len);
                for (rows, 0..) |row, i| {
                    q[i] = probability[i] * (1 - probability[i]);
                    const z = ((if (row.label == 1) @as(f64, 1) else 0) - probability[i]) / q[i];
                    targets[i] = if (z > p.clip) p.clip else if (z < -p.clip) -p.clip else z;
                }
                const total = sum(q);
                for (weights, q) |*weight, value| weight.* = value / total;
            }
            const candidate = stumps.regression(rows, search, targets, weights);
            var stump = candidate.stump;
            if (c.eq(variant, "logit")) {
                const values = c.dupe(f64, stump.values);
                for (values) |*value| value.* = value.* / 2;
                stump.values = values;
            }
            round = .{ .stump = stump, .error_ = candidate.error_, .weights = c.dupe(f64, weights) };
        }
        if (c.eq(variant, "logit")) {
            var loss: f64 = 0;
            for (rows, 0..) |row, i| {
                score[i] = score[i] + round.stump.output(row.values);
                probability[i] = 1 / (1 + @exp(-2 * score[i]));
                loss += @log(1 + @exp(-2 * c.f(row.label) * score[i]));
            }
            round.loss = loss / c.f(rows.len);
        } else {
            for (rows, weights) |row, *weight| weight.* = weight.* * @exp(-c.f(row.label) * round.stump.output(row.values));
            const total = sum(weights);
            for (weights) |*weight| weight.* = weight.* / total;
        }
        c.append(adaboost.Round, &rounds, round);
    }
    return .{ .variant = variant, .stop = reason, .rounds = rounds.items, .cuts = cuts };
}
