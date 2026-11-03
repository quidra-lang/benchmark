const m = @import("matrix.zig");
const association = @import("association.zig");
pub fn squaredDistance(a: m.Position, b: m.Position) f64 {
    const x = a[0] - b[0];
    const y = a[1] - b[1];
    return x * x + y * y;
}
pub fn distance(a: m.Position, b: m.Position) f64 {
    return @sqrt(squaredDistance(a, b));
}
pub fn ospa(a: []const m.Position, b: []const m.Position, cutoff: f64) f64 {
    if (a.len == 0 and b.len == 0) return 0;
    if (a.len == 0 or b.len == 0) return cutoff;
    const small = if (a.len <= b.len) a else b;
    const large = if (a.len <= b.len) b else a;
    const costs = m.alloc(f64, small.len * large.len);
    for (small, 0..) |point, i| for (large, 0..) |other, j| {
        const value = @min(cutoff, distance(point, other));
        costs[i * large.len + j] = value * value;
    };
    var sum: f64 = 0;
    for (association.minimumMatching(costs, small.len, large.len)) |pair| sum += costs[pair.row * large.len + pair.column];
    return @sqrt((sum + cutoff * cutoff * m.f(large.len - small.len)) / m.f(large.len));
}
pub const Continuity = struct { covered: usize = 0, breaks: usize = 0, swaps: usize = 0, delay: ?usize = null };
pub fn continuity(labels: []const i64) Continuity {
    var out: Continuity = .{};
    var previous: i64 = -1;
    var groups: usize = 0;
    var adjacent = false;
    for (labels, 0..) |label, i| {
        if (label < 0) {
            adjacent = false;
            continue;
        }
        out.covered += 1;
        if (out.delay == null) out.delay = i;
        if (!adjacent) groups += 1;
        if (previous >= 0 and previous != label) out.swaps += 1;
        previous = label;
        adjacent = true;
    }
    out.breaks = if (groups > 0) groups - 1 else 0;
    return out;
}
pub fn real(value: f64) []const u8 {
    const out = m.fmt("{d:.4}", .{value});
    return if (m.eq(out, "-0.0000")) "0.0000" else out;
}
