const std = @import("std");
const d = @import("network_io.zig");
pub fn parentRow(parents: []const usize, assignment: d.Assignment, sizes: []const usize) usize {
    var row: usize = 0;
    for (parents) |parent| row = row * sizes[parent] + assignment[parent];
    return row;
}
pub fn total(values: []const f64) f64 {
    var out: f64 = 0;
    for (values) |value| out += value;
    return out;
}
pub fn countSamples(variable: usize, parents: []const usize, samples: []const d.Assignment,
     sizes: []const usize) d.Counts {
    var count: usize = 1;
    for (parents) |parent| count *= sizes[parent];
    const rows = d.alloc([4]i64, count);
    @memset(rows, [_]i64{0} ** 4);
    for (samples) |sample| rows[parentRow(parents, sample, sizes)][sample[variable]] += 1;
    return .{ .rows = rows, .states = sizes[variable] };
}
pub fn learn(counts: d.Counts, alpha: f64) d.CPT {
    const rows = d.alloc([4]f64, counts.rows.len);
    @memset(rows, [_]f64{0} ** 4);
    for (counts.rows, rows) |counts_row, *values| {
        var denominator: f64 = 0;
        for (0..counts.states) |state| {
            values[state] = d.f(counts_row[state]) + alpha;
            denominator += values[state];
        }
        for (0..counts.states) |state| values[state] /= denominator;
    }
    return .{ .rows = rows, .states = counts.states };
}
pub fn logLikelihood(counts: d.Counts, cpt: d.CPT) f64 {
    var likelihood: f64 = 0;
    for (counts.rows, cpt.rows) |count_row, probabilities| for (0..counts.states) |state| {
        if (count_row[state] != 0) likelihood += d.f(count_row[state]) * @log(probabilities[state]);
    };
    return likelihood;
}
pub fn parameterCount(counts: d.Counts) usize {
    return (counts.states - 1) * counts.rows.len;
}
fn less(_: void, a: usize, b: usize) bool {
    return a < b;
}
pub fn familyScore(variable: usize, parent_set: []const usize, samples: []const d.Assignment,
     sizes: []const usize, alpha: f64) f64 {
    const parents = d.dupe(usize, parent_set);
    std.mem.sort(usize, parents, {}, less);
    const counts = countSamples(variable, parents, samples, sizes);
    const cpt = learn(counts, alpha);
    return logLikelihood(counts, cpt) - d.f(parameterCount(counts)) * @log(d.f(samples.len)) / 2;
}
