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
pub fn f(value: anytype) f64 {
    return @floatFromInt(value);
}
pub fn decimal(value: []const u8) f64 {
    return std.fmt.parseFloat(f64, value) catch unreachable;
}
pub const Vector = []f64;
pub const Matrix = [][]f64;
pub fn vector(count: usize) Vector {
    const out = alloc(f64, count);
    @memset(out, 0);
    return out;
}
pub fn matrix(rows: usize, columns: usize) Matrix {
    const out = alloc(Vector, rows);
    for (out) |*row| row.* = vector(columns);
    return out;
}
pub const Point = struct { x: i64 = 0, y: i64 = 0 };
pub const Pair = struct { a: usize, b: usize };
pub const Triangle = [3]usize;
pub fn orient(p: Point, q: Point, r: Point) i64 {
    return (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x);
}
pub fn d2(p: Point, q: Point) i64 {
    return (p.x - q.x) * (p.x - q.x) + (p.y - q.y) * (p.y - q.y);
}
pub fn dot(o: Point, p: Point, q: Point) i64 {
    return (p.x - o.x) * (q.x - o.x) + (p.y - o.y) * (q.y - o.y);
}
pub fn incircle(a0: Point, b0: Point, c0: Point, d: Point) i64 {
    const a: Point = .{ .x = a0.x - d.x, .y = a0.y - d.y };
    const b: Point = .{ .x = b0.x - d.x, .y = b0.y - d.y };
    const q: Point = .{ .x = c0.x - d.x, .y = c0.y - d.y };
    const aa = a.x * a.x + a.y * a.y;
    const bb = b.x * b.x + b.y * b.y;
    const cc = q.x * q.x + q.y * q.y;
    return a.x * (b.y * cc - bb * q.y) - a.y * (b.x * cc - bb * q.x) + aa * (b.x * q.y - b.y * q.x);
}
pub const Center = struct { x: i64 = 0, y: i64 = 0, d: i64 = 1 };
pub fn center(a: Point, b: Point, q: Point) Center {
    const u_: Point = .{ .x = b.x - a.x, .y = b.y - a.y };
    const v: Point = .{ .x = q.x - a.x, .y = q.y - a.y };
    const dd = 2 * (u_.x * v.y - u_.y * v.x);
    const uu = u_.x * u_.x + u_.y * u_.y;
    const vv = v.x * v.x + v.y * v.y;
    return .{ .x = a.x * dd + v.y * uu - u_.y * vv, .y = a.y * dd + u_.x * vv - v.x * uu, .d = dd };
}
fn gcd(a0: i64, b0: i64) i64 {
    var a = @abs(a0);
    var b = @abs(b0);
    while (b != 0) {
        const remainder = a % b;
        a = b;
        b = remainder;
    }
    return @intCast(a);
}
pub fn fraction(numerator_: i64, denominator_: i64) []const u8 {
    const divisor = gcd(numerator_, denominator_);
    const numerator = @divExact(numerator_, divisor);
    const denominator = @divExact(denominator_, divisor);
    return if (denominator == 1) fmt("{d}", .{numerator}) else fmt("{d}/{d}", .{ numerator, denominator });
}
pub fn outward(u_: Point, v: Point) Point {
    const dx = v.x - u_.x;
    const dy = v.y - u_.y;
    const g = gcd(dx, dy);
    return .{ .x = @divExact(dy, g), .y = @divExact(-dx, g) };
}
pub fn canonical(triangle: Triangle) Triangle {
    var start: usize = 0;
    for (triangle[1..], 1..) |site, i| if (site < triangle[start]) {
        start = i;
    };
    return .{ triangle[start], triangle[(start + 1) % 3], triangle[(start + 2) % 3] };
}
