const std = @import("std");
const C = @import("clues.zig");
const L = @import("line_solver.zig");
const P = @import("propagation.zig");
pub const Position = struct { row: usize, column: usize };
pub fn guessCell(grid: *const P.Grid) Position { var rows = [_]usize{0} ** 30; var columns = [_]usize{0} ** 30; for (0..grid.height) |r| { for (0..grid.width) |c| { if (grid.get(r, c) == .unknown) { rows[r] += 1; columns[c] += 1; } } } var best: ?Position = null; var score: usize = 0; for (0..grid.height) |r| { for (0..grid.width) |c| { if (grid.get(r, c) != .unknown) continue; const value = rows[r] + columns[c]; if (best == null or value < score) { best = .{ .row = r, .column = c }; score = value; } } } return best.?; }
pub const Guess = struct { number: usize, depth: usize, position: Position, value: L.Cell, solves: usize, known: usize, outcome: enum { contradiction, solution1, solution2, open }, conflict: ?P.Step = null };
pub const Search = struct {
    guesses: std.ArrayList(Guess) = .empty, solutions: std.ArrayList(P.Grid) = .empty, backtracks: usize = 0, max_depth: usize = 0, line_solves: usize = 0,
    pub fn run(self: *Search, allocator: std.mem.Allocator, grid: *const P.Grid, rows: C.Clues, columns: C.Clues, depth: usize) bool {
        const position = guessCell(grid); for ([_]L.Cell{ .filled, .empty }) |value| { var child = grid.*; child.set(position.row, position.column, value); var row_marks = [_]bool{false} ** 30; var column_marks = [_]bool{false} ** 30; row_marks[position.row] = true; column_marks[position.column] = true; const propagation = P.propagate(allocator, &child, rows, columns, true, &row_marks, &column_marks); const known = child.known(); var guess: Guess = .{ .number = self.guesses.items.len + 1, .depth = depth, .position = position, .value = value, .solves = propagation.steps.items.len, .known = known, .outcome = .open, .conflict = propagation.conflict };
            if (propagation.conflict != null) { guess.outcome = .contradiction; self.backtracks += 1; } else if (known == grid.width * grid.height) { self.solutions.append(allocator, child) catch @panic("allocation failed"); guess.outcome = if (self.solutions.items.len == 1) .solution1 else .solution2; }
            self.guesses.append(allocator, guess) catch @panic("allocation failed"); self.max_depth = @max(self.max_depth, depth); self.line_solves += guess.solves;
            if (guess.outcome == .open) { if (self.run(allocator, &child, rows, columns, depth + 1)) return true; } else if (self.solutions.items.len == 2) return true;
        } return false;
    }
};
