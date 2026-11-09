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

pub const Names = []const []const u8;
pub fn join(values: Names, separator: []const u8) []const u8 {
    return std.mem.join(allocator, separator, values) catch @panic("allocation failed");
}
pub fn zero(comptime T: type, count: usize, value: T) []T {
    const out = alloc(T, count);
    @memset(out, value);
    return out;
}
pub const Type = enum(u8) { integer, string, boolean, date };
pub const type_names = [_][]const u8{ "INT", "STRING", "BOOL", "DATE" };
pub const Value = union(enum) { null_value, unknown, integer: i64, string: []const u8 };
pub const Values = []const Value;
pub const Row = Values;
pub const Table = []const Row;
pub const Numbers = []const i64;
pub fn valueEqual(left: Value, right: Value) bool {
    if (std.meta.activeTag(left) != std.meta.activeTag(right)) return false;
    return switch (left) {
        .null_value, .unknown => true,
        .integer => |n_value| n_value == right.integer,
        .string => |s| eq(s, right.string),
    };
}
pub fn valueCompare(left: Value, right: Value) i64 {
    if (left == .null_value and right == .null_value) return 0;
    if (left == .null_value) return -1;
    if (right == .null_value) return 1;
    return switch (left) {
        .integer => |n_value| if (n_value < right.integer) -1 else if (n_value > right.integer) 1 else 0,
        .string => |s| switch (std.mem.order(u8, s, right.string)) {
            .lt => -1,
            .eq => 0,
            .gt => 1,
        },
        else => unreachable,
    };
}
pub const Bounds = struct { low: Value, high: Value };
pub const Column = struct { name: []const u8, kind: Type, nullable: bool };
pub const Options = struct { row_group_size: usize, page_size: usize, dictionary_limit: usize, encoding: Names };
pub const Inputs = struct { columns: []const Column, rows: Table, options: Options, queries: Names,
     damaged: []const u8 };
fn leap(year: i64) bool {
    return @mod(year, 4) == 0 and (@mod(year, 100) != 0 or @mod(year, 400) == 0);
}
fn monthDays(year: i64, month: usize) i64 {
    const days = [_]i64{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    return days[month - 1] + @as(i64, @intFromBool(month == 2 and leap(year)));
}
fn beforeYear(year: i64) i64 {
    const y = year - 1;
    return 365 * y + @divTrunc(y, 4) - @divTrunc(y, 100) + @divTrunc(y, 400);
}
pub fn dayNumber(source: []const u8) i64 {
    const year = number(source[0..4]);
    const month = u(number(source[5..7]));
    const day = number(source[8..10]);
    var result = beforeYear(year) - beforeYear(1970) + day - 1;
    for (1..month) |m| result += monthDays(year, m);
    return result;
}
pub fn parseValue(kind: Type, source: []const u8) Value {
    if (source.len == 0) return .null_value;
    if (kind == .string) return .{ .string = source };
    if (kind == .boolean) return .{ .integer = @intFromBool(eq(source, "true")) };
    return .{ .integer = if (kind == .date) dayNumber(source) else number(source) };
}
pub fn valueText(kind: Type, value: Value, null_text: []const u8) []const u8 {
    if (value == .unknown) return "?";
    if (value == .null_value) return null_text;
    if (kind == .string) return value.string;
    if (kind == .boolean) return if (value.integer != 0) "true" else "false";
    if (kind == .integer) return fmt("{d}", .{value.integer});
    var year: i64 = 1970;
    var month: usize = 1;
    var day = value.integer;
    while (day < 0) {
        year -= 1;
        day += if (leap(year)) @as(i64, 366) else 365;
    }
    while (day >= (if (leap(year)) @as(i64, 366) else 365)) {
        day -= if (leap(year)) @as(i64, 366) else 365;
        year += 1;
    }
    while (day >= monthDays(year, month)) {
        day -= monthDays(year, month);
        month += 1;
    }
    return fmt("{d:0>4}-{d:0>2}-{d:0>2}", .{ year, month, day + 1 });
}
pub fn readInputs(io: std.Io) !Inputs {
    var columns: std.ArrayList(Column) = .empty;
    for (try readLines(io, "input/schema.txt")) |line| {
        const f = words(line);
        var kind: usize = 0;
        while (!eq(type_names[kind], f[1])) kind += 1;
        append(Column, &columns, .{ .name = f[0], .kind = @enumFromInt(kind), .nullable = eq(f[2], "NULLABLE") });
    }
    const lines = try readLines(io, "input/table.csv");
    var rows: std.ArrayList(Row) = .empty;
    for (lines[1..]) |line| {
        const fields = split(line, ',');
        const row = alloc(Value, columns.items.len);
        for (columns.items, fields, row) |column, field, *value| value.* = parseValue(column.kind, field);
        append(Row, &rows, row);
    }
    const options = try readLines(io, "input/options.txt");
    var encoding: std.ArrayList([]const u8) = .empty;
    for (options[3..]) |line| append([]const u8, &encoding, words(line)[2]);
    var damaged: std.ArrayList(u8) = .empty;
    for (try readLines(io, "input/damaged.hex")) |line| {
        var i: usize = 0;
        while (i < line.len) : (i += 2) append(u8, &damaged, std.fmt.parseInt(u8, line[i .. i + 2],
             16) catch unreachable);
    }
    return .{ .columns = columns.items, .rows = rows.items, .options = .{ .row_group_size = u(number(words(options[0])[1])),
         .page_size = u(number(words(options[1])[1])), .dictionary_limit = u(number(words(options[2])[1])),
         .encoding = encoding.items }, .queries = try readLines(io, "input/queries.txt"), .damaged = damaged.items };
}
pub fn writeLines(io: std.Io, filename: []const u8, lines: Lines) !void {
    try std.Io.Dir.cwd().createDirPath(io, "output");
    var out: Text = .{};
    for (lines.data.items) |line| out.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = fmt("output/{s}", .{filename}), .data = out.value() });
}
