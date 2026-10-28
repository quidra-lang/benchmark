const std = @import("std");
const c = @import("dataset.zig");
const estimators = @import("estimators.zig");
const numerics = @import("numerics.zig");
pub const Test = struct { groups: []const usize, events: [6]i64 = std.mem.zeroes([6]i64), observed: c.Vector = std.mem.zeroes(c.Vector),
     expected: c.Vector = std.mem.zeroes(c.Vector), covariance: c.Matrix = std.mem.zeroes(c.Matrix),
     statistic: f64 = 0, p: f64 = 1, degrees: usize = 0 };
pub fn finalize(test_: *Test) void {
    const size = test_.groups.len - 1;
    var difference = std.mem.zeroes(c.Vector);
    for (0..size) |g| difference[g] = test_.observed[g] - test_.expected[g];
    const solution = numerics.solve(test_.covariance, difference, size);
    test_.statistic = 0;
    for (0..size) |g| test_.statistic += difference[g] * solution[g];
    test_.degrees = size;
    test_.p = numerics.pValue(test_.statistic, size);
}
pub fn weighted(subjects: c.Subjects, groups: []const usize, kind: usize, total_subjects: usize) Test {
    var out: Test = .{ .groups = groups };
    for (estimators.eventTimes(subjects)) |time| {
        var n = std.mem.zeroes([6]i64);
        var d = std.mem.zeroes([6]i64);
        for (subjects) |subject| {
            const group = std.mem.indexOfScalar(usize, groups, subject.group).?;
            n[group] += @intFromBool(subject.time >= time);
            d[group] += @intFromBool(subject.time == time and subject.event == 1);
        }
        var risk: i64 = 0;
        var events: i64 = 0;
        for (0..groups.len) |g| {
            risk += n[g];
            events += d[g];
        }
        const weight = if (kind == 0) @as(f64, 1) else if (kind == 1) c.f(risk) / c.f(total_subjects) else @sqrt(c.f(risk) / c.f(total_subjects));
        for (0..groups.len) |g| {
            out.events[g] += d[g];
            out.observed[g] += weight * c.f(d[g]);
            out.expected[g] += weight * (c.f(events * n[g]) / c.f(risk));
            if (risk >= 2) for (0..groups.len) |h| {
                const multiplier = if (g == h) n[g] * (risk - n[g]) else -(n[g] * n[h]);
                out.covariance[g][h] += weight * weight * (c.f(events * (risk - events)) / c.f((risk - 1) * risk * risk)) * c.f(multiplier);
            };
        }
    }
    finalize(&out);
    return out;
}
pub fn combine(tests: []const Test) Test {
    var out: Test = .{ .groups = tests[0].groups };
    for (tests) |test_| for (0..out.groups.len) |g| {
        out.events[g] += test_.events[g];
        out.observed[g] += test_.observed[g];
        out.expected[g] += test_.expected[g];
        for (0..out.groups.len) |h| out.covariance[g][h] += test_.covariance[g][h];
    };
    finalize(&out);
    return out;
}
