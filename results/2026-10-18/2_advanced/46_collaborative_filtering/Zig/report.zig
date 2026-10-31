const std = @import("std");
const c = @import("ratings.zig");
pub fn real(value: f64) []const u8 {
    return c.fmt("{d:.4}", .{if (@abs(value) < 0.00005) @as(f64, 0) else value});
}
pub fn optionalReal(value: ?f64) []const u8 {
    return if (value) |number| real(number) else "-";
}
pub fn write(io: std.Io, name: []const u8, lines: c.Lines) !void {
    var out: c.Text = .{};
    for (lines.data.items) |line| out.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = c.fmt("output/{s}", .{name}), .data = out.value() });
}
