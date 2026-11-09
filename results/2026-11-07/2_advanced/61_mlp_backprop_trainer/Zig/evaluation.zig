const std = @import("std");
const c = @import("dataset.zig");
pub fn real(value: f64, digits: usize) []const u8 {
    const text = switch (digits) {
        2 => c.fmt("{d:.2}", .{value}),
        4 => c.fmt("{d:.4}", .{value}),
        6 => c.fmt("{d:.6}", .{value}),
        else => unreachable,
    };
    if (text.len > 0 and text[0] == '-') {
        var zero = true;
        for (text[1..]) |ch| {
            if (ch != '0' and ch != '.') zero = false;
        }
        if (zero) return text[1..];
    }
    return text;
}
pub fn ratio(numerator: i64, denominator: i64) []const u8 {
    if (denominator == 0) return "-";
    const q = @divTrunc(20000 * numerator + denominator, 2 * denominator);
    return c.fmt("{d}.{d:0>4}", .{ @divTrunc(q, 10000), @mod(q, 10000) });
}
pub fn prediction(scores: []const f64) usize {
    var out: usize = 0;
    for (scores, 0..) |score, k| if (score > scores[out]) {
        out = k;
    };
    return out;
}
pub fn secondClass(scores: []const f64, first: usize) usize {
    var out: usize = if (first == 0) 1 else 0;
    for (scores, 0..) |score, k| if (k != first and score > scores[out]) {
        out = k;
    };
    return out;
}
pub const Counts = [10][10]i64;
pub fn confusion(images: []const c.Image, predictions: []const usize) Counts {
    var out = [_][10]i64{[_]i64{0} ** 10} ** 10;
    for (images, predictions) |image, chosen| out[image.label][chosen] += 1;
    return out;
}
pub const ClassStats = struct { support: i64 = 0, predicted: i64 = 0, true_positive: i64 };
pub fn classStats(matrix: Counts, label: usize, classes: usize) ClassStats {
    var out: ClassStats = .{ .true_positive = matrix[label][label] };
    for (0..classes) |k| {
        out.support += matrix[label][k];
        out.predicted += matrix[k][label];
    }
    return out;
}
pub fn levelMaps(lines: *c.Lines, levels: [][64]usize, width: usize, height: usize) void {
    for (0..height) |row| {
        var text: c.Text = .{};
        for (levels, 0..) |map, k| {
            if (k > 0) text.add(" ", .{});
            for (0..width) |column| text.add("{d}", .{map[row * width + column]});
        }
        lines.add("{s}", .{text.value()});
    }
}
pub fn imageLines(lines: *c.Lines, image: c.Image, width: usize, height: usize) void {
    for (0..height) |row| {
        var text: c.Text = .{};
        for (0..width) |column| text.add("{c}", .{if (image.pixels[row * width + column] == '1') @as(u8,
             '#') else '.'});
        lines.add("{s}", .{text.value()});
    }
}
pub fn save(io: std.Io, name: []const u8, lines: c.Lines) !void {
    var out: c.Text = .{};
    for (lines.data.items) |line| out.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = c.fmt("output/{s}", .{name}), .data = out.value() });
}
