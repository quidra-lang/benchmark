const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub const Strings = []const []const u8;
pub fn eq(a: []const u8, b: []const u8) bool { return std.mem.eql(u8, a, b); }
pub fn less(a: []const u8, b: []const u8) bool { return std.mem.order(u8, a, b) == .lt; }
pub fn fmt(comptime pattern: []const u8, args: anytype) []const u8 { return std.fmt.allocPrint(allocator, pattern, args) catch @panic("allocation failed"); }
pub fn append(comptime T: type, list: *std.ArrayList(T), value: T) void { list.append(allocator, value) catch @panic("allocation failed"); }
pub fn alloc(comptime T: type, count: usize) []T { return allocator.alloc(T, count) catch @panic("allocation failed"); }
pub fn clone(comptime T: type, source: []const T) []T { return allocator.dupe(T, source) catch @panic("allocation failed"); }
pub fn join(parts: Strings, delimiter: []const u8) []const u8 { return std.mem.join(allocator, delimiter, parts) catch @panic("allocation failed"); }
pub fn split(text: []const u8, delimiter: u8) Strings { var result: std.ArrayList([]const u8) = .empty; var it = std.mem.splitScalar(u8, text, delimiter); while (it.next()) |part| append([]const u8, &result, part); return result.items; }
pub fn lines(text: []const u8) Strings { const all = split(text, '\n'); return all[0..all.len - 1]; }
pub fn integer(text: []const u8) i64 { return std.fmt.parseInt(i64, text, 10) catch unreachable; }
pub const Row = struct { number: usize, fields: Strings };
pub fn rows(text: []const u8) []const Row { var result: std.ArrayList(Row) = .empty; for (lines(text)[1..], 2..) |line, number| append(Row, &result, .{ .number = number, .fields = split(line, ',') }); return result.items; }
pub fn problem(errors: *std.ArrayList([]const u8), file: []const u8, number: usize, message: []const u8) void { append([]const u8, errors, fmt("{s} line {d}: {s}", .{ file, number, message })); }
pub fn money(cents: i64) []const u8 { return fmt("{d}.{d:0>2}", .{ @divFloor(cents, 100), @mod(cents, 100) }); }
pub fn percent(part: i64, whole: i64) i64 { return @divFloor(200 * part + whole, 2 * whole); }
pub fn repeat(byte: u8, count: usize) []const u8 { const text = alloc(u8, count); @memset(text, byte); return text; }
pub fn table(label: []const u8, values: []const i64, width: usize) []const u8 {
    var parts: std.ArrayList([]const u8) = .empty;
    append([]const u8, &parts, label);
    append([]const u8, &parts, repeat(' ', 10 - label.len));
    for (values) |value| { const text = fmt("{d}", .{value}); append([]const u8, &parts, repeat(' ', width - text.len)); append([]const u8, &parts, text); }
    return join(parts.items, "");
}
pub fn write(io: std.Io, name: []const u8, output: Strings) !void {
    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, "output");
    const text = if (output.len == 0) "" else fmt("{s}\n", .{join(output, "\n")});
    try cwd.writeFile(io, .{ .sub_path = fmt("output/{s}", .{name}), .data = text });
}
