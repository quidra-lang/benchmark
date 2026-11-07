const std = @import("std");
const c = @import("signal_io.zig");
const filters = @import("filters.zig");
pub const PeakClass = enum { qrs, searchback, twave, refractory, noise, pending };
pub const Peak = struct { time: usize, r: usize, integrated: i64, filtered: i64, slope: i64, thr_i: i64 = 0,
     thr_f: i64 = 0, kind: PeakClass = .pending };
pub const Levels = struct { spki: i64 = 0, npki: i64 = 0, spkf: i64 = 0, npkf: i64 = 0 };
pub fn abs(value: i64) i64 {
    return @intCast(@abs(value));
}
pub fn findPeaks(signals: filters.Signals) std.ArrayList(Peak) {
    var out: std.ArrayList(Peak) = .empty;
    for (signals.integrated, 0..) |value, n| {
        if (value <= 0) continue;
        var maximum = true;
        for (n -| 20..n) |j| if (signals.integrated[j] >= value) {
            maximum = false;
        };
        for (n + 1..@min(signals.integrated.len, n + 21)) |j| if (signals.integrated[j] > value) {
            maximum = false;
        };
        if (!maximum) continue;
        var r = n -| 30;
        for (r + 1..n + 1) |j| if (abs(signals.bandpass[j]) > abs(signals.bandpass[r])) {
            r = j;
        };
        var slope: i64 = 0;
        for (n -| 29..n + 1) |j| slope = @max(slope, abs(signals.derivative[j]));
        c.append(Peak, &out, .{ .time = n, .r = r, .integrated = value, .filtered = abs(signals.bandpass[r]), .slope = slope });
    }
    return out;
}
pub fn qrsWidth(signals: filters.Signals, r: usize) i64 {
    const peak = abs(signals.bandpass[r]);
    var first = r;
    var last = r;
    for (r -| 25..@min(signals.bandpass.len, r + 26)) |j| if (4 * abs(signals.bandpass[j]) >= peak) {
        first = @min(first, j);
        last = @max(last, j);
    };
    return 5 * c.n(last - first + 1);
}
pub fn initialLevels(signals: filters.Signals) Levels {
    var maximum_i: i64 = 0;
    var sum_i: i64 = 0;
    var maximum_f: i64 = 0;
    var sum_f: i64 = 0;
    for (0..400) |i| {
        maximum_i = @max(maximum_i, signals.integrated[i]);
        sum_i += signals.integrated[i];
        const value = abs(signals.bandpass[i]);
        maximum_f = @max(maximum_f, value);
        sum_f += value;
    }
    return .{ .spki = @divFloor(maximum_i, 3), .npki = @divFloor(sum_i, 800), .spkf = @divFloor(maximum_f,
         3), .npkf = @divFloor(sum_f, 800) };
}
