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
pub var backing_allocator: std.mem.Allocator = undefined;
pub const Point = [2]f64;
pub const Matrix = [][]f64;
pub const Example = struct { id: []const u8, point: Point, label: i64 };
pub const KernelKind = enum { linear, poly, rbf };
pub const Kernel = struct { name: []const u8, kind: KernelKind, degree: usize = 1, gamma: f64 = 0, coef0: f64 = 0 };
pub const Params = struct {
    c_grid: []const f64 = &.{},
    kernels: std.ArrayList(Kernel) = .empty,
    tolerance: f64 = 0,
    epsilon: f64 = 0,
    max_passes: usize = 0,
    folds: usize = 0,
    learning: []const usize = &.{},
    newton_iterations: usize = 0,
    multi_name: []const u8 = "",
    multi_c: f64 = 0,
    lambda: f64 = 0,
    pegasos_iterations: usize = 0,
    seed: i64 = 0,
    x_min: f64 = 0,
    x_max: f64 = 0,
    y_min: f64 = 0,
    y_max: f64 = 0,
    width: usize = 0,
    height: usize = 0,
};
pub const Input = struct { train: []const Example, test_data: []const Example, multi_train: []const Example,
     multi_test: []const Example, params: Params };
fn readData(io: std.Io, path: []const u8) ![]const Example {
    const lines = try readLines(io, path);
    var out: std.ArrayList(Example) = .empty;
    for (lines[1..]) |line| {
        const row = split(line, ',');
        append(Example, &out, .{ .id = row[0], .point = .{ real(row[1]), real(row[2]) }, .label = number(row[3]) });
    }
    return out.items;
}
pub fn load(io: std.Io) !Input {
    var multi_train: std.ArrayList(Example) = .empty;
    var multi_test: std.ArrayList(Example) = .empty;
    const multi = try readLines(io, "input/multiclass.csv");
    for (multi[1..]) |line| {
        const row = split(line, ',');
        const value: Example = .{ .id = row[0], .point = .{ real(row[1]), real(row[2]) }, .label = number(row[3]) };
        if (eq(row[4], "train")) append(Example, &multi_train, value) else append(Example, &multi_test, value);
    }
    var params: Params = .{};
    for (try readLines(io, "input/params.txt")) |line| {
        const row = words(line);
        const key = row[0];
        if (eq(key, "C_GRID")) {
            const values = alloc(f64, row.len - 1);
            for (row[1..], values) |field, *value| value.* = real(field);
            params.c_grid = values;
        } else if (eq(key, "KERNEL")) {
            var kernel: Kernel = .{ .name = row[1], .kind = std.meta.stringToEnum(KernelKind, row[2]).? };
            if (kernel.kind == .poly) {
                kernel.degree = u(number(row[3]));
                kernel.gamma = real(row[4]);
                kernel.coef0 = real(row[5]);
            } else if (kernel.kind == .rbf) kernel.gamma = real(row[3]);
            append(Kernel, &params.kernels, kernel);
        } else if (eq(key, "TOLERANCE")) params.tolerance = real(row[1]) else if (eq(key, "EPS")) params.epsilon = real(row[1]) else if (eq(key,
             "MAX_PASSES")) params.max_passes = u(number(row[1])) else if (eq(key, "FOLDS")) params.folds = u(number(row[1])) else if (eq(key,
             "LEARNING_CURVE")) {
            const values = alloc(usize, row.len - 1);
            for (row[1..], values) |field, *value| value.* = u(number(field));
            params.learning = values;
        } else if (eq(key, "NEWTON_ITERATIONS")) params.newton_iterations = u(number(row[1])) else if (eq(key,
             "MULTICLASS")) {
            params.multi_name = row[1];
            params.multi_c = real(row[2]);
        } else if (eq(key, "PEGASOS")) {
            params.lambda = real(row[1]);
            params.pegasos_iterations = u(number(row[2]));
            params.seed = number(row[3]);
        } else if (eq(key, "PLOT_X")) {
            params.x_min = real(row[1]);
            params.x_max = real(row[2]);
        } else if (eq(key, "PLOT_Y")) {
            params.y_min = real(row[1]);
            params.y_max = real(row[2]);
        } else if (eq(key, "PLOT_SIZE")) {
            params.width = u(number(row[1]));
            params.height = u(number(row[2]));
        }
    }
    return .{ .train = try readData(io, "input/train.csv"), .test_data = try readData(io, "input/test.csv"),
         .multi_train = multi_train.items, .multi_test = multi_test.items, .params = params };
}
