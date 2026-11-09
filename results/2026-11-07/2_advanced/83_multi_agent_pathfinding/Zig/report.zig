const std = @import("std");
const g = @import("grid_map.zig");
const c = @import("cbs.zig");
pub fn cellText(cell: usize, grid: g.Grid) []const u8 {
    return g.fmt("{d},{d}", .{ cell % grid.width, cell / grid.width });
}
pub fn agentName(id: usize) u8 {
    return 'A' + @as(u8, @intCast(id));
}
pub fn action(first: usize, second: usize, grid: g.Grid) u8 {
    if (first == second) return '.';
    if (second + grid.width == first) return 'N';
    if (second == first + 1) return 'E';
    if (second == first + grid.width) return 'S';
    return 'W';
}
pub fn actionString(path: g.Path, grid: g.Grid) []const u8 {
    const out = g.alloc(u8, path.len - 1);
    for (path[0 .. path.len - 1], path[1..], out) |a, b, *character| character.* = action(a, b, grid);
    return out;
}
pub fn conflictText(conflict: c.Conflict, grid: g.Grid) []const u8 {
    if (!conflict.edge) return g.fmt("vertex t {d} {c} {c} at {s}", .{ conflict.time, agentName(conflict.a),
         agentName(conflict.b), cellText(conflict.u, grid) });
    return g.fmt("edge t {d} {c} {c} from {s} to {s}", .{ conflict.time, agentName(conflict.a),
         agentName(conflict.b), cellText(conflict.u, grid), cellText(conflict.v, grid) });
}
pub fn fraction(numerator: i64, denominator: i64) []const u8 {
    var a = numerator;
    var b = denominator;
    while (b != 0) {
        const next = @mod(a, b);
        a = b;
        b = next;
    }
    return g.fmt("{d}/{d}", .{ @divTrunc(numerator, a), @divTrunc(denominator, a) });
}
pub fn csvLine(values: g.Names) []const u8 {
    return g.join(values, ",");
}
pub fn write(io: std.Io, name: []const u8, lines: g.Lines) !void {
    try std.Io.Dir.cwd().createDirPath(io, "output");
    var out: g.Text = .{};
    for (lines.data.items) |line| out.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = g.fmt("output/{s}", .{name}), .data = out.value() });
}
