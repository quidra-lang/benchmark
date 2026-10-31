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
const entropy = @import("entropy.zig");
pub const Pixel = [3]i64;
pub const Sequence = [64]i64;
pub const Matrix = [8][8]i64;
pub const Factor = struct { h: usize, v: usize };
pub const Image = struct { width: usize, height: usize, pixels: []const Pixel };
pub const Plane = struct { width: usize, height: usize, pixels: []i64 };
pub const Params = struct { qualities: []const usize = &.{}, truncate: []const usize = &.{},
     sampling: usize = 0, restart: usize = 0, target: usize = 0, generations: usize = 0, optimized: bool = false };
pub const Tables = [2][16]?entropy.Huffman;
pub const Quantization = [4]?Matrix;
pub const SourceTables = struct { transform: Matrix = std.mem.zeroes(Matrix), basic: [2]Matrix = std.mem.zeroes([2]Matrix),
     huffman: Tables = [_][16]?entropy.Huffman{[_]?entropy.Huffman{null} ** 16} ** 2 };
pub fn readPPM(io: std.Io, path: []const u8) !Image {
    const lines = try readLines(io, path);
    const dimensions = words(lines[1]);
    const width = u(number(dimensions[0]));
    const height = u(number(dimensions[1]));
    const pixels = alloc(Pixel, width * height);
    var index: usize = 0;
    for (lines[3..]) |line| {
        const values = words(line);
        for (0..width) |x| {
            pixels[index] = .{ number(values[3 * x]), number(values[3 * x + 1]), number(values[3 * x + 2]) };
            index += 1;
        }
    }
    return .{ .width = width, .height = height, .pixels = pixels };
}
pub fn readParams(io: std.Io) !Params {
    var out: Params = .{};
    for (try readLines(io, "input/params.txt")) |line| {
        const row = words(line);
        const key = row[0];
        if (eq(key, "qualities") or eq(key, "truncate")) {
            const values = alloc(usize, row.len - 1);
            for (row[1..], values) |value, *destination| destination.* = u(number(value));
            if (eq(key, "qualities")) out.qualities = values else out.truncate = values;
        } else if (eq(key, "sampling")) out.sampling = u(number(row[1])) else if (eq(key, "restart_interval")) out.restart = u(number(row[1])) else if (eq(key,
             "huffman")) out.optimized = eq(row[1], "optimized") else if (eq(key, "target_bytes")) out.target = u(number(row[1])) else if (eq(key,
             "generations")) out.generations = u(number(row[1]));
    }
    return out;
}
pub fn readTables(io: std.Io) !*SourceTables {
    const lines = try readLines(io, "input/tables.txt");
    const out = create(SourceTables, .{});
    for (0..8) |r| {
        const row = words(lines[1 + r]);
        for (0..8) |c| out.transform[r][c] = number(row[c]);
    }
    for (0..2) |t| for (0..8) |r| {
        const row = words(lines[10 + 9 * t + r]);
        for (0..8) |c| out.basic[t][r][c] = number(row[c]);
    };
    for (0..4) |t| {
        const header = words(lines[27 + 3 * t]);
        const kind = u(number(header[1]));
        const id = u(number(header[2]));
        const count_values = words(lines[28 + 3 * t]);
        var counts: [16]usize = undefined;
        for (0..16) |i| counts[i] = u(number(count_values[i]));
        const values = words(lines[29 + 3 * t]);
        var symbols: [256]u8 = undefined;
        for (values, 0..) |value, i| symbols[i] = @intCast(number(value));
        out.huffman[kind][id] = entropy.Huffman.init(counts, symbols[0..values.len]);
    }
    return out;
}
pub fn readHex(io: std.Io, path: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (try readLines(io, path)) |line| {
        var i: usize = 0;
        while (i < line.len) : (i += 2) append(u8, &out, std.fmt.parseInt(u8, line[i .. i + 2], 16) catch unreachable);
    }
    return out.items;
}
pub fn save(io: std.Io, name: []const u8, lines: Lines) !void {
    var text: Text = .{};
    for (lines.data.items) |line| text.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = fmt("output/{s}", .{name}), .data = text.value() });
}
pub fn writePPM(io: std.Io, name: []const u8, image: Image) !void {
    var out: Lines = .{};
    out.add("P3", .{});
    out.add("{d} {d}", .{ image.width, image.height });
    out.add("255", .{});
    for (0..image.height) |y| {
        var row: Text = .{};
        for (0..image.width) |x| for (image.pixels[y * image.width + x], 0..) |value, c| {
            row.add("{s}{d}", .{ if (x > 0 or c > 0) " " else "", value });
        };
        out.add("{s}", .{row.value()});
    }
    try save(io, name, out);
}
pub fn writeHex(io: std.Io, name: []const u8, bytes: []const u8) !void {
    const digits = "0123456789abcdef";
    var out: Lines = .{};
    var offset: usize = 0;
    while (offset < bytes.len) : (offset += 32) {
        var row: Text = .{};
        for (bytes[offset..@min(offset + 32, bytes.len)]) |value| row.add("{c}{c}", .{ digits[value / 16],
             digits[value % 16] });
        out.add("{s}", .{row.value()});
    }
    try save(io, name, out);
}
