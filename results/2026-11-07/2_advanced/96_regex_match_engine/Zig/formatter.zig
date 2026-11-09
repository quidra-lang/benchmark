const std = @import("std");
const chars = @import("charset.zig");
const code = @import("compiler.zig");
pub const Buffer = struct {
    a: std.mem.Allocator, data: std.ArrayList(u8) = .empty,
    pub fn add(b: *Buffer, s: []const u8) !void { try b.data.appendSlice(b.a, s); }
    pub fn print(b: *Buffer, comptime fmt: []const u8, args: anytype) !void { try b.add(try std.fmt.allocPrint(b.a, fmt, args)); }
    pub fn line(b: *Buffer, s: []const u8) !void { try b.add(s); try b.add("\n"); }
};
pub fn quoted(a: std.mem.Allocator, text: []const u8) ![]const u8 {
    var b: Buffer = .{ .a = a }; try b.add("\"");
    for (text) |c| switch (c) { '\\' => try b.add("\\\\"), '"' => try b.add("\\\""), 10 => try b.add("\\n"), 9 => try b.add("\\t"), else => try b.data.append(a, c) };
    try b.add("\""); return b.data.items;
}
pub fn decode(a: std.mem.Allocator, text: []const u8) ![]const u8 {
    var b: std.ArrayList(u8) = .empty; var p: usize = 1;
    while (p + 1 < text.len) : (p += 1) { var c = text[p]; if (c == '\\') { p += 1; c = switch (text[p]) { 'n' => 10, 't' => 9, else => text[p] }; } try b.append(a, c); }
    return b.items;
}
pub fn character(a: std.mem.Allocator, c: usize) ![]const u8 {
    if (c >= 33 and c <= 126 and c != '\\' and c != ']' and c != '^' and c != '-') { const s = try a.alloc(u8, 1); s[0] = @intCast(c); return s; }
    return std.fmt.allocPrint(a, "\\x{X:0>2}", .{c});
}
pub fn set(a: std.mem.Allocator, s: chars.Set, neg: bool) ![]const u8 {
    var b: Buffer = .{ .a = a }; try b.add(if (neg) "[^" else "["); var p: usize = 0;
    while (p < 128) { if (!s.isSet(p)) { p += 1; continue; } const start = p; while (p + 1 < 128 and s.isSet(p + 1)) p += 1; try b.add(try character(a, start)); if (p > start) { if (p > start + 1) try b.add("-"); try b.add(try character(a, p)); } p += 1; }
    try b.add("]"); return b.data.items;
}
pub fn instruction(a: std.mem.Allocator, ins: code.Instruction) ![]const u8 {
    return switch (ins.op) {
        .CHAR => std.fmt.allocPrint(a, "CHAR {s}", .{try character(a, ins.x)}),
        .ANY => "ANY", .CLASS => std.fmt.allocPrint(a, "CLASS {s}", .{try set(a, ins.set, ins.neg)}),
        .SPLIT => std.fmt.allocPrint(a, "SPLIT {d}, {d}", .{ins.x, ins.y}),
        .JMP, .SAVE, .BACKREF => std.fmt.allocPrint(a, "{s} {d}", .{@tagName(ins.op), ins.x}),
        .ASSERT => std.fmt.allocPrint(a, "ASSERT {s}", .{@tagName(ins.assertion)}),
        .LOOK => std.fmt.allocPrint(a, "LOOK {s} {d}", .{@tagName(ins.look), ins.x}), .MATCH => "MATCH",
    };
}
