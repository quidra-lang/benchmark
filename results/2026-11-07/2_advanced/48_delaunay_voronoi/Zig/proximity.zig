const std = @import("std");
const c = @import("predicates.zig");
const triangulation = @import("triangulation.zig");
pub const Edge = struct { a: usize, b: usize, left: ?usize, right: ?usize, length2: i64, gabriel: bool = false,
     rng: bool = false, mst: bool = false };
pub const Disjoint = struct {
    parent: []usize,
    pub fn init(n: usize) Disjoint {
        const parent = c.alloc(usize, n);
        for (parent, 0..) |*value, i| value.* = i;
        return .{ .parent = parent };
    }
    pub fn find(self: *Disjoint, value: usize) usize {
        if (self.parent[value] != value) self.parent[value] = self.find(self.parent[value]);
        return self.parent[value];
    }
    pub fn join(self: *Disjoint, a_: usize, b_: usize) bool {
        const a = self.find(a_);
        const b = self.find(b_);
        if (a == b) return false;
        self.parent[b] = a;
        return true;
    }
};
pub fn nearest(points: []const c.Point, neighbors: []const []const usize) []const usize {
    const out = c.alloc(usize, points.len);
    for (points, 0..) |point, s| {
        var best = neighbors[s][0];
        for (neighbors[s]) |t| if (c.d2(point, points[t]) < c.d2(point, points[best]) or (c.d2(point,
             points[t]) == c.d2(point, points[best]) and t < best)) {
            best = t;
        };
        out[s] = best;
    }
    return out;
}
fn edgeLess(edges: []const Edge, a: usize, b: usize) bool {
    return if (edges[a].length2 != edges[b].length2) edges[a].length2 < edges[b].length2 else a < b;
}
pub fn kruskal(edges: []Edge, sites: usize) []const usize {
    const order = c.alloc(usize, edges.len);
    for (order, 0..) |*value, i| value.* = i;
    std.mem.sort(usize, order, @as([]const Edge, edges), edgeLess);
    var sets = Disjoint.init(sites);
    var out: std.ArrayList(usize) = .empty;
    for (order) |index| if (sets.join(edges[index].a, edges[index].b)) {
        edges[index].mst = true;
        c.append(usize, &out, index);
    };
    return out.items;
}
pub fn gabriel(points: []const c.Point, t: triangulation.Triangulation, a: usize, b: usize) bool {
    if (t.third(a, b)) |q| if (c.dot(points[q], points[a], points[b]) <= 0) return false;
    if (t.third(b, a)) |q| if (c.dot(points[q], points[a], points[b]) <= 0) return false;
    return true;
}
pub fn relativeNeighborhood(points: []const c.Point, a: usize, b: usize) bool {
    const length = c.d2(points[a], points[b]);
    for (points) |point| if (c.d2(points[a], point) < length and c.d2(points[b], point) < length) return false;
    return true;
}
pub fn greedyRoute(points: []const c.Point, neighbors: []const []const usize, source: usize, target: usize) []const usize {
    var out: std.ArrayList(usize) = .empty;
    c.append(usize, &out, source);
    var current = source;
    while (current != target) {
        var best = neighbors[current][0];
        for (neighbors[current]) |next| if (c.d2(points[next], points[target]) < c.d2(points[best],
             points[target]) or (c.d2(points[next], points[target]) == c.d2(points[best], points[target]) and next < best)) {
            best = next;
        };
        current = best;
        c.append(usize, &out, current);
    }
    return out.items;
}
pub const Paths = struct { distance: c.Vector, previous: []?usize };
pub fn dijkstra(points: []const c.Point, neighbors: []const []const usize, source: usize) Paths {
    const distance = c.vector(points.len);
    @memset(distance, std.math.inf(f64));
    const previous = c.alloc(?usize, points.len);
    @memset(previous, null);
    const visited = c.alloc(bool, points.len);
    @memset(visited, false);
    distance[source] = 0;
    for (0..points.len) |_| {
        var current: ?usize = null;
        for (0..points.len) |v| if (!visited[v] and (current == null or distance[v] < distance[current.?])) {
            current = v;
        };
        const site = current.?;
        visited[site] = true;
        for (neighbors[site]) |next| {
            const value = distance[site] + @sqrt(c.f(c.d2(points[site], points[next])));
            if (value < distance[next]) {
                distance[next] = value;
                previous[next] = site;
            }
        }
    }
    return .{ .distance = distance, .previous = previous };
}
