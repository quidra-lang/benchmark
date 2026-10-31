const std = @import("std");
const c = @import("dataset.zig");
pub const Grid = struct {
    world: usize,
    side: usize,
    dimension: usize,
    cells: []std.ArrayList(c.Point),
    pub fn init(world: usize, side: usize) Grid {
        const dimension = world / side;
        const cells = c.alloc(std.ArrayList(c.Point), dimension * dimension);
        @memset(cells, .empty);
        return .{ .world = world, .side = side, .dimension = dimension, .cells = cells };
    }
    pub fn insert(self: *Grid, point: c.Point) void {
        c.pointInsert(&self.cells[c.u(point.y) / self.side * self.dimension + c.u(point.x) / self.side], point);
    }
    pub fn delete(self: *Grid, point: c.Point) void {
        c.pointRemove(&self.cells[c.u(point.y) / self.side * self.dimension + c.u(point.x) / self.side], point.id);
    }
};
