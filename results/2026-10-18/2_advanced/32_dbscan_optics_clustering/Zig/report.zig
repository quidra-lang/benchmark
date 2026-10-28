const std = @import("std");
const d = @import("dataset.zig");
pub const Text = struct {
    data: std.ArrayList(u8) = .empty,
    pub fn add(self: *Text, comptime pattern: []const u8, args: anytype) void {
        self.data.appendSlice(d.allocator, d.fmt(pattern, args)) catch @panic("allocation failed");
    }
    pub fn value(self: Text) []const u8 {
        return self.data.items;
    }
};
pub const Lines = struct {
    data: std.ArrayList([]const u8) = .empty,
    pub fn add(self: *Lines, comptime pattern: []const u8, args: anytype) void {
        d.append([]const u8, &self.data, d.fmt(pattern, args));
    }
    pub fn blank(self: *Lines) void {
        self.add("", .{});
    }
    pub fn extend(self: *Lines, other: Lines) void {
        for (other.data.items) |line| self.add("{s}", .{line});
    }
};
fn gcd(first: i64, second: i64) i64 {
    var a = first;
    var b = second;
    while (b != 0) {
        const next = @mod(a, b);
        a = b;
        b = next;
    }
    return a;
}
pub fn fraction(numerator: i64, denominator: i64) []const u8 {
    const divisor = gcd(@intCast(@abs(numerator)), denominator);
    return d.fmt("{d}/{d}", .{ @divTrunc(numerator, divisor), @divTrunc(denominator, divisor) });
}
pub fn root(value: i64) []const u8 {
    return if (value == d.INF) "-" else d.fmt("{d:.3}", .{@sqrt(d.f(value))});
}
pub fn ariValue(numerator: i64, denominator: i64) []const u8 {
    const text = d.fmt("{d:.4}", .{d.f(numerator) / d.f(denominator)});
    return if (std.mem.eql(u8, text, "-0.0000")) "0.0000" else text;
}
pub fn framed(rows: []const []const u8) Lines {
    const middle = d.alloc(u8, rows[0].len);
    @memset(middle, '-');
    const frame = d.fmt("+{s}+", .{middle});
    var out: Lines = .{};
    out.add("{s}", .{frame});
    for (rows) |row| out.add("|{s}|", .{row});
    out.add("{s}", .{frame});
    return out;
}
pub fn writeLines(io: std.Io, name: []const u8, lines: Lines) !void {
    var text: Text = .{};
    for (lines.data.items) |line| text.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = d.fmt("output/{s}", .{name}), .data = text.value() });
}
