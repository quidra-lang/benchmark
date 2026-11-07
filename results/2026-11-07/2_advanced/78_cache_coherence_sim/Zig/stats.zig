const std = @import("std");
const b = @import("config_io.zig");
const p = @import("protocol.zig");
pub const service_names = [_][]const u8{ "l1", "upgrade", "through", "cache", "l2", "memory" };
pub const miss_names = [_][]const u8{ "compulsory", "capacity", "conflict", "coherence" };
pub const CoreStats = struct {
    accesses: i64 = 0,
    reads: i64 = 0,
    writes: i64 = 0,
    hits: i64 = 0,
    misses: i64 = 0,
    fences: i64 = 0,
    latency: i64 = 0,
    fence_stall: i64 = 0,
    read_latency: i64 = 0,
    write_latency: i64 = 0,
    finish: i64 = 0,
    miss_counts: [6]i64 = @splat(0),
    service: [6]i64 = @splat(0),
    bus: [5]i64 = @splat(0),
    snoop: [4]i64 = @splat(0),
};
pub fn totalCounters(cores: []const CoreStats) CoreStats {
    var total: CoreStats = .{};
    for (cores) |s| {
        total.accesses += s.accesses;
        total.reads += s.reads;
        total.writes += s.writes;
        total.hits += s.hits;
        total.misses += s.misses;
        total.fences += s.fences;
        total.latency += s.latency;
        total.fence_stall += s.fence_stall;
        total.read_latency += s.read_latency;
        total.write_latency += s.write_latency;
        total.finish = @max(total.finish, s.finish);
        for (0..6) |i| {
            total.miss_counts[i] += s.miss_counts[i];
            total.service[i] += s.service[i];
        }
        for (0..5) |i| total.bus[i] += s.bus[i];
        for (0..4) |i| total.snoop[i] += s.snoop[i];
    }
    return total;
}
pub fn fraction(p_value: i64, q: i64) []const u8 {
    var left = p_value;
    var right = q;
    while (right != 0) {
        const next = @mod(left, right);
        left = right;
        right = next;
    }
    return b.fmt("{d}/{d}", .{ @divTrunc(p_value, left), @divTrunc(q, left) });
}
pub fn decimal(p_value: i64, q: i64) []const u8 {
    const value = @divTrunc(2 * p_value * 100 + q, 2 * q);
    return b.fmt("{d}.{d:0>2}", .{ @divTrunc(value, 100), @mod(value, 100) });
}
pub fn coreString(cores: u8) []const u8 {
    var out: b.Text = .{};
    for (0..8) |core| if (cores & (@as(u8, 1) << @intCast(core)) != 0) out.add("{d}", .{core});
    return if (out.value().len == 0) "-" else out.value();
}
pub fn rangeCounts(names: []const []const u8, counts: []const i64) []const u8 {
    var values: std.ArrayList([]const u8) = .empty;
    for (names, counts) |name, count| b.append([]const u8, &values, b.fmt("{s}:{d}", .{ name, count }));
    return b.join(values.items, " ");
}
pub fn sixLines(label: []const u8, s: CoreStats) b.Lines {
    var out: b.Lines = .{};
    out.add("{s} accesses {d} reads {d} writes {d} hits {d} misses {d} fences {d}", .{ label,
         s.accesses, s.reads, s.writes, s.hits, s.misses, s.fences });
    out.add("{s} misses compulsory {d} capacity {d} conflict {d} coherence {d} true_sharing {d} false_sharing {d}",
         .{ label, s.miss_counts[0], s.miss_counts[1], s.miss_counts[2], s.miss_counts[3],
         s.miss_counts[4], s.miss_counts[5] });
    var values: std.ArrayList([]const u8) = .empty;
    for (service_names, s.service) |kind, count| b.append([]const u8, &values, b.fmt("{s} {d}", .{ kind, count }));
    out.add("{s} service {s}", .{ label, b.join(values.items, " ") });
    values = .empty;
    for (p.transaction_names, s.bus) |kind, count| b.append([]const u8, &values, b.fmt("{s} {d}", .{ kind, count }));
    out.add("{s} bus {s}", .{ label, b.join(values.items, " ") });
    values = .empty;
    for ([_][]const u8{ "invalidations_sent", "invalidations_received", "supplied", "back_invalidations" },
         s.snoop) |kind, count| b.append([]const u8, &values, b.fmt("{s} {d}", .{ kind, count }));
    out.add("{s} snoop {s}", .{ label, b.join(values.items, " ") });
    out.add("{s} time latency {d} amat {s} {s} fence_stall {d} finish {d}", .{ label, s.latency,
         fraction(s.latency, s.accesses), decimal(s.latency, s.accesses), s.fence_stall, s.finish });
    return out;
}
