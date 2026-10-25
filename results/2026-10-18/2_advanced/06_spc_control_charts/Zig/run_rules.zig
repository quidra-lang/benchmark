const std = @import("std");
const d = @import("dataset.zig");
const v = @import("variable_charts.zig");
pub const Direction = enum { UP, DOWN, NONE };
pub const Signal = struct { chart: usize, rule: usize, first: usize, last: usize, value: f64, direction: Direction };
pub const Zones = struct { lcl: f64, cl: f64, ucl: f64, u1: f64, u2: f64, l1: f64, l2: f64 };
pub fn zones(l: v.Limits) Zones { const a = (l.ucl - l.cl) / 3; const b = (l.cl - l.lcl) / 3; return .{ .lcl = l.lcl, .cl = l.cl, .ucl = l.ucl, .u1 = l.cl + a, .u2 = l.cl + 2 * a, .l1 = l.cl - b, .l2 = l.cl - 2 * b }; }
pub fn zoneName(l: v.Limits, value: f64) []const u8 { const z = zones(l); return if (value > z.ucl) "OUT+" else if (value < z.lcl) "OUT-" else if (value > z.u2) "A+" else if (value > z.u1) "B+" else if (value > z.cl) "C+" else if (value < z.l2) "A-" else if (value < z.l1) "B-" else if (value < z.cl) "C-" else "C0"; }
fn direction(rule: usize, window: []const f64, z: Zones) ?Direction {
    const last = window[window.len - 1];
    switch (rule) {
        1 => { if (last > z.ucl or last < z.lcl) return if (last > z.cl) .UP else .DOWN; },
        2, 3 => { const upper = if (rule == 2) z.u2 else z.u1; const lower = if (rule == 2) z.l2 else z.l1; const needed: usize = if (rule == 2) 2 else 4; var up: usize = 0; var down: usize = 0; for (window) |value| { if (value > upper) up += 1; if (value < lower) down += 1; } if (last > upper and up >= needed) return .UP; if (last < lower and down >= needed) return .DOWN; },
        4 => { var up = true; var down = true; for (window) |value| { up = up and value > z.cl; down = down and value < z.cl; } if (up) return .UP; if (down) return .DOWN; },
        5 => { var up = true; var down = true; for (1..window.len) |i| { up = up and window[i] > window[i - 1]; down = down and window[i] < window[i - 1]; } if (up) return .UP; if (down) return .DOWN; },
        6 => { var previous: f64 = 0; for (1..window.len) |i| { const delta = window[i] - window[i - 1]; if (delta == 0 or (i > 1 and (delta > 0) == (previous > 0))) return null; previous = delta; } return .NONE; },
        7 => { for (window) |value| { if (!(value > z.l1 and value < z.u1)) return null; } return .NONE; },
        8 => { var up = false; var down = false; for (window) |value| { if (value > z.u1) up = true else if (value < z.l1) down = true else return null; } if (up and down) return .NONE; },
        else => unreachable,
    }
    return null;
}
pub fn check(chart: usize, series: v.Series, limits: v.Limits, rules: []const usize) []const Signal {
    const lengths = [_]usize{ 1, 3, 5, 8, 6, 14, 15, 8 };
    const z = zones(limits);
    var signals: std.ArrayList(Signal) = .empty;
    for (series.values, 0..) |value, i| for (rules) |rule| { const length = lengths[rule - 1]; if (i + 1 < length) continue; const first = i + 1 - length; if (direction(rule, series.values[first..i + 1], z)) |side| d.append(Signal, &signals, .{ .chart = chart, .rule = rule, .first = series.numbers[first], .last = series.numbers[i], .value = value, .direction = side }); };
    return signals.items;
}
