const std = @import("std");
const p = @import("pgm_reader.zig");
pub const Rational = struct {
    numerator: i64 = 0,
    denominator: i64 = 1,
    pub fn init(numerator: i64, denominator: i64) Rational {
        var first = p.abs(numerator);
        var second = denominator;
        while (second != 0) {
            const remainder = @mod(first, second);
            first = second;
            second = remainder;
        }
        return .{ .numerator = @divExact(numerator, first), .denominator = @divExact(denominator, first) };
    }
    pub fn parse(source: []const u8) Rational {
        const parts = p.split(source, '/');
        return init(p.number(parts[0]), if (parts.len > 1) p.number(parts[1]) else 1);
    }
    pub fn compare(self: Rational, other: Rational) std.math.Order {
        return std.math.order(self.numerator * other.denominator, other.numerator * self.denominator);
    }
};
pub fn decimal(value: Rational, places: usize) []const u8 {
    var scale: i64 = 1;
    for (0..places) |_| scale *= 10;
    const rounded = @divFloor(2 * scale * p.abs(value.numerator) + value.denominator, 2 * value.denominator);
    const fractional = p.fmt("{d}", .{@mod(rounded, scale)});
    var text: p.Text = .{};
    if (value.numerator < 0 and rounded > 0) text.write("-");
    text.add("{d}.", .{@divFloor(rounded, scale)});
    for (fractional.len..places) |_| text.write("0");
    text.write(fractional);
    return text.value();
}
pub fn hullAreaText(doubled: i64) []const u8 { return p.fmt("{d}.{d}", .{ @divFloor(doubled, 2), if (@mod(doubled, 2) == 0) @as(i64, 0) else 5 }); }
pub fn writeLines(io: std.Io, name: []const u8, source: p.Lines) !void {
    var text: p.Text = .{};
    for (source.data.items) |line| { text.write(line); text.write("\n"); }
    try std.Io.Dir.cwd().createDirPath(io, "output");
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = p.fmt("output/{s}", .{name}), .data = text.value() });
}
