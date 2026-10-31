const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub fn alloc(comptime T: type, count: usize) []T {
    return allocator.alloc(T, count) catch @panic("allocation failed");
}
pub fn zero(comptime T: type, count: usize) []T {
    const values = alloc(T, count);
    @memset(values, std.mem.zeroes(T));
    return values;
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
pub fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
pub fn integer(text: []const u8) i64 {
    return std.fmt.parseInt(i64, text, 10) catch unreachable;
}
pub fn real(text: []const u8) f64 {
    return std.fmt.parseFloat(f64, text) catch unreachable;
}
pub fn hundredths(text: []const u8) i64 {
    var value: i64 = 0;
    for (text) |c| if (c >= '0' and c <= '9') {
        value = value * 10 + c - '0';
    };
    return if (text[0] == '-') -value else value;
}
pub fn split(text: []const u8, delimiter: u8) []const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var fields = std.mem.splitScalar(u8, text, delimiter);
    while (fields.next()) |field| append([]const u8, &out, field);
    return out.items;
}
pub fn readLines(io: std.Io, path: []const u8) ![]const []const u8 {
    const text = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited);
    const lines = split(text, '\n');
    return lines[0 .. lines.len - 1];
}
pub const Data = struct { x: []i64, y: []i64, real_x: []f64, real_y: []f64 };
pub const Series = struct { name: []const u8, data: Data };
pub const TestPoint = struct { series: []const u8, x: i64 };
pub const Params = struct { rows: [17][]const []const u8 };
pub const Input = struct { series: []Series, tests: []TestPoint, params: Params };
const Point = struct { x: i64, y: i64 };
fn pointLess(_: void, a: Point, b: Point) bool {
    return a.x < b.x;
}
pub fn readInput(io: std.Io) !Input {
    const TempSeries = struct { name: []const u8, points: std.ArrayList(Point) = .empty };
    var temp: std.ArrayList(TempSeries) = .empty;
    const observations = try readLines(io, "input/series.csv");
    for (observations[1..]) |line| {
        const fields = split(line, ',');
        var found: ?usize = null;
        for (temp.items, 0..) |series, i| if (eq(series.name, fields[0])) {
            found = i;
            break;
        };
        if (found == null) {
            found = temp.items.len;
            append(TempSeries, &temp, .{ .name = fields[0] });
        }
        append(Point, &temp.items[found.?].points, .{ .x = hundredths(fields[1]), .y = hundredths(fields[2]) });
    }
    const series = alloc(Series, temp.items.len);
    for (temp.items, series) |value, *target| {
        std.mem.sort(Point, value.points.items, {}, pointLess);
        const count = value.points.items.len;
        const data: Data = .{ .x = alloc(i64, count), .y = alloc(i64, count), .real_x = alloc(f64,
             count), .real_y = alloc(f64, count) };
        for (value.points.items, 0..) |point, i| {
            data.x[i] = point.x;
            data.y[i] = point.y;
            data.real_x[i] = f(point.x) / 100;
            data.real_y[i] = f(point.y) / 100;
        }
        target.* = .{ .name = value.name, .data = data };
    }
    const test_lines = try readLines(io, "input/test_points.csv");
    const tests = alloc(TestPoint, test_lines.len - 1);
    for (test_lines[1..], tests) |line, *point| {
        const fields = split(line, ',');
        point.* = .{ .series = fields[0], .x = hundredths(fields[1]) };
    }
    const settings = try readLines(io, "input/params.txt");
    var params: Params = undefined;
    for (settings, &params.rows) |line, *row| row.* = split(line, ' ')[1..];
    return .{ .series = series, .tests = tests, .params = params };
}
pub const Kind = enum { linear, mean, median, nw, ll, loess, spline, isotonic };
pub const Parameter = struct { text: []const u8 = "-", value: f64 = 0, integer: i64 = 0 };
pub const Method = struct { name: []const u8, kind: Kind, kernel: []const u8 = "", degree: usize = 0,
     candidates: []Parameter = &.{} };
