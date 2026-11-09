const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub const Strings = []const []const u8;
pub fn alloc(comptime T: type, count: usize) []T { return allocator.alloc(T, count) catch @panic("allocation failed"); }
pub fn create(comptime T: type, initial: T) *T { const result = allocator.create(T) catch @panic("allocation failed"); result.* = initial; return result; }
pub fn append(comptime T: type, list: *std.ArrayList(T), element: T) void { list.append(allocator, element) catch @panic("allocation failed"); }
pub fn fmt(comptime pattern: []const u8, args: anytype) []const u8 { return std.fmt.allocPrint(allocator, pattern, args) catch @panic("allocation failed"); }
pub fn eq(first: []const u8, second: []const u8) bool { return std.mem.eql(u8, first, second); }
pub fn number(word: []const u8) i64 { return std.fmt.parseInt(i64, word, 10) catch unreachable; }
pub fn integer(word: []const u8) usize { return @intCast(number(word)); }
pub fn n(value: anytype) i64 { return @intCast(value); }
pub fn real(value: anytype) f64 { return @floatFromInt(value); }
pub fn split(source: []const u8, separator: u8) Strings {
    var parts: std.ArrayList([]const u8) = .empty;
    var iterator = std.mem.splitScalar(u8, source, separator);
    while (iterator.next()) |part| append([]const u8, &parts, part);
    return parts.items;
}
pub fn lines(source: []const u8) Strings { const parts = split(source, '\n'); return parts[0 .. parts.len - 1]; }
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
pub const Attribute = struct { name: []const u8, integer: bool, values: Strings };
pub const Row = struct { id: []const u8, values: [12]i64 = [_]i64{-1} ** 12, label: usize };
pub const Rows = struct {
    values: [500]*const Row = undefined,
    len: usize = 0,
    pub fn add(self: *Rows, row: *const Row) void { self.values[self.len] = row; self.len += 1; }
    pub fn slice(self: *const Rows) []const *const Row { return self.values[0..self.len]; }
};
pub const Settings = struct {
    max_depth: usize, min_split: usize, min_leaf: usize, max_surrogates: usize, folds: usize, curve: []usize,
    bag_trees: usize, bag_seed: i64, repeats: usize, permutation_seed: i64,
};
pub const Dataset = struct { attributes: []Attribute, target: []const u8, classes: Strings, train: []Row, validation: []Row, test: []Row, settings: Settings };
fn position(names: Strings, name: []const u8) usize {
    for (names, 0..) |candidate, i| { if (eq(candidate, name)) return i; }
    unreachable;
}
fn readRows(source: []const u8, attributes: []const Attribute, classes: Strings) []Row {
    var rows: std.ArrayList(Row) = .empty;
    for (lines(source)[1..]) |line| {
        const fields = split(line, ',');
        var row: Row = .{ .id = fields[0], .label = position(classes, fields[fields.len - 1]) };
        for (attributes, 0..) |attribute, i| {
            const field = fields[i + 1];
            row.values[i] = if (eq(field, "?")) -1 else if (attribute.integer) number(field) else n(position(attribute.values, field));
        }
        append(Row, &rows, row);
    }
    return rows.items;
}
pub fn rowSequence(rows: []const Row) Rows {
    var result: Rows = .{};
    for (rows) |*row| result.add(row);
    return result;
}
pub fn load(io: std.Io) !Dataset {
    const directory = std.Io.Dir.cwd();
    const schema = lines(try directory.readFileAlloc(io, "input/schema.txt", allocator, .unlimited));
    var attributes: std.ArrayList(Attribute) = .empty;
    for (schema[0 .. schema.len - 1]) |line| {
        const fields = split(line, ' ');
        append(Attribute, &attributes, .{ .name = fields[1], .integer = eq(fields[2], "INT"), .values = fields[3..] });
    }
    const class_fields = split(schema[schema.len - 1], ' ');
    const parameters = lines(try directory.readFileAlloc(io, "input/params.txt", allocator, .unlimited));
    var settings: [10]Strings = undefined;
    for (parameters, &settings) |line, *fields| fields.* = split(line, ' ')[1..];
    const curve = alloc(usize, settings[5].len);
    for (settings[5], curve) |word, *value| value.* = integer(word);
    var data: Dataset = .{
        .attributes = attributes.items, .target = class_fields[1], .classes = class_fields[2..], .train = undefined, .validation = undefined, .test = undefined,
        .settings = .{ .max_depth = integer(settings[0][0]), .min_split = integer(settings[1][0]), .min_leaf = integer(settings[2][0]), .max_surrogates = integer(settings[3][0]), .folds = integer(settings[4][0]), .curve = curve, .bag_trees = integer(settings[6][0]), .bag_seed = number(settings[7][0]), .repeats = integer(settings[8][0]), .permutation_seed = number(settings[9][0]) },
    };
    data.train = readRows(try directory.readFileAlloc(io, "input/train.csv", allocator, .unlimited), data.attributes, data.classes);
    data.validation = readRows(try directory.readFileAlloc(io, "input/validation.csv", allocator, .unlimited), data.attributes, data.classes);
    data.test = readRows(try directory.readFileAlloc(io, "input/test.csv", allocator, .unlimited), data.attributes, data.classes);
    return data;
}
