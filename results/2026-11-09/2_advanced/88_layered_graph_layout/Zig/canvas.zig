const std = @import("std");
const g = @import("graph_io.zig");
const Cell = struct { lines: u8 = 0, arrow: u8 = 0, box: u8 = 0, highlighted: bool = false };
pub const Canvas = struct {
    rows: usize, columns: usize, main_size: i64, settings: g.Settings, cells: []Cell,
    pub fn init(settings: g.Settings, main_size: i64, secondary_size: i64) Canvas { const rows: usize = @intCast(if (settings.vertical()) main_size else secondary_size); const columns: usize = @intCast(if (settings.vertical()) secondary_size else main_size); return .{ .rows = rows, .columns = columns, .main_size = main_size, .settings = settings, .cells = g.zero(Cell, rows * columns, .{}) }; }
    pub fn map(self: Canvas, main: i64, secondary: i64) g.Point { const m = if (g.eq(self.settings.direction, "BT") or g.eq(self.settings.direction, "RL")) self.main_size - 1 - main else main; return if (self.settings.vertical()) .{ .row = m, .column = secondary } else .{ .row = secondary, .column = m }; }
    fn cell(self: *Canvas, p: g.Point) *Cell { return &self.cells[@as(usize, @intCast(p.row)) * self.columns + @as(usize, @intCast(p.column))]; }
    pub fn line(self: *Canvas, main: i64, secondary: i64, main_direction: bool) void { const bit: u8 = if (self.settings.vertical() == main_direction) 1 else 2; self.cell(self.map(main, secondary)).lines |= bit; }
    pub fn corner(self: *Canvas, main: i64, secondary: i64) void { self.cell(self.map(main, secondary)).lines |= 4; }
    pub fn arrow(self: *Canvas, point: g.Point, reversed: bool) void { const direction = self.settings.direction; const value: u8 = if (g.eq(direction, "TB")) (if (reversed) @as(u8, '^') else 'v') else if (g.eq(direction, "BT")) (if (reversed) @as(u8, 'v') else '^') else if (g.eq(direction, "LR")) (if (reversed) @as(u8, '<') else '>') else (if (reversed) @as(u8, '>') else '<'); self.cell(point).arrow = value; }
    pub fn highlight(self: *Canvas, a: g.Point, b: g.Point) void { var row = a.row; var column = a.column; while (true) { self.cell(.{ .row = row, .column = column }).highlighted = true; if (row == b.row and column == b.column) break; row += std.math.sign(b.row - row); column += std.math.sign(b.column - column); } }
    pub fn box(self: *Canvas, point: g.Point, label: []const u8, highlighted: bool) void { const value = g.fmt("{s}{s}{s}", .{if (highlighted) "{" else "[", label, if (highlighted) "}" else "]"}); for (value, 0..) |c, i| self.cell(.{ .row = point.row, .column = point.column + @as(i64, @intCast(i)) }).box = c; }
    pub fn crossings(self: Canvas) usize { var count: usize = 0; for (self.cells) |c| count += @intFromBool(c.lines & 3 == 3); return count; }
    pub fn display(self: Canvas, name: []const u8, out: *g.Text) void {
        out.line("graph {s} {d}x{d}", .{name, self.columns, self.rows}); out.put("    ", .{}); for (0..self.columns) |i| out.put("{d}", .{i % 10}); out.put("\n", .{});
        for (0..self.rows) |row| { var text: g.Text = .{}; text.put("{d: >3} ", .{row}); for (0..self.columns) |column| { const c = self.cells[row * self.columns + column]; const value: u8 = if (c.box != 0) c.box else if (c.arrow != 0) c.arrow else if (c.highlighted) '#' else switch (c.lines) { 0 => ' ', 1 => '|', 2 => '-', else => '+' }; text.put("{c}", .{value}); } out.line("{s}", .{std.mem.trimEnd(u8, text.data.items, " ")}); }
    }
};
