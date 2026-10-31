const d = @import("dataset.zig");
pub const Subgroup = struct { number: usize, values: []const i64, total: i64, squares: i64, mean: f64, range: i64, sd: f64 };
pub const Limits = struct { lcl: f64, cl: f64, ucl: f64, pub fn outside(l: Limits, value: f64) bool { return value > l.ucl or value < l.lcl; } };
pub const Series = struct { numbers: []const usize, values: []const f64 };
pub fn statistics(values: []const i64, size: usize) []const Subgroup {
    const groups = d.alloc(Subgroup, values.len / size);
    const n: i64 = @intCast(size);
    for (groups, 0..) |*group, i| {
        const chosen = values[i * size..][0..size];
        var total: i64 = 0; var squares: i64 = 0; var low = chosen[0]; var high = chosen[0];
        for (chosen) |value| { total += value; squares += value * value; low = @min(low, value); high = @max(high, value); }
        group.* = .{ .number = i + 1, .values = chosen, .total = total, .squares = squares, .mean = d.real(total) / d.real(n), .range = high - low, .sd = @sqrt(d.real(n * squares - total * total) / d.real(n * (n - 1))) };
    }
    return groups;
}
pub fn familyLimits(family: usize, numbers: []const usize, groups: []const Subgroup, values: []const i64, n: usize, c: d.Constants) [2]Limits {
    var total: i64 = 0; var ranges: i64 = 0; var deviations: f64 = 0;
    if (family == 2) {
        for (numbers, 0..) |number, i| { total += values[number - 1]; if (i > 0) ranges += @intCast(@abs(values[number - 1] - values[numbers[i - 1] - 1])); }
        const mean = d.real(total) / d.real(numbers.len);
        const rbar = d.real(ranges) / d.real(numbers.len - 1);
        const width = 3 * rbar / 1.128;
        return .{ .{ .lcl = mean - width, .cl = mean, .ucl = mean + width }, .{ .lcl = 0, .cl = rbar, .ucl = 3.267 * rbar } };
    }
    for (numbers) |number| { const g = groups[number - 1]; total += g.total; ranges += g.range; deviations += g.sd; }
    const mean = d.real(total) / d.real(numbers.len * n);
    const spread = if (family == 0) d.real(ranges) / d.real(numbers.len) else deviations / d.real(numbers.len);
    const width = (if (family == 0) c.a2 else c.a3) * spread;
    return .{ .{ .lcl = mean - width, .cl = mean, .ucl = mean + width }, .{ .lcl = (if (family == 0) c.d3 else c.b3) * spread, .cl = spread, .ucl = (if (family == 0) c.d4 else c.b4) * spread } };
}
pub fn familySeries(family: usize, numbers: []const usize, groups: []const Subgroup, values: []const i64) [2]Series {
    const first = d.alloc(f64, numbers.len);
    const second = d.alloc(f64, if (family == 2) numbers.len - 1 else numbers.len);
    for (numbers, 0..) |number, i| {
        if (family == 2) { first[i] = d.real(values[number - 1]); if (i > 0) second[i - 1] = d.real(@abs(values[number - 1] - values[numbers[i - 1] - 1])); }
        else { const g = groups[number - 1]; first[i] = g.mean; second[i] = if (family == 0) d.real(g.range) else g.sd; }
    }
    return .{ .{ .numbers = numbers, .values = first }, .{ .numbers = if (family == 2) numbers[1..] else numbers, .values = second } };
}
