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
pub const Sample = struct { id: []const u8, values: []const ?f64 };
pub const Params = struct { missing: []const u8 = "", scaling: []const u8 = "", components: []const u8 = "",
     cumulative: f64 = 0, t2: f64 = 0, spe: f64 = 0, repetitions: usize = 0, cycles: usize = 0, top: usize = 0,
     scree: usize = 0, bw: usize = 0, bh: usize = 0, radius: usize = 0, dw: usize = 0, dh: usize = 0,
     seed: i64 = 0 };
pub const Input = struct { names: []const []const u8, data: []const Sample, supplementary: []const Sample, params: Params };
fn samples(lines: []const []const u8) []const Sample {
    const out = alloc(Sample, lines.len - 1);
    for (lines[1..], out) |line, *row| {
        const fields = split(line, ',');
        const values = alloc(?f64, fields.len - 1);
        for (fields[1..], values) |field, *value| value.* = if (eq(field, "NA")) null else decimal(field);
        row.* = .{ .id = fields[0], .values = values };
    }
    return out;
}
pub fn readInput(io: std.Io) !Input {
    const data_lines = try readLines(io, "input/data.csv");
    const names = split(data_lines[0], ',')[1..];
    const lines = try readLines(io, "input/params.txt");
    var p: Params = .{};
    p.missing = words(lines[0])[1];
    p.scaling = words(lines[1])[1];
    p.components = words(lines[2])[1];
    p.cumulative = decimal(words(lines[3])[1]);
    p.repetitions = u(number(words(lines[4])[1]));
    p.seed = number(words(lines[4])[2]);
    p.t2 = decimal(words(lines[5])[1]);
    p.spe = decimal(words(lines[6])[1]);
    p.cycles = u(number(words(lines[7])[1]));
    p.top = u(number(words(lines[8])[1]));
    p.scree = u(number(words(lines[9])[1]));
    p.bw = u(number(words(lines[10])[1]));
    p.bh = u(number(words(lines[10])[2]));
    p.radius = u(number(words(lines[11])[1]));
    p.dw = u(number(words(lines[12])[1]));
    p.dh = u(number(words(lines[12])[2]));
    return .{ .names = names, .data = samples(data_lines), .supplementary = samples(try readLines(io,
         "input/supplementary.csv")), .params = p };
}
