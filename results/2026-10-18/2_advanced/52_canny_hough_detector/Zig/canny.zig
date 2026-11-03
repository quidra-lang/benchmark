const std = @import("std");
const c = @import("pgm_io.zig");
const filters = @import("filters.zig");
pub const Result = struct { direction: c.Image, nms: c.Image, edges: c.Image, components: []const []const c.Point,
     strong: i64 = 0, weak: i64 = 0 };
pub fn detect(g: filters.Gradient, p: c.Params) Result {
    const width = g.gx.width;
    const height = g.gx.height;
    var out: Result = .{ .direction = c.Image.init(width, height), .nms = c.Image.init(width, height),
         .edges = c.Image.init(width, height), .components = &.{} };
    for (0..height) |yy| for (0..width) |xx| {
        const x = c.n(xx);
        const y = c.n(yy);
        const point: c.Point = .{ .x = x, .y = y };
        const gx = g.gx.at(point);
        const gy = g.gy.at(point);
        const ax = filters.absolute(gx);
        const ay = filters.absolute(gy);
        const direction: i64 = if (29 * ay <= 12 * ax) 0 else if (29 * ay >= 70 * ax) 90 else if (gx * gy < 0) 45 else 135;
        out.direction.set(point, direction);
        if (xx == 0 or yy == 0 or xx == width - 1 or yy == height - 1) continue;
        const previous: c.Point = switch (direction) {
            0 => .{ .x = x - 1, .y = y },
            45 => .{ .x = x + 1, .y = y - 1 },
            90 => .{ .x = x, .y = y - 1 },
            else => .{ .x = x - 1, .y = y - 1 },
        };
        const next: c.Point = switch (direction) {
            0 => .{ .x = x + 1, .y = y },
            45 => .{ .x = x - 1, .y = y + 1 },
            90 => .{ .x = x, .y = y + 1 },
            else => .{ .x = x + 1, .y = y + 1 },
        };
        const value = g.magnitude.at(point);
        if (value > g.magnitude.at(previous) and value >= g.magnitude.at(next)) out.nms.set(point, value);
    };
    var queue: std.ArrayList(c.Point) = .empty;
    for (0..height) |yy| for (0..width) |xx| {
        const point: c.Point = .{ .x = c.n(xx), .y = c.n(yy) };
        const value = out.nms.at(point);
        if (value >= p.high) {
            out.strong += 1;
            out.edges.set(point, 1);
            c.append(c.Point, &queue, point);
        } else if (value >= p.low) out.weak += 1;
    };
    var head: usize = 0;
    while (head < queue.items.len) : (head += 1) {
        const point = queue.items[head];
        for (c.offsets) |dy| for (c.offsets) |dx| {
            const next: c.Point = .{ .x = point.x + dx, .y = point.y + dy };
            if (out.edges.inside(next) and out.edges.at(next) == 0 and out.nms.at(next) >= p.low) {
                out.edges.set(next, 1);
                c.append(c.Point, &queue, next);
            }
        };
    }
    const visited = c.Image.init(width, height);
    var components: std.ArrayList([]const c.Point) = .empty;
    for (0..height) |yy| for (0..width) |xx| {
        const first: c.Point = .{ .x = c.n(xx), .y = c.n(yy) };
        if (out.edges.at(first) == 0 or visited.at(first) != 0) continue;
        var component: std.ArrayList(c.Point) = .empty;
        c.append(c.Point, &component, first);
        visited.set(first, 1);
        head = 0;
        while (head < component.items.len) : (head += 1) {
            const point = component.items[head];
            for (c.offsets) |dy| for (c.offsets) |dx| {
                const next: c.Point = .{ .x = point.x + dx, .y = point.y + dy };
                if (out.edges.inside(next) and out.edges.at(next) != 0 and visited.at(next) == 0) {
                    visited.set(next, 1);
                    c.append(c.Point, &component, next);
                }
            };
        }
        c.append([]const c.Point, &components, component.items);
    };
    out.components = components.items;
    return out;
}
