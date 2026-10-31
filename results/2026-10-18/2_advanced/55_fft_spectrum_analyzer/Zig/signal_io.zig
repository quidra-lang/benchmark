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
pub const Params = struct { main_length: usize, peak_count: usize, search: usize, welch_length: usize,
     frame_length: usize, hop: usize, shade: usize, pitch_low: i64, pitch_high: i64, band_low: i64,
     band_high: i64, notch_frequency: i64, notch_width: i64, envelope_low: i64, envelope_high: i64,
     zoom_low: i64, zoom_high: i64, zoom_points: usize, max_lag: usize, third_low: i64, third_high: i64,
     block_length: usize, main_window: []const u8, welch_window: []const u8, frame_window: []const u8,
     peak_threshold: f64, fundamental: f64, onset_factor: f64, fir: []const f64, bands: []const i64 };
pub const Input = struct { fs: i64, signal: [2][]const f64, params: Params };
fn integer(rows: []const []const []const u8, index: usize, field: usize) i64 {
    return number(rows[index][field]);
}
pub fn load(io: std.Io) !Input {
    const lines = try readLines(io, "input/signal.csv");
    const header = split(lines[0], ',');
    const count = u(number(header[1]));
    const first = alloc(f64, count);
    const second = alloc(f64, count);
    for (lines[1..], first, second) |line, *x, *y| {
        const fields = split(line, ',');
        x.* = real(fields[0]);
        y.* = real(fields[1]);
    }
    const settings = try readLines(io, "input/params.txt");
    const rows = alloc([]const []const u8, settings.len);
    for (settings, rows) |line, *row| row.* = words(line);
    const fir = alloc(f64, rows[13].len - 1);
    for (rows[13][1..], fir) |field, *value| value.* = real(field);
    const bands = alloc(i64, rows[15].len - 1);
    for (rows[15][1..], bands) |field, *value| value.* = number(field);
    return .{ .fs = number(header[0]), .signal = .{ first, second }, .params = .{ .main_length = u(integer(rows,
         0, 1)), .main_window = rows[1][1], .peak_threshold = real(rows[2][1]), .peak_count = u(integer(rows,
         3, 1)), .fundamental = real(rows[4][1]), .search = u(integer(rows, 4, 2)), .welch_length = u(integer(rows,
         5, 1)), .welch_window = rows[5][2], .frame_length = u(integer(rows, 6, 1)), .hop = u(integer(rows,
         6, 2)), .shade = u(integer(rows, 6, 3)), .frame_window = rows[6][4], .onset_factor = real(rows[7][1]),
         .pitch_low = integer(rows, 8, 1), .pitch_high = integer(rows, 8, 2), .band_low = integer(rows,
         9, 1), .band_high = integer(rows, 9, 2), .notch_frequency = integer(rows, 10, 1), .notch_width = integer(rows,
         10, 2), .envelope_low = integer(rows, 11, 1), .envelope_high = integer(rows, 11, 2), .zoom_low = integer(rows,
         12, 1), .zoom_high = integer(rows, 12, 2), .zoom_points = u(integer(rows, 12, 3)), .fir = fir,
         .max_lag = u(integer(rows, 14, 1)), .bands = bands, .third_low = integer(rows, 16, 1), .third_high = integer(rows,
         16, 2), .block_length = u(integer(rows, 17, 1)) } };
}
