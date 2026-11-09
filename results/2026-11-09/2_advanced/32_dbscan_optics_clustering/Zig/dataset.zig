const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub const INF = std.math.maxInt(i64);
pub const Distances = [][]i64;
pub fn alloc(comptime T: type, count: usize) []T {
    return allocator.alloc(T, count) catch @panic("allocation failed");
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
pub fn f(value: anytype) f64 {
    return @floatFromInt(value);
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
pub fn sequence(count: usize) []usize {
    const result = alloc(usize, count);
    for (result, 0..) |*value, index| value.* = index;
    return result;
}
pub fn readLines(io: std.Io, name: []const u8) ![]const []const u8 {
    const text = try std.Io.Dir.cwd().readFileAlloc(io, fmt("input/{s}", .{name}), allocator, .unlimited);
    const lines = split(text, '\n');
    return lines[0 .. lines.len - 1];
}
pub const Point = struct { id: i64, x: i64, y: i64 };
pub const Params = struct { eps: []i64, min_points: usize, max_eps: i64, extract: []i64, xi_u: i64,
     xi_v: i64, xi_size: usize, width: usize, height: usize, kwidth: usize, kheight: usize, rwidth: usize };
pub const Input = struct { points: []Point, params: Params };
fn pointLess(_: void, a: Point, b: Point) bool {
    return a.id < b.id;
}
pub fn readInput(io: std.Io) !Input {
    const observations = try readLines(io, "points.csv");
    const points = alloc(Point, observations.len - 1);
    for (observations[1..], points) |line, *point| {
        const fields = split(line, ',');
        point.* = .{ .id = number(fields[0]), .x = number(fields[1]), .y = number(fields[2]) };
    }
    std.mem.sort(Point, points, {}, pointLess);
    const lines = try readLines(io, "params.txt");
    var fields: [9][]const []const u8 = undefined;
    for (lines, &fields) |line, *field| field.* = split(line, ' ')[1..];
    const eps = alloc(i64, fields[0].len);
    for (fields[0], eps) |word, *value| value.* = number(word);
    const extract = alloc(i64, fields[3].len);
    for (fields[3], extract) |word, *value| value.* = number(word);
    const ratio = split(fields[4][0], '/');
    return .{ .points = points, .params = .{ .eps = eps, .min_points = u(number(fields[1][0])), .max_eps = number(fields[2][0]),
         .extract = extract, .xi_u = number(ratio[0]), .xi_v = number(ratio[1]), .xi_size = u(number(fields[5][0])),
         .width = u(number(fields[6][0])), .height = u(number(fields[6][1])), .kwidth = u(number(fields[7][0])),
         .kheight = u(number(fields[7][1])), .rwidth = u(number(fields[8][0])) } };
}
pub fn distance(a: Point, b: Point) i64 {
    const x = a.x - b.x;
    const y = a.y - b.y;
    return x * x + y * y;
}
