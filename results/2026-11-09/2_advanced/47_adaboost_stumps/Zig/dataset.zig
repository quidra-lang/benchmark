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
pub const Row = struct { id: []const u8, values: []const f64, label: i64 };
pub const Params = struct { rounds: usize = 0, bins: usize = 0, folds: usize = 0, classes: usize = 0,
     samme_rounds: usize = 0, permutations: usize = 0, bootstrap: usize = 0, smoothing: f64 = 0, convergence: f64 = 0,
     clip: f64 = 0, permutation_seed: i64 = 0, noise_seed: i64 = 0, bootstrap_seed: i64 = 0, variants: []const []const u8 = &.{},
     margins: []const f64 = &.{}, shrinkage: []const f64 = &.{}, noise: []const i64 = &.{}, sizes: []const i64 = &.{} };
pub const Input = struct { train: []const Row, test_rows: []const Row, multi_train: []const Row, multi_test: []const Row,
     names: []const []const u8, multi_names: []const []const u8, params: Params };
fn binary(lines: []const []const u8) []const Row {
    const out = alloc(Row, lines.len - 1);
    for (lines[1..], out) |line, *row| {
        const fields = split(line, ',');
        const values = vector(fields.len - 2);
        for (fields[1 .. fields.len - 1], values) |field, *value| value.* = decimal(field);
        row.* = .{ .id = fields[0], .values = values, .label = number(fields[fields.len - 1]) };
    }
    return out;
}
pub fn readInput(io: std.Io) !Input {
    const train_lines = try readLines(io, "input/train.csv");
    const header = split(train_lines[0], ',');
    const multi_lines = try readLines(io, "input/multiclass.csv");
    const multi_header = split(multi_lines[0], ',');
    var multi_train: std.ArrayList(Row) = .empty;
    var multi_test: std.ArrayList(Row) = .empty;
    for (multi_lines[1..]) |line| {
        const fields = split(line, ',');
        const values = vector(fields.len - 3);
        for (fields[1 .. fields.len - 2], values) |field, *value| value.* = decimal(field);
        const row: Row = .{ .id = fields[0], .values = values, .label = number(fields[fields.len - 2]) };
        append(Row, if (eq(fields[fields.len - 1], "train")) &multi_train else &multi_test, row);
    }
    var p: Params = .{};
    for (try readLines(io, "input/params.txt")) |line| {
        const fields = words(line);
        const key = fields[0];
        if (eq(key, "ROUNDS")) p.rounds = u(number(fields[1])) else if (eq(key, "VARIANTS")) p.variants = fields[1..] else if (eq(key,
             "BINS")) p.bins = u(number(fields[1])) else if (eq(key, "SMOOTHING")) p.smoothing = decimal(fields[1]) else if (eq(key,
             "CONVERGENCE")) p.convergence = decimal(fields[1]) else if (eq(key, "CLIP")) p.clip = decimal(fields[1]) else if (eq(key,
             "FOLDS")) p.folds = u(number(fields[1])) else if (eq(key, "CLASSES")) p.classes = u(number(fields[1])) else if (eq(key,
             "SAMME_ROUNDS")) p.samme_rounds = u(number(fields[1])) else if (eq(key, "PERMUTATION")) {
            p.permutations = u(number(fields[1]));
            p.permutation_seed = number(fields[2]);
        } else if (eq(key, "BOOTSTRAP")) {
            p.bootstrap = u(number(fields[1]));
            p.bootstrap_seed = number(fields[2]);
        } else if (eq(key, "NOISE") or eq(key, "SIZES")) {
            const start: usize = if (eq(key, "NOISE")) 2 else 1;
            if (start == 2) p.noise_seed = number(fields[1]);
            const values = alloc(i64, fields.len - start);
            for (fields[start..], values) |field, *value| value.* = number(field);
            if (start == 2) p.noise = values else p.sizes = values;
        } else {
            const values = vector(fields.len - 1);
            for (fields[1..], values) |field, *value| value.* = decimal(field);
            if (eq(key, "MARGINS")) p.margins = values else p.shrinkage = values;
        }
    }
    return .{ .train = binary(train_lines), .test_rows = binary(try readLines(io, "input/test.csv")),
         .multi_train = multi_train.items, .multi_test = multi_test.items, .names = header[1 .. header.len - 1],
         .multi_names = multi_header[1 .. multi_header.len - 2], .params = p };
}
