const std = @import("std");
const c = @import("waveform_io.zig");
pub fn logarithm(value: f64) f64 {
    return @log(value) / 2.302585092994046;
}
fn less(_: void, a: f64, b: f64) bool {
    return a < b;
}
pub fn median(values: []const f64) f64 {
    const ordered = c.dupe(f64, values);
    std.mem.sort(f64, ordered, {}, less);
    const middle = values.len / 2;
    return if (values.len % 2 == 1) ordered[middle] else (ordered[middle - 1] + ordered[middle]) / 2;
}
pub const PickMagnitude = struct { radius: f64, md: f64, ml: ?f64 = null };
pub fn magnitude(pick: c.Pick, radius: f64, p: c.Params) PickMagnitude {
    var out: PickMagnitude = .{ .radius = radius, .md = p.duration[0] + p.duration[1] * logarithm(c.f(pick.duration) / 100) + p.duration[2] * radius };
    if (!pick.clipped) out.ml = logarithm(c.f(pick.amplitude)) + p.local[0] * logarithm(radius / 100) + p.local[1] * (radius - 100) + p.local[2];
    return out;
}
pub fn scaled(value: f64, places: usize) i64 {
    var factor: i64 = 1;
    for (0..places) |_| factor *= 10;
    const result: i64 = @intFromFloat(@floor(@abs(value) * c.f(factor) + 0.5));
    return if (value < 0) -result else result;
}
pub fn classNumber(value: f64) i64 {
    return @divFloor(scaled(value, 2) + 5, 10);
}
pub fn classText(value: i64) []const u8 {
    const absolute = if (value < 0) -value else value;
    return c.fmt("{s}{d}.{d}", .{ if (value < 0) "-" else "", @divTrunc(absolute, 10), @mod(absolute, 10) });
}
pub const ClassCount = struct { value: i64, count: usize };
pub const Frequency = struct { counts: []ClassCount, completeness: i64 = 0, nb: usize = 0, n: usize = 0,
     b: f64 = 0, sigma: f64 = 0, a: f64 = 0, slope: f64 = 0, intercept: f64 = 0, r: f64 = 0, mean_diff: f64 = 0 };
fn classLess(_: void, a: ClassCount, b: ClassCount) bool {
    return a.value < b.value;
}
pub fn frequency(local: []const f64, duration: []const f64) Frequency {
    var counts: std.ArrayList(ClassCount) = .empty;
    for (local) |value| {
        const t = classNumber(value);
        var index: usize = 0;
        while (index < counts.items.len and counts.items[index].value != t) index += 1;
        if (index == counts.items.len) c.append(ClassCount, &counts, .{ .value = t, .count = 0 });
        counts.items[index].count += 1;
    }
    std.mem.sort(ClassCount, counts.items, {}, classLess);
    var out: Frequency = .{ .counts = counts.items, .n = local.len };
    var best: usize = 0;
    for (counts.items) |entry| if (entry.count > best) {
        best = entry.count;
        out.completeness = entry.value;
    };
    var total: i64 = 0;
    for (local) |value| {
        const t = classNumber(value);
        if (t >= out.completeness) {
            out.nb += 1;
            total += t;
        }
    }
    const mc = c.f(out.completeness) / 10;
    const mean = c.f(total) / (10 * c.f(out.nb));
    out.b = 0.4342944819032518 / (mean - (mc - 0.05));
    out.sigma = out.b / @sqrt(c.f(out.nb));
    out.a = logarithm(c.f(out.nb)) + out.b * mc;
    var xm: f64 = 0;
    var ym: f64 = 0;
    for (duration) |value| xm += value;
    for (local) |value| ym += value;
    xm /= c.f(out.n);
    ym /= c.f(out.n);
    var xx: f64 = 0;
    var xy: f64 = 0;
    var yy: f64 = 0;
    for (duration, local) |x, y| {
        xx += (x - xm) * (x - xm);
        xy += (x - xm) * (y - ym);
        yy += (y - ym) * (y - ym);
    }
    out.slope = xy / xx;
    out.intercept = ym - out.slope * xm;
    out.r = xy / @sqrt(xx * yy);
    out.mean_diff = ym - xm;
    return out;
}
