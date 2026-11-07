const std = @import("std");
const g = @import("grid.zig");
pub fn startsRun(grid: g.Grid, row: usize, column: usize, across: bool) bool {
    return grid.isOpen(g.n(row), g.n(column)) and !grid.isOpen(g.n(row) - @intFromBool(!across), g.n(column) - @intFromBool(across));
}
pub fn runLength(grid: g.Grid, row: usize, column: usize, across: bool) usize {
    var length: usize = 0;
    while (grid.isOpen(g.n(row + length * @intFromBool(!across)), g.n(column + length * @intFromBool(across)))) length += 1;
    return length;
}
pub const ShortRun = struct { cell: usize, across: bool };
pub fn shortRun(grid: g.Grid) ?ShortRun {
    for (0..grid.height) |row| {
        for (0..grid.width) |column| {
            for (0..2) |direction| {
                const across = direction == 0;
                if (startsRun(grid, row, column, across) and runLength(grid, row, column, across) == 2) return .{ .cell = row * grid.width + column, .across = across };
            }
        }
    }
    return null;
}
pub const Slot = struct { number: usize, across: bool, cells: []usize, label: []const u8, crossings: []usize = &.{} };
pub const Layout = struct {
    grid: g.Grid, slots: []Slot, numbers: []usize, across: []?usize, down: []?usize,
    pub fn init(grid: g.Grid) Layout {
        var result: Layout = .{ .grid = grid, .slots = undefined, .numbers = g.alloc(usize, grid.cells.len), .across = g.alloc(?usize, grid.cells.len), .down = g.alloc(?usize, grid.cells.len) };
        @memset(result.numbers, 0);
        @memset(result.across, null);
        @memset(result.down, null);
        var entries: std.ArrayList(Slot) = .empty;
        var numbered: usize = 0;
        for (0..grid.height) |row| {
            for (0..grid.width) |column| {
                for (0..2) |direction| {
                    const across = direction == 0;
                    if (!startsRun(grid, row, column, across)) continue;
                    const length = runLength(grid, row, column, across);
                    if (length < 3) continue;
                    const start = row * grid.width + column;
                    if (result.numbers[start] == 0) { numbered += 1; result.numbers[start] = numbered; }
                    const cells = g.alloc(usize, length);
                    const owners = if (across) result.across else result.down;
                    for (cells, 0..) |*cell, i| {
                        cell.* = (row + i * @intFromBool(!across)) * grid.width + column + i * @intFromBool(across);
                        owners[cell.*] = entries.items.len;
                    }
                    g.append(Slot, &entries, .{ .number = result.numbers[start], .across = across, .cells = cells, .label = g.fmt("{d}{s}", .{ result.numbers[start], if (across) "A" else "D" }) });
                }
            }
        }
        result.slots = entries.items;
        for (result.slots) |*slot| {
            var crossed = [_]bool{false} ** 150;
            const owners = if (slot.across) result.down else result.across;
            for (slot.cells) |cell| if (owners[cell]) |other| { crossed[other] = true; };
            var crossings: std.ArrayList(usize) = .empty;
            for (0..result.slots.len) |i| if (crossed[i]) { g.append(usize, &crossings, i); };
            slot.crossings = crossings.items;
        }
        return result;
    }
    pub fn ownerCount(self: Layout, cell: usize) usize { return @as(usize, @intFromBool(self.across[cell] != null)) + @intFromBool(self.down[cell] != null); }
};
