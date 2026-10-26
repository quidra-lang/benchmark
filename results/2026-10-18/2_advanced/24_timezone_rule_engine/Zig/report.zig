const std = @import("std");
const d = @import("day_rules.zig");
const resolver = @import("resolver.zig");
pub var allocator: std.mem.Allocator = undefined;
pub fn alloc(comptime T: type, count: usize) []T { return allocator.alloc(T, count) catch @panic("allocation failed"); }
pub fn append(comptime T: type, list: *std.ArrayList(T), value: T) void { list.append(allocator, value) catch @panic("allocation failed"); }
pub fn fmt(comptime pattern: []const u8, arguments: anytype) []const u8 { return std.fmt.allocPrint(allocator, pattern, arguments) catch @panic("allocation failed"); }
pub fn eq(first: []const u8, second: []const u8) bool { return std.mem.eql(u8, first, second); }
pub fn n(value: anytype) i64 { return @intCast(value); }
pub fn u(value: i64) usize { return @intCast(value); }
pub fn number(text: []const u8) i64 { return std.fmt.parseInt(i64, text, 10) catch unreachable; }
pub fn splitFields(text: []const u8) []const []const u8 {
    var result: std.ArrayList([]const u8) = .empty;
    var iterator = std.mem.tokenizeScalar(u8, text, ' ');
    while (iterator.next()) |field| append([]const u8, &result, field);
    return result.items;
}
pub fn lines(text: []const u8) []const []const u8 {
    var result: std.ArrayList([]const u8) = .empty;
    var iterator = std.mem.splitScalar(u8, text, '\n');
    while (iterator.next()) |line| append([]const u8, &result, line);
    result.items.len -= 1;
    return result.items;
}
pub const Text = struct {
    data: std.ArrayList(u8) = .empty,
    pub fn write(self: *Text, text: []const u8) void { self.data.appendSlice(allocator, text) catch @panic("allocation failed"); }
    pub fn add(self: *Text, comptime pattern: []const u8, arguments: anytype) void { self.write(fmt(pattern, arguments)); }
    pub fn value(self: Text) []const u8 { return self.data.items; }
};
pub const Lines = struct {
    data: std.ArrayList([]const u8) = .empty,
    pub fn write(self: *Lines, text: []const u8) void { append([]const u8, &self.data, text); }
    pub fn add(self: *Lines, comptime pattern: []const u8, arguments: anytype) void { self.write(fmt(pattern, arguments)); }
    pub fn extend(self: *Lines, other: Lines) void { self.data.appendSlice(allocator, other.data.items) catch @panic("allocation failed"); }
    pub fn paragraph(self: *Lines, other: Lines) void { if (self.data.items.len > 0) self.write(""); self.extend(other); }
};
pub fn join(source: []const []const u8, separator: []const u8) []const u8 {
    var text: Text = .{};
    for (source, 0..) |word, i| { if (i > 0) text.write(separator); text.write(word); }
    return text.value();
}
pub fn localText(time: i64) []const u8 {
    const date = d.splitTime(time);
    return fmt("{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}", .{ date.year, date.month, date.day, date.hour, date.minute, date.second });
}
pub fn utText(time: i64) []const u8 { return fmt("{s}Z", .{localText(time)}); }
pub fn offsetText(value: i64) []const u8 {
    const magnitude = @abs(value);
    const text = fmt("{s}{d:0>2}:{d:0>2}", .{ if (value < 0) "-" else "+", magnitude / 3600, (magnitude / 60) % 60 });
    return if (magnitude % 60 > 0) fmt("{s}:{d:0>2}", .{ text, magnitude % 60 }) else text;
}
pub fn durationText(value: i64) []const u8 {
    const magnitude = @abs(value);
    return fmt("{s}{d}:{d:0>2}:{d:0>2}", .{ if (value < 0) "-" else "", magnitude / 3600, (magnitude / 60) % 60, magnitude % 60 });
}
pub fn clockText(value: i64) []const u8 {
    const text = fmt("{d}:{d:0>2}", .{ @divTrunc(value, 3600), @mod(@divTrunc(value, 60), 60) });
    return if (@mod(value, 60) > 0) fmt("{s}:{d:0>2}", .{ text, @mod(value, 60) }) else text;
}
pub fn stateText(period: resolver.Period) []const u8 { return fmt("{s} {s} {s}", .{ offsetText(period.offset), if (period.dst) "DST" else "STD", period.abbreviation }); }
pub fn changeText(timeline: resolver.Timeline, index: usize) []const u8 { return fmt("{s} {s} -> {s}", .{ utText(timeline.periods[index].start), stateText(timeline.periods[index - 1]), stateText(timeline.periods[index]) }); }
pub fn writeLines(io: std.Io, name: []const u8, source: Lines) !void {
    var text: Text = .{};
    for (source.data.items) |line| text.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = fmt("output/{s}", .{name}), .data = text.value() });
}
