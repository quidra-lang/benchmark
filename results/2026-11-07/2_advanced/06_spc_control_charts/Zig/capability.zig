const std = @import("std");
const d = @import("dataset.zig");
const v = @import("variable_charts.zig");
pub const Result = struct { count: usize, mean: f64, sigma_within: f64, sigma_sbar: f64, sigma_overall: f64, cp: f64, cpu: f64, cpl: f64, cpk: f64, pp: f64, ppu: f64, ppl: f64, ppk: f64, cpm: f64, cpk_ci: [2]f64, ppk_ci: [2]f64, below: usize, above: usize, ppm: f64, verdict: []const u8 };
fn indices(mean: f64, sigma: f64, s: d.Settings) [4]f64 { const upper = (d.real(s.usl) - mean) / (3 * sigma); const lower = (mean - d.real(s.lsl)) / (3 * sigma); return .{ d.real(s.usl - s.lsl) / (6 * sigma), upper, lower, @min(upper, lower) }; }
fn interval(value: f64, count: usize, z: f64) [2]f64 { const delta = z * @sqrt(1 / d.real(9 * count) + value * value / d.real(2 * (count - 1))); return .{ value - delta, value + delta }; }
pub fn assess(groups: []const v.Subgroup, numbers: []const usize, s: d.Settings, c: d.Constants) Result {
    var total: i64 = 0; var ranges: i64 = 0; var deviations: f64 = 0;
    for (numbers) |number| { const g = groups[number - 1]; total += g.total; ranges += g.range; deviations += g.sd; }
    const count = numbers.len * s.n;
    const mean = d.real(total) / d.real(count);
    const within = (d.real(ranges) / d.real(numbers.len)) / c.d2;
    const sbar = (deviations / d.real(numbers.len)) / c.c4;
    var squares: f64 = 0; var below: usize = 0; var above: usize = 0;
    for (numbers) |number| for (groups[number - 1].values) |value| { const delta = d.real(value) - mean; squares += delta * delta; if (value < s.lsl) below += 1; if (value > s.usl) above += 1; };
    const overall = @sqrt(squares / d.real(count - 1));
    const cp = indices(mean, within, s); const pp = indices(mean, overall, s); const offset = mean - d.real(s.target);
    return .{ .count = count, .mean = mean, .sigma_within = within, .sigma_sbar = sbar, .sigma_overall = overall, .cp = cp[0], .cpu = cp[1], .cpl = cp[2], .cpk = cp[3], .pp = pp[0], .ppu = pp[1], .ppl = pp[2], .ppk = pp[3], .cpm = d.real(s.usl - s.lsl) / (6 * @sqrt(overall * overall + offset * offset)), .cpk_ci = interval(cp[3], count, s.z), .ppk_ci = interval(pp[3], count, s.z), .below = below, .above = above, .ppm = d.real(1000000 * (below + above)) / d.real(count), .verdict = if (cp[3] >= 1.33) "capable" else if (cp[3] >= 1) "marginal" else "incapable" };
}
pub fn histogram(groups: []const v.Subgroup, numbers: []const usize, s: d.Settings) d.Strings {
    var low = s.lsl; var high = s.usl;
    for (numbers) |number| for (groups[number - 1].values) |value| { low = @min(low, value); high = @max(high, value); };
    low = s.bin * @divFloor(low, s.bin); high = s.bin * @divFloor(high, s.bin) + s.bin;
    const frequencies = d.alloc(usize, @intCast(@divFloor(high - low, s.bin))); @memset(frequencies, 0);
    for (numbers) |number| for (groups[number - 1].values) |value| { frequencies[@intCast(@divFloor(value - low, s.bin))] += 1; };
    var top: usize = 0; for (frequencies) |frequency| top = @max(top, frequency);
    var rows: std.ArrayList([]const u8) = .empty;
    for (frequencies, 0..) |frequency, i| {
        const a = low + @as(i64, @intCast(i)) * s.bin; const b = a + s.bin - 1;
        var parts: std.ArrayList([]const u8) = .empty;
        d.append([]const u8, &parts, d.fmt("bin {d} {d} {d}", .{ a, b, frequency }));
        if (frequency > 0) d.append([]const u8, &parts, d.repeated('#', (50 * frequency + top - 1) / top));
        const names = [_][]const u8{ "lsl", "target", "usl" }; const marks = [_]i64{ s.lsl, s.target, s.usl };
        for (names, marks) |name, value| { if (value >= a and value <= b) d.append([]const u8, &parts, name); }
        d.append([]const u8, &rows, d.join(parts.items, " "));
    }
    return rows.items;
}
