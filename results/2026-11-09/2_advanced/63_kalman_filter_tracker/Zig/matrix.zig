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
pub const Position = [2]f64;
pub const Vector = struct { count: usize = 0, values: [6]f64 = [_]f64{0} ** 6 };
pub const Matrix = struct { rows: usize = 0, columns: usize = 0, values: [6][6]f64 = std.mem.zeroes([6][6]f64) };
pub fn zeros(rows: usize, columns: usize) Matrix {
    return .{ .rows = rows, .columns = columns };
}
pub fn identity(size: usize) Matrix {
    var out = zeros(size, size);
    for (0..size) |i| out.values[i][i] = 1;
    return out;
}
pub fn diagonal(values: Vector) Matrix {
    var out = zeros(values.count, values.count);
    for (0..values.count) |i| out.values[i][i] = values.values[i];
    return out;
}
pub fn transpose(a: Matrix) Matrix {
    var out = zeros(a.columns, a.rows);
    for (0..a.rows) |i| for (0..a.columns) |j| {
        out.values[j][i] = a.values[i][j];
    };
    return out;
}
pub fn add(a: Matrix, b: Matrix) Matrix {
    var out = a;
    for (0..a.rows) |i| for (0..a.columns) |j| {
        out.values[i][j] = a.values[i][j] + b.values[i][j];
    };
    return out;
}
pub fn subtract(a: Matrix, b: Matrix) Matrix {
    var out = a;
    for (0..a.rows) |i| for (0..a.columns) |j| {
        out.values[i][j] = a.values[i][j] - b.values[i][j];
    };
    return out;
}
pub fn vectorAdd(a: Vector, b: Vector) Vector {
    var out = a;
    for (0..a.count) |i| out.values[i] = a.values[i] + b.values[i];
    return out;
}
pub fn vectorSubtract(a: Vector, b: Vector) Vector {
    var out = a;
    for (0..a.count) |i| out.values[i] = a.values[i] - b.values[i];
    return out;
}
pub fn product(a: Matrix, b: Matrix) Matrix {
    var out = zeros(a.rows, b.columns);
    for (0..a.rows) |i| for (0..b.columns) |j| {
        for (0..a.columns) |k| out.values[i][j] += a.values[i][k] * b.values[k][j];
    };
    return out;
}
pub fn matrixVector(a: Matrix, b: Vector) Vector {
    var out: Vector = .{ .count = a.rows };
    for (0..a.rows) |i| for (0..b.count) |k| {
        out.values[i] += a.values[i][k] * b.values[k];
    };
    return out;
}
pub fn inverse(a: Matrix) Matrix {
    const size = a.rows;
    var augmented: [6][12]f64 = std.mem.zeroes([6][12]f64);
    for (0..size) |i| {
        for (0..size) |j| augmented[i][j] = a.values[i][j];
        augmented[i][size + i] = 1;
    }
    for (0..size) |column| {
        const pivot = augmented[column][column];
        for (0..2 * size) |j| augmented[column][j] /= pivot;
        for (0..size) |row| {
            if (row == column) continue;
            const factor = augmented[row][column];
            for (0..2 * size) |j| augmented[row][j] -= factor * augmented[column][j];
        }
    }
    var out = zeros(size, size);
    for (0..size) |i| for (0..size) |j| {
        out.values[i][j] = augmented[i][size + j];
    };
    return out;
}
pub fn determinant2(a: Matrix) f64 {
    return a.values[0][0] * a.values[1][1] - a.values[0][1] * a.values[1][0];
}
pub fn quadratic2(v: Position, a: Matrix) f64 {
    return v[0] * (a.values[0][0] * v[0] + a.values[0][1] * v[1]) + v[1] * (a.values[1][0] * v[0] + a.values[1][1] * v[1]);
}
