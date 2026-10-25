const std = @import("std");
const b = @import("baskets.zig");
pub const Fraction = struct {
    n: i64, d: i64,
    pub fn init(numerator: i64, denominator: i64) Fraction { var left = @abs(numerator); var right: u64 = @intCast(denominator); while (right != 0) { const remainder = left % right; left = right; right = remainder; } const divisor: i64 = @intCast(left); return .{ .n = @divTrunc(numerator, divisor), .d = @divTrunc(denominator, divisor) }; }
    pub fn compare(a: Fraction, c: Fraction) std.math.Order { return std.math.order(a.n * c.d, c.n * a.d); }
    pub fn sub(a: Fraction, c: Fraction) Fraction { return init(a.n * c.d - c.n * a.d, a.d * c.d); }
    pub fn mul(a: Fraction, c: Fraction) Fraction { return init(a.n * c.n, a.d * c.d); }
    pub fn negative(a: Fraction) Fraction { return .{ .n = -a.n, .d = a.d }; }
};
pub const Rule = struct { x: u128, y: u128, count: i64, support: Fraction, confidence: Fraction, lift: Fraction, leverage: Fraction, conviction: ?Fraction, improvement: Fraction };
pub fn lift(total: i64, together: i64, first: i64, second: i64) Fraction { return Fraction.init(total * together, first * second); }
pub fn make(x: u128, y: u128, together: i64, total: i64, first: i64, second: i64, improvement: Fraction) Rule {
    return .{ .x = x, .y = y, .count = together, .support = Fraction.init(together, total), .confidence = Fraction.init(together, first), .lift = lift(total, together, first, second), .leverage = Fraction.init(total * together - first * second, total * total), .conviction = if (first == together) null else Fraction.init((total - second) * first, total * (first - together)), .improvement = improvement };
}
pub fn meets(confidence: Fraction, value: Fraction, min_confidence: Fraction, min_lift: Fraction) bool { return confidence.compare(min_confidence) != .lt and value.compare(min_lift) != .lt; }
pub fn less(_: void, a: Rule, c: Rule) bool { const confidence = a.confidence.compare(c.confidence); if (confidence != .eq) return confidence == .gt; const value = a.lift.compare(c.lift); if (value != .eq) return value == .gt; if (a.count != c.count) return a.count > c.count; return if (a.x == c.x) b.setLess(a.y, c.y) else b.setLess(a.x, c.x); }
