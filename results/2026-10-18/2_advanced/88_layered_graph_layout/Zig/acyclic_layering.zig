const std = @import("std");
const g = @import("graph_io.zig");
pub fn acyclic(graph: *g.Graph) []const usize {
    const n = graph.nodes; const remaining = g.zero(bool, n, true); var head: std.ArrayList(usize) = .empty; var tail: std.ArrayList(usize) = .empty;
    for (0..n) |_| {
        const indeg = g.zero(i64, n, 0); const outdeg = g.zero(i64, n, 0); for (graph.edges.items) |e| if (remaining[e.from] and remaining[e.to]) { outdeg[e.from] += 1; indeg[e.to] += 1; };
        var chosen: ?usize = null; var sink = false;
        for (0..n) |v| if (remaining[v] and outdeg[v] == 0) { chosen = v; sink = true; break; };
        if (chosen == null) for (0..n) |v| if (remaining[v] and indeg[v] == 0) { chosen = v; break; };
        if (chosen == null) { var best: i64 = std.math.minInt(i64); for (0..n) |v| if (remaining[v] and outdeg[v] - indeg[v] > best) { chosen = v; best = outdeg[v] - indeg[v]; }; }
        const v = chosen.?; remaining[v] = false; g.append(usize, if (sink) &tail else &head, v);
    }
    std.mem.reverse(usize, tail.items); for (tail.items) |v| g.append(usize, &head, v); const positions = g.alloc(usize, n); for (head.items, 0..) |v, i| positions[v] = i;
    for (graph.edges.items) |*e| { e.reversed = positions[e.from] > positions[e.to]; e.a = if (e.reversed) e.to else e.from; e.b = if (e.reversed) e.from else e.to; }
    if (graph.settings.reduce) { const reach = g.zero(bool, n * n, false); for (graph.edges.items) |e| reach[e.a * n + e.b] = true; for (0..n) |k| for (0..n) |i| for (0..n) |j| { reach[i * n + j] = reach[i * n + j] or (reach[i * n + k] and reach[k * n + j]); };
        for (graph.edges.items) |*e| { if (e.reversed) continue; for (graph.edges.items) |other| if (other.a == e.a and other.b != e.b and reach[other.b * n + e.b]) { e.transitive = true; break; }; }
    }
    return head.items;
}
pub const Promotion = struct { round: usize, vertex: usize, difference: i64 };
pub const Result = struct { heights: []i64, labels: []usize, promotions: []const Promotion, rounds: usize = 0, dummies_before: i64 = 0 };
fn promote(graph: *const g.Graph, h: []i64, v: usize) i64 { var difference: i64 = 0; for (graph.edges.items) |e| if (!e.transitive and e.b == v and h[e.a] == h[v] + 1) { difference += promote(graph, h, e.a); }; h[v] += 1; for (graph.edges.items) |e| if (!e.transitive) { if (e.a == v) difference += 1; if (e.b == v) difference -= 1; }; return difference; }
fn lexLess(a: []const usize, b: []const usize) bool { for (a[0..@min(a.len,b.len)], b[0..@min(a.len,b.len)]) |x,y| { if (x != y) return x < y; } return a.len < b.len; }
pub fn layers(graph: *g.Graph, order: []const usize) Result {
    const n = graph.nodes; const h = g.zero(i64, n, -1); const labels = g.zero(usize, n, 0);
    if (g.eq(graph.settings.layering, "longest")) { var i = n; while (i > 0) { i -= 1; const v = order[i]; h[v] = 0; for (graph.edges.items) |e| if (!e.transitive and e.a == v) { h[v] = @max(h[v], h[e.b] + 1); }; } }
    else {
        for (1..n + 1) |label| { var chosen: ?usize = null; var best: []const usize = &.{};
            for (0..n) |v| { if (labels[v] != 0) continue; var parents: std.ArrayList(usize) = .empty; var ready = true; for (graph.edges.items) |e| if (!e.transitive and e.b == v) { if (labels[e.a] == 0) ready = false; g.append(usize, &parents, labels[e.a]); }; if (!ready) continue; std.mem.sort(usize, parents.items, {}, std.sort.desc(usize)); if (chosen == null or lexLess(parents.items, best)) { chosen = v; best = parents.items; } } labels[chosen.?] = label;
        }
        var height: i64 = 0; var count: usize = 0;
        for (0..n) |_| { var chosen: ?usize = null; for (0..n) |v| { if (h[v] >= 0) continue; var ready = true; for (graph.edges.items) |e| if (!e.transitive and e.a == v and h[e.b] < 0) { ready = false; break; }; if (ready and (chosen == null or labels[v] > labels[chosen.?])) chosen = v; } const v = chosen.?; var collision = count == graph.settings.width; for (graph.edges.items) |e| if (!e.transitive and e.a == v and h[e.b] == height) { collision = true; }; if (collision) { height += 1; count = 0; } h[v] = height; count += 1; }
    }
    var result = Result{ .heights = h, .labels = labels, .promotions = &.{} }; for (graph.edges.items) |e| if (!e.transitive) { result.dummies_before += h[e.a] - h[e.b] - 1; };
    var records: std.ArrayList(Promotion) = .empty;
    if (graph.settings.promotion) while (true) { result.rounds += 1; var changed = false; for (0..n) |v| { var parent = false; for (graph.edges.items) |e| if (!e.transitive and e.b == v) { parent = true; break; }; if (!parent) continue; const saved = g.copy(i64, h); const difference = promote(graph, h, v); if (difference < 0) { changed = true; g.append(Promotion, &records, .{ .round = result.rounds, .vertex = v, .difference = difference }); } else @memcpy(h, saved); } if (!changed) break; };
    result.promotions = records.items; var maximum: i64 = 0; for (h) |x| maximum = @max(maximum, x); const used = g.zero(bool, @intCast(maximum + 1), false); for (h) |x| used[@intCast(maximum - x)] = true;
    for (graph.edges.items) |e| if (!e.transitive) { var level = maximum - h[e.a] + 1; while (level < maximum - h[e.b]) : (level += 1) used[@intCast(level)] = true; };
    const normalized = g.alloc(usize, used.len); var next: usize = 0; for (used, 0..) |yes, level| { normalized[level] = next; next += @intFromBool(yes); } for (graph.vertices.items, h) |*v, x| v.layer = normalized[@intCast(maximum - x)]; return result;
}
