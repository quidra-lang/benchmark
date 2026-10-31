const std = @import("std");
const g = @import("grid.zig");
const slots = @import("slots.zig");
const filler = @import("filler.zig");
pub fn decimal(numerator: usize, denominator: usize, places: usize) []const u8 {
    var scale: usize = 1;
    for (0..places) |_| scale *= 10;
    const rounded = (2 * numerator * scale + denominator) / (2 * denominator);
    const fractional = g.fmt("{d}", .{rounded % scale});
    var text: g.Text = .{};
    text.add("{d}.", .{rounded / scale});
    for (fractional.len..places) |_| text.write("0");
    text.write(fractional);
    return text.value();
}
pub fn gridLines(grid: g.Grid, state: *const filler.State, lines: *g.Lines) void {
    for (0..grid.height) |row| lines.write(state.letters[row * grid.width .. (row + 1) * grid.width]);
}
pub fn numberLines(layout: *const slots.Layout, lines: *g.Lines) void {
    const grid = layout.grid;
    for (0..grid.height) |row| {
        var text: g.Text = .{};
        for (0..grid.width) |column| {
            const cell = row * grid.width + column;
            if (column > 0) text.write(" ");
            if (grid.cells[cell] == '#') text.write("##") else if (layout.numbers[cell] > 0) {
                if (layout.numbers[cell] < 10) text.write(" ");
                text.add("{d}", .{layout.numbers[cell]});
            } else text.write(" .");
        }
        lines.write(text.value());
    }
}
pub fn listLine(slot: slots.Slot, clue: []const u8, entry: []const u8, score: []const u8, theme: bool) []const u8 {
    return g.fmt("{d}. {s} ({d}) {s} {s}{s}", .{ slot.number, clue, slot.cells.len, entry, score, if (theme) " theme" else "" });
}
pub fn writeLines(io: std.Io, name: []const u8, source: g.Lines) !void {
    var text: g.Text = .{};
    for (source.data.items) |line| { text.write(line); text.write("\n"); }
    try std.Io.Dir.cwd().createDirPath(io, "output");
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = g.fmt("output/{s}", .{name}), .data = text.value() });
}
