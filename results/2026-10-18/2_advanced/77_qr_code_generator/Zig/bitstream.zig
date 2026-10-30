const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub fn alloc(comptime T: type, count: usize) []T {
    return allocator.alloc(T, count) catch @panic("allocation failed");
}
pub fn create(comptime T: type, value: T) *T {
    const out = allocator.create(T) catch @panic("allocation failed");
    out.* = value;
    return out;
}
pub fn dupe(comptime T: type, values: []const T) []T {
    return allocator.dupe(T, values) catch @panic("allocation failed");
}
pub fn append(comptime T: type, list: *std.ArrayList(T), value: T) void {
    list.append(allocator, value) catch @panic("allocation failed");
}
pub fn fmt(comptime pattern: []const u8, args: anytype) []const u8 {
    return std.fmt.allocPrint(allocator, pattern, args) catch @panic("allocation failed");
}
pub fn n(value: anytype) i64 {
    return @intCast(value);
}
pub fn u(value: i64) usize {
    return @intCast(value);
}
pub fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
pub fn number(value: []const u8) i64 {
    return std.fmt.parseInt(i64, value, 10) catch unreachable;
}
pub fn split(value: []const u8, delimiter: u8) []const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var fields = std.mem.splitScalar(u8, value, delimiter);
    while (fields.next()) |field| append([]const u8, &out, field);
    return out.items;
}
pub fn words(value: []const u8) []const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (split(value, ' ')) |field| if (field.len > 0) append([]const u8, &out, field);
    return out.items;
}
pub const Text = struct {
    data: std.ArrayList(u8) = .empty,
    pub fn add(self: *Text, comptime pattern: []const u8, args: anytype) void {
        self.data.appendSlice(allocator, fmt(pattern, args)) catch @panic("allocation failed");
    }
    pub fn value(self: Text) []const u8 {
        return self.data.items;
    }
};
pub const Lines = struct {
    data: std.ArrayList([]const u8) = .empty,
    pub fn add(self: *Lines, comptime pattern: []const u8, args: anytype) void {
        append([]const u8, &self.data, fmt(pattern, args));
    }
    pub fn extend(self: *Lines, lines: Lines) void {
        for (lines.data.items) |line| self.add("{s}", .{line});
    }
};
pub fn readLines(io: std.Io, path: []const u8) ![]const []const u8 {
    const value = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited);
    const lines = split(value, '\n');
    return lines[0 .. lines.len - 1];
}

pub const Words = []const i64;
pub const alphanumeric = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:";
pub fn join(values: []const []const u8, separator: []const u8) []const u8 {
    return std.mem.join(allocator, separator, values) catch @panic("allocation failed");
}
pub fn binary(value: i64, width: i64) []const u8 {
    const bits = alloc(u8, u(width));
    for (0..bits.len) |i| bits[bits.len - 1 - i] = @intCast('0' + ((value >> @intCast(i)) & 1));
    return bits;
}
pub const BitWriter = struct {
    data: std.ArrayList(u8) = .empty,
    pub fn write(self: *BitWriter, value: i64, width: i64) void {
        self.data.appendSlice(allocator, binary(value, width)) catch @panic("allocation failed");
    }
    pub fn bits(self: BitWriter) []const u8 {
        return self.data.items;
    }
};
pub const BitReader = struct {
    bits: []const u8,
    position: usize = 0,
    pub fn remaining(self: BitReader) i64 {
        return n(self.bits.len - self.position);
    }
    pub fn read(self: *BitReader, width: i64) i64 {
        var value: i64 = 0;
        for (0..u(width)) |_| {
            value = value * 2 + self.bits[self.position] - '0';
            self.position += 1;
        }
        return value;
    }
};
pub fn fromCodewords(codewords: Words) []const u8 {
    var writer: BitWriter = .{};
    for (codewords) |value| writer.write(value, 8);
    return writer.bits();
}
pub fn toCodewords(bits: []const u8) Words {
    var out: std.ArrayList(i64) = .empty;
    var reader: BitReader = .{ .bits = bits };
    while (reader.remaining() >= 8) append(i64, &out, reader.read(8));
    return out.items;
}
pub fn hexadecimal(codewords: Words) []const u8 {
    const digits = "0123456789abcdef";
    const out = alloc(u8, codewords.len * 2);
    for (codewords, 0..) |value, i| {
        out[2 * i] = digits[u(value >> 4)];
        out[2 * i + 1] = digits[u(value & 15)];
    }
    return out;
}
