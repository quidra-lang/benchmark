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
pub const Vector = [6]f64;
pub const Matrix = [6]Vector;
pub const Features = []const usize;
pub const Row = struct { id: i64, label: usize, values: Vector = std.mem.zeroes(Vector) };
pub const Rows = []const Row;
pub const Subset = struct { name: []const u8, features: Features };
pub const Pair = struct { x: usize, y: usize };
pub const Params = struct { empirical: bool = true, smoothing: f64 = 0, gamma: f64 = 0, outlier: f64 = 0,
     smoothing_grid: []const f64 = &.{}, gamma_grid: []const f64 = &.{}, calibration: []const f64 = &.{},
     reject: []const f64 = &.{}, curve: []const usize = &.{}, folds: usize = 0, bootstrap: usize = 0,
     map_width: usize = 0, map_height: usize = 0, plot_width: usize = 0, plot_height: usize = 0, seed: i64 = 0,
     subsets: std.ArrayList(Subset) = .empty, pairs: std.ArrayList(Pair) = .empty };
pub const Dataset = struct { features: []const []const u8, classes: []const []const u8, train: Rows,
     test_rows: Rows, costs: [5][5]f64 = std.mem.zeroes([5][5]f64), params: Params = .{} };
fn textLess(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}
pub fn nameIndex(names: []const []const u8, name: []const u8) usize {
    for (names, 0..) |value, i| if (eq(value, name)) return i;
    unreachable;
}
fn parseRows(lines: []const []const u8, features: usize, classes: []const []const u8) Rows {
    var rows: std.ArrayList(Row) = .empty;
    for (lines[1..]) |line| {
        const fields = split(line, ',');
        var row: Row = .{ .id = number(fields[0]), .label = nameIndex(classes, fields[fields.len - 1]) };
        for (0..features) |j| row.values[j] = decimal(fields[j + 1]);
        append(Row, &rows, row);
    }
    return rows.items;
}
fn decimals(fields: []const []const u8) []const f64 {
    const out = alloc(f64, fields.len);
    for (fields, out) |field, *value| value.* = decimal(field);
    return out;
}
pub fn readDataset(io: std.Io) !Dataset {
    const training = try readLines(io, "input/train.csv");
    const header = split(training[0], ',');
    const features = header[1 .. header.len - 1];
    var classes: std.ArrayList([]const u8) = .empty;
    for (training[1..]) |line| {
        const fields = split(line, ',');
        const label = fields[fields.len - 1];
        var found = false;
        for (classes.items) |earlier| if (eq(earlier, label)) {
            found = true;
        };
        if (!found) append([]const u8, &classes, label);
    }
    std.mem.sort([]const u8, classes.items, {}, textLess);
    var out: Dataset = .{ .features = features, .classes = classes.items, .train = parseRows(training,
         features.len, classes.items), .test_rows = parseRows(try readLines(io, "input/test.csv"),
         features.len, classes.items) };
    const costs = try readLines(io, "input/costs.csv");
    const cost_header = split(costs[0], ',');
    for (costs[1..]) |line| {
        const fields = split(line, ',');
        const actual = nameIndex(classes.items, fields[0]);
        for (fields[1..], 1..) |value, j| out.costs[actual][nameIndex(classes.items, cost_header[j])] = decimal(value);
    }
    for (try readLines(io, "input/params.txt")) |line| {
        const fields = split(line, ' ');
        const name = fields[0];
        if (eq(name, "PRIOR")) out.params.empirical = eq(fields[1], "empirical") else if (eq(name,
             "VAR_SMOOTHING")) out.params.smoothing = decimal(fields[1]) else if (eq(name, "SMOOTHING_GRID")) out.params.smoothing_grid = decimals(fields[1..]) else if (eq(name,
             "QDA_GAMMA")) out.params.gamma = decimal(fields[1]) else if (eq(name, "GAMMA_GRID")) out.params.gamma_grid = decimals(fields[1..]) else if (eq(name,
             "CV_FOLDS")) out.params.folds = u(number(fields[1])) else if (eq(name, "CALIBRATION_EDGES")) out.params.calibration = decimals(fields[1..]) else if (eq(name,
             "REJECT_THRESHOLDS")) out.params.reject = decimals(fields[1..]) else if (eq(name, "CURVE")) {
            const values = alloc(usize, fields.len - 1);
            for (fields[1..], values) |field, *value| value.* = u(number(field));
            out.params.curve = values;
        } else if (eq(name, "OUTLIER_THRESHOLD")) out.params.outlier = decimal(fields[1]) else if (eq(name, "BOOTSTRAP")) {
            out.params.bootstrap = u(number(fields[1]));
            out.params.seed = number(fields[2]);
        } else if (eq(name, "MAP_SIZE")) {
            out.params.map_width = u(number(fields[1]));
            out.params.map_height = u(number(fields[2]));
        } else if (eq(name, "PLOT_SIZE")) {
            out.params.plot_width = u(number(fields[1]));
            out.params.plot_height = u(number(fields[2]));
        } else if (eq(name, "SUBSET")) {
            const selected = alloc(usize, fields.len - 2);
            for (fields[2..], selected) |field, *value| value.* = nameIndex(features, field);
            append(Subset, &out.params.subsets, .{ .name = fields[1], .features = selected });
        } else if (eq(name, "PAIR")) append(Pair, &out.params.pairs, .{ .x = nameIndex(features, fields[1]),
             .y = nameIndex(features, fields[2]) });
    }
    return out;
}
