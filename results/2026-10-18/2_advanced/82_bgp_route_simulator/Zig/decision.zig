const std = @import("std");
const t = @import("topology.zig");
pub var work_allocator: std.mem.Allocator = undefined;
pub const Attribute = struct { id: usize, path: []const usize, origin: t.Origin, med: i64, communities: []const u32 };
pub const Route = struct {
    attribute: *const Attribute,
    local_pref: i64 = 0,
    link: ?usize = null,
    pub fn local(self: Route) bool {
        return self.link == null;
    }
    pub fn neighbor(self: Route) usize {
        return self.attribute.path[0];
    }
};
pub fn equal(left: ?Route, right: ?Route) bool {
    if (left == null or right == null) return left == null and right == null;
    const a = left.?;
    const b = right.?;
    return a.attribute.id == b.attribute.id and a.link == b.link and (a.local() or a.local_pref == b.local_pref);
}
pub fn writeNumber(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u64) void {
    for (0..8) |i| out.append(allocator, @intCast((value >> @intCast(8 * i)) & 255)) catch @panic("allocation failed");
}
var attributes: std.StringHashMapUnmanaged(*const Attribute) = .empty;
var attribute_count: usize = 0;
pub fn intern(path: []const usize, origin: t.Origin, med: i64, communities: []const u32) *const Attribute {
    var key: std.ArrayList(u8) = .empty;
    defer key.deinit(work_allocator);
    writeNumber(&key, work_allocator, path.len);
    for (path) |owner| writeNumber(&key, work_allocator, owner);
    writeNumber(&key, work_allocator, @intFromEnum(origin));
    writeNumber(&key, work_allocator, @intCast(med));
    writeNumber(&key, work_allocator, communities.len);
    for (communities) |community| writeNumber(&key, work_allocator, community);
    if (attributes.get(key.items)) |attribute| return attribute;
    attribute_count += 1;
    const attribute = t.create(Attribute, .{ .id = attribute_count, .path = t.dupe(usize, path),
         .origin = origin, .med = med, .communities = t.dupe(u32, communities) });
    attributes.put(t.allocator, t.dupe(u8, key.items), attribute) catch @panic("allocation failed");
    return attribute;
}
pub const Selection = struct { route: Route, reason: []const u8 };
pub fn bestRoute(candidates: []const Route, network: *const t.Topology) Selection {
    var remaining: [100]Route = undefined;
    @memcpy(remaining[0..candidates.len], candidates);
    var count = candidates.len;
    if (count == 1) return .{ .route = remaining[0], .reason = "ONLY" };
    const reasons = [_][]const u8{ "LOCALPREF", "ASPATH", "ORIGIN", "MED", "ROUTERID", "LINK" };
    for (reasons, 0..) |reason, stage| {
        var scores: [100]i64 = undefined;
        var minimum: i64 = std.math.maxInt(i64);
        for (remaining[0..count], 0..) |route, i| {
            scores[i] = switch (stage) {
                0 => -route.local_pref,
                1 => t.n(route.attribute.path.len),
                2 => t.n(@intFromEnum(route.attribute.origin)),
                3 => 0,
                4 => @intCast(network.ases[route.neighbor()].router_id),
                else => t.n(route.link.?),
            };
            if (stage == 3) {
                for (remaining[0..count]) |other| if (route.neighbor() == other.neighbor() and other.attribute.med < route.attribute.med) {
                    scores[i] = 1;
                    break;
                };
            }
            minimum = @min(minimum, scores[i]);
        }
        var next: usize = 0;
        for (0..count) |i| if (scores[i] == minimum) {
            remaining[next] = remaining[i];
            next += 1;
        };
        count = next;
        if (count == 1) return .{ .route = remaining[0], .reason = reason };
    }
    unreachable;
}
