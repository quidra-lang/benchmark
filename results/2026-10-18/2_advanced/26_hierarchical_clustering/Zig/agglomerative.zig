const d = @import("dataset.zig");
pub const Merge = struct { a: usize, b: usize, height: f64, size: usize };
pub const Edge = struct { parent: usize, child: usize, weight: f64 };
pub fn lanceWilliams(method: []const u8, size_a: usize, size_b: usize, size_k: usize) [4]f64 {
    if (d.eq(method, "single")) return .{ 0.5, 0.5, 0, -0.5 };
    if (d.eq(method, "complete")) return .{ 0.5, 0.5, 0, 0.5 };
    const merged = size_a + size_b;
    if (d.eq(method, "average")) return .{ d.f(size_a) / d.f(merged), d.f(size_b) / d.f(merged), 0, 0 };
    if (d.eq(method, "weighted")) return .{ 0.5, 0.5, 0, 0 };
    if (d.eq(method, "centroid")) return .{ d.f(size_a) / d.f(merged), d.f(size_b) / d.f(merged), -d.f(size_a * size_b) / d.f(merged * merged), 0 };
    if (d.eq(method, "median")) return .{ 0.5, 0.5, -0.25, 0 };
    const total = merged + size_k;
    return .{ d.f(size_a + size_k) / d.f(total), d.f(size_b + size_k) / d.f(total), -d.f(size_k) / d.f(total), 0 };
}
pub fn agglomerate(delta: d.Matrix, method: []const u8) []Merge {
    const count = delta.len;
    const capacity = 2 * count - 1;
    const values = d.scratch.alloc(f64, capacity * capacity) catch @panic("allocation failed");
    defer d.scratch.free(values);
    @memset(values, 0);
    const squared = d.eq(method, "centroid") or d.eq(method, "median") or d.eq(method, "ward");
    for (0..count) |u| {
        for (0..count) |w| values[u * capacity + w] = if (squared) delta[u][w] * delta[u][w] else delta[u][w];
    }
    var sizes: [239]usize = @splat(1);
    var active: [239]bool = @splat(false);
    @memset(active[0..count], true);
    const merges = d.alloc(Merge, count - 1);
    for (merges, 0..) |*merge, step| {
        const node = count + step;
        var best_a: ?usize = null;
        var best_b: usize = 0;
        var best: f64 = 0;
        for (0..node) |a| {
            if (!active[a]) continue;
            for (a + 1..node) |b| {
                if (!active[b]) continue;
                const value = values[a * capacity + b];
                if (best_a == null or value < best) { best_a = a; best_b = b; best = value; }
            }
        }
        const a = best_a.?;
        const b = best_b;
        sizes[node] = sizes[a] + sizes[b];
        merge.* = .{ .a = a, .b = b, .height = if (squared) @sqrt(best) else best, .size = sizes[node] };
        for (0..node) |k| {
            if (!active[k] or k == a or k == b) continue;
            const coefficients = lanceWilliams(method, sizes[a], sizes[b], sizes[k]);
            const first = values[a * capacity + k];
            const second = values[b * capacity + k];
            const value = coefficients[0] * first + coefficients[1] * second + coefficients[2] * best + coefficients[3] * @abs(first - second);
            values[node * capacity + k] = value;
            values[k * capacity + node] = value;
        }
        active[a] = false;
        active[b] = false;
        active[node] = true;
    }
    return merges;
}
pub fn minimumSpanningTree(delta: d.Matrix) []Edge {
    const count = delta.len;
    var in_tree: [120]bool = @splat(false);
    in_tree[0] = true;
    var keys: [120]f64 = undefined;
    @memcpy(keys[0..count], delta[0]);
    var parents: [120]usize = @splat(0);
    const edges = d.alloc(Edge, count - 1);
    for (edges) |*edge| {
        var chosen: ?usize = null;
        for (0..count) |u| {
            if (!in_tree[u] and (chosen == null or keys[u] < keys[chosen.?])) chosen = u;
        }
        const vertex = chosen.?;
        in_tree[vertex] = true;
        edge.* = .{ .parent = parents[vertex], .child = vertex, .weight = keys[vertex] };
        for (0..count) |u| {
            if (!in_tree[u] and delta[vertex][u] < keys[u]) {
                keys[u] = delta[vertex][u];
                parents[u] = vertex;
            }
        }
    }
    return edges;
}
