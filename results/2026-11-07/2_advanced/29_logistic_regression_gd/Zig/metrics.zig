const std = @import("std");
const d = @import("dataset.zig");
pub fn real(value: f64, digits: usize) []const u8 {
    const text = if (digits == 6) d.fmt("{d:.6}", .{value}) else d.fmt("{d:.4}", .{value});
    return if (d.eq(text, "-0.0000")) "0.0000" else if (d.eq(text, "-0.000000")) "0.000000" else text;
}
pub fn ratio(a: i64, b: i64) []const u8 {
    if (b == 0) return "-";
    const value = @divTrunc(20000 * a + b, 2 * b);
    return d.fmt("{d}.{d:0>4}", .{ @divTrunc(value, 10000), @mod(value, 10000) });
}
fn gcd(first: i64, second: i64) i64 {
    var a = first;
    var b = second;
    while (b != 0) {
        const next = @mod(a, b);
        a = b;
        b = next;
    }
    return a;
}
pub const Fraction = struct {
    numerator: i64,
    denominator: i64,
    pub fn value(self: Fraction) f64 {
        return d.f(self.numerator) / d.f(self.denominator);
    }
    pub fn text(self: Fraction) []const u8 {
        const divisor = gcd(self.numerator, self.denominator);
        return d.fmt("{d}/{d} {s}", .{ @divTrunc(self.numerator, divisor), @divTrunc(self.denominator,
             divisor), ratio(self.numerator, self.denominator) });
    }
};
pub const Confusion = struct { tp: i64 = 0, fp: i64 = 0, tn: i64 = 0, fn_: i64 = 0 };
pub fn confusion(probabilities: []const f64, targets: []const usize, threshold: f64) Confusion {
    var result: Confusion = .{};
    for (probabilities, targets) |pi, target| {
        const predicted = pi >= threshold;
        if (target == 1) {
            if (predicted) result.tp += 1 else result.fn_ += 1;
        } else {
            if (predicted) result.fp += 1 else result.tn += 1;
        }
    }
    return result;
}
pub const ScoreOrder = struct { values: []const f64, descending: bool };
pub fn scoreLess(context: ScoreOrder, a: usize, b: usize) bool {
    if (context.values[a] == context.values[b]) return a < b;
    return if (context.descending) context.values[a] > context.values[b] else context.values[a] < context.values[b];
}
pub fn scoreOrder(values: []const f64, descending: bool) []usize {
    const result = d.sequence(values.len);
    std.mem.sort(usize, result, ScoreOrder{ .values = values, .descending = descending }, scoreLess);
    return result;
}
pub fn auc(scores: []const f64, targets: []const usize) Fraction {
    const order = scoreOrder(scores, false);
    var positive: i64 = 0;
    for (targets) |target| positive += d.n(target);
    var ranks: i64 = 0;
    var first: usize = 0;
    while (first < order.len) {
        var end = first + 1;
        while (end < order.len and scores[order[end]] == scores[order[first]]) end += 1;
        for (order[first..end]) |id| if (targets[id] == 1) {
            ranks += d.n(first + 1 + end);
        };
        first = end;
    }
    return .{ .numerator = ranks - positive * (positive + 1), .denominator = 2 * positive * (d.n(scores.len) - positive) };
}
pub const RocPoint = struct { threshold: f64, tp: i64, fp: i64 };
pub fn roc(probabilities: []const f64, targets: []const usize) []RocPoint {
    const order = scoreOrder(probabilities, true);
    var points: std.ArrayList(RocPoint) = .empty;
    var tp: i64 = 0;
    var fp: i64 = 0;
    var first: usize = 0;
    while (first < order.len) {
        var end = first;
        const threshold = probabilities[order[first]];
        while (end < order.len and probabilities[order[end]] == threshold) : (end += 1) {
            if (targets[order[end]] == 1) tp += 1 else fp += 1;
        }
        d.append(RocPoint, &points, .{ .threshold = threshold, .tp = tp, .fp = fp });
        first = end;
    }
    return points.items;
}
