const dates = @import("dates_calendar.zig");

pub fn bisect(context: anytype, comptime evaluate: anytype, low: f64, high: f64, target: f64) f64 {
    var lo = low;
    var hi = high;
    for (0..80) |_| {
        const middle = (lo + hi) / 2;
        if (evaluate(context, middle) > target) lo = middle else hi = middle;
    }
    return (lo + hi) / 2;
}

pub const Risk = struct { macaulay: f64 = 0, modified: f64 = 0, convexity: f64 = 0, dv01: f64 = 0 };
pub const YieldPricer = struct {
    flows: []const i64,
    fraction: f64,
    frequency: i64,
    outstanding: i64,
    pub fn dirty(p: YieldPricer, rate: f64) f64 {
        const first = 1 + p.fraction * rate / dates.real(p.frequency);
        const growth = 1 + rate / dates.real(p.frequency);
        var factor: f64 = 1;
        var total: f64 = 0;
        for (p.flows) |flow| { total += dates.real(flow) / (first * factor); factor *= growth; }
        return total * 100 / dates.real(p.outstanding);
    }
    pub fn solve(p: YieldPricer, target: f64) f64 { return bisect(p, dirty, 0, 1, target); }
    pub fn risk(p: YieldPricer, rate: f64) Risk {
        const frequency = dates.real(p.frequency);
        const first = 1 + p.fraction * rate / frequency;
        const growth = 1 + rate / frequency;
        var factor: f64 = 1;
        var total: f64 = 0;
        var weighted: f64 = 0;
        var curvature: f64 = 0;
        for (p.flows, 0..) |flow, index| {
            const value = dates.real(flow) / (first * factor);
            const years = (dates.real(index) + p.fraction) / frequency;
            total += value;
            weighted += years * value;
            curvature += years * (years + 1 / frequency) * value;
            factor *= growth;
        }
        const macaulay = weighted / total;
        return .{ .macaulay = macaulay, .modified = macaulay / growth, .convexity = curvature / (total * growth * growth), .dv01 = (p.dirty(rate - 0.0001) - p.dirty(rate + 0.0001)) / 2 };
    }
};
