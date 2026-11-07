const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub const Strings = []const []const u8;
pub fn alloc(comptime T: type, count: usize) []T { return allocator.alloc(T, count) catch @panic("allocation failed"); }
pub fn append(comptime T: type, list: *std.ArrayList(T), value: T) void { list.append(allocator, value) catch @panic("allocation failed"); }
pub fn fmt(comptime pattern: []const u8, args: anytype) []const u8 { return std.fmt.allocPrint(allocator, pattern, args) catch @panic("allocation failed"); }
pub fn eq(a: []const u8, b: []const u8) bool { return std.mem.eql(u8, a, b); }
pub fn number(value: []const u8) i64 { return std.fmt.parseInt(i64, value, 10) catch unreachable; }
pub fn integer(value: []const u8) usize { return @intCast(number(value)); }
pub fn n(value: anytype) i64 { return @intCast(value); }
pub fn split(value: []const u8, separator: u8) Strings {
    var result: std.ArrayList([]const u8) = .empty;
    var iterator = std.mem.splitScalar(u8, value, separator);
    while (iterator.next()) |part| append([]const u8, &result, part);
    return result.items;
}
pub fn lines(value: []const u8) Strings { const result = split(value, '\n'); return result[0 .. result.len - 1]; }
pub const Text = struct {
    data: std.ArrayList(u8) = .empty,
    pub fn write(self: *Text, text: []const u8) void { self.data.appendSlice(allocator, text) catch @panic("allocation failed"); }
    pub fn byte(self: *Text, ch: u8) void { append(u8, &self.data, ch); }
    pub fn add(self: *Text, comptime pattern: []const u8, args: anytype) void { self.write(fmt(pattern, args)); }
    pub fn value(self: Text) []const u8 { return self.data.items; }
};
pub const Lines = struct {
    data: std.ArrayList([]const u8) = .empty,
    pub fn write(self: *Lines, value: []const u8) void { append([]const u8, &self.data, value); }
    pub fn add(self: *Lines, comptime pattern: []const u8, args: anytype) void { self.write(fmt(pattern, args)); }
    pub fn extend(self: *Lines, other: Lines) void { self.data.appendSlice(allocator, other.data.items) catch @panic("allocation failed"); }
    pub fn content(self: Lines) []const u8 {
        var result: Text = .{};
        for (self.data.items) |line| { result.write(line); result.byte('\n'); }
        return result.value();
    }
};
pub fn fixedWidth(label: []const u8, cells: Strings, label_width: usize, cell_width: usize) []const u8 {
    var result: Text = .{};
    result.write(label);
    var position = label.len;
    while (position < label_width) : (position += 1) result.byte(' ');
    for (cells) |cell| {
        position = cell.len;
        while (position < cell_width) : (position += 1) result.byte(' ');
        result.write(cell);
    }
    return result.value();
}
pub fn roundedPercent(part: i64, whole: i64) i64 { return @divFloor(200 * part + whole, 2 * whole); }
pub const File = struct { name: []const u8, lines: Lines };
pub fn writeFiles(io: std.Io, files: []const File) !void {
    const directory = std.Io.Dir.cwd();
    try directory.createDirPath(io, "output");
    for (files) |file| try directory.writeFile(io, .{ .sub_path = fmt("output/{s}", .{file.name}), .data = file.lines.content() });
}
