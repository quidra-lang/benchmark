const std = @import("std");
const c = @import("dataset.zig");
const numerics = @import("numerics.zig");
pub const Time = struct { time: i64, events: usize, s0: f64, s1: c.Vector };
pub const Evaluation = struct { loglik: f64 = 0, score: c.Vector = std.mem.zeroes(c.Vector), information: c.Matrix = std.mem.zeroes(c.Matrix),
     theta: []f64, risks: []f64, times: std.ArrayList(Time) = .empty };
fn timeLess(subjects: c.Subjects, a: usize, b: usize) bool {
    return if (subjects[a].time != subjects[b].time) subjects[a].time > subjects[b].time else subjects[a].id < subjects[b].id;
}
pub fn evaluate(subjects: c.Subjects, design: []const c.Vector, size: usize, beta: c.Vector) Evaluation {
    var out: Evaluation = .{ .theta = c.alloc(f64, subjects.len), .risks = c.alloc(f64, subjects.len) };
    for (subjects, 0..) |_, j| {
        var theta: f64 = 0;
        for (0..size) |column| theta += beta[column] * design[j][column];
        out.theta[j] = theta;
        out.risks[j] = @exp(theta);
    }
    const order = c.alloc(usize, subjects.len);
    for (order, 0..) |*value, i| value.* = i;
    std.mem.sort(usize, order, subjects, timeLess);
    var s0: f64 = 0;
    var s1 = std.mem.zeroes(c.Vector);
    var s2 = std.mem.zeroes(c.Matrix);
    var first: usize = 0;
    while (first < order.len) {
        const time = subjects[order[first]].time;
        var last = first;
        while (last < order.len and subjects[order[last]].time == time) {
            const j = order[last];
            s0 += out.risks[j];
            for (0..size) |column| {
                s1[column] += out.risks[j] * design[j][column];
                for (0..size) |d| s2[column][d] += out.risks[j] * design[j][column] * design[j][d];
            }
            last += 1;
        }
        var events: usize = 0;
        var theta_sum: f64 = 0;
        var x_sum = std.mem.zeroes(c.Vector);
        for (order[first..last]) |i| {
            if (subjects[i].event == 0) continue;
            events += 1;
            theta_sum += out.theta[i];
            for (0..size) |column| x_sum[column] += design[i][column];
        }
        if (events > 0) {
            out.loglik += theta_sum - c.f(events) * @log(s0);
            for (0..size) |column| {
                out.score[column] += x_sum[column] - c.f(events) * s1[column] / s0;
                for (0..size) |d| out.information[column][d] += c.f(events) * (s2[column][d] / s0 - (s1[column] / s0) * (s1[d] / s0));
            }
            c.append(Time, &out.times, .{ .time = time, .events = events, .s0 = s0, .s1 = s1 });
        }
        first = last;
    }
    return out;
}
pub const Iteration = struct { loglik: f64, beta: c.Vector };
pub const Fit = struct { beta: c.Vector = std.mem.zeroes(c.Vector), initial: Evaluation, final: Evaluation,
     iterations: [25]Iteration };
pub fn fit(subjects: c.Subjects, design: []const c.Vector, size: usize) Fit {
    var beta = std.mem.zeroes(c.Vector);
    const initial = evaluate(subjects, design, size, beta);
    var current = initial;
    var iterations: [25]Iteration = undefined;
    for (&iterations) |*iteration| {
        const delta = numerics.solve(current.information, current.score, size);
        for (0..size) |column| beta[column] = beta[column] + delta[column];
        iteration.* = .{ .loglik = current.loglik, .beta = beta };
        current = evaluate(subjects, design, size, beta);
    }
    return .{ .beta = beta, .initial = initial, .final = current, .iterations = iterations };
}
