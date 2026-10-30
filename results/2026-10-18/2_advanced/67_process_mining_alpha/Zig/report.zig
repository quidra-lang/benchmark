const std = @import("std");
const d = @import("eventlog.zig");
pub fn fraction(value: d.Fraction) []const u8 {
    const numerator = if (value.numerator < 0) -value.numerator else value.numerator;
    const scaled = @divTrunc(10000 * numerator, value.denominator);
    return d.fmt("{s}{d}/{d}={s}{d}.{d:0>4}", .{ if (value.numerator < 0) "-" else "", numerator,
         value.denominator, if (value.numerator < 0 and scaled > 0) "-" else "", @divTrunc(scaled,
         10000), @mod(scaled, 10000) });
}
pub fn percentage(count: i64, total: i64) []const u8 {
    const scaled = @divTrunc(10000 * count, total);
    return d.fmt("{d}.{d:0>2}%", .{ @divTrunc(scaled, 100), @mod(scaled, 100) });
}
pub fn names(values: []const []const u8) []const u8 {
    if (values.len == 0) return "-";
    var text: d.Text = .{};
    for (values, 0..) |value, i| text.add("{s}{s}", .{ if (i == 0) "" else ",", value });
    return text.value();
}
pub fn save(io: std.Io, name: []const u8, lines: d.Lines) !void {
    var text: d.Text = .{};
    for (lines.data.items) |line| text.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = d.fmt("output/{s}", .{name}), .data = text.value() });
}
