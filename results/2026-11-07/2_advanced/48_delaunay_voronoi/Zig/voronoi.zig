const std = @import("std");
const c = @import("predicates.zig");
const triangulation = @import("triangulation.zig");
pub fn radius2(a: c.Point, b: c.Point, q: c.Point) f64 {
    const first = c.d2(a, b);
    const second = c.d2(b, q);
    const third = c.d2(q, a);
    const area = c.orient(a, b, q);
    return c.f((first * second) * third) / c.f((4 * area) * area);
}
pub fn position(vertex: c.Center, points: []const c.Point, hull: []const usize) []const u8 {
    var on = false;
    for (hull, 0..) |site, k| {
        const a = points[site];
        const b = points[hull[(k + 1) % hull.len]];
        const sigma = (b.x - a.x) * (vertex.y - a.y * vertex.d) - (b.y - a.y) * (vertex.x - a.x * vertex.d);
        if (sigma < 0) return "outside";
        on = on or sigma == 0;
    }
    return if (on) "on" else "inside";
}
pub fn neighborOrder(t: triangulation.Triangulation, site: usize, neighbors: []const usize, next: ?usize) []const usize {
    var out: std.ArrayList(usize) = .empty;
    const start = next orelse neighbors[0];
    var current = start;
    while (true) {
        c.append(usize, &out, current);
        current = t.third(site, current) orelse break;
        if (current == start) break;
    }
    return out.items;
}
pub fn cellArea(site: c.Point, vertices: []const c.Center, sequence: []const usize) f64 {
    var out: f64 = 0;
    for (sequence, 0..) |index, k| {
        const a = vertices[index];
        const b = vertices[sequence[(k + 1) % sequence.len]];
        const u = c.f(a.x) / c.f(a.d) - c.f(site.x);
        const w = c.f(a.y) / c.f(a.d) - c.f(site.y);
        const un = c.f(b.x) / c.f(b.d) - c.f(site.x);
        const wn = c.f(b.y) / c.f(b.d) - c.f(site.y);
        out += u * wn - un * w;
    }
    return out / 2;
}
const RealPoint = struct { x: f64, y: f64 };
fn side(p: RealPoint, c1: i64, c2: i64, c3: i64) f64 {
    return c.f(c1) * p.x + c.f(c2) * p.y - c.f(c3);
}
pub fn clippedArea(points: []const c.Point, site: usize, neighbors: []const usize) f64 {
    var polygon: std.ArrayList(RealPoint) = .empty;
    for ([_]RealPoint{ .{ .x = 0, .y = 0 }, .{ .x = 1000, .y = 0 }, .{ .x = 1000, .y = 1000 }, .{ .x = 0,
         .y = 1000 } }) |point| c.append(RealPoint, &polygon, point);
    const s = points[site];
    for (neighbors) |neighbor| {
        const t = points[neighbor];
        const c1 = 2 * (t.x - s.x);
        const c2 = 2 * (t.y - s.y);
        const c3 = t.x * t.x + t.y * t.y - s.x * s.x - s.y * s.y;
        var next: std.ArrayList(RealPoint) = .empty;
        for (polygon.items, 0..) |p, k| {
            const q = polygon.items[(k + 1) % polygon.items.len];
            const fp = side(p, c1, c2, c3);
            const fq = side(q, c1, c2, c3);
            if (fp <= 0) c.append(RealPoint, &next, p);
            if ((fp < 0 and fq > 0) or (fq < 0 and fp > 0)) {
                const lambda = fp / (fp - fq);
                c.append(RealPoint, &next, .{ .x = p.x + (q.x - p.x) * lambda, .y = p.y + (q.y - p.y) * lambda });
            }
        }
        polygon = next;
    }
    var sum: f64 = 0;
    for (polygon.items, 0..) |p, k| {
        const q = polygon.items[(k + 1) % polygon.items.len];
        sum += p.x * q.y - q.x * p.y;
    }
    return sum / 2;
}
