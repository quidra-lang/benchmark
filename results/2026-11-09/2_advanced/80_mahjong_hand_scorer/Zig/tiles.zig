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

pub const Names = []const []const u8;
pub fn join(values: Names, separator: []const u8) []const u8 {
    return std.mem.join(allocator, separator, values) catch @panic("allocation failed");
}
pub fn writeLines(io: std.Io, filename: []const u8, lines: Lines) !void {
    try std.Io.Dir.cwd().createDirPath(io, "output");
    var out: Text = .{};
    for (lines.data.items) |line| out.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = fmt("output/{s}", .{filename}), .data = out.value() });
}
pub const suits = "mpsz";
pub const winds = "ESWN";
pub const orphans = [_]usize{ 0, 8, 9, 17, 18, 26, 27, 28, 29, 30, 31, 32, 33 };
pub const Counts = [34]u32;
pub const Tile = struct { kind: usize, red: bool = false };
pub const Tiles = []const Tile;
pub const Block = struct {
    first: usize,
    size: usize = 3,
    sequence: bool = false,
    pub fn same(self: Block, other: Block) bool {
        return self.first == other.first and self.size == other.size and self.sequence == other.sequence;
    }
    pub fn contains(self: Block, kind: usize) bool {
        return if (self.sequence) kind >= self.first and kind <= self.first + 2 else kind == self.first;
    }
    pub fn text(self: Block) []const u8 {
        const out = alloc(u8, self.size + 1);
        for (0..self.size) |i| out[i] = '1' + @as(u8, @intCast((self.first + (if (self.sequence) i else 0)) % 9));
        out[self.size] = suits[self.first / 9];
        return out;
    }
};
pub fn parse(source: []const u8, allow_empty: bool) ?Tiles {
    if (eq(source, "-")) return if (allow_empty) &.{} else null;
    if (source.len == 0) return null;
    var out: std.ArrayList(Tile) = .empty;
    var start: usize = 0;
    while (start < source.len) {
        var end = start;
        while (end < source.len and source[end] >= '0' and source[end] <= '9') : (end += 1) {}
        if (end == start or end == source.len) return null;
        const suit = std.mem.indexOfScalar(u8, suits, source[end]) orelse return null;
        for (source[start..end]) |digit| {
            if (suit == 3 and (digit < '1' or digit > '7')) return null;
            append(Tile, &out, .{ .kind = suit * 9 + (if (digit == '0') @as(usize, 5) else @as(usize,
                 digit - '0')) - 1, .red = digit == '0' });
        }
        start = end + 1;
    }
    return out.items;
}
pub fn name(kind: usize) []const u8 {
    return fmt("{d}{c}", .{ kind % 9 + 1, suits[kind / 9] });
}
pub fn counts(tiles: Tiles) Counts {
    var out: Counts = @splat(0);
    for (tiles) |tile| out[tile.kind] += 1;
    return out;
}
pub fn honor(kind: usize) bool {
    return kind >= 27;
}
pub fn terminal(kind: usize) bool {
    return kind < 27 and (kind % 9 == 0 or kind % 9 == 8);
}
pub fn yaochuu(kind: usize) bool {
    return honor(kind) or terminal(kind);
}
pub fn green(kind: usize) bool {
    return kind == 19 or kind == 20 or kind == 21 or kind == 23 or kind == 25 or kind == 32;
}
pub fn nextDora(kind: usize) usize {
    return if (kind < 27) kind / 9 * 9 + (kind % 9 + 1) % 9 else if (kind < 31) 27 + (kind - 26) % 4 else 31 + (kind - 30) % 3;
}
pub fn windTile(wind: u8) usize {
    return 27 + (std.mem.indexOfScalar(u8, winds, wind) orelse unreachable);
}
