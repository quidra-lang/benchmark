const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub const Strings = []const []const u8;
pub fn alloc(comptime T: type, count: usize) []T { return allocator.alloc(T, count) catch @panic("allocation failed"); }
pub fn append(comptime T: type, list: *std.ArrayList(T), value: T) void { list.append(allocator, value) catch @panic("allocation failed"); }
pub fn fmt(comptime pattern: []const u8, arguments: anytype) []const u8 { return std.fmt.allocPrint(allocator, pattern, arguments) catch @panic("allocation failed"); }
pub fn eq(first: []const u8, second: []const u8) bool { return std.mem.eql(u8, first, second); }
pub fn n(value: anytype) i64 { return @intCast(value); }
pub fn u(value: i64) usize { return @intCast(value); }
pub fn number(source: []const u8) i64 { return std.fmt.parseInt(i64, source, 10) catch unreachable; }
pub fn integer(source: []const u8) usize { return u(number(source)); }
pub fn abs(value: i64) i64 { return if (value < 0) -value else value; }
pub fn split(source: []const u8, separator: u8) Strings {
    var result: std.ArrayList([]const u8) = .empty;
    var iterator = std.mem.splitScalar(u8, source, separator);
    while (iterator.next()) |part| append([]const u8, &result, part);
    return result.items;
}
pub fn lines(source: []const u8) Strings { const result = split(source, '\n'); return result[0 .. result.len - 1]; }
pub const Text = struct {
    data: std.ArrayList(u8) = .empty,
    pub fn write(self: *Text, source: []const u8) void { self.data.appendSlice(allocator, source) catch @panic("allocation failed"); }
    pub fn add(self: *Text, comptime pattern: []const u8, arguments: anytype) void { self.write(fmt(pattern, arguments)); }
    pub fn value(self: Text) []const u8 { return self.data.items; }
};
pub const Lines = struct {
    data: std.ArrayList([]const u8) = .empty,
    pub fn write(self: *Lines, source: []const u8) void { append([]const u8, &self.data, source); }
    pub fn add(self: *Lines, comptime pattern: []const u8, arguments: anytype) void { self.write(fmt(pattern, arguments)); }
};
pub const Point = struct { x: i64, y: i64 };
pub const Image = struct { name: []const u8, width: usize, height: usize, maxval: usize, pixels: []i64 };
pub const Mask = struct {
    width: usize, height: usize, pixels: []bool,
    pub fn init(width: usize, height: usize) Mask {
        const pixels = alloc(bool, width * height);
        @memset(pixels, false);
        return .{ .width = width, .height = height, .pixels = pixels };
    }
    pub fn get(self: Mask, x: i64, y: i64) bool {
        return x >= 0 and y >= 0 and x < n(self.width) and y < n(self.height) and self.pixels[u(y) * self.width + u(x)];
    }
    pub fn count(self: Mask) usize {
        var result: usize = 0;
        for (self.pixels) |value| result += @intFromBool(value);
        return result;
    }
};
pub fn readImages(io: std.Io) ![]Image {
    const data = try std.Io.Dir.cwd().readFileAlloc(io, "input/images.txt", allocator, .unlimited);
    var comment = false;
    for (data) |*character| {
        if (character.* == '\n') comment = false;
        if (character.* == '#') comment = true;
        if (comment) character.* = ' ';
    }
    var tokens = std.mem.tokenizeAny(u8, data, " \n");
    var images: std.ArrayList(Image) = .empty;
    while (tokens.next() != null) {
        const name = tokens.next().?;
        _ = tokens.next().?;
        const width = integer(tokens.next().?);
        const height = integer(tokens.next().?);
        const maxval = integer(tokens.next().?);
        const pixels = alloc(i64, width * height);
        for (pixels) |*pixel| pixel.* = number(tokens.next().?);
        append(Image, &images, .{ .name = name, .width = width, .height = height, .maxval = maxval, .pixels = pixels });
    }
    return images.items;
}
