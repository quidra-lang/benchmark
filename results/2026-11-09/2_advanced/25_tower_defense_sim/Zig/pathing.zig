const g = @import("grid_map.zig");
pub const directions = [_]g.Cell{ .{ .x = 0, .y = -1 }, .{ .x = 1, .y = 0 }, .{ .x = 0, .y = 1 }, .{ .x = -1, .y = 0 } };
pub fn neighbor(cell: g.Cell, direction: usize) g.Cell { return .{ .x = cell.x + directions[direction].x, .y = cell.y + directions[direction].y }; }
pub const DistanceField = struct {
    grid: *const g.GridMap,
    dist: [1200]i64 = @splat(-1),

    pub fn compute(grid: *const g.GridMap, blocked: []const bool) DistanceField {
        var result: DistanceField = .{ .grid = grid };
        result.dist[grid.index(grid.exit)] = 0;
        var queue: [1200]g.Cell = undefined;
        queue[0] = grid.exit;
        var head: usize = 0;
        var tail: usize = 1;
        while (head < tail) : (head += 1) {
            const cell = queue[head];
            for (0..directions.len) |candidate_direction| {
                const following = neighbor(cell, candidate_direction);
                if (!grid.inside(following) or grid.rock(following)) continue;
                const index = grid.index(following);
                if (blocked[index] or result.dist[index] >= 0) continue;
                result.dist[index] = result.at(cell) + 1;
                queue[tail] = following;
                tail += 1;
            }
        }
        return result;
    }
    pub fn at(self: *const DistanceField, cell: g.Cell) i64 { return self.dist[self.grid.index(cell)]; }
    pub fn direction(self: *const DistanceField, cell: g.Cell) usize {
        var best: ?usize = null;
        var best_distance: i64 = 0;
        for (0..directions.len) |candidate| {
            const following = neighbor(cell, candidate);
            if (!self.grid.inside(following)) continue;
            const distance = self.at(following);
            if (distance < 0) continue;
            if (best == null or distance < best_distance) {
                best = candidate;
                best_distance = distance;
            }
        }
        return best.?;
    }
    pub fn nextCell(self: *const DistanceField, cell: g.Cell) g.Cell { return neighbor(cell, self.direction(cell)); }
    pub fn path(self: *const DistanceField, start: g.Cell) []g.Cell {
        const cells = g.alloc(g.Cell, g.u(self.at(start) + 1));
        cells[0] = start;
        for (1..cells.len) |index| cells[index] = self.nextCell(cells[index - 1]);
        return cells;
    }
};
