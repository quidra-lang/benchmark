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
pub fn f(value: anytype) f64 {
    return @floatFromInt(value);
}
pub fn real(value: []const u8) f64 {
    return std.fmt.parseFloat(f64, value) catch unreachable;
}
pub const Vec = [2]f64;
pub const Cov = [3]f64;
pub const Type = enum { FULL, TIED, DIAG, SPHERICAL };
pub const Point = struct { id: []const u8, xy: Vec };
pub const Component = struct { weight: f64, mean: Vec, cov: Cov };
pub const Model = struct { components: []Component = &.{}, kind: Type = .FULL };
pub const Params = struct { ks: []const usize, types: []const Type, iterations: usize, kmeans_max: usize,
     folds: usize, width: usize, height: usize, epsilon: f64, tolerance: f64, uncertain: f64, low_density: f64,
     xmin: f64, xmax: f64, ymin: f64, ymax: f64, gof: []const f64 };
pub const Input = struct { points: []const Point, params: Params, initial: [5]Model };
fn parseType(value: []const u8) Type {
    return std.meta.stringToEnum(Type, value).?;
}
fn firstInteger(line: []const u8) usize {
    return u(number(words(line)[1]));
}
fn firstReal(line: []const u8) f64 {
    return real(words(line)[1]);
}
pub fn load(io: std.Io) !Input {
    const point_lines = try readLines(io, "input/points.csv");
    const points = alloc(Point, point_lines.len - 1);
    for (point_lines[1..], points) |line, *point| {
        const fields = split(line, ',');
        point.* = .{ .id = fields[0], .xy = .{ real(fields[1]), real(fields[2]) } };
    }
    const lines = try readLines(io, "input/params.txt");
    const k_fields = words(lines[0]);
    const ks = alloc(usize, k_fields.len - 1);
    for (k_fields[1..], ks) |field, *k| k.* = u(number(field));
    const type_fields = words(lines[2]);
    const types = alloc(Type, type_fields.len - 1);
    for (type_fields[1..], types) |field, *kind| kind.* = parseType(field);
    const boundaries = words(lines[9]);
    const gof = alloc(f64, boundaries.len - 1);
    for (boundaries[1..], gof) |field, *value| value.* = real(field);
    const xs = words(lines[10]);
    const ys = words(lines[11]);
    const dimensions = words(lines[12]);
    var out: Input = .{ .points = points, .params = .{ .ks = ks, .types = types, .iterations = firstInteger(lines[1]),
         .epsilon = firstReal(lines[3]), .tolerance = firstReal(lines[4]), .kmeans_max = firstInteger(lines[5]),
         .folds = firstInteger(lines[6]), .uncertain = firstReal(lines[7]), .low_density = firstReal(lines[8]),
         .gof = gof, .xmin = real(xs[1]), .xmax = real(xs[2]), .ymin = real(ys[1]), .ymax = real(ys[2]),
         .width = u(number(dimensions[1])), .height = u(number(dimensions[2])) }, .initial = .{ .{},
         .{}, .{}, .{}, .{} } };
    const blocks = try readLines(io, "input/init.txt");
    var cursor: usize = 0;
    while (cursor < blocks.len) {
        if (blocks[cursor].len == 0) {
            cursor += 1;
            continue;
        }
        const k = firstInteger(blocks[cursor]);
        cursor += 1;
        const weights = words(blocks[cursor]);
        cursor += 1;
        const components = alloc(Component, k);
        for (components, 0..) |*component, j| {
            const fields = words(blocks[cursor]);
            cursor += 1;
            component.* = .{ .weight = real(weights[j + 1]), .mean = .{ real(fields[2]), real(fields[3]) },
                 .cov = .{ real(fields[4]), real(fields[5]), real(fields[6]) } };
        }
        if (k <= 4) out.initial[k] = .{ .components = components };
    }
    return out;
}
