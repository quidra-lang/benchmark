pub const Cell = enum(u8) { unknown, filled, empty };
const Table = [31][31]bool;
fn fitTable(cells: []const Cell, clue: []const usize) Table {
    var empties = [_]usize{0} ** 31; for (cells, 0..) |state, i| empties[i + 1] = empties[i] + @intFromBool(state == .empty);
    var table = [_][31]bool{[_]bool{false} ** 31} ** 31; table[0][0] = true;
    for (1..cells.len + 1) |end| { for (0..clue.len + 1) |blocks| { var fits = cells[end - 1] != .filled and table[end - 1][blocks];
        if (!fits and blocks > 0 and end >= clue[blocks - 1]) { const start = end - clue[blocks - 1]; if (empties[end] == empties[start]) fits = if (start == 0) blocks == 1 else cells[start - 1] != .filled and table[start - 1][blocks - 1]; }
        table[end][blocks] = fits;
    } }
    return table;
}
pub fn hasPlacement(cells: []const Cell, clue: []const usize) bool { const table = fitTable(cells, clue); return table[cells.len][clue.len]; }
const Placements = struct {
    cells: []const Cell, clue: []const usize, before: Table, after: Table,
    fn init(cells: []const Cell, clue: []const usize) Placements { var reversed: [30]Cell = undefined; var reversed_clue: [30]usize = undefined; for (cells, 0..) |state, i| reversed[cells.len - 1 - i] = state; for (clue, 0..) |value, i| reversed_clue[clue.len - 1 - i] = value; return .{ .cells = cells, .clue = clue, .before = fitTable(cells, clue), .after = fitTable(reversed[0..cells.len], reversed_clue[0..clue.len]) }; }
    fn canStart(self: *const Placements, block: usize, start: usize) bool { const end = start + self.clue[block]; for (self.cells[start..end]) |state| { if (state == .empty) return false; } const left = if (start == 0) block == 0 else self.cells[start - 1] != .filled and self.before[start - 1][block]; const rest = self.clue.len - block - 1; const right = if (end == self.cells.len) rest == 0 else self.cells[end] != .filled and self.after[self.cells.len - end - 1][rest]; return left and right; }
    fn canBeEmpty(self: *const Placements, index: usize) bool { if (self.cells[index] == .filled) return false; for (0..self.clue.len + 1) |blocks| { if (self.before[index][blocks] and self.after[self.cells.len - index - 1][self.clue.len - blocks]) return true; } return false; }
};
pub const Result = struct { consistent: bool, cells: [30]Cell = [_]Cell{.unknown} ** 30 };
pub fn solve(cells: []const Cell, clue: []const usize, precise: bool) Result {
    const placements = Placements.init(cells, clue); if (!placements.before[cells.len][clue.len]) return .{ .consistent = false }; var result: Result = .{ .consistent = true }; @memcpy(result.cells[0..cells.len], cells); var covered = [_]bool{false} ** 30;
    for (clue, 0..) |length, block| { var low: ?usize = null; var high: usize = 0; for (0..cells.len - length + 1) |start| { if (!placements.canStart(block, start)) continue; if (low == null) low = start; high = start; if (precise) @memset(covered[start..start + length], true); }
        if (!precise) { if (high < low.? + length) { for (high..low.? + length) |i| { if (result.cells[i] == .unknown) result.cells[i] = .filled; } } @memset(covered[low.?..high + length], true); }
    }
    for (cells, 0..) |state, i| { if (state != .unknown) continue; if (precise) { const emptiable = placements.canBeEmpty(i); if (covered[i] and !emptiable) result.cells[i] = .filled else if (emptiable and !covered[i]) result.cells[i] = .empty; } else if (result.cells[i] == .unknown and !covered[i]) result.cells[i] = .empty; }
    return result;
}
