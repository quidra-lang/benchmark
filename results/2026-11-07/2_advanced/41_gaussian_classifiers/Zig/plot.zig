const c = @import("dataset.zig");
const evaluation = @import("evaluation.zig");
pub fn real(value: f64) []const u8 {
    return c.fmt("{d:.4}", .{if (@abs(value) < 0.00005) @as(f64, 0) else value});
}
pub fn fraction(value: evaluation.Fraction) []const u8 {
    return c.fmt("{d}/{d} {s}", .{ value.numerator, value.denominator, real(c.f(value.numerator) / c.f(value.denominator)) });
}
pub fn frame(cells: []const []const u8) c.Lines {
    var out: c.Lines = .{};
    const rule = c.alloc(u8, cells[0].len);
    @memset(rule, '-');
    out.add("+{s}+", .{rule});
    for (cells) |row| out.add("|{s}|", .{row});
    out.add("+{s}+", .{rule});
    return out;
}
pub fn cell(value: f64, low: f64, high: f64, size: usize) usize {
    return @intFromFloat(@floor((value - low) / (high - low) * c.f(size - 1) + 0.5));
}
pub fn write(io: @import("std").Io, name: []const u8, lines: c.Lines) !void {
    var out: c.Text = .{};
    for (lines.data.items) |line| out.add("{s}\n", .{line});
    try @import("std").Io.Dir.cwd().writeFile(io, .{ .sub_path = c.fmt("output/{s}", .{name}), .data = out.value() });
}
pub fn numbers(values: c.Vector, size: usize) []const u8 {
    var out: c.Text = .{};
    for (values[0..size], 0..) |value, j| out.add("{s}{s}", .{ if (j == 0) "" else " ", real(value) });
    return out.value();
}
pub fn integers(values: []const usize) []const u8 {
    var out: c.Text = .{};
    for (values, 0..) |value, j| out.add("{s}{d}", .{ if (j == 0) "" else " ", value });
    return out.value();
}
pub fn names(features: c.Features, all: []const []const u8) []const u8 {
    var out: c.Text = .{};
    for (features, 0..) |feature, j| out.add("{s}{s}", .{ if (j == 0) "" else " ", all[feature] });
    return out.value();
}
