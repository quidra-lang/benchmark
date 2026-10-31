const std = @import("std");
const dates = @import("dates_calendar.zig");
const daycount = @import("daycount.zig");
const schedule = @import("schedule.zig");
const pricing = @import("pricing.zig");
pub const Pillar = struct { maturity: i64, coupon: i64, frequency: i64 };
pub const Flow = struct { days: i64, amount: f64 };
pub const ZeroCurve = struct {
    days: []const i64,
    rates: []const f64,
    pub fn zero(c: ZeroCurve, day: i64) f64 {
        if (day <= c.days[0]) return c.rates[0];
        if (day >= c.days[c.days.len - 1]) return c.rates[c.rates.len - 1];
        var index: usize = 1;
        while (c.days[index] < day) : (index += 1) {}
        if (c.days[index] == day) return c.rates[index];
        return c.rates[index - 1] + (c.rates[index] - c.rates[index - 1]) * (dates.real(day - c.days[index - 1]) / dates.real(c.days[index] - c.days[index - 1]));
    }
    pub fn discount(c: ZeroCurve, day: i64, spread: f64) f64 {
        const rate = c.zero(day) + spread;
        const years = @divFloor(day, 365);
        const remainder = @mod(day, 365);
        var growth: f64 = 1;
        var i: i64 = 0;
        while (i < years) : (i += 1) growth *= 1 + rate;
        return 1 / (growth * (1 + rate * dates.real(remainder) / 365));
    }
    pub fn presentValue(c: ZeroCurve, flows: []const Flow, spread: f64) f64 { var total: f64 = 0; for (flows) |flow| total += flow.amount * c.discount(flow.days, spread); return total; }
    pub fn forward(c: ZeroCurve, start: i64, end: i64) f64 { return (c.discount(start, 0) / c.discount(end, 0) - 1) * 365 / dates.real(end - start); }
    pub fn shifted(c: ZeroCurve, deltas: []const f64) ZeroCurve { const rates = dates.clone(f64, c.rates); for (rates, deltas) |*rate, delta| rate.* += delta; return .{ .days = c.days, .rates = rates }; }
};
const BootstrapContext = struct { curve: ZeroCurve, trial: *f64, flows: []const Flow };
fn bootstrapValue(context: BootstrapContext, trial: f64) f64 { context.trial.* = trial; return context.curve.presentValue(context.flows, 0); }
pub fn bootstrap(settlement: i64, pillars: []const Pillar) ZeroCurve {
    var days: std.ArrayList(i64) = .empty;
    var rates: std.ArrayList(f64) = .empty;
    for (pillars) |pillar| {
        const boundaries = schedule.build(settlement, pillar.maturity, pillar.frequency, false, false);
        var flows: std.ArrayList(Flow) = .empty;
        for (1..boundaries.len) |i| {
            const fraction = daycount.fraction("30/360", boundaries[i - 1], boundaries[i]);
            var amount = dates.real(pillar.coupon) * dates.real(fraction.n) / (10000 * dates.real(fraction.m));
            if (i == boundaries.len - 1) amount += 1;
            dates.append(Flow, &flows, .{ .days = boundaries[i] - settlement, .amount = amount });
        }
        dates.append(i64, &days, pillar.maturity - settlement);
        dates.append(f64, &rates, 0);
        const context: BootstrapContext = .{ .curve = .{ .days = days.items, .rates = rates.items }, .trial = &rates.items[rates.items.len - 1], .flows = flows.items };
        const rate = pricing.bisect(context, bootstrapValue, 0, 1, 1);
        rates.items[rates.items.len - 1] = rate;
    }
    return .{ .days = days.items, .rates = rates.items };
}
const SpreadContext = struct { curve: ZeroCurve, flows: []const Flow };
fn spreadValue(context: SpreadContext, spread: f64) f64 { return context.curve.presentValue(context.flows, spread); }
pub fn zSpread(c: ZeroCurve, flows: []const Flow, target: f64) f64 { return pricing.bisect(SpreadContext{ .curve = c, .flows = flows }, spreadValue, -0.5, 0.5, target); }
pub fn flatPresentValue(flows: []const Flow, rate: f64) f64 { return (ZeroCurve{ .days = &.{0}, .rates = &.{rate} }).presentValue(flows, 0); }
