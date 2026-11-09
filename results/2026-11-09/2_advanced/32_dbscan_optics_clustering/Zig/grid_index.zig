const std = @import("std");
const d = @import("dataset.zig");
pub const Grid = struct { radius: i64, cells: std.AutoHashMap([2]i64, std.ArrayList(usize)), neighbors: []const []const usize,
     candidates: []usize, occupancy: []usize, busiest_x: i64 = 0, busiest_y: i64 = 0, busiest_count: usize = 0,
     total_candidates: i64 = 0, pairs: i64 = 0, brute_pairs: i64 = 0, correct: bool = true };
pub fn build(points: []const d.Point, distances: d.Distances, radius: i64) Grid {
    var cells = std.AutoHashMap([2]i64, std.ArrayList(usize)).init(d.allocator);
    for (points, 0..) |point, index| {
        const key = [2]i64{ @divTrunc(point.x, radius), @divTrunc(point.y, radius) };
        if (!cells.contains(key)) cells.put(key, .empty) catch @panic("allocation failed");
        d.append(usize, cells.getPtr(key).?, index);
    }
    const neighbors = d.alloc([]const usize, points.len);
    var result: Grid = .{ .radius = radius, .cells = cells, .neighbors = neighbors, .candidates = d.alloc(usize,
         points.len), .occupancy = d.alloc(usize, points.len + 1) };
    @memset(result.candidates, 0);
    @memset(result.occupancy, 0);
    var iterator = cells.iterator();
    while (iterator.next()) |entry| {
        const key = entry.key_ptr.*;
        const count = entry.value_ptr.items.len;
        result.occupancy[count] += 1;
        if (count > result.busiest_count or (count == result.busiest_count and (key[1] < result.busiest_y or (key[1] == result.busiest_y and key[0] < result.busiest_x)))) {
            result.busiest_count = count;
            result.busiest_x = key[0];
            result.busiest_y = key[1];
        }
    }
    var neighbor_total: i64 = 0;
    var brute_total: i64 = 0;
    for (points, 0..) |point, index| {
        const gx = @divTrunc(point.x, radius);
        const gy = @divTrunc(point.y, radius);
        var found: std.ArrayList(usize) = .empty;
        var row = gy - 1;
        while (row <= gy + 1) : (row += 1) {
            var column = gx - 1;
            while (column <= gx + 1) : (column += 1) {
                if (cells.get(.{ column, row })) |cell| for (cell.items) |q| {
                    result.candidates[index] += 1;
                    if (distances[index][q] <= radius * radius) d.append(usize, &found, q);
                };
            }
        }
        neighbors[index] = found.items;
        var brute: usize = 0;
        for (distances[index]) |squared| if (squared <= radius * radius) {
            brute += 1;
        };
        if (brute != found.items.len) result.correct = false;
        brute_total += d.n(brute);
        neighbor_total += d.n(found.items.len);
        result.total_candidates += d.n(result.candidates[index]);
    }
    result.pairs = @divTrunc(neighbor_total - d.n(points.len), 2);
    result.brute_pairs = @divTrunc(brute_total - d.n(points.len), 2);
    return result;
}
