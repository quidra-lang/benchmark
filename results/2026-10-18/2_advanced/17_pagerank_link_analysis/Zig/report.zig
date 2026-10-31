const std = @import("std");
const D = @import("graph_io.zig");
pub fn fixed(value: f64, places: usize) []const u8 {
    const result = switch (places) { 4 => D.fmt("{d:.4}", .{value}), 6 => D.fmt("{d:.6}", .{value}), 10 => D.fmt("{d:.10}", .{value}), else => unreachable };
    return if (result.len > 0 and result[0] == '-' and D.decimal(result) == 0) result[1..] else result;
}
pub fn scaled(value: f64, places: usize) i64 {
    var multiplier: i64 = 1;
    for (0..places) |_| multiplier *= 10;
    return @intFromFloat(@round(D.decimal(fixed(value, places)) * D.real(multiplier)));
}
pub fn fraction(numerator: i64, denominator: i64) []const u8 {
    var first = D.abs(numerator);
    var second = denominator;
    while (second != 0) { const remainder = @mod(first, second); first = second; second = remainder; }
    const a = @divTrunc(numerator, first);
    const b = @divTrunc(denominator, first);
    return D.fmt("{d}/{d} {s}", .{ a, b, fixed(D.real(a) / D.real(b), 4) });
}
pub fn writeLines(io: std.Io, name: []const u8, lines: D.Lines) !void {
    var result: D.Text = .{};
    for (lines.data.items) |line| result.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = D.fmt("output/{s}", .{name}), .data = result.value() });
}
