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
const v = @import("vector3.zig");
pub const Vec = v.Vec;
pub const Bounds = struct { lo: Vec, hi: Vec };
pub const Ray = struct { origin: Vec, direction: Vec };
pub const Material = struct { name: []const u8, color: Vec, second: Vec = .{ 0, 0, 0 }, kd: i64, ks: i64, exponent: i64, kr: i64, kt: i64, ior: i64, checker_size: i64 = 0 };
pub const ObjectKind = enum { sphere, plane, box };
pub const LightKind = enum { point, spot, sun, area };
pub const Object = struct { kind: ObjectKind, label: u8, material: usize, first: Vec, second: Vec = .{ 0, 0, 0 }, radius: i64 = 0 };
pub const Light = struct { kind: LightKind, position: Vec = .{ 0, 0, 0 }, direction: Vec = .{ 0, 0, 0 }, u: Vec = .{ 0, 0, 0 }, v: Vec = .{ 0, 0, 0 }, outer: i64 = 0, inner: i64 = 0, intensity: i64, divisions: usize = 1 };
pub const Scene = struct {
    eye: Vec = .{ 0, 0, 0 },
    forward: Vec = .{ 0, 0, 0 },
    right: Vec = .{ 0, 0, 0 },
    up: Vec = .{ 0, 0, 0 },
    half_width: i64 = 0,
    half_height: i64 = 0,
    ambient: i64 = 0,
    background: Vec = .{ 0, 0, 0 },
    fog_color: Vec = .{ 0, 0, 0 },
    fog: bool = false,
    fog_start: i64 = 0,
    fog_end: i64 = 0,
    materials: std.ArrayList(Material) = .empty,
    objects: std.ArrayList(Object) = .empty,
    lights: std.ArrayList(Light) = .empty,
    fn material(self: Scene, name: []const u8) usize {
        for (self.materials.items, 0..) |m, i| if (eq(m.name, name)) return i;
        unreachable;
    }
};
pub fn vector(fields: []const []const u8, start: usize) Vec {
    return .{ number(fields[start]), number(fields[start + 1]), number(fields[start + 2]) };
}
pub fn load(io: std.Io) !Scene {
    var out: Scene = .{};
    for (try readLines(io, "input/scene.txt")) |line| {
        if (line.len == 0 or line[0] == '#') continue;
        const row = words(line);
        const key = row[0];
        if (eq(key, "eye")) {
            out.eye = vector(row, 1);
        } else if (eq(key, "forward")) {
            out.forward = vector(row, 1);
        } else if (eq(key, "right")) {
            out.right = vector(row, 1);
        } else if (eq(key, "up")) {
            out.up = vector(row, 1);
        } else if (eq(key, "view")) {
            out.half_width = number(row[1]);
            out.half_height = number(row[2]);
        } else if (eq(key, "background")) {
            out.background = vector(row, 1);
        } else if (eq(key, "ambient")) {
            out.ambient = number(row[1]);
        } else if (eq(key, "fog")) {
            out.fog = true;
            out.fog_color = vector(row, 1);
            out.fog_start = number(row[4]);
            out.fog_end = number(row[5]);
        } else if (eq(key, "material")) {
            append(Material, &out.materials, .{ .name = row[1], .color = vector(row, 2), .kd = number(row[5]), .ks = number(row[6]), .exponent = number(row[7]), .kr = number(row[8]), .kt = number(row[9]), .ior = number(row[10]) });
        } else if (eq(key, "checker")) {
            const m = &out.materials.items[out.material(row[1])];
            m.second = vector(row, 2);
            m.checker_size = number(row[5]);
        } else if (eq(key, "point") or eq(key, "spot") or eq(key, "sun") or eq(key, "area")) {
            var light: Light = .{ .kind = std.meta.stringToEnum(LightKind, key).?, .intensity = number(row[row.len - 1]) };
            if (light.kind == .sun) light.direction = v.norm(v.neg(vector(row, 1))) else {
                light.position = vector(row, 1);
                if (light.kind == .spot) {
                    light.direction = v.norm(vector(row, 4));
                    light.outer = number(row[7]);
                    light.inner = number(row[8]);
                } else if (light.kind == .area) {
                    light.u = vector(row, 4);
                    light.v = vector(row, 7);
                    light.divisions = u(number(row[10]));
                }
            }
            append(Light, &out.lights, light);
        } else {
            var object: Object = .{ .kind = std.meta.stringToEnum(ObjectKind, key).?, .label = row[1][0], .material = out.material(row[2]), .first = vector(row, 3) };
            if (object.kind == .sphere) object.radius = number(row[6]) else {
                object.second = vector(row, 6);
                if (object.kind == .plane) object.second = v.norm(object.second);
            }
            append(Object, &out.objects, object);
        }
    }
    return out;
}
