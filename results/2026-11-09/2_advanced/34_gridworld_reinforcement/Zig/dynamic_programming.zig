const std = @import("std");
const e = @import("environment.zig");
pub fn firstMaximum(values: [4]i64) usize {
    var action: usize = 0;
    for (1..4) |a| if (values[a] > values[action]) {
        action = a;
    };
    return action;
}
pub fn bellman(model: e.Model, values: []const i64, state: usize, action: usize, gamma: i64) i64 {
    const transitions = model.transitions(state, action);
    var sum: i64 = 0;
    for (transitions.items()) |t| {
        const future = if (model.world.index[t.cell]) |next| @divFloor(gamma * values[next], 100) else 0;
        sum += t.weight * (10000 * model.reward(t.cell) + future);
    }
    return @divFloor(sum, model.q);
}
pub fn actionValues(model: e.Model, values: []const i64, gamma: i64) e.Table {
    const q = e.alloc([4]i64, values.len);
    for (q, 0..) |*row, state| for (row, 0..) |*value, action| {
        value.* = bellman(model, values, state, action, gamma);
    };
    return q;
}
pub fn greedy(q: []const [4]i64) []usize {
    const policy = e.alloc(usize, q.len);
    for (q, policy) |row, *action| action.* = firstMaximum(row);
    return policy;
}
pub const Iteration = struct { values: []i64, deltas: []i64, actions: e.Table, policy: []usize };
pub fn valueIteration(model: e.Model, gamma: i64, theta: i64) Iteration {
    var values = e.zero(i64, model.world.states.len);
    var next = e.alloc(i64, values.len);
    var deltas: std.ArrayList(i64) = .empty;
    while (true) {
        var delta: i64 = 0;
        for (next, 0..) |*value, state| {
            var actions: [4]i64 = undefined;
            for (&actions, 0..) |*q, action| q.* = bellman(model, values, state, action, gamma);
            value.* = actions[firstMaximum(actions)];
            delta = @max(delta, @as(i64, @intCast(@abs(value.* - values[state]))));
        }
        std.mem.swap([]i64, &values, &next);
        e.append(i64, &deltas, delta);
        if (delta <= theta) break;
    }
    const actions = actionValues(model, values, gamma);
    return .{ .values = values, .deltas = deltas.items, .actions = actions, .policy = greedy(actions) };
}
pub const Evaluation = struct { values: []i64, sweeps: usize };
pub fn inPlace(model: e.Model, gamma: i64, theta: i64) Evaluation {
    const values = e.zero(i64, model.world.states.len);
    var sweeps: usize = 0;
    while (true) {
        sweeps += 1;
        var delta: i64 = 0;
        for (values, 0..) |*old, state| {
            var actions: [4]i64 = undefined;
            for (&actions, 0..) |*q, action| q.* = bellman(model, values, state, action, gamma);
            const value = actions[firstMaximum(actions)];
            delta = @max(delta, @as(i64, @intCast(@abs(value - old.*))));
            old.* = value;
        }
        if (delta <= theta) return .{ .values = values, .sweeps = sweeps };
    }
}
pub fn evaluate(model: e.Model, policy: []const usize, values: []i64, gamma: i64, theta: i64) Evaluation {
    var sweeps: usize = 0;
    while (true) {
        sweeps += 1;
        var delta: i64 = 0;
        for (values, policy, 0..) |*old, action, state| {
            const value = bellman(model, values, state, action, gamma);
            delta = @max(delta, @as(i64, @intCast(@abs(value - old.*))));
            old.* = value;
        }
        if (delta <= theta) return .{ .values = values, .sweeps = sweeps };
    }
}
pub const Round = struct { sweeps: usize, changed: usize, start: i64 };
pub const PolicyIteration = struct { values: []i64, policy: []usize, rounds: []Round };
pub fn policyIteration(model: e.Model, gamma: i64, theta: i64) PolicyIteration {
    const values = e.zero(i64, model.world.states.len);
    var policy = e.zero(usize, values.len);
    var rounds: std.ArrayList(Round) = .empty;
    while (true) {
        const result = evaluate(model, policy, values, gamma, theta);
        const next = greedy(actionValues(model, values, gamma));
        var changed: usize = 0;
        for (next, policy) |a, b| if (a != b) {
            changed += 1;
        };
        e.append(Round, &rounds, .{ .sweeps = result.sweeps, .changed = changed, .start = values[model.world.index[model.world.start].?] });
        policy = next;
        if (changed == 0) return .{ .values = values, .policy = policy, .rounds = rounds.items };
    }
}
