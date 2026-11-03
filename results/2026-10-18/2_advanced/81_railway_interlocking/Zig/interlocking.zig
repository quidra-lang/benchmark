const std = @import("std");
const l = @import("layout.zig");
pub const State = enum { none, locked, used, approach };
pub const state_names = [_][]const u8{ "none", "LOCKED", "USED", "APPROACH" };
pub fn protected(state: State) bool {
    return state == .locked or state == .approach;
}
pub const Requirement = struct { point: usize, position: u8 };
pub const Route = struct { name: []const u8, start: usize, finish: []const u8, requirements: []const Requirement,
     sections: []const usize, overlap: []const usize, conflicts: []const usize, direction: l.Direction,
     approach_time: i64, state: State = .none, release_time: ?i64 = null, passed: u64 = 0,
     overlap_locked: bool = false, overlap_counter: i64 = 0, requests: i64 = 0, grants: i64 = 0,
     uses: i64 = 0, cancels: i64 = 0, wait: i64 = 0, maxwait: i64 = 0, locked_seconds: i64 = 0 };
pub const Interlocking = struct {
    routes: []Route,
    pub fn lock(self: *Interlocking, layout: *l.Layout, index: usize) void {
        const route = &self.routes[index];
        route.state = .locked;
        route.release_time = null;
        route.passed = 0;
        route.overlap_locked = true;
        route.overlap_counter = 0;
        for (route.sections) |section| layout.sections[section].route_lock = index;
        for (route.overlap) |section| layout.sections[section].overlap_locks |= l.bit(index);
        for (route.requirements) |req| {
            const point = &layout.points[req.point];
            if (req.position == 'N') point.normal_locks |= l.bit(index) else point.reverse_locks |= l.bit(index);
        }
    }
    fn unlockPoints(_: *Interlocking, layout: *l.Layout, index: usize, sections: ?[]const usize) void {
        for (layout.points) |*point| {
            if (sections) |names| {
                if (std.mem.indexOfScalar(usize, names, point.common) == null) continue;
            }
            point.normal_locks &= ~l.bit(index);
            point.reverse_locks &= ~l.bit(index);
        }
    }
    pub fn unlockSection(self: *Interlocking, layout: *l.Layout, index: usize, section: usize) void {
        if (layout.sections[section].route_lock == index) layout.sections[section].route_lock = null;
        self.unlockPoints(layout, index, &.{section});
    }
    pub fn unlockOverlap(self: *Interlocking, layout: *l.Layout, index: usize) void {
        const route = &self.routes[index];
        for (route.overlap) |section| layout.sections[section].overlap_locks &= ~l.bit(index);
        self.unlockPoints(layout, index, route.overlap);
        route.overlap_locked = false;
    }
    pub fn release(self: *Interlocking, layout: *l.Layout, index: usize) void {
        const route = &self.routes[index];
        for (route.sections) |section| if (layout.sections[section].route_lock == index) {
            layout.sections[section].route_lock = null;
        };
        if (route.overlap_locked) self.unlockOverlap(layout, index);
        self.unlockPoints(layout, index, null);
        route.state = .none;
        route.release_time = null;
    }
};
fn names(source: []const u8) l.Names {
    return if (l.eq(source, "-")) &.{} else l.split(source, ',');
}
fn indices(items: anytype, source: []const u8) []const usize {
    var out: std.ArrayList(usize) = .empty;
    for (names(source)) |name| l.append(usize, &out, l.indexOf(items, name));
    return out.items;
}
pub fn read(io: std.Io, layout: *const l.Layout) !Interlocking {
    const lines = try l.readLines(io, "input/routes.txt");
    const routes = l.alloc(Route, lines.len);
    for (lines, routes) |line, *route| {
        const f = l.words(line);
        var requirements: std.ArrayList(Requirement) = .empty;
        for ([_][]const u8{ f[4], f[7] }) |source| for (names(source)) |item| {
            const pair = l.split(item, ':');
            l.append(Requirement, &requirements, .{ .point = l.indexOf(layout.points, pair[0]),
                 .position = pair[1][0] });
        };
        const start = l.indexOf(layout.signals, f[2]);
        route.* = .{ .name = f[1], .start = start, .finish = f[3], .requirements = requirements.items,
             .sections = indices(layout.sections, f[5]), .overlap = indices(layout.sections,
             f[6]), .conflicts = &.{}, .direction = layout.signals[start].direction, .approach_time = l.number(f[9]) };
    }
    for (lines, routes) |line, *route| route.conflicts = indices(routes, l.words(line)[8]);
    return .{ .routes = routes };
}
