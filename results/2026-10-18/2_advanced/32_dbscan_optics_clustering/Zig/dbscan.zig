const std = @import("std");
const d = @import("dataset.zig");
const Grid = @import("grid_index.zig").Grid;
pub fn run(grid: *const Grid, min_points: usize) []i64 {
    const labels = d.alloc(i64, grid.neighbors.len);
    @memset(labels, -2);
    var cluster: i64 = 0;
    for (0..labels.len) |p| {
        if (labels[p] != -2) continue;
        if (grid.neighbors[p].len < min_points) {
            labels[p] = -1;
            continue;
        }
        labels[p] = cluster;
        var queue: std.ArrayList(usize) = .empty;
        for (grid.neighbors[p]) |id| d.append(usize, &queue, id);
        var front: usize = 0;
        while (front < queue.items.len) : (front += 1) {
            const q = queue.items[front];
            if (labels[q] == -1) {
                labels[q] = cluster;
                continue;
            }
            if (labels[q] >= 0) continue;
            labels[q] = cluster;
            if (grid.neighbors[q].len >= min_points) for (grid.neighbors[q]) |id| d.append(usize, &queue, id);
        }
        cluster += 1;
    }
    return labels;
}
