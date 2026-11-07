const std = @import("std");
const c = @import("predicates.zig");
pub const Insertion = struct { site: usize, inside: bool = false, containing: c.Triangle = .{ 0, 0,
     0 }, visible: usize = 0, flips: usize = 0, triangles: usize = 0, hull: usize = 0 };
pub const Walk = struct { path: []const usize, outside: bool = false, edge: c.Pair = .{ .a = 0, .b = 0 } };
pub const Triangulation = struct {
    directed: [][]?usize,
    entries: usize = 0,
    pub fn add(self: *Triangulation, a: usize, b: usize, q: usize) void {
        self.set(a, b, q);
        self.set(b, q, a);
        self.set(q, a, b);
    }
    fn set(self: *Triangulation, a: usize, b: usize, q: usize) void {
        if (self.directed[a][b] == null) self.entries += 1;
        self.directed[a][b] = q;
    }
    pub fn remove(self: *Triangulation, a: usize, b: usize, q: usize) void {
        self.erase(a, b);
        self.erase(b, q);
        self.erase(q, a);
    }
    fn erase(self: *Triangulation, a: usize, b: usize) void {
        if (self.directed[a][b] != null) self.entries -= 1;
        self.directed[a][b] = null;
    }
    pub fn third(self: Triangulation, a: usize, b: usize) ?usize {
        return self.directed[a][b];
    }
    pub fn triangles(self: Triangulation) []const c.Triangle {
        var out: std.ArrayList(c.Triangle) = .empty;
        for (0..self.directed.len) |a| for (a + 1..self.directed.len) |b| {
            if (self.directed[a][b]) |q| if (q > a) c.append(c.Triangle, &out, .{ a, b, q });
        };
        return out.items;
    }
    pub fn hullEdges(self: Triangulation) []const c.Pair {
        var out: std.ArrayList(c.Pair) = .empty;
        for (0..self.directed.len) |a| for (0..self.directed.len) |b| {
            if (self.directed[a][b] != null and self.directed[b][a] == null) c.append(c.Pair, &out, .{ .a = a, .b = b });
        };
        return out.items;
    }
    pub fn insert(self: *Triangulation, points: []const c.Point, s: usize) Insertion {
        var out: Insertion = .{ .site = s };
        var pending: std.ArrayList(c.Pair) = .empty;
        for (self.triangles()) |triangle| if (c.orient(points[triangle[0]], points[triangle[1]], points[s]) > 0 and c.orient(points[triangle[1]],
             points[triangle[2]], points[s]) > 0 and c.orient(points[triangle[2]], points[triangle[0]],
             points[s]) > 0) {
            out.inside = true;
            out.containing = triangle;
            self.remove(triangle[0], triangle[1], triangle[2]);
            for (0..3) |k| {
                const a = triangle[k];
                const b = triangle[(k + 1) % 3];
                self.add(a, b, s);
                pendingAdd(&pending, .{ .a = a, .b = b });
            }
            break;
        };
        if (!out.inside) for (self.hullEdges()) |edge| {
            if (c.orient(points[edge.a], points[edge.b], points[s]) < 0) {
                out.visible += 1;
                self.add(edge.b, edge.a, s);
                pendingAdd(&pending, .{ .a = edge.b, .b = edge.a });
            }
        };
        while (pending.items.len > 0) {
            const edge = pendingPop(&pending);
            const a = edge.a;
            const b = edge.b;
            if (self.third(a, b) != s) continue;
            const q = self.third(b, a) orelse continue;
            if (c.incircle(points[a], points[b], points[s], points[q]) <= 0) continue;
            self.remove(a, b, s);
            self.remove(b, a, q);
            self.add(a, q, s);
            self.add(q, b, s);
            pendingAdd(&pending, .{ .a = a, .b = q });
            pendingAdd(&pending, .{ .a = q, .b = b });
            out.flips += 1;
        }
        out.triangles = self.entries / 3;
        out.hull = self.hullEdges().len;
        return out;
    }
    pub fn walk(self: Triangulation, points: []const c.Point, query: c.Point) Walk {
        const values = self.triangles();
        var path: std.ArrayList(usize) = .empty;
        var current: usize = 0;
        c.append(usize, &path, current);
        while (true) {
            const triangle = values[current];
            var moved = false;
            for (0..3) |k| {
                const a = triangle[k];
                const b = triangle[(k + 1) % 3];
                if (c.orient(points[a], points[b], query) >= 0) continue;
                const q = self.third(b, a) orelse return .{ .path = path.items, .outside = true, .edge = .{ .a = @min(a,
                     b), .b = @max(a, b) } };
                const target = c.canonical(.{ b, a, q });
                for (values, 0..) |value, i| if (std.meta.eql(value, target)) {
                    current = i;
                    break;
                };
                c.append(usize, &path, current);
                moved = true;
                break;
            }
            if (!moved) return .{ .path = path.items };
        }
    }
};
fn pendingAdd(pending: *std.ArrayList(c.Pair), value: c.Pair) void {
    for (pending.items) |entry| if (entry.a == value.a and entry.b == value.b) return;
    c.append(c.Pair, pending, value);
}
fn pendingPop(pending: *std.ArrayList(c.Pair)) c.Pair {
    var smallest: usize = 0;
    for (pending.items[1..], 1..) |value, i| {
        const previous = pending.items[smallest];
        if (value.a < previous.a or (value.a == previous.a and value.b < previous.b)) smallest = i;
    }
    return pending.swapRemove(smallest);
}
pub fn initialize(points: []const c.Point) Triangulation {
    const directed = c.alloc([]?usize, points.len);
    for (directed) |*row| {
        row.* = c.alloc(?usize, points.len);
        @memset(row.*, null);
    }
    var out: Triangulation = .{ .directed = directed };
    if (c.orient(points[0], points[1], points[2]) > 0) out.add(0, 1, 2) else out.add(0, 2, 1);
    return out;
}
