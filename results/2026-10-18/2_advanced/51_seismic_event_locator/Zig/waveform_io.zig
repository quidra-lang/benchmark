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
pub const Params = struct { sw: i64, lw: i64, on_p: i64, on_q: i64, off_p: i64, off_q: i64, min_duration: i64,
     noise: i64, aw: i64, clip: i64, window: i64, minimum: i64, velocity: f64, gx: [3]i64, gy: [3]i64,
     gz: [3]i64, limit: f64, qa: [3]f64, qb: [3]f64, cluster: [2]f64, local: [3]f64, duration: [3]f64,
     area: [4]i64, map_size: [2]i64, section: [2]i64, timeline: [5]i64 };
pub const Station = struct { code: []const u8, x: i64, y: i64, elevation: i64, start: i64 = 0, samples: []i64 = &.{},
     mean: i64 = 0, peak: i64 = 0, clipped: i64 = 0, noise: f64 = 0, triggers: usize = 0, short_triggers: usize = 0,
     correction: f64 = 0, mag_correction: f64 = 0, used: usize = 0, mag_count: usize = 0, first_square: f64 = 0,
     final_square: f64 = 0 };
pub const State = enum { used, dropped, added, rejected, unassociated };
pub const Pick = struct {
    station: usize,
    sample: i64,
    duration: i64,
    amplitude: i64,
    ratio: f64,
    clipped: bool,
    assigned: bool = false,
    state: State = .unassociated,
    event: usize = 0,
    first_residual: f64 = 0,
    residual: f64 = 0,
    pub fn time(self: Pick) f64 {
        return f(self.sample) / 100;
    }
};
pub const Input = struct { stations: []Station, params: Params };
fn integers(comptime count: usize, line: []const u8) [count]i64 {
    const fields = words(line);
    var out: [count]i64 = undefined;
    for (&out, fields[1..]) |*value, field| value.* = number(field);
    return out;
}
fn reals(comptime count: usize, line: []const u8) [count]f64 {
    const fields = words(line);
    var out: [count]f64 = undefined;
    for (&out, fields[1..]) |*value, field| value.* = real(field);
    return out;
}
pub fn load(io: std.Io) !Input {
    const geometry = try readLines(io, "input/stations.csv");
    var stations: std.ArrayList(Station) = .empty;
    for (geometry[1..]) |line| {
        const fields = split(line, ',');
        append(Station, &stations, .{ .code = fields[0], .x = number(fields[1]), .y = number(fields[2]),
             .elevation = number(fields[3]) });
    }
    const waveforms = try readLines(io, "input/waveforms.txt");
    var cursor: usize = 0;
    for (stations.items) |*station| {
        const fields = words(waveforms[cursor]);
        cursor += 1;
        station.start = number(fields[2]);
        const count = u(number(fields[3]));
        station.samples = alloc(i64, count);
        var index: usize = 0;
        while (index < count) {
            for (words(waveforms[cursor])) |field| {
                station.samples[index] = number(field);
                index += 1;
            }
            cursor += 1;
        }
    }
    const lines = try readLines(io, "input/params.txt");
    const on = integers(2, lines[2]);
    const off = integers(2, lines[3]);
    return .{ .stations = stations.items, .params = .{ .sw = integers(1, lines[0])[0], .lw = integers(1,
         lines[1])[0], .on_p = on[0], .on_q = on[1], .off_p = off[0], .off_q = off[1], .min_duration = integers(1,
         lines[4])[0], .noise = integers(1, lines[5])[0], .aw = integers(1, lines[6])[0], .clip = integers(1,
         lines[7])[0], .window = integers(1, lines[8])[0], .minimum = integers(1, lines[9])[0], .velocity = reals(1,
         lines[10])[0], .gx = integers(3, lines[11]), .gy = integers(3, lines[12]), .gz = integers(3,
         lines[13]), .limit = reals(1, lines[14])[0], .qa = reals(3, lines[15]), .qb = reals(3, lines[16]),
         .cluster = reals(2, lines[17]), .local = reals(3, lines[18]), .duration = reals(3, lines[19]),
         .area = integers(4, lines[20]), .map_size = integers(2, lines[21]), .section = integers(2,
         lines[22]), .timeline = integers(5, lines[23]) } };
}
