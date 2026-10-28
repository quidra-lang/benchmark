const std = @import("std");
const d = @import("dataset.zig");
const Grid = @import("grid_index.zig").Grid;
pub const Optics = struct { core: []i64, reach: []i64, predecessor: []?usize, order: []usize };
fn integerLess(_: void, a: i64, b: i64) bool {
    return a < b;
}
pub fn run(grid: *const Grid, distances: d.Distances, min_points: usize) Optics {
    const n = grid.neighbors.len;
    const result: Optics = .{ .core = d.alloc(i64, n), .reach = d.alloc(i64, n), .predecessor = d.alloc(?usize,
         n), .order = d.alloc(usize, n) };
    @memset(result.core, d.INF);
    @memset(result.reach, d.INF);
    @memset(result.predecessor, null);
    for (grid.neighbors, 0..) |neighbors, p| if (neighbors.len >= min_points) {
        const values = d.alloc(i64, neighbors.len);
        for (neighbors, values) |q, *value| value.* = distances[p][q];
        std.mem.sort(i64, values, {}, integerLess);
        result.core[p] = values[min_points - 1];
    };
    const processed = d.alloc(bool, n);
    const seeds = d.alloc(bool, n);
    @memset(processed, false);
    @memset(seeds, false);
    var position: usize = 0;
    for (0..n) |t| {
        if (processed[t]) continue;
        seeds[t] = true;
        while (true) {
            var selected: ?usize = null;
            for (seeds, 0..) |seed, q| if (seed and (selected == null or result.reach[q] < result.reach[selected.?] or (result.reach[q] == result.reach[selected.?] and q < selected.?))) {
                selected = q;
            };
            const p = selected orelse break;
            seeds[p] = false;
            processed[p] = true;
            result.order[position] = p;
            position += 1;
            if (result.core[p] == d.INF) continue;
            for (grid.neighbors[p]) |q| if (!processed[q]) {
                const reach = @max(result.core[p], distances[p][q]);
                if (reach < result.reach[q]) {
                    result.reach[q] = reach;
                    result.predecessor[q] = p;
                    seeds[q] = true;
                }
            };
        }
    }
    return result;
}
