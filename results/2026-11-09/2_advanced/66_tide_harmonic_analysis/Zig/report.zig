const std = @import("std");
const d = @import("records.zig");
pub fn real(value: f64, comptime digits: usize) []const u8 {
    const text = d.fmt("{d:." ++ std.fmt.comptimePrint("{d}", .{digits}) ++ "}", .{value});
    if (text.len > 0 and text[0] == '-') {
        var zero = true;
        for (text[1..]) |c| {
            if (c != '0' and c != '.') zero = false;
        }
        if (zero) return text[1..];
    }
    return text;
}
pub fn save(io: std.Io, name: []const u8, lines: d.Lines) !void {
    var text: d.Text = .{};
    for (lines.data.items) |line| text.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = d.fmt("output/{s}", .{name}), .data = text.value() });
}
pub fn plotLines(heights: []const f64, cells: []const []u8, axis: []const u8) d.Lines {
    const labels = d.alloc([]const u8, heights.len);
    var width: usize = 0;
    for (heights, labels) |height, *label| {
        label.* = real(height, 2);
        width = @max(width, label.*.len);
    }
    var out: d.Lines = .{};
    for (labels, cells) |label, row| {
        var text: d.Text = .{};
        for (0..width - label.len) |_| text.add(" ", .{});
        text.add("{s} |{s}|", .{ label, row });
        out.add("{s}", .{text.value()});
    }
    var text: d.Text = .{};
    for (0..width) |_| text.add(" ", .{});
    text.add(" +{s}+", .{axis});
    out.add("{s}", .{text.value()});
    return out;
}
