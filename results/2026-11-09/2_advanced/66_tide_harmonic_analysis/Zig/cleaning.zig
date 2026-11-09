const std = @import("std");
const d = @import("records.zig");
fn less(_: void, a: f64, b: f64) bool {
    return a < b;
}
pub fn median(values: []f64) f64 {
    std.mem.sort(f64, values, {}, less);
    const count = values.len;
    return if (count % 2 == 1) values[count / 2] else (values[count / 2 - 1] + values[count / 2]) / 2;
}
pub const Flat = struct { first: usize, last: usize, milli: i64 };
pub fn flatRuns(station: *const d.Station, minimum: usize) []const Flat {
    var out: std.ArrayList(Flat) = .empty;
    var time = station.first;
    while (time <= station.last) {
        const value = station.observations[time] orelse {
            time += 1;
            continue;
        };
        const start = time;
        while (time < station.last and station.observations[time + 1] == value) time += 1;
        if (time - start + 1 >= minimum) d.append(Flat, &out, .{ .first = start, .last = time, .milli = value });
        time += 1;
    }
    return out.items;
}
pub const Spike = struct { time: usize, residual: f64, median: f64, mad: f64, limit: f64 };
pub const Spikes = struct { values: []const Spike, tested: usize };
pub fn spikes(residuals: []const d.Sample, p: d.Params) Spikes {
    var out: std.ArrayList(Spike) = .empty;
    const window = d.alloc(f64, residuals.len);
    const deviations = d.alloc(f64, residuals.len);
    var first: usize = 0;
    var last: usize = 0;
    var tested: usize = 0;
    for (residuals) |sample| {
        const t = sample.time;
        while (first < residuals.len and d.n(residuals[first].time) < d.n(t) - d.n(p.spike_window)) first += 1;
        while (last < residuals.len and residuals[last].time <= t + p.spike_window) last += 1;
        const count = last - first;
        if (count < p.spike_count) continue;
        tested += 1;
        for (0..count) |j| window[j] = residuals[first + j].value;
        const center = median(window[0..count]);
        for (0..count) |j| deviations[j] = @abs(window[j] - center);
        const mad = median(deviations[0..count]);
        const limit = @max(p.spike_factor * 1.4826 * mad, p.spike_minimum);
        if (@abs(sample.value - center) > limit) d.append(Spike, &out, .{ .time = t, .residual = sample.value,
             .median = center, .mad = mad, .limit = limit });
    }
    return .{ .values = out.items, .tested = tested };
}
pub const Reason = enum { usable, absent, na, flat, spike, mixed };
pub const Gap = struct { first: usize, last: usize, cause: Reason };
pub fn gaps(reasons: []const Reason, first: usize, last: usize) []const Gap {
    var out: std.ArrayList(Gap) = .empty;
    var time = first;
    while (time <= last) {
        if (reasons[time] == .usable) {
            time += 1;
            continue;
        }
        const start = time;
        var cause = reasons[time];
        while (time < last and reasons[time + 1] != .usable) {
            time += 1;
            if (reasons[time] != cause) cause = .mixed;
        }
        d.append(Gap, &out, .{ .first = start, .last = time, .cause = cause });
        time += 1;
    }
    return out.items;
}
