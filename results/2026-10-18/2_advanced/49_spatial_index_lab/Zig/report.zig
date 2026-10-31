const std = @import("std");
const c = @import("dataset.zig");
pub fn fraction(numerator: anytype, denominator: anytype) []const u8 {
    var a = c.n(numerator);
    var b = c.n(denominator);
    while (b != 0) {
        const remainder = @mod(a, b);
        a = b;
        b = remainder;
    }
    return c.fmt("{d}/{d}", .{ @divExact(c.n(numerator), a), @divExact(c.n(denominator), a) });
}
pub fn ids(values: anytype) []const u8 {
    if (values.len == 0) return "-";
    var out: c.Text = .{};
    for (values, 0..) |value, i| out.add("{s}{d}", .{ if (i == 0) "" else " ", value });
    return out.value();
}
pub fn write(io: std.Io, name: []const u8, lines: c.Lines) !void {
    var out: c.Text = .{};
    for (lines.data.items) |line| out.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = c.fmt("output/{s}", .{name}), .data = out.value() });
}
