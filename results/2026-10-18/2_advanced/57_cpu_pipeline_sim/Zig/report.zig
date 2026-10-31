const std = @import("std");
const c = @import("trace_io.zig");
pub fn decimal(p: i64, q: i64) []const u8 {
    const scaled = @divTrunc(2 * p * 10000 + q, 2 * q);
    return c.fmt("{d}.{d:0>4}", .{ @divTrunc(scaled, 10000), @mod(scaled, 10000) });
}
pub fn percentage(p: i64, q: i64) []const u8 {
    if (q == 0) return "-";
    const scaled = @divTrunc(2 * p * 10000 + q, 2 * q);
    return c.fmt("{d}.{d:0>2}", .{ @divTrunc(scaled, 100), @mod(scaled, 100) });
}
pub fn fraction(p: i64, q: i64) []const u8 {
    var a = p;
    var b = q;
    while (b != 0) {
        const remainder = @mod(a, b);
        a = b;
        b = remainder;
    }
    return c.fmt("{d}/{d}", .{ @divTrunc(p, a), @divTrunc(q, a) });
}
pub fn hexadecimal(value: i64) []const u8 {
    return c.fmt("{x:0>8}", .{value});
}
pub fn register(value: i64) []const u8 {
    return if (value < 0) "-" else c.fmt("r{d}", .{value});
}
pub fn cycleHeading(start: i64, end: i64) []const u8 {
    var out: c.Text = .{};
    out.add("cycle                  ", .{});
    var cycle = start;
    while (cycle <= end) : (cycle += 1) out.add("{d}", .{@mod(cycle, 10)});
    return out.value();
}
pub fn diagramRow(number: ?usize, pc: i64, kind: []const u8, characters: []const u8, annotation: []const u8) []const u8 {
    const identifier = if (number) |value| c.fmt("{d: >6}", .{value}) else "     -";
    return c.fmt("{s} {s} {s: <6} {s}{s}", .{ identifier, hexadecimal(pc), kind, characters, annotation });
}
pub fn save(io: std.Io, name: []const u8, lines: c.Lines) !void {
    var out: c.Text = .{};
    for (lines.data.items) |line| out.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = c.fmt("output/{s}", .{name}), .data = out.value() });
}
