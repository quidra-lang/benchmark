const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub const Strings = []const []const u8;
pub fn alloc(comptime T: type, count: usize) []T { return allocator.alloc(T, count) catch @panic("allocation failed"); }
pub fn append(comptime T: type, list: *std.ArrayList(T), value: T) void { list.append(allocator, value) catch @panic("allocation failed"); }
pub fn fmt(comptime pattern: []const u8, args: anytype) []const u8 { return std.fmt.allocPrint(allocator, pattern, args) catch @panic("allocation failed"); }
pub fn eq(first: []const u8, second: []const u8) bool { return std.mem.eql(u8, first, second); }
pub fn number(word: []const u8) i64 { return std.fmt.parseInt(i64, word, 10) catch unreachable; }
pub fn integer(word: []const u8) usize { return @intCast(number(word)); }
pub fn n(value: anytype) i64 { return @intCast(value); }
pub fn real(value: anytype) f64 { return @floatFromInt(value); }
pub fn abs(value: i64) i64 { return if (value < 0) -value else value; }
pub fn copy(comptime T: type, values: []const T) []T { const result = alloc(T, values.len); @memcpy(result, values); return result; }
pub fn split(source: []const u8, separator: u8) Strings {
    var result: std.ArrayList([]const u8) = .empty;
    var parts = std.mem.splitScalar(u8, source, separator);
    while (parts.next()) |part| append([]const u8, &result, part);
    return result.items;
}
pub fn lines(source: []const u8) Strings { const result = split(source, '\n'); return result[0 .. result.len - 1]; }
pub const Text = struct {
    data: std.ArrayList(u8) = .empty,
    pub fn write(self: *Text, source: []const u8) void { self.data.appendSlice(allocator, source) catch @panic("allocation failed"); }
    pub fn add(self: *Text, comptime pattern: []const u8, args: anytype) void { self.write(fmt(pattern, args)); }
    pub fn value(self: Text) []const u8 { return self.data.items; }
};
pub const Lines = struct {
    data: std.ArrayList([]const u8) = .empty,
    pub fn write(self: *Lines, source: []const u8) void { append([]const u8, &self.data, source); }
    pub fn add(self: *Lines, comptime pattern: []const u8, args: anytype) void { self.write(fmt(pattern, args)); }
    pub fn extend(self: *Lines, other: Lines) void { self.data.appendSlice(allocator, other.data.items) catch @panic("allocation failed"); }
};
pub const Group = struct { name: []const u8, values: []i64 };
pub const Pair = struct { first: usize, second: usize };
pub const Settings = struct { seed: i64, bootstrap: usize, permutations: usize, confidence: i64, pilot: usize, simulations: usize, inner_permutations: usize, bins: usize };
pub const Dataset = struct { groups: []Group, before: []i64, after: []i64, differences: []i64, pairs: []Pair, settings: Settings };
fn hundredths(word: []const u8) i64 {
    if (std.mem.indexOfScalar(u8, word, '.')) |point| {
        return 100 * number(word[0..point]) + 10 * @as(i64, word[point + 1] - '0') + (if (word.len == point + 3) @as(i64, word[point + 2] - '0') else 0);
    }
    return 100 * number(word);
}
fn groupIndex(groups: []const Group, name: []const u8) usize {
    for (groups, 0..) |group, i| { if (eq(group.name, name)) return i; }
    unreachable;
}
pub fn load(io: std.Io) !Dataset {
    const directory = std.Io.Dir.cwd();
    const samples = lines(try directory.readFileAlloc(io, "input/samples.csv", allocator, .unlimited));
    var groups: std.ArrayList(Group) = .empty;
    var values = [_]std.ArrayList(i64){.empty} ** 4;
    for (samples[1..]) |line| {
        const fields = split(line, ',');
        var index: ?usize = null;
        for (groups.items, 0..) |group, i| { if (eq(group.name, fields[0])) { index = i; break; } }
        if (index == null) {
            index = groups.items.len;
            append(Group, &groups, .{ .name = fields[0], .values = undefined });
        }
        append(i64, &values[index.?], hundredths(fields[1]));
    }
    for (groups.items, 0..) |*group, i| group.values = values[i].items;
    const paired = lines(try directory.readFileAlloc(io, "input/paired.csv", allocator, .unlimited));
    const before = alloc(i64, paired.len - 1);
    const after = alloc(i64, before.len);
    const differences = alloc(i64, before.len);
    for (paired[1..], 0..) |line, i| {
        const fields = split(line, ',');
        before[i] = hundredths(fields[1]);
        after[i] = hundredths(fields[2]);
        differences[i] = after[i] - before[i];
    }
    const parameters = lines(try directory.readFileAlloc(io, "input/params.txt", allocator, .unlimited));
    var settings: [7]Strings = undefined;
    for (parameters[0..7], &settings) |line, *fields| fields.* = split(line, ' ')[1..];
    const pairs = alloc(Pair, parameters.len - 7);
    for (parameters[7..], pairs) |line, *pair| {
        const fields = split(line, ' ');
        pair.* = .{ .first = groupIndex(groups.items, fields[1]), .second = groupIndex(groups.items, fields[2]) };
    }
    return .{
        .groups = groups.items, .before = before, .after = after, .differences = differences, .pairs = pairs,
        .settings = .{ .seed = number(settings[0][0]), .bootstrap = integer(settings[1][0]), .permutations = integer(settings[2][0]), .confidence = number(settings[3][0]), .pilot = integer(settings[4][0]), .simulations = integer(settings[5][0]), .inner_permutations = integer(settings[5][1]), .bins = integer(settings[6][0]) },
    };
}
