const std = @import("std");
const c = @import("dataset.zig");
pub fn real(value: f64, precision: usize) []const u8 {
    if (precision == 6) return c.fmt("{d:.6}", .{if (@abs(value) < 0.0000005) @as(f64, 0) else value});
    return c.fmt("{d:.4}", .{if (@abs(value) < 0.00005) @as(f64, 0) else value});
}
pub fn ratio(a: anytype, b: anytype) []const u8 {
    return if (b == 0) "-" else real(c.f(a) / c.f(b), 4);
}
pub fn prediction(score: f64) i64 {
    return if (score > 0) 1 else -1;
}
pub const Fraction = struct { numerator: i64, denominator: i64 };
pub fn auc(rows: []const c.Row, scores: []const f64) Fraction {
    var positive: i64 = 0;
    var negative: i64 = 0;
    var wins: i64 = 0;
    var ties: i64 = 0;
    for (rows, 0..) |row, i| if (row.label == 1) {
        positive += 1;
        for (rows, 0..) |other, j| if (other.label == -1) {
            wins += @intFromBool(scores[i] > scores[j]);
            ties += @intFromBool(scores[i] == scores[j]);
        };
    } else {
        negative += 1;
    };
    return .{ .numerator = 2 * wins + ties, .denominator = 2 * positive * negative };
}
pub fn confusion(rows: []const c.Row, predictions: []const usize, classes: usize) [][]usize {
    const out = c.alloc([]usize, classes);
    for (out) |*row| {
        row.* = c.alloc(usize, classes);
        @memset(row.*, 0);
    }
    for (rows, predictions) |row, value| out[c.u(row.label - 1)][value - 1] += 1;
    return out;
}
pub fn marginCount(margins: []const f64, threshold: f64) usize {
    var out: usize = 0;
    for (margins) |value| out += @intFromBool(value <= threshold);
    return out;
}
pub fn write(io: std.Io, name: []const u8, lines: c.Lines) !void {
    var out: c.Text = .{};
    for (lines.data.items) |line| out.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = c.fmt("output/{s}", .{name}), .data = out.value() });
}
