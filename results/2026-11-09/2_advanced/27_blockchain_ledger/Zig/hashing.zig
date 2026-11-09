const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub fn alloc(comptime T: type, count: usize) []T {
    return allocator.alloc(T, count) catch @panic("allocation failed");
}
pub fn create(comptime T: type, value: T) *T {
    const result = allocator.create(T) catch @panic("allocation failed");
    result.* = value;
    return result;
}
pub fn append(comptime T: type, list: *std.ArrayList(T), value: T) void {
    list.append(allocator, value) catch @panic("allocation failed");
}
pub fn dupe(comptime T: type, values: []const T) []T {
    return allocator.dupe(T, values) catch @panic("allocation failed");
}
pub fn fmt(comptime pattern: []const u8, args: anytype) []const u8 {
    return std.fmt.allocPrint(allocator, pattern, args) catch @panic("allocation failed");
}
pub fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
pub fn n(value: anytype) i64 {
    return @intCast(value);
}
pub fn u(value: i64) usize {
    return @intCast(value);
}
pub fn number(text: []const u8) i64 {
    return std.fmt.parseInt(i64, text, 10) catch unreachable;
}
pub fn split(text: []const u8, delimiter: u8) []const []const u8 {
    var result: std.ArrayList([]const u8) = .empty;
    var fields = std.mem.splitScalar(u8, text, delimiter);
    while (fields.next()) |field| append([]const u8, &result, field);
    return result.items;
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
};
pub fn readLines(io: std.Io, name: []const u8) ![]const []const u8 {
    const text = try std.Io.Dir.cwd().readFileAlloc(io, fmt("input/{s}", .{name}), allocator, .unlimited);
    const lines = split(text, '\n');
    return lines[0 .. lines.len - 1];
}
pub fn writeLines(io: std.Io, name: []const u8, lines: Lines) !void {
    var text: Text = .{};
    for (lines.data.items) |line| text.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = fmt("output/{s}", .{name}), .data = text.value() });
}
pub fn digest(text: []const u8) []const u8 {
    const bases = [_]i64{ 1000003, 1500007, 2750159, 4194301 };
    const initials = [_]i64{ 11, 23, 37, 53 };
    var result: Text = .{};
    for (bases, initials) |base, initial| {
        var value = initial;
        for (text) |character| value = @mod(value * base + character, 2147483647);
        value = @mod(value * base + n(text.len), 2147483647);
        value = @mod(value * base, 2147483647);
        value = @mod(value * base, 2147483647);
        result.add("{x:0>8}", .{@as(u64, @intCast(value))});
    }
    return result.value();
}
pub fn merkle(ids: []const []const u8) []const u8 {
    var values = ids;
    while (values.len > 1) {
        const next = alloc([]const u8, (values.len + 1) / 2);
        for (next, 0..) |*value, index| {
            const first = values[index * 2];
            const second = values[@min(index * 2 + 1, values.len - 1)];
            value.* = digest(fmt("{s}{s}", .{ first, second }));
        }
        values = next;
    }
    return values[0];
}
pub fn short(hash: []const u8) []const u8 {
    return hash[0..8];
}
