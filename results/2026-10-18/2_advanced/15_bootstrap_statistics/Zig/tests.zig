const std = @import("std");
const D = @import("dataset.zig");
const R = @import("resampling.zig");
pub const Fraction = struct { numerator: i64, denominator: i64 };
pub fn reduced(numerator: i64, denominator: i64) Fraction {
    var first = numerator;
    var second = denominator;
    while (second != 0) { const remainder = @mod(first, second); first = second; second = remainder; }
    return .{ .numerator = @divTrunc(numerator, first), .denominator = @divTrunc(denominator, first) };
}
pub fn contrast(first: []const i64, second: []const i64) i64 { return D.n(second.len) * R.sum(first) - D.n(first.len) * R.sum(second); }
pub fn doubledRanks(values: []const i64, storage: []i64) []const i64 {
    for (values, 0..) |value, i| {
        var smaller: i64 = 0;
        var equal: i64 = 0;
        for (values) |other| { if (other < value) smaller += 1; if (other == value) equal += 1; }
        storage[i] = 2 * smaller + equal + 1;
    }
    return storage[0..values.len];
}
pub const Counts = struct { keys: [320]i64 = undefined, counts: [320]i64 = undefined, len: usize = 0 };
pub fn valueCounts(values: []const i64) Counts {
    var storage: [320]i64 = undefined;
    const ordered = storage[0..values.len];
    @memcpy(ordered, values);
    std.mem.sort(i64, ordered, {}, std.sort.asc(i64));
    var result: Counts = .{};
    for (ordered) |value| {
        if (result.len == 0 or result.keys[result.len - 1] != value) {
            result.keys[result.len] = value;
            result.counts[result.len] = 0;
            result.len += 1;
        }
        result.counts[result.len - 1] += 1;
    }
    return result;
}
pub fn divide(values: []const i64, sizes: []const usize, storage: [][]const i64) []const []const i64 {
    var start: usize = 0;
    for (sizes, 0..) |size, i| { storage[i] = values[start .. start + size]; start += size; }
    return storage[0..sizes.len];
}
pub fn nextChoice(choice: []usize, total: usize) bool {
    var i = choice.len;
    while (i > 0 and choice[i - 1] == total - choice.len + i - 1) i -= 1;
    if (i == 0) return false;
    choice[i - 1] += 1;
    while (i < choice.len) : (i += 1) choice[i] = choice[i - 1] + 1;
    return true;
}
pub const Anova = struct { between: f64 = 0, within: f64 = 0, f: f64 = 0, means: [4]f64 = undefined, count: usize = 0 };
pub fn anova(samples: []const []const i64) Anova {
    var result: Anova = .{};
    var total: i64 = 0;
    for (samples) |sample| { total += R.sum(sample); result.count += sample.len; }
    const grand = D.real(total) / D.real(100 * D.n(result.count));
    for (samples, 0..) |sample, g| {
        const center = R.mean(sample);
        const difference = center - grand;
        var within: f64 = 0;
        result.means[g] = center;
        result.between += D.real(sample.len) * (difference * difference);
        for (sample) |value| { const residual = D.real(value) / 100 - center; within += residual * residual; }
        result.within += within;
    }
    result.f = result.between / D.real(samples.len - 1) / (result.within / D.real(result.count - samples.len));
    return result;
}
pub fn kruskal(rank_groups: []const []const i64, correction: f64) f64 {
    var total: f64 = 0;
    var count: i64 = 0;
    for (rank_groups) |ranks| {
        const rank = R.sum(ranks);
        total += D.real(rank * rank) / D.real(4 * D.n(ranks.len));
        count += D.n(ranks.len);
    }
    return (12 * total / D.real(count * (count + 1)) - D.real(3 * (count + 1))) / correction;
}
