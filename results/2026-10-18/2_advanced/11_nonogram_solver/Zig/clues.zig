const std = @import("std");
const L = @import("line_solver.zig");
pub var allocator: std.mem.Allocator = undefined;
pub var backing: std.mem.Allocator = undefined;
pub const Clue = []const usize;
pub const Clues = []const Clue;
pub const Strings = []const []const u8;
pub fn alloc(comptime T: type, count: usize) []T { return allocator.alloc(T, count) catch @panic("allocation failed"); }
pub fn create(comptime T: type, value: T) *T { const result = allocator.create(T) catch @panic("allocation failed"); result.* = value; return result; }
pub fn append(comptime T: type, list: *std.ArrayList(T), value: T) void { list.append(allocator, value) catch @panic("allocation failed"); }
pub fn fmt(comptime pattern: []const u8, args: anytype) []const u8 { return std.fmt.allocPrint(allocator, pattern, args) catch @panic("allocation failed"); }
pub fn eq(a: []const u8, b: []const u8) bool { return std.mem.eql(u8, a, b); }
pub fn int(value: anytype) i64 { return @intCast(value); }
pub fn number(text: []const u8) usize { return std.fmt.parseInt(usize, text, 10) catch unreachable; }
pub fn split(text: []const u8, delimiter: u8) Strings { var result: std.ArrayList([]const u8) = .empty; var it = std.mem.splitScalar(u8, text, delimiter); while (it.next()) |part| append([]const u8, &result, part); return result.items; }
pub fn lines(text: []const u8) Strings { const result = split(text, '\n'); return result[0..result.len - 1]; }
pub fn join(parts: Strings, separator: []const u8) []const u8 { return std.mem.join(allocator, separator, parts) catch @panic("allocation failed"); }
pub const Text = struct {
    data: std.ArrayList(u8) = .empty,
    pub fn write(self: *Text, text: []const u8) void { self.data.appendSlice(allocator, text) catch @panic("allocation failed"); }
    pub fn byte(self: *Text, ch: u8) void { append(u8, &self.data, ch); }
    pub fn add(self: *Text, comptime pattern: []const u8, args: anytype) void { self.write(fmt(pattern, args)); }
    pub fn spaces(self: *Text, count: usize) void { for (0..count) |_| self.byte(' '); }
    pub fn value(self: Text) []const u8 { return self.data.items; }
};
pub const Lines = struct {
    data: std.ArrayList([]const u8) = .empty,
    pub fn write(self: *Lines, text: []const u8) void { append([]const u8, &self.data, text); }
    pub fn add(self: *Lines, comptime pattern: []const u8, args: anytype) void { self.write(fmt(pattern, args)); }
    pub fn extend(self: *Lines, other: Lines) void { for (other.data.items) |line| self.write(line); }
    pub fn paragraph(self: *Lines, other: Lines) void { if (self.data.items.len > 0) self.write(""); self.extend(other); }
    pub fn content(self: Lines) []const u8 { var text: Text = .{}; for (self.data.items) |line| { text.write(line); text.byte('\n'); } return text.value(); }
};
pub fn isClueLine(text: []const u8) bool { if (text.len == 0) return false; for (text) |ch| { if (ch != ' ' and (ch < '0' or ch > '9')) return false; } return true; }
pub fn parse(text: []const u8) ?Clue { if (eq(text, "0")) return &.{}; const tokens = split(text, ' '); const result = alloc(usize, tokens.len); for (tokens, result) |token, *value| { if (token.len == 0 or token.len > 2 or token[0] < '1' or token[0] > '9') return null; for (token) |ch| { if (ch < '0' or ch > '9') return null; } value.* = number(token); } return result; }
pub fn run(cells: []const L.Cell) Clue { var result: std.ArrayList(usize) = .empty; var count: usize = 0; for (cells) |state| { if (state == .filled) count += 1 else if (count > 0) { append(usize, &result, count); count = 0; } } if (count > 0) append(usize, &result, count); return result.items; }
pub fn formatted(clue: Clue, separator: []const u8) []const u8 { if (clue.len == 0) return "0"; const parts = alloc([]const u8, clue.len); for (clue, parts) |length, *part| part.* = fmt("{d}", .{length}); return join(parts, separator); }
pub fn total(clue: Clue) usize { var result: usize = 0; for (clue) |length| result += length; return result; }
pub fn span(clue: Clue) i64 { return int(total(clue)) + int(clue.len) - 1; }
pub fn fits(clue: Clue, length: usize) bool { return span(clue) <= int(length); }
