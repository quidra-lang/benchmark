const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub const Matrix = [][]f64;
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
pub fn f(value: anytype) f64 {
    return @floatFromInt(value);
}
pub fn number(text: []const u8) usize {
    return std.fmt.parseInt(usize, text, 10) catch unreachable;
}
pub fn floating(text: []const u8) f64 {
    return std.fmt.parseFloat(f64, text) catch unreachable;
}
pub fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
pub fn split(text: []const u8, delimiter: u8) []const []const u8 {
    var result: std.ArrayList([]const u8) = .empty;
    var fields = std.mem.splitScalar(u8, text, delimiter);
    while (fields.next()) |field| append([]const u8, &result, field);
    return result.items;
}
pub fn zeros(count: usize) []f64 {
    const values = alloc(f64, count);
    @memset(values, 0);
    return values;
}
pub fn matrix(rows: usize, columns: usize) Matrix {
    const result = alloc([]f64, rows);
    for (result) |*row| row.* = zeros(columns);
    return result;
}
pub fn sequence(count: usize) []usize {
    const values = alloc(usize, count);
    for (values, 0..) |*value, index| value.* = index;
    return values;
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
    pub fn blank(self: *Lines) void {
        self.add("", .{});
    }
};
pub fn readLines(io: std.Io, name: []const u8) ![]const []const u8 {
    const text = try std.Io.Dir.cwd().readFileAlloc(io, fmt("input/{s}", .{name}), allocator, .unlimited);
    const lines = split(text, '\n');
    return lines[0 .. lines.len - 1];
}
pub fn writeLines(io: std.Io, name: []const u8, lines: Lines) !void {
    var text: Text = .{};
    for (lines.data.items) |line| text.add("{s}\n", .{line});
    try std.Io.Dir.cwd().createDirPath(io, "output");
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = fmt("output/{s}", .{name}), .data = text.value() });
}
pub const Row = struct { id: []const u8, values: []f64, label: usize };
pub const Table = struct { names: []const []const u8, rows: []Row };
pub fn readTable(io: std.Io, name: []const u8) !Table {
    const lines = try readLines(io, name);
    const header = split(lines[0], ',');
    const rows = alloc(Row, lines.len - 1);
    for (lines[1..], rows) |line, *row| {
        const fields = split(line, ',');
        const values = alloc(f64, fields.len - 2);
        for (fields[1 .. fields.len - 1], values) |field, *value| value.* = floating(field);
        row.* = .{ .id = fields[0], .values = values, .label = number(fields[fields.len - 1]) };
    }
    return .{ .names = header[1 .. header.len - 1], .rows = rows };
}
pub const Params = struct {
    positive: usize,
    degree: usize,
    threshold: f64,
    lambdas: []f64,
    gd_rate: f64,
    gd_iterations: usize,
    sgd_rate: f64,
    batch: usize,
    epochs: usize,
    sgd_seed: i64,
    softmax_rate: f64,
    softmax_iterations: usize,
    softmax_lambda: f64,
    bootstrap: usize,
    bootstrap_seed: i64,
    permutations: usize,
    permutation_seed: i64,
    width: usize,
    height: usize,
    fp_cost: i64,
    fn_cost: i64,
    pub fn read(io: std.Io) !Params {
        const lines = try readLines(io, "params.txt");
        var fields: [11][]const []const u8 = undefined;
        for (lines, &fields) |line, *field| field.* = split(line, ' ')[1..];
        const lambdas = alloc(f64, fields[3].len);
        for (fields[3], lambdas) |field, *value| value.* = floating(field);
        return .{ .positive = number(fields[0][0]), .degree = number(fields[1][0]), .threshold = floating(fields[2][0]),
             .lambdas = lambdas, .gd_rate = floating(fields[4][0]), .gd_iterations = number(fields[4][1]),
             .sgd_rate = floating(fields[5][0]), .batch = number(fields[5][1]), .epochs = number(fields[5][2]),
             .sgd_seed = n(number(fields[5][3])), .softmax_rate = floating(fields[6][0]), .softmax_iterations = number(fields[6][1]),
             .softmax_lambda = floating(fields[6][2]), .bootstrap = number(fields[7][0]), .bootstrap_seed = n(number(fields[7][1])),
             .permutations = number(fields[8][0]), .permutation_seed = n(number(fields[8][1])), .width = number(fields[9][0]),
             .height = number(fields[9][1]), .fp_cost = n(number(fields[10][0])), .fn_cost = n(number(fields[10][1])) };
    }
};
pub const Feature = struct { indices: []const usize, name: []const u8 };
fn visit(names: []const []const u8, remaining: usize, first: usize, tuple: []const usize, result: *std.ArrayList(Feature)) void {
    if (remaining == 0) {
        var text: Text = .{};
        for (tuple, 0..) |index, position| text.add("{s}{s}", .{ if (position > 0) "*" else "", names[index] });
        append(Feature, result, .{ .indices = tuple, .name = text.value() });
        return;
    }
    for (first..names.len) |index| {
        const next = alloc(usize, tuple.len + 1);
        @memcpy(next[0..tuple.len], tuple);
        next[tuple.len] = index;
        visit(names, remaining - 1, index, next, result);
    }
}
pub fn features(names: []const []const u8, degree: usize) []Feature {
    var result: std.ArrayList(Feature) = .empty;
    for (1..degree + 1) |count| visit(names, count, 0, &.{}, &result);
    return result.items;
}
pub fn expand(values: []const f64, terms: []const Feature) []f64 {
    const result = alloc(f64, terms.len);
    for (terms, result) |feature, *value| {
        value.* = values[feature.indices[0]];
        for (feature.indices[1..]) |index| value.* *= values[index];
    }
    return result;
}
pub fn expanded(rows: []const Row, terms: []const Feature) Matrix {
    const result = alloc([]f64, rows.len);
    for (rows, result) |row, *values| values.* = expand(row.values, terms);
    return result;
}
pub const Statistics = struct { mean: []f64, deviation: []f64 };
pub fn statistics(data: Matrix, count: usize) Statistics {
    const result: Statistics = .{ .mean = zeros(count), .deviation = zeros(count) };
    for (0..count) |j| {
        var total: f64 = 0;
        for (data) |row| total += row[j];
        result.mean[j] = total / f(data.len);
        var squares: f64 = 0;
        for (data) |row| {
            const delta = row[j] - result.mean[j];
            squares += delta * delta;
        }
        result.deviation[j] = @sqrt(squares / f(data.len - 1));
    }
    return result;
}
pub fn standardizePoint(row: []const f64, stats: Statistics, count: usize) []f64 {
    const result = alloc(f64, count + 1);
    result[0] = 1;
    for (0..count) |j| result[j + 1] = (row[j] - stats.mean[j]) / stats.deviation[j];
    return result;
}
pub fn standardize(data: Matrix, stats: Statistics, count: usize) Matrix {
    const result = alloc([]f64, data.len);
    for (data, result) |row, *values| values.* = standardizePoint(row, stats, count);
    return result;
}
pub fn labels(rows: []const Row, positive: ?usize) []usize {
    const result = alloc(usize, rows.len);
    for (rows, result) |row, *value| value.* = if (positive) |class| @intFromBool(row.label == class) else row.label;
    return result;
}
