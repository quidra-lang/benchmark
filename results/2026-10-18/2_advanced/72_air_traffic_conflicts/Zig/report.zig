const std = @import("std");
const d = @import("flight_plans.zig");
pub fn decimal(value: f64, comptime digits: usize) []const u8 {
    var factor: f64 = 1;
    for (0..digits) |_| factor *= 10;
    const rounded = @floor(@abs(value) * factor + 0.5);
    const result = if (rounded == 0) @as(f64, 0) else (if (value < 0) -rounded else rounded) / factor;
    return if (digits == 1) d.fmt("{d:.1}", .{result}) else if (digits == 2) d.fmt("{d:.2}",
         .{result}) else d.fmt("{d:.3}", .{result});
}
pub fn dec(value: f64) []const u8 {
    return decimal(value, 3);
}
pub fn signedInteger(value: i64) []const u8 {
    return if (value > 0) d.fmt("+{d}", .{value}) else d.fmt("{d}", .{value});
}
pub fn joined(values: []const []const u8) []const u8 {
    var out: d.Text = .{};
    for (values, 0..) |value, i| {
        if (i > 0) out.add(",", .{});
        out.add("{s}", .{value});
    }
    return out.value();
}
pub fn frame(out: *d.Lines, grid: []const []u8) void {
    const middle = d.alloc(u8, grid[0].len);
    @memset(middle, '-');
    out.add("+{s}+", .{middle});
    for (grid) |row| out.add("|{s}|", .{row});
    out.add("+{s}+", .{middle});
}
pub fn writeLines(io: std.Io, name: []const u8, lines: d.Lines) !void {
    var text: d.Text = .{};
    for (lines.data.items) |line| text.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = d.fmt("output/{s}", .{name}), .data = text.value() });
}
