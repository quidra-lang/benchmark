const c = @import("dataset.zig");
const kernels = @import("kernels.zig");
const smo = @import("smo.zig");
pub const pairs = [_][2]i64{ .{ 1, 2 }, .{ 1, 3 }, .{ 2, 3 } };
pub const Multi = struct { rest: [3]smo.Model, one: [3]smo.Model };
pub const Prediction = struct { rest: [3]f64 = .{ 0, 0, 0 }, one: [3]f64 = .{ 0, 0, 0 }, scores: [3]f64 = .{ 0,
     0, 0 }, votes: [3]i64 = .{ 0, 0, 0 }, ovr: i64 = 1, ovo: i64 = 0, tie: bool = false };
pub fn train(input: c.Input, kernel: c.Kernel) Multi {
    var out: Multi = undefined;
    const matrix = kernels.matrix(kernel, input.multi_train);
    for (0..3) |k| {
        const data = c.dupe(c.Example, input.multi_train);
        for (data) |*example| example.label = if (example.label == c.n(k + 1)) 1 else -1;
        out.rest[k] = smo.train(data, kernel, matrix, input.params.multi_c, input.params);
    }
    for (pairs, 0..) |pair, k| {
        var count: usize = 0;
        for (input.multi_train) |example| {
            if (example.label == pair[0] or example.label == pair[1]) count += 1;
        }
        const data = c.alloc(c.Example, count);
        const indices = c.alloc(usize, count);
        var next: usize = 0;
        for (input.multi_train, 0..) |example, i| if (example.label == pair[0] or example.label == pair[1]) {
            data[next] = example;
            data[next].label = if (example.label == pair[0]) 1 else -1;
            indices[next] = i;
            next += 1;
        };
        const selected = c.alloc([]f64, count);
        for (selected, 0..) |*row, i| {
            row.* = c.alloc(f64, count);
            for (row.*, 0..) |*value, j| value.* = matrix[indices[i]][indices[j]];
        }
        out.one[k] = smo.train(data, kernel, selected, input.params.multi_c, input.params);
    }
    return out;
}
pub fn classify(models: *const Multi, point: c.Point) Prediction {
    var out: Prediction = .{};
    for (models.rest, 0..) |model, k| {
        out.rest[k] = model.decision(point);
        if (out.rest[k] > out.rest[c.u(out.ovr - 1)]) out.ovr = c.n(k + 1);
    }
    for (pairs, 0..) |pair, k| {
        const a = c.u(pair[0] - 1);
        const b = c.u(pair[1] - 1);
        const value = models.one[k].decision(point);
        out.one[k] = value;
        out.votes[if (value > 0) a else b] += 1;
        out.scores[a] += value;
        out.scores[b] -= value;
    }
    var maximum = out.votes[0];
    for (out.votes[1..]) |value| maximum = @max(maximum, value);
    var tied: usize = 0;
    for (out.votes, 0..) |value, k| if (value == maximum) {
        tied += 1;
        if (out.ovo == 0 or out.scores[k] > out.scores[c.u(out.ovo - 1)]) out.ovo = c.n(k + 1);
    };
    out.tie = tied > 1;
    return out;
}
