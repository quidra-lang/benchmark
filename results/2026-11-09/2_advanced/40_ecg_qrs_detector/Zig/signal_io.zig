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
pub const Params = struct { refractory_ms: i64 = 0, twave_ms: i64 = 0, searchback_percent: i64 = 0,
     premature_percent: i64 = 0, qrs_width_ms: i64 = 0, match_ms: i64 = 0, pause_ms: i64 = 0, brady_ms: i64 = 0,
     tachy_ms: i64 = 0, excerpt_ms: i64 = 0, segment_ms: i64 = 0, strip_start_ms: i64 = 0, strip_ms: i64 = 0,
     strip_rows: i64 = 0, chart_rows: i64 = 0, poincare_size: i64 = 0 };
pub const Annotation = struct { sample: usize, label: u8, beat: ?usize = null };
pub const Input = struct { ecg: []const i64, annotations: []Annotation, params: Params };
pub fn readInput(io: std.Io) !Input {
    var ecg: std.ArrayList(i64) = .empty;
    const ecg_lines = try readLines(io, "input/ecg.csv");
    for (ecg_lines[1..]) |line| append(i64, &ecg, number(split(line, ',')[1]));
    var annotations: std.ArrayList(Annotation) = .empty;
    const annotation_lines = try readLines(io, "input/annotations.csv");
    for (annotation_lines[1..]) |line| {
        const fields = split(line, ',');
        append(Annotation, &annotations, .{ .sample = u(number(fields[0])), .label = fields[1][0] });
    }
    var params: Params = .{};
    for (try readLines(io, "input/params.txt")) |line| {
        const fields = split(line, ' ');
        inline for (std.meta.fields(Params)) |field| if (eq(fields[0], field.name)) {
            @field(params, field.name) = number(fields[1]);
        };
    }
    return .{ .ecg = ecg.items, .annotations = annotations.items, .params = params };
}
pub fn write(io: std.Io, name: []const u8, lines: Lines) !void {
    var out: Text = .{};
    for (lines.data.items) |line| out.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = fmt("output/{s}", .{name}), .data = out.value() });
}
