const std = @import("std");
const c = @import("cnf_io.zig");
pub fn numberList(values: []const i64) []const u8 {
    if (values.len == 0) return "-";
    var out: c.Text = .{};
    for (values, 0..) |value, i| out.add("{s}{d}", .{ if (i == 0) "" else ",", value });
    return out.value();
}
pub fn frequencyList(counts: []const i64) []const u8 {
    var out: c.Text = .{};
    for (counts, 0..) |count, i| if (count > 0) out.add("{s}{d}:{d}", .{ if (out.value().len == 0) "" else ",", i, count });
    return if (out.value().len == 0) "-" else out.value();
}
pub const Item = struct { name: []const u8, value: []const u8 };
pub fn items(prefix: []const u8, fields: []const Item) []const u8 {
    var out: c.Text = .{};
    out.add("{s}", .{prefix});
    for (fields) |field| out.add("{s}{s}={s}", .{ if (out.value().len == 0) "" else " ", field.name, field.value });
    return out.value();
}
pub fn boardLines(columns: []const i64) c.Lines {
    var out: c.Lines = .{};
    for (columns) |column| {
        const row = c.alloc(u8, columns.len);
        @memset(row, '.');
        row[c.u(column - 1)] = 'Q';
        out.add("{s}", .{row});
    }
    return out;
}
pub fn paragraph(target: *c.Lines, lines: c.Lines) void {
    if (target.data.items.len > 0) target.add("", .{});
    target.extend(lines);
}
pub fn write(io: std.Io, name: []const u8, lines: c.Lines) !void {
    var out: c.Text = .{};
    for (lines.data.items) |line| out.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = c.fmt("output/{s}", .{name}), .data = out.value() });
}
