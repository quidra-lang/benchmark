const std = @import("std");
const c = @import("waveform_io.zig");
const magnitude = @import("magnitude.zig");
fn absolute(value: i64) i64 {
    return if (value < 0) -value else value;
}
fn finish(station: *c.Station, index: usize, p: c.Params, picks: *std.ArrayList(c.Pick), d: []const i64,
     energy: []const i64, beginning: usize, end: usize, maximum: f64) void {
    station.triggers += 1;
    const duration = c.n(end - beginning);
    if (duration < p.min_duration) {
        station.short_triggers += 1;
        return;
    }
    var k = beginning;
    while (c.n(k) - 1 >= c.n(beginning) - p.sw + 1 and energy[k - 1] >= p.noise) k -= 1;
    var amplitude: i64 = 0;
    var clipped = false;
    for (k..@min(k + c.u(p.aw), station.samples.len)) |j| {
        amplitude = @max(amplitude, absolute(d[j]));
        clipped = clipped or absolute(station.samples[j]) >= p.clip;
    }
    c.append(c.Pick, picks, .{ .station = index, .sample = station.start + c.n(k), .duration = duration,
         .amplitude = amplitude, .ratio = maximum, .clipped = clipped });
}
pub fn detect(station: *c.Station, index: usize, p: c.Params) []const c.Pick {
    const count = station.samples.len;
    var sum: i64 = 0;
    for (station.samples) |value| sum += value;
    station.mean = @divFloor(sum, c.n(count));
    const d = c.alloc(i64, count);
    const energy = c.alloc(i64, count);
    const prefix = c.alloc(i64, count + 1);
    prefix[0] = 0;
    const amplitudes = c.alloc(f64, count);
    for (station.samples, 0..) |value, i| {
        d[i] = value - station.mean;
        energy[i] = d[i] * d[i];
        prefix[i + 1] = prefix[i] + energy[i];
        amplitudes[i] = c.f(absolute(d[i]));
        station.peak = @max(station.peak, absolute(d[i]));
        station.clipped += @intFromBool(absolute(value) >= p.clip);
    }
    station.noise = magnitude.median(amplitudes);
    var picks: std.ArrayList(c.Pick) = .empty;
    var on = false;
    var beginning: usize = 0;
    var maximum: f64 = 0;
    const sw = c.u(p.sw);
    const lw = c.u(p.lw);
    for (sw + lw - 1..count) |i| {
        const sta = prefix[i + 1] - prefix[i - sw + 1];
        const lta = prefix[i - sw + 1] - prefix[i - sw - lw + 1];
        if (!on) {
            if (sta * p.lw * p.on_q >= p.on_p * lta * p.sw) {
                on = true;
                beginning = i;
                maximum = c.f(sta * p.lw) / c.f(lta * p.sw);
            }
        } else if (sta * p.lw * p.off_q < p.off_p * lta * p.sw) {
            finish(station, index, p, &picks, d, energy, beginning, i, maximum);
            on = false;
        } else maximum = @max(maximum, c.f(sta * p.lw) / c.f(lta * p.sw));
    }
    if (on) finish(station, index, p, &picks, d, energy, beginning, count, maximum);
    return picks.items;
}
