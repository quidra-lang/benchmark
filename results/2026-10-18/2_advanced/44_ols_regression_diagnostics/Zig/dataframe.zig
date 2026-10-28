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
pub const Value = union(enum) { number: f64, label: []const u8 };
pub const Cell = ?Value;
pub const Record = []const Cell;
pub const Dataframe = struct { names: []const []const u8, categorical: []const bool, rows: []const Record };
pub const Params = struct { rank_tol: f64 = 0, alpha: f64 = 0, confidence: f64 = 0, leverage: f64 = 0,
     studentized: f64 = 0, cook: f64 = 0, dffits: f64 = 0, vif: f64 = 0, durbin: f64 = 0, breusch: f64 = 0,
     normality: f64 = 0, plot_limit: f64 = 0, best_subsets: usize = 0, plot_width: usize = 0, plot_height: usize = 0 };
pub const Input = struct { data: Dataframe, prediction: Dataframe, formulas: []const []const u8, params: Params };
pub fn nameIndex(names: []const []const u8, name: []const u8) usize {
    for (names, 0..) |value, i| if (eq(value, name)) return i;
    unreachable;
}
pub fn readInput(io: std.Io) !Input {
    const lines = try readLines(io, "input/data.csv");
    const names = split(lines[0], ',');
    const categorical = alloc(bool, names.len);
    @memset(categorical, false);
    const rows = alloc(Record, lines.len - 1);
    for (lines[1..], rows) |line, *record| {
        const fields = split(line, ',');
        const values = alloc(Cell, names.len);
        @memset(values, null);
        for (fields, 0..) |field, j| {
            if (eq(field, "NA")) continue;
            if (field[0] >= 'A' and field[0] <= 'Z') {
                values[j] = .{ .label = field };
                categorical[j] = true;
            } else values[j] = .{ .number = decimal(field) };
        }
        record.* = values;
    }
    const prediction_lines = try readLines(io, "input/predict.csv");
    const header = split(prediction_lines[0], ',');
    const mapping = alloc(usize, header.len);
    for (header, mapping) |name, *column| column.* = nameIndex(names, name);
    const prediction_rows = alloc(Record, prediction_lines.len - 1);
    for (prediction_lines[1..], prediction_rows) |line, *record| {
        const fields = split(line, ',');
        const values = alloc(Cell, names.len);
        @memset(values, null);
        for (fields, mapping) |field, j| {
            if (eq(field, "NA")) continue;
            values[j] = if (categorical[j]) Value{ .label = field } else Value{ .number = decimal(field) };
        }
        record.* = values;
    }
    var params: Params = .{};
    for (try readLines(io, "input/params.txt")) |line| {
        const fields = split(line, ' ');
        const key = fields[0];
        const value = decimal(fields[1]);
        if (eq(key, "RANK_TOL")) params.rank_tol = value else if (eq(key, "ALPHA_REMOVE")) params.alpha = value else if (eq(key,
             "CONFIDENCE")) params.confidence = value else if (eq(key, "LEVERAGE")) params.leverage = value else if (eq(key,
             "STUDENTIZED")) params.studentized = value else if (eq(key, "COOK")) params.cook = value else if (eq(key,
             "DFFITS")) params.dffits = value else if (eq(key, "VIF")) params.vif = value else if (eq(key,
             "DURBIN_WATSON")) params.durbin = value else if (eq(key, "BREUSCH_PAGAN")) params.breusch = value else if (eq(key,
             "NORMALITY")) params.normality = value else if (eq(key, "BEST_SUBSETS")) params.best_subsets = @intFromFloat(value) else if (eq(key,
             "PLOT")) {
            params.plot_width = @intFromFloat(value);
            params.plot_height = u(number(fields[2]));
            params.plot_limit = decimal(fields[3]);
        }
    }
    return .{ .data = .{ .names = names, .categorical = categorical, .rows = rows }, .prediction = .{ .names = names,
         .categorical = categorical, .rows = prediction_rows }, .formulas = try readLines(io, "input/model.txt"),
         .params = params };
}
