const std = @import("std");
const C = @import("clues.zig");
const L = @import("line_solver.zig");
pub const Grid = struct {
    width: usize, height: usize, cells: [900]L.Cell = [_]L.Cell{.unknown} ** 900,
    pub fn get(self: *const Grid, row: usize, column: usize) L.Cell { return self.cells[row * self.width + column]; }
    pub fn set(self: *Grid, row: usize, column: usize, value: L.Cell) void { self.cells[row * self.width + column] = value; }
    pub fn line(self: *const Grid, is_row: bool, index: usize) [30]L.Cell { var result: [30]L.Cell = undefined; const count = if (is_row) self.width else self.height; for (0..count) |position| result[position] = if (is_row) self.get(index, position) else self.get(position, index); return result; }
    pub fn known(self: *const Grid) usize { var count: usize = 0; for (self.cells[0..self.width * self.height]) |state| { if (state != .unknown) count += 1; } return count; }
};
pub const Step = struct {
    is_row: bool, index: usize, gain: usize, contradiction: bool = false,
    pub fn label(self: Step) []const u8 { return lineLabel(self.is_row, self.index); }
    pub fn text(self: Step) []const u8 { return if (self.contradiction) C.fmt("{s}!", .{self.label()}) else C.fmt("{s}+{d}", .{ self.label(), self.gain }); }
};
pub fn lineLabel(is_row: bool, index: usize) []const u8 { return C.fmt("{c}{d}", .{ if (is_row) @as(u8, 'R') else @as(u8, 'C'), index + 1 }); }
pub const Result = struct { steps: std.ArrayList(Step) = .empty, conflict: ?Step = null };
pub fn propagate(allocator: std.mem.Allocator, grid: *Grid, rows: C.Clues, columns: C.Clues, precise: bool, row_marks: *[30]bool, column_marks: *[30]bool) Result {
    var result: Result = .{};
    while (true) { var chosen: ?usize = null; var is_row = true; for (row_marks[0..grid.height], 0..) |mark, i| { if (mark) { chosen = i; break; } } if (chosen == null) { is_row = false; for (column_marks[0..grid.width], 0..) |mark, i| { if (mark) { chosen = i; break; } } } const index = chosen orelse return result;
        if (is_row) row_marks[index] = false else column_marks[index] = false; const clue = if (is_row) rows[index] else columns[index]; const count = if (is_row) grid.width else grid.height; const cells = grid.line(is_row, index); const solved = L.solve(cells[0..count], clue, precise);
        if (!solved.consistent) { const step: Step = .{ .is_row = is_row, .index = index, .gain = 0, .contradiction = true }; result.steps.append(allocator, step) catch @panic("allocation failed"); result.conflict = step; return result; }
        var gain: usize = 0; for (cells[0..count], solved.cells[0..count], 0..) |old, value, position| { if (old != .unknown or value == .unknown) continue; gain += 1; if (is_row) { grid.set(index, position, value); column_marks[position] = true; } else { grid.set(position, index, value); row_marks[position] = true; } }
        result.steps.append(allocator, .{ .is_row = is_row, .index = index, .gain = gain }) catch @panic("allocation failed");
    }
}
