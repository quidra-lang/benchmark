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
pub const Point = [3]i64;
pub const Polygon = struct { vertices: []const usize, line: usize, group: usize };
pub const InputError = struct { line: usize, kind: []const u8 };
pub const Object = struct { vertices: std.ArrayList(Point) = .empty, polygons: std.ArrayList(Polygon) = .empty,
     groups: std.ArrayList([]const u8) = .empty, errors: std.ArrayList(InputError) = .empty, lines: usize = 0,
     ignored: usize = 0 };
pub const Face = struct { vertices: [3]usize, polygon: usize = 0, line: usize = 0, group: usize, triangle: usize = 0 };
pub const Faces = std.ArrayList(Face);
pub const Options = struct { snap: i64 = 1, fill_holes: usize = 0, merge: bool = true, degenerate: bool = true,
     duplicates: bool = true, orient: bool = true, outward: bool = true, keep_unused: bool = true,
     sections: []const []const u8 = &.{ "summary", "components" }, queries: std.ArrayList([]const []const u8) = .empty };
pub fn integerWord(word: []const u8) bool {
    const first: usize = if (word.len > 0 and word[0] == '-') 1 else 0;
    if (first == word.len) return false;
    for (word[first..]) |char| if (char < '0' or char > '9') return false;
    return true;
}
pub fn readObject(io: std.Io) !Object {
    var out: Object = .{};
    append(Point, &out.vertices, .{ 0, 0, 0 });
    var current: []const u8 = "default";
    for (try readLines(io, "input/model.obj")) |line| {
        out.lines += 1;
        if (line.len == 0 or line[0] == '#') continue;
        const tokens = words(line);
        const key = tokens[0];
        var reason: ?[]const u8 = null;
        if (eq(key, "v")) {
            if (tokens.len != 4 or !integerWord(tokens[1]) or !integerWord(tokens[2]) or !integerWord(tokens[3])) reason = "bad_vertex" else append(Point,
                 &out.vertices, .{ number(tokens[1]), number(tokens[2]), number(tokens[3]) });
        } else if (eq(key, "f")) {
            var vertices: std.ArrayList(usize) = .empty;
            if (tokens.len < 4) reason = "short_face" else for (tokens[1..]) |reference| {
                const part = reference[0 .. std.mem.indexOfScalar(u8, reference, '/') orelse reference.len];
                if (!integerWord(part) or number(part) == 0) {
                    reason = "bad_index";
                    break;
                }
                const index = number(part);
                const vertex = if (index > 0) index else n(out.vertices.items.len) + index;
                if (vertex < 1 or vertex >= n(out.vertices.items.len)) {
                    reason = "out_of_range";
                    break;
                }
                append(usize, &vertices, u(vertex));
            };
            if (reason == null) {
                var group: usize = 0;
                while (group < out.groups.items.len and !eq(out.groups.items[group], current)) group += 1;
                if (group == out.groups.items.len) append([]const u8, &out.groups, current);
                append(Polygon, &out.polygons, .{ .vertices = vertices.items, .line = out.lines, .group = group });
            }
        } else if (eq(key, "g")) current = if (tokens.len > 1) tokens[1] else "default" else if (eq(key,
             "vt") or eq(key, "vn") or eq(key, "s") or eq(key, "o") or eq(key, "usemtl") or eq(key,
             "mtllib")) out.ignored += 1 else reason = "unknown_keyword";
        if (reason) |kind| append(InputError, &out.errors, .{ .line = out.lines, .kind = kind });
    }
    return out;
}
pub fn list(values: []const usize, offset: usize) []const u8 {
    if (values.len == 0) return "-";
    var out: Text = .{};
    for (values, 0..) |value, i| out.add("{s}{d}", .{ if (i == 0) "" else " ", value + offset });
    return out.value();
}
pub fn write(io: std.Io, name: []const u8, lines: Lines) !void {
    var out: Text = .{};
    for (lines.data.items) |line| out.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = fmt("output/{s}", .{name}), .data = out.value() });
}
pub fn writeObject(io: std.Io, points: []const Point, faces: []const Face, groups: []const []const u8) !void {
    var lines: Lines = .{};
    lines.add("# vertices {d} faces {d}", .{ points.len - 1, faces.len });
    for (points[1..]) |point| lines.add("v {d} {d} {d}", .{ point[0], point[1], point[2] });
    var previous: ?usize = null;
    for (faces) |face| {
        if (previous == null or previous.? != face.group) {
            previous = face.group;
            lines.add("g {s}", .{groups[face.group]});
        }
        lines.add("f {d} {d} {d}", .{ face.vertices[0], face.vertices[1], face.vertices[2] });
    }
    try write(io, "repaired.obj", lines);
}
