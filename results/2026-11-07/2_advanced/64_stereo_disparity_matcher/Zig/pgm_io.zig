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
pub const Point = struct { x: i64, y: i64 };
pub const PGM = struct { width: usize, height: usize, pixels: []const i64 };
pub const Volume = struct { values: []i64, pixels: usize, disparities: usize };
pub const Params = struct { minimum: usize = 0, maximum: usize = 0, texture_window: usize = 0,
     sgm_window: usize = 0, paths: usize = 0, speckle_size: usize = 0, speckle_range: i64 = 0,
     fusion_votes: usize = 0, object_range: i64 = 0, object_size: usize = 0, texture_threshold: i64 = 0,
     uniqueness: i64 = 0, lr: i64 = 0, p1: i64 = 0, p2: i64 = 0, gamma: i64 = 0, focal: i64 = 0,
     baseline: i64 = 0, wta_kind: usize = 0, sgm_kind: usize = 0, windows: [3][]const usize = .{ &.{},
     &.{}, &.{} }, samples: std.ArrayList(Point) = .empty };
pub fn readPGM(io: std.Io, path: []const u8) !PGM {
    const lines = try readLines(io, path);
    const dimensions = words(lines[1]);
    const width = u(number(dimensions[0]));
    const height = u(number(dimensions[1]));
    const pixels = alloc(i64, width * height);
    var index: usize = 0;
    for (lines[3..]) |line| for (words(line)) |value| {
        pixels[index] = number(value);
        index += 1;
    };
    return .{ .width = width, .height = height, .pixels = pixels };
}
pub fn readParameters(io: std.Io) !Params {
    var p: Params = .{};
    for (try readLines(io, "input/params.txt")) |line| {
        const row = words(line);
        const key = row[0];
        if (eq(key, "disparity_min")) p.minimum = u(number(row[1])) else if (eq(key, "disparity_max")) p.maximum = u(number(row[1])) else if (eq(key,
             "sad_windows") or eq(key, "ssd_windows") or eq(key, "census_windows")) {
            const kind: usize = if (eq(key, "sad_windows")) 0 else if (eq(key, "ssd_windows")) 1 else 2;
            const values = alloc(usize, row.len - 1);
            for (row[1..], values) |value, *destination| destination.* = u(number(value));
            p.windows[kind] = values;
        } else if (eq(key, "texture_window")) p.texture_window = u(number(row[1])) else if (eq(key,
             "texture_threshold")) p.texture_threshold = number(row[1]) else if (eq(key, "uniqueness")) p.uniqueness = number(row[1]) else if (eq(key,
             "lr_max_diff")) p.lr = number(row[1]) else if (eq(key, "wta_cost") or eq(key,
             "sgm_cost")) {
            const kind: usize = if (eq(row[1], "sad")) 0 else if (eq(row[1], "ssd")) 1 else 2;
            if (eq(key, "wta_cost")) p.wta_kind = kind else p.sgm_kind = kind;
        } else if (eq(key, "sgm_window")) p.sgm_window = u(number(row[1])) else if (eq(key,
             "sgm_paths")) p.paths = u(number(row[1])) else if (eq(key, "p1")) p.p1 = number(row[1]) else if (eq(key,
             "p2")) p.p2 = number(row[1]) else if (eq(key, "p2_gamma")) p.gamma = number(row[1]) else if (eq(key,
             "speckle_size")) p.speckle_size = u(number(row[1])) else if (eq(key, "speckle_range")) p.speckle_range = number(row[1]) else if (eq(key,
             "fusion_min_votes")) p.fusion_votes = u(number(row[1])) else if (eq(key, "object_range")) p.object_range = number(row[1]) else if (eq(key,
             "object_min_size")) p.object_size = u(number(row[1])) else if (eq(key, "focal_length")) p.focal = number(row[1]) else if (eq(key,
             "baseline")) p.baseline = number(row[1]) else if (eq(key, "sample")) append(Point,
             &p.samples, .{ .x = number(row[1]), .y = number(row[2]) });
    }
    return p;
}
pub fn save(io: std.Io, name: []const u8, lines: Lines) !void {
    var text: Text = .{};
    for (lines.data.items) |line| text.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = fmt("output/{s}", .{name}), .data = text.value() });
}
pub fn writePGM(io: std.Io, name: []const u8, image: PGM) !void {
    var out: Lines = .{};
    out.add("P2", .{});
    out.add("{d} {d}", .{ image.width, image.height });
    out.add("255", .{});
    for (0..image.height) |y| {
        var row: Text = .{};
        for (0..image.width) |x| row.add("{s}{d}", .{ if (x > 0) " " else "", image.pixels[y * image.width + x] });
        out.add("{s}", .{row.value()});
    }
    try save(io, name, out);
}
