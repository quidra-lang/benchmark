const C = @import("clues.zig");
const L = @import("line_solver.zig");
const P = @import("propagation.zig");
pub fn stateChar(state: L.Cell) u8 { return switch (state) { .unknown => '?', .filled => '#', .empty => '.' }; }
pub fn charState(ch: u8) L.Cell { return switch (ch) { '?' => .unknown, '#' => .filled, else => .empty }; }
pub fn stateString(cells: []const L.Cell) []const u8 { const result = C.alloc(u8, cells.len); for (cells, result) |state, *ch| ch.* = stateChar(state); return result; }
pub fn gridDisplay(names: C.Strings, grids: []const *const P.Grid) C.Lines { var result: C.Lines = .{}; result.add("grid {s}", .{C.join(names, " ")}); for (0..grids[0].height) |r| { const parts = C.alloc([]const u8, grids.len); for (grids, parts) |grid, *part| { const cells = grid.line(true, r); part.* = stateString(cells[0..grid.width]); } result.write(C.join(parts, " | ")); } return result; }
pub fn answerSheet(rows: C.Clues, columns: C.Clues, grid: *const P.Grid) C.Lines {
    const tokens = C.alloc(C.Strings, columns.len); var width: usize = 0; var depth: usize = 0; var margin: usize = 0; for (columns, tokens) |clue, *column| { column.* = C.split(C.formatted(clue, " "), ' '); depth = @max(depth, column.*.len); for (column.*) |token| width = @max(width, token.len + 1); } for (rows) |clue| margin = @max(margin, C.formatted(clue, " ").len); var result: C.Lines = .{};
    for (0..depth) |t| { var text: C.Text = .{}; text.spaces(margin); for (tokens) |column| { const skipped = depth - column.len; if (t >= skipped) { const token = column[t - skipped]; text.spaces(width - token.len); text.write(token); } else text.spaces(width); } while (text.data.items.len > 0 and text.data.items[text.data.items.len - 1] == ' ') text.data.items.len -= 1; result.write(text.value()); }
    for (rows, 0..) |clue, r| { const label = C.formatted(clue, " "); var text: C.Text = .{}; text.spaces(margin - label.len); text.write(label); for (0..grid.width) |c| { text.spaces(width - 1); text.byte(stateChar(grid.get(r, c))); } result.write(text.value()); } return result;
}
