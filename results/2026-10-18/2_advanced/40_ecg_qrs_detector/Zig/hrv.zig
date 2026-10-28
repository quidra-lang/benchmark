const std = @import("std");
const c = @import("signal_io.zig");
const report = @import("report.zig");
pub fn integerSqrt(value: i64) i64 {
    if (value == 0) return 0;
    var high: i64 = 1;
    while (high <= @divFloor(value, high)) high *= 2;
    var low = @divFloor(high, 2);
    while (low + 1 < high) {
        const middle = low + @divFloor(high - low, 2);
        if (middle <= @divFloor(value, middle)) low = middle else high = middle;
    }
    return low;
}
pub fn root(numerator: i64, denominator: i64) i64 {
    return @divFloor(integerSqrt(@divFloor(40000 * numerator, denominator)) + 1, 2);
}
pub fn meanScaled(values: []const i64) i64 {
    var sum: i64 = 0;
    for (values) |value| sum += value;
    return report.rdiv(100 * sum, c.n(values.len));
}
pub fn meanHr(intervals: []const i64) i64 {
    var sum: i64 = 0;
    for (intervals) |value| sum += value;
    return report.rdiv(6000000 * c.n(intervals.len), sum);
}
pub fn sampleDeviation(values: []const i64, multiplier: i64) i64 {
    var sum: i64 = 0;
    var squares: i64 = 0;
    for (values) |value| {
        sum += value;
        squares += value * value;
    }
    const count = c.n(values.len);
    return root(count * squares - sum * sum, multiplier * count * (count - 1));
}
pub fn rms(values: []const i64) i64 {
    var squares: i64 = 0;
    for (values) |value| squares += value * value;
    return root(squares, c.n(values.len));
}
pub const Bin = struct { bin: i64, count: usize = 0 };
pub fn histogram(intervals: []const i64) []const Bin {
    const bins = c.alloc(i64, intervals.len);
    for (intervals, bins) |value, *bin| bin.* = @divFloor(16 * value, 125);
    std.mem.sort(i64, bins, {}, std.sort.asc(i64));
    var out: std.ArrayList(Bin) = .empty;
    for (bins) |bin| {
        if (out.items.len == 0 or out.items[out.items.len - 1].bin != bin) c.append(Bin, &out, .{ .bin = bin });
        out.items[out.items.len - 1].count += 1;
    }
    return out.items;
}
pub const Range = struct { first: usize, last: usize };
pub fn ranges(flags: []const bool) []const Range {
    var out: std.ArrayList(Range) = .empty;
    var first: usize = 0;
    while (first < flags.len) {
        if (!flags[first]) {
            first += 1;
            continue;
        }
        var last = first;
        while (last + 1 < flags.len and flags[last + 1]) last += 1;
        c.append(Range, &out, .{ .first = first, .last = last });
        first = last + 1;
    }
    return out.items;
}
