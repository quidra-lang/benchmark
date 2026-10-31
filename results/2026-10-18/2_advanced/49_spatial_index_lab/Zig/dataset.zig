const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
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
pub const Box = struct { x1: i64 = 0, y1: i64 = 0, x2: i64 = 0, y2: i64 = 0 };
pub const Point = struct {
    id: i64,
    x: i64,
    y: i64,
    pub fn box(self: Point) Box {
        return .{ .x1 = self.x, .y1 = self.y, .x2 = self.x, .y2 = self.y };
    }
};
pub const Object = struct { id: i64, box: Box };
pub const Params = struct { world: usize, bucket: usize, maximum: usize, minimum: usize, grid: usize };
pub const Command = struct { name: []const u8, values: []const i64 };
pub const Input = struct { points: []const Point, rectangles: []const Object, params: Params, commands: []const Command };
pub fn create(comptime T: type, value: T) *T {
    const out = alloc(T, 1);
    out[0] = value;
    return &out[0];
}
pub fn pointInsert(values: *std.ArrayList(Point), point: Point) void {
    append(Point, values, point);
    var position = values.items.len - 1;
    while (position > 0 and point.id < values.items[position - 1].id) {
        values.items[position] = values.items[position - 1];
        position -= 1;
    }
    values.items[position] = point;
}
pub fn pointRemove(values: *std.ArrayList(Point), id: i64) void {
    for (values.items, 0..) |point, i| if (point.id == id) {
        _ = values.orderedRemove(i);
        return;
    };
}
pub fn readInput(io: std.Io) !Input {
    const point_lines = try readLines(io, "input/points.csv");
    const points = alloc(Point, point_lines.len - 1);
    for (point_lines[1..], points) |line, *point| {
        const fields = split(line, ',');
        point.* = .{ .id = number(fields[0]), .x = number(fields[1]), .y = number(fields[2]) };
    }
    const rectangle_lines = try readLines(io, "input/rects.csv");
    const rectangles = alloc(Object, rectangle_lines.len - 1);
    for (rectangle_lines[1..], rectangles) |line, *object| {
        const fields = split(line, ',');
        object.* = .{ .id = number(fields[0]), .box = .{ .x1 = number(fields[1]), .y1 = number(fields[2]),
             .x2 = number(fields[3]), .y2 = number(fields[4]) } };
    }
    const params = try readLines(io, "input/params.txt");
    const p: Params = .{ .world = u(number(words(params[0])[1])), .bucket = u(number(words(params[1])[1])),
         .maximum = u(number(words(params[2])[1])), .minimum = u(number(words(params[2])[2])), .grid = u(number(words(params[3])[1])) };
    const command_lines = try readLines(io, "input/queries.txt");
    const commands = alloc(Command, command_lines.len);
    for (command_lines, commands) |line, *command| {
        const fields = words(line);
        const values = alloc(i64, fields.len - 1);
        for (fields[1..], values) |field, *value| value.* = number(field);
        command.* = .{ .name = fields[0], .values = values };
    }
    return .{ .points = points, .rectangles = rectangles, .params = p, .commands = commands };
}
