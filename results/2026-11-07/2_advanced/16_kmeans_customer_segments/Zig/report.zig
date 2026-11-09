const std = @import("std");
const D = @import("transactions.zig");
pub fn realText(value: f64) []const u8 { const result = D.fmt("{d:.4}", .{value}); return if (D.eq(result, "-0.0000")) "0.0000" else result; }
pub fn rounded(value: f64) f64 { return D.decimal(realText(value)); }
pub fn amount(cents: i64) []const u8 {
    const magnitude = D.abs(cents);
    return D.fmt("{s}{d}.{d:0>2}", .{ if (cents < 0) "-" else "", @divTrunc(magnitude, 100), @mod(magnitude, 100) });
}
pub fn reals(values: []const f64) []const u8 {
    var result: D.Text = .{};
    for (values, 0..) |value, i| result.add("{s}{s}", .{ if (i == 0) "" else " ", realText(value) });
    return result.value();
}
pub fn integers(values: []const usize) []const u8 {
    var result: D.Text = .{};
    for (values, 0..) |value, i| result.add("{s}{d}", .{ if (i == 0) "" else " ", value });
    return result.value();
}
pub fn writeLines(io: std.Io, name: []const u8, lines: D.Lines) !void {
    var result: D.Text = .{};
    for (lines.data.items) |line| result.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = D.fmt("output/{s}", .{name}), .data = result.value() });
}
