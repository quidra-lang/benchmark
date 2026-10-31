const l = @import("layout.zig");
const inter = @import("interlocking.zig");
pub fn cleared(layout: *const l.Layout, route: inter.Route) bool {
    if (route.state != .locked) return false;
    for (route.requirements) |req| {
        const point = layout.points[req.point];
        if (!point.detected() or point.position != req.position) return false;
    }
    for (route.sections) |section| if (layout.occupied(section)) return false;
    for (route.overlap) |section| if (layout.occupied(section)) return false;
    return true;
}
pub fn aspects(layout: *const l.Layout, interlocking: *const inter.Interlocking) [30]l.Aspect {
    var clear: [30]?usize = @splat(null);
    for (layout.signals, 0..) |_, signal| for (interlocking.routes, 0..) |route, index| if (route.start == signal and cleared(layout,
         route)) {
        clear[signal] = index;
        break;
    };
    var result: [30]l.Aspect = @splat(.red);
    for (layout.signals, 0..) |_, signal| if (clear[signal]) |index| {
        const route = interlocking.routes[index];
        if (l.findIndex(layout.signals, route.finish)) |finish| result[signal] = if (clear[finish] != null) .green else .yellow else if (l.findIndex(layout.buffers,
             route.finish) != null) result[signal] = .yellow else result[signal] = .green;
    };
    return result;
}
