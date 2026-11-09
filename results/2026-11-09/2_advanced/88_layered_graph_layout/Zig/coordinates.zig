const std = @import("std");
const g = @import("graph_io.zig");
const c = @import("crossing.zig");
pub const Result = struct { aligned: [4][]i64, x: []i64, blocks: [4]usize, widths: [4]i64, smallest: usize, conflicts: usize };
fn delta(graph: *const g.Graph, a: usize, b: usize) i64 { const v = graph.vertices.items; return v[a].right + v[b].left + 1 + (if (!v[a].dummy and !v[b].dummy) graph.settings.node_sep else graph.settings.dummy_sep); }
fn marked(graph: *const g.Graph, a: usize, b: usize) bool { for (graph.segments.items) |s| if (((s.upper == a and s.lower == b) or (s.upper == b and s.lower == a)) and s.marked) return true; return false; }
pub fn assign(graph: *g.Graph, orders: c.Orders) Result {
    const n = graph.vertices.items.len; const pos = c.positions(orders, n);
    for (0..orders.len - 1) |layer| {
        const upper = orders[layer]; const lower = orders[layer + 1]; var k0: usize = 0; var t: usize = 0;
        for (lower, 0..) |v, l1| {
            const refs = c.neighbors(graph, v, true); const inner = graph.vertices.items[v].dummy and refs.len == 1 and graph.vertices.items[refs[0]].dummy;
            if (inner or l1 + 1 == lower.len) {
                const k1 = if (inner) pos[refs[0]] else upper.len - 1;
                for (lower[t .. l1 + 1]) |w| for (graph.segments.items) |*s| { if (s.lower == w and (pos[s.upper] < k0 or pos[s.upper] > k1)) s.marked = true; };
                t = l1 + 1; k0 = k1;
            }
        }
    }
    var result: Result = undefined; result.conflicts = 0; for (graph.segments.items) |s| result.conflicts += @intFromBool(s.marked);
    var lows: [4]i64 = undefined; var highs: [4]i64 = undefined;
    for (0..4) |variant| {
        const down = variant >= 2; const right = variant % 2 == 1; const root = g.alloc(usize, n); const align = g.alloc(usize, n); const rank = g.alloc(usize, n);
        for (0..n) |v| { root[v] = v; align[v] = v; }
        for (orders) |layer| for (layer, 0..) |v, i| { rank[v] = if (right) layer.len - 1 - i else i; };
        for (1..orders.len) |step| {
            const layer = if (down) orders.len - 1 - step else step; const row = orders[layer]; var rho: i64 = -1;
            for (0..row.len) |j| { const v = row[if (right) row.len - 1 - j else j]; const refs = c.neighbors(graph, v, !down); if (refs.len == 0) continue;
                std.mem.sort(usize, refs, rank, struct { fn less(ranks: []const usize, a: usize, b: usize) bool { return ranks[a] < ranks[b]; } }.less);
                for ([_]usize{(refs.len - 1) / 2, refs.len / 2}) |median| { const u = refs[median]; if (align[v] == v and !marked(graph, u, v) and rho < @as(i64, @intCast(rank[u]))) { align[u] = v; root[v] = root[u]; align[v] = root[v]; rho = @intCast(rank[u]); } }
            }
        }
        const weights = g.zero(i64, n * n, 0); const indegrees = g.zero(usize, n, 0); var blocks: std.ArrayList(usize) = .empty;
        for (0..n) |v| if (root[v] == v) g.append(usize, &blocks, v);
        for (orders) |row| { for (1..row.len) |j| { const a = row[if (right) row.len - j else j - 1]; const b = row[if (right) row.len - j - 1 else j]; const distance = if (right) delta(graph, b, a) else delta(graph, a, b); const key = root[a] * n + root[b]; weights[key] = @max(weights[key], distance); } }
        for (blocks.items) |a| for (blocks.items) |b| { if (weights[a * n + b] > 0) indegrees[b] += 1; };
        var topo: std.ArrayList(usize) = .empty; const placed = g.zero(bool, n, false);
        while (topo.items.len < blocks.items.len) {
            var choice: ?usize = null; for (blocks.items) |v| if (!placed[v] and indegrees[v] == 0) { choice = v; break; };
            const v = choice orelse unreachable; placed[v] = true; g.append(usize, &topo, v); for (blocks.items) |w| if (weights[v * n + w] > 0) { indegrees[w] -= 1; };
        }
        const y1 = g.zero(i64, n, 0); for (topo.items) |v| for (blocks.items) |w| { const distance = weights[v * n + w]; if (distance > 0) y1[w] = @max(y1[w], y1[v] + distance); };
        const y2 = g.copy(i64, y1); var bi = topo.items.len; while (bi > 0) { bi -= 1; const v = topo.items[bi]; var value: ?i64 = null; for (blocks.items) |w| { const distance = weights[v * n + w]; if (distance > 0) value = if (value) |old| @min(old, y2[w] - distance) else y2[w] - distance; } if (value) |x| y2[v] = @max(y1[v], x); }
        const x = g.alloc(i64, n); var lo: i64 = std.math.maxInt(i64); var hi: i64 = std.math.minInt(i64);
        for (graph.vertices.items, 0..) |v, j| { x[j] = y2[root[j]] * (if (right) @as(i64, -1) else 1); lo = @min(lo, x[j] - v.left); hi = @max(hi, x[j] + v.right); }
        result.aligned[variant] = x; result.blocks[variant] = blocks.items.len; result.widths[variant] = hi - lo + 1; lows[variant] = lo; highs[variant] = hi;
    }
    result.smallest = 0; for (1..4) |variant| if (result.widths[variant] < result.widths[result.smallest]) { result.smallest = variant; };
    for (0..4) |variant| { const shift = if (variant % 2 == 0) lows[result.smallest] - lows[variant] else highs[result.smallest] - highs[variant]; for (result.aligned[variant]) |*x| x.* += shift; }
    result.x = g.alloc(i64, n); var minimum: i64 = std.math.maxInt(i64);
    for (graph.vertices.items, 0..) |v, j| { var values = [_]i64{result.aligned[0][j], result.aligned[1][j], result.aligned[2][j], result.aligned[3][j]}; std.mem.sort(i64, &values, {}, std.sort.asc(i64)); result.x[j] = @divFloor(values[1] + values[2], 2); minimum = @min(minimum, result.x[j] - v.left); }
    for (result.x) |*x| x.* -= minimum; return result;
}
