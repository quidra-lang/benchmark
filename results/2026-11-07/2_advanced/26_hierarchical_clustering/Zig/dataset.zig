const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub var scratch: std.mem.Allocator = undefined;
pub const Matrix = [][]f64;
pub fn alloc(comptime T: type, count: usize) []T { return allocator.alloc(T, count) catch @panic("allocation failed"); }
pub fn append(comptime T: type, list: *std.ArrayList(T), value: T) void { list.append(allocator, value) catch @panic("allocation failed"); }
pub fn fmt(comptime pattern: []const u8, arguments: anytype) []const u8 { return std.fmt.allocPrint(allocator, pattern, arguments) catch @panic("allocation failed"); }
pub fn eq(first: []const u8, second: []const u8) bool { return std.mem.eql(u8, first, second); }
pub fn n(value: anytype) i64 { return @intCast(value); }
pub fn f(value: anytype) f64 { return @floatFromInt(value); }
pub fn number(text: []const u8) usize { return std.fmt.parseInt(usize, text, 10) catch unreachable; }
pub fn floating(text: []const u8) f64 { return std.fmt.parseFloat(f64, text) catch unreachable; }
pub fn split(text: []const u8, separator: u8) []const []const u8 {
    var result: std.ArrayList([]const u8) = .empty;
    var iterator = std.mem.splitScalar(u8, text, separator);
    while (iterator.next()) |word| append([]const u8, &result, word);
    return result.items;
}
pub fn matrix(rows: usize, columns: usize) Matrix {
    const result = alloc([]f64, rows);
    const values = alloc(f64, rows * columns);
    @memset(values, 0);
    for (result, 0..) |*row, index| row.* = values[index * columns .. (index + 1) * columns];
    return result;
}
pub fn sequence(count: usize) []usize {
    const result = alloc(usize, count);
    for (result, 0..) |*value, index| value.* = index;
    return result;
}
pub fn stringOrder(_: void, first: []const u8, second: []const u8) bool { return std.mem.order(u8, first, second) == .lt; }
pub const Text = struct {
    data: std.ArrayList(u8) = .empty,
    pub fn write(self: *Text, text: []const u8) void { self.data.appendSlice(allocator, text) catch @panic("allocation failed"); }
    pub fn add(self: *Text, comptime pattern: []const u8, arguments: anytype) void { self.write(fmt(pattern, arguments)); }
    pub fn value(self: Text) []const u8 { return self.data.items; }
};
pub const Lines = struct {
    data: std.ArrayList([]const u8) = .empty,
    pub fn write(self: *Lines, text: []const u8) void { append([]const u8, &self.data, text); }
    pub fn add(self: *Lines, comptime pattern: []const u8, arguments: anytype) void { self.write(fmt(pattern, arguments)); }
    pub fn extend(self: *Lines, other: Lines) void { self.data.appendSlice(allocator, other.data.items) catch @panic("allocation failed"); }
    pub fn paragraph(self: *Lines, other: Lines) void { if (self.data.items.len > 0) self.write(""); self.extend(other); }
};
pub fn join(source: []const []const u8, separator: []const u8) []const u8 {
    var text: Text = .{};
    for (source, 0..) |word, index| { if (index > 0) text.write(separator); text.write(word); }
    return text.value();
}
pub fn repeat(character: u8, count: usize) []const u8 {
    const result = alloc(u8, count);
    @memset(result, character);
    return result;
}
pub fn readLines(io: std.Io, name: []const u8) ![]const []const u8 {
    const text = try std.Io.Dir.cwd().readFileAlloc(io, fmt("input/{s}", .{name}), allocator, .unlimited);
    const result = split(text, '\n');
    return result[0 .. result.len - 1];
}
pub fn writeLines(io: std.Io, name: []const u8, source: Lines) !void {
    var text: Text = .{};
    for (source.data.items) |line| text.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = fmt("output/{s}", .{name}), .data = text.value() });
}
pub const Observations = struct {
    features: []const []const u8,
    idents: []const []const u8,
    labels: []const []const u8,
    raw: Matrix,
    pub fn read(io: std.Io) !Observations {
        const source = try readLines(io, "data.csv");
        const features = split(source[0], ',')[2..];
        const count = source.len - 1;
        const idents = alloc([]const u8, count);
        const labels = alloc([]const u8, count);
        const raw = matrix(count, features.len);
        for (source[1..], 0..) |line, index| {
            const fields = split(line, ',');
            idents[index] = fields[0];
            labels[index] = fields[1];
            for (fields[2..], raw[index]) |word, *value| value.* = floating(word);
        }
        return .{ .features = features, .idents = idents, .labels = labels, .raw = raw };
    }
};
fn bounded(text: []const u8, limit: usize) usize {
    var value: usize = 0;
    for (text) |character| {
        const digit: usize = character - '0';
        if (value > limit / 10 or value * 10 + digit >= limit) return limit;
        value = value * 10 + digit;
    }
    return value;
}
pub const Settings = struct {
    distance: []const u8,
    standardize: []const u8,
    linkages: []const []const u8,
    cut_heights: []f64,
    cut_counts: []usize,
    inconsistency_depth: usize,
    depth_text: []const u8,
    inconsistency_count: usize,
    gap_max_k: usize,
    list_size: usize,
    width: usize,
    compare_linkage: []const u8,
    replicates: usize,
    percent: usize,
    seed: i64,
    refine_iterations: usize,

    pub fn read(io: std.Io) !Settings {
        const source = try readLines(io, "params.txt");
        var fields: [12][]const []const u8 = undefined;
        for (source, &fields) |line, *row| row.* = split(line, ' ')[1..];
        const cut_heights = alloc(f64, fields[3].len);
        for (fields[3], cut_heights) |word, *value| value.* = floating(word);
        const cut_counts = alloc(usize, fields[4].len);
        for (fields[4], cut_counts) |word, *value| value.* = number(word);
        return .{
            .distance = fields[0][0], .standardize = fields[1][0], .linkages = fields[2],
            .cut_heights = cut_heights, .cut_counts = cut_counts,
            .inconsistency_depth = bounded(fields[5][0], 120), .depth_text = fields[5][0],
            .inconsistency_count = number(fields[5][1]), .gap_max_k = number(fields[6][0]),
            .list_size = number(fields[7][0]), .width = number(fields[8][0]),
            .compare_linkage = fields[9][0], .replicates = number(fields[10][0]),
            .percent = number(fields[10][1]), .seed = @intCast(number(fields[10][2])),
            .refine_iterations = number(fields[11][0]),
        };
    }
};
