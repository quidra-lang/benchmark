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

pub const Names = []const []const u8;
pub fn join(values: Names, separator: []const u8) []const u8 {
    return std.mem.join(allocator, separator, values) catch @panic("allocation failed");
}

pub fn zero(comptime T: type, count: usize, value: T) []T {
    const out = alloc(T, count);
    @memset(out, value);
    return out;
}

pub const Integer = i256;
fn gcd(first: Integer, second: Integer) Integer {
    var a: Integer = @intCast(@abs(first));
    var b: Integer = @intCast(@abs(second));
    while (b != 0) {
        const next = @mod(a, b);
        a = b;
        b = next;
    }
    return a;
}
pub const Fraction = struct {
    numerator: Integer = 0,
    denominator: Integer = 1,
    pub fn init(numerator: Integer, denominator: Integer) Fraction {
        const divisor = gcd(numerator, denominator);
        const sign: Integer = if (denominator < 0) -1 else 1;
        return .{ .numerator = sign * @divTrunc(numerator, divisor), .denominator = sign * @divTrunc(denominator,
             divisor) };
    }
    pub fn integer(value: Integer) Fraction {
        return .{ .numerator = value };
    }
    pub fn same(self: Fraction, other: Fraction) bool {
        return self.numerator == other.numerator and self.denominator == other.denominator;
    }
    pub fn add(self: Fraction, other: Fraction) Fraction {
        const divisor = gcd(self.denominator, other.denominator);
        const left = @divTrunc(self.denominator, divisor);
        const right = @divTrunc(other.denominator, divisor);
        return init(self.numerator * right + other.numerator * left, left * other.denominator);
    }
    pub fn subtract(self: Fraction, other: Fraction) Fraction {
        return self.add(.{ .numerator = -other.numerator, .denominator = other.denominator });
    }
    pub fn multiply(self: Fraction, other: Fraction) Fraction {
        const first = gcd(self.numerator, other.denominator);
        const second = gcd(other.numerator, self.denominator);
        return init(@divTrunc(self.numerator, first) * @divTrunc(other.numerator, second),
             @divTrunc(self.denominator, second) * @divTrunc(other.denominator, first));
    }
    pub fn divide(self: Fraction, other: Fraction) Fraction {
        return self.multiply(init(other.denominator, other.numerator));
    }
    pub fn less(self: Fraction, other: Fraction) bool {
        return @as(i512, self.numerator) * other.denominator < @as(i512, other.numerator) * self.denominator;
    }
    pub fn real(self: Fraction) f64 {
        return @as(f64, @floatFromInt(self.numerator)) / @as(f64, @floatFromInt(self.denominator));
    }
    pub fn rounded(self: Fraction) Integer {
        return @divFloor(2 * self.numerator + self.denominator, 2 * self.denominator);
    }
    pub fn text(self: Fraction) []const u8 {
        return if (self.denominator == 1) fmt("{d}", .{self.numerator}) else fmt("{d}/{d}",
             .{ self.numerator, self.denominator });
    }
};
pub const Point = struct {
    x: Fraction,
    y: Fraction,
    pub fn init(x: Integer, y: Integer) Point {
        return .{ .x = Fraction.integer(x), .y = Fraction.integer(y) };
    }
    pub fn same(self: Point, other: Point) bool {
        return self.x.same(other.x) and self.y.same(other.y);
    }
    pub fn add(self: Point, other: Point) Point {
        return .{ .x = self.x.add(other.x), .y = self.y.add(other.y) };
    }
    pub fn subtract(self: Point, other: Point) Point {
        return .{ .x = self.x.subtract(other.x), .y = self.y.subtract(other.y) };
    }
    pub fn scale(self: Point, value: Fraction) Point {
        return .{ .x = self.x.multiply(value), .y = self.y.multiply(value) };
    }
    pub fn text(self: Point) []const u8 {
        return fmt("({s},{s})", .{ self.x.text(), self.y.text() });
    }
};
pub fn cross(origin: Point, first: Point, second: Point) Fraction {
    const a = first.subtract(origin);
    const b = second.subtract(origin);
    return a.x.multiply(b.y).subtract(a.y.multiply(b.x));
}
pub fn pointLess(_: void, a: Point, b: Point) bool {
    return if (a.y.same(b.y)) a.x.less(b.x) else a.y.less(b.y);
}
pub fn along(first: Point, second: Point, position: Fraction) Point {
    return first.add(second.subtract(first).scale(position));
}
pub fn segmentText(first: Point, second: Point) []const u8 {
    return fmt("{s}-{s}", .{ first.text(), second.text() });
}
