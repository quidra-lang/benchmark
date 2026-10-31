const std = @import("std");
const D = @import("dataset.zig");
const T = @import("tests.zig");
pub fn realText(value: f64) []const u8 {
    const result = D.fmt("{d:.4}", .{value});
    return if (D.eq(result, "-0.0000")) "0.0000" else result;
}
pub fn pValue(numerator: i64, denominator: i64) []const u8 {
    const value = T.reduced(numerator, denominator);
    return D.fmt("{d}/{d} {s}", .{ value.numerator, value.denominator, realText(D.real(value.numerator) / D.real(value.denominator)) });
}
pub fn numberList(numbers: []const usize) []const u8 {
    if (numbers.len == 0) return "none";
    var result: D.Text = .{};
    for (numbers, 0..) |number, i| result.add("{s}{d}", .{ if (i == 0) "" else " ", number });
    return result.value();
}
pub fn binNumber(value: f64, low: f64, high: f64, bins: usize) usize {
    const result: usize = @intFromFloat(@floor(D.real(bins) * (value - low) / (high - low)));
    return @min(result, bins - 1) + 1;
}
pub fn bar(count: usize, top: usize) []const u8 {
    const result = D.alloc(u8, (40 * count + top - 1) / top);
    @memset(result, '#');
    return result;
}
pub fn writeLines(io: std.Io, name: []const u8, lines: D.Lines) !void {
    var result: D.Text = .{};
    for (lines.data.items) |line| result.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = D.fmt("output/{s}", .{name}), .data = result.value() });
}
