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
pub const normal_z: f64 = 1.959963984540054;
pub const Subject = struct { id: i64, group: usize, time: i64, event: i64, age: i64, stage: i64, sex: u8 };
pub const Subjects = []const Subject;
pub const Params = struct { groups: []const []const u8 = &.{}, subgroups: []const []const u8 = &.{},
     covariates: []const []const u8 = &.{}, report_times: []const i64 = &.{}, tau: i64 = 0, life_width: i64 = 0,
     life_intervals: usize = 0, landmark: i64 = 0, residuals: usize = 0, plot_width: usize = 0, plot_height: usize = 0,
     plot_time: i64 = 0, plot_divisions: usize = 0, strata: []const u8 = "" };
pub const Dataset = struct { subjects: Subjects, params: Params };
fn subjectLess(_: void, a: Subject, b: Subject) bool {
    return a.id < b.id;
}
pub fn readDataset(io: std.Io) !Dataset {
    var params: Params = .{};
    for (try readLines(io, "input/params.txt")) |line| {
        const fields = split(line, ' ');
        const key = fields[0];
        if (eq(key, "GROUPS")) params.groups = fields[1..] else if (eq(key, "REPORT_TIMES")) {
            const times = alloc(i64, fields.len - 1);
            for (fields[1..], times) |field, *value| value.* = number(field);
            params.report_times = times;
        } else if (eq(key, "TAU")) params.tau = number(fields[1]) else if (eq(key, "LIFE_TABLE")) {
            params.life_width = number(fields[1]);
            params.life_intervals = u(number(fields[2]));
        } else if (eq(key, "STRATA")) params.strata = fields[1] else if (eq(key, "SUBGROUPS")) params.subgroups = fields[1..] else if (eq(key,
             "LANDMARK")) params.landmark = number(fields[1]) else if (eq(key, "COX")) params.covariates = fields[1..] else if (eq(key,
             "RESIDUALS")) params.residuals = u(number(fields[1])) else if (eq(key, "PLOT")) {
            params.plot_width = u(number(fields[1]));
            params.plot_height = u(number(fields[2]));
            params.plot_time = number(fields[3]);
            params.plot_divisions = u(number(fields[4]));
        }
    }
    var subjects: std.ArrayList(Subject) = .empty;
    const lines = try readLines(io, "input/subjects.csv");
    for (lines[1..]) |line| {
        const fields = split(line, ',');
        var group: usize = 0;
        while (!eq(params.groups[group], fields[1])) group += 1;
        append(Subject, &subjects, .{ .id = number(fields[0]), .group = group, .time = number(fields[2]),
             .event = number(fields[3]), .age = number(fields[4]), .stage = number(fields[6]), .sex = fields[5][0] });
    }
    std.mem.sort(Subject, subjects.items, {}, subjectLess);
    return .{ .subjects = subjects.items, .params = params };
}
