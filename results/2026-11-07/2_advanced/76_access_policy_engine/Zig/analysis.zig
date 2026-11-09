const x = @import("expressions.zig");
const std = @import("std");
const Element = @import("policy_parser.zig").Element;
const Decision = @import("combining.zig").Decision;
pub const Domain = struct { reference: []const u8, candidates: []const x.Value };
pub const Days = [366]bool;
pub fn pointCount(domains: []const Domain) usize {
    var count: usize = 1;
    for (domains) |d| count *= d.candidates.len;
    return count;
}
pub fn point(domains: []const Domain, ordinal: usize) x.Attributes {
    var values: x.Attributes = .empty;
    var divisor = pointCount(domains);
    for (domains) |d| {
        divisor /= d.candidates.len;
        const index = ordinal / divisor % d.candidates.len;
        x.set(&values, d.reference, d.candidates[index]);
    }
    return values;
}
pub fn dayNotation(days: Days) []const u8 {
    var runs: std.ArrayList([]const u8) = .empty;
    var day: usize = 1;
    while (day <= 365) : (day += 1) if (days[day]) {
        const first = day;
        while (day < 365 and days[day + 1]) : (day += 1) {}
        x.append([]const u8, &runs, x.fmt("{d}-{d}", .{ first, day }));
    };
    return x.join(runs.items, ",");
}
pub fn blocker(rule: *Element, standalone: [100]Decision) ?*Element {
    for (rule.parent.?.children.items) |earlier| {
        if (earlier == rule) break;
        if (standalone[earlier.index] != .na) return earlier;
    }
    return null;
}
pub fn conflictWinner(policy: *Element, earlier: *Element, later: *Element) *Element {
    if (x.eq(policy.behavior, "first-applicable")) return earlier;
    const effect = if (x.eq(policy.behavior, "deny-overrides") or x.eq(policy.behavior, "permit-unless-deny")) "DENY" else "PERMIT";
    return if (x.eq(earlier.behavior, effect)) earlier else later;
}
