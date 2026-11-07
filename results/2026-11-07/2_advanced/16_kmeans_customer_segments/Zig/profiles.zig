const std = @import("std");
const D = @import("transactions.zig");
const F = @import("features.zig");
const K = @import("kmeans.zig");
pub const Condition = struct { feature: usize, greater: bool, threshold: f64 };
pub const Rule = struct { name: []const u8, conditions: []Condition };
pub fn readRules(io: std.Io) ![]Rule {
    const lines = D.lines(try std.Io.Dir.cwd().readFileAlloc(io, "input/segment_rules.txt", D.allocator, .unlimited));
    const result = D.alloc(Rule, lines.len);
    for (lines, result) |line, *rule| {
        const words = D.split(line, ' ');
        const conditions = D.alloc(Condition, (words.len - 1) / 3);
        for (conditions, 0..) |*condition, i| {
            condition.* = .{ .feature = D.stringIndex(&F.names, words[1 + 3 * i]).?, .greater = D.eq(words[2 + 3 * i], ">"), .threshold = D.decimal(words[3 + 3 * i]) };
        }
        rule.* = .{ .name = words[0], .conditions = conditions };
    }
    return result;
}
pub fn matchingRule(rules: []const Rule, center: K.Point) usize {
    for (rules, 0..) |rule, r| {
        var holds = true;
        for (rule.conditions) |condition| {
            if (!(if (condition.greater) center[condition.feature] > condition.threshold else center[condition.feature] < condition.threshold)) { holds = false; break; }
        }
        if (holds) return r;
    }
    unreachable;
}
pub fn originalScale(center: K.Point, scaling: F.Scaling) K.Point {
    var result: K.Point = undefined;
    for (0..6) |f| {
        const value = scaling.mean[f] + scaling.sd[f] * center[f];
        result[f] = if (f >= 1 and f <= 3) value * value else value;
    }
    return result;
}
