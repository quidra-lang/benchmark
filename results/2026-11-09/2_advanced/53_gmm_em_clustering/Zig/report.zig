const std = @import("std");
const c = @import("dataset.zig");
pub fn rounded(value: f64, digits: usize) i64 {
    var factor: i64 = 1;
    for (0..digits) |_| factor *= 10;
    const amount: i64 = @intFromFloat(@floor(@abs(value) * c.f(factor) + 0.5));
    return if (value < 0) -amount else amount;
}
pub fn real(value: f64, digits: usize) []const u8 {
    const amount = rounded(value, digits);
    const absolute = if (amount < 0) -amount else amount;
    var factor: i64 = 1;
    for (0..digits) |_| factor *= 10;
    const tail = c.fmt("{d}", .{@mod(absolute, factor)});
    const zeroes = c.alloc(u8, digits - tail.len);
    @memset(zeroes, '0');
    return c.fmt("{s}{d}.{s}{s}", .{ if (amount < 0) "-" else "", @divTrunc(absolute, factor), zeroes, tail });
}
pub fn frame(lines: *c.Lines, grid: anytype) void {
    const border = c.alloc(u8, grid[0].len);
    @memset(border, '-');
    lines.add("+{s}+", .{border});
    for (grid) |row| lines.add("|{s}|", .{row});
    lines.add("+{s}+", .{border});
}
pub fn save(io: std.Io, name: []const u8, lines: c.Lines) !void {
    var text: c.Text = .{};
    for (lines.data.items) |line| text.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = c.fmt("output/{s}", .{name}), .data = text.value() });
}
