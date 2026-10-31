const std = @import("std");
const c = @import("dataset.zig");
const stumps = @import("stumps.zig");
pub const Round = struct { stump: stumps.Stump, weights: []const f64 = &.{}, error_: f64 = 0, alpha: f64 = 0,
     z: f64 = 0, bound: f64 = 0, loss: f64 = 0, polarity: i64 = 0 };
pub const Model = struct { variant: []const u8, stop: []const u8 = "completed", rounds: []const Round,
     cuts: []const []const f64 = &.{} };
fn sum(values: []const f64) f64 {
    var out: f64 = 0;
    for (values) |value| out += value;
    return out;
}
pub fn discrete(rows: []const c.Row, p: c.Params, maximum: usize, shrinkage: f64, initial: ?[]const f64) Model {
    _ = p;
    const weights = if (initial) |values| c.dupe(f64, values) else c.vector(rows.len);
    if (initial == null) @memset(weights, 1 / c.f(rows.len));
    const search = stumps.prepare(rows, 0);
    var rounds: std.ArrayList(Round) = .empty;
    var reason: []const u8 = "completed";
    var bound: f64 = 1;
    for (0..maximum) |_| {
        const candidate = stumps.discrete(rows, search, weights);
        const e = candidate.error_;
        if (e >= 0.5) {
            reason = "weak";
            break;
        }
        const alpha = if (e <= 0.0000000001) @as(f64, 1) else shrinkage * (0.5 * @log((1 - e) / e));
        const values = c.dupe(f64, candidate.stump.values);
        for (values) |*value| value.* = value.* * alpha;
        var round: Round = .{ .stump = .{ .feature = candidate.stump.feature, .thresholds = candidate.stump.thresholds,
             .values = values }, .weights = c.dupe(f64, weights), .error_ = e, .alpha = alpha, .polarity = candidate.polarity };
        for (rows, weights) |row, *weight| {
            const decision = candidate.stump.output(row.values);
            weight.* = weight.* * @exp(if (decision == c.f(row.label)) -alpha else alpha);
        }
        round.z = sum(weights);
        for (weights) |*weight| weight.* = weight.* / round.z;
        bound = bound * round.z;
        round.bound = bound;
        c.append(Round, &rounds, round);
        if (e <= 0.0000000001) {
            reason = "perfect";
            break;
        }
    }
    return .{ .variant = "discrete", .stop = reason, .rounds = rounds.items };
}
pub fn samme(rows: []const c.Row, p: c.Params) Model {
    const search = stumps.prepare(rows, 0);
    const weights = c.vector(rows.len);
    @memset(weights, 1 / c.f(rows.len));
    var rounds: std.ArrayList(Round) = .empty;
    var reason: []const u8 = "completed";
    for (0..p.samme_rounds) |_| {
        const candidate = stumps.multiclass(rows, search, weights, p.classes);
        const e = candidate.error_;
        if (e >= c.f(p.classes - 1) / c.f(p.classes)) {
            reason = "weak";
            break;
        }
        const alpha = if (e <= 0.0000000001) @as(f64, 1) else @log((1 - e) / e) + @log(c.f(p.classes - 1));
        for (rows, weights) |row, *weight| if (candidate.stump.output(row.values) != c.f(row.label)) {
            weight.* = weight.* * @exp(alpha);
        };
        const normalizer = sum(weights);
        for (weights) |*weight| weight.* = weight.* / normalizer;
        c.append(Round, &rounds, .{ .stump = candidate.stump, .error_ = e, .alpha = alpha });
        if (e <= 0.0000000001) {
            reason = "perfect";
            break;
        }
    }
    return .{ .variant = "samme", .stop = reason, .rounds = rounds.items };
}
