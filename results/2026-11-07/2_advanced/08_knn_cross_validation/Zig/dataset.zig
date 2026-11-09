const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub var backing: std.mem.Allocator = undefined;
pub const Strings = []const []const u8;
pub const Scaling = enum { standard, minmax };
pub const Metric = enum { squared_euclidean, manhattan, chebyshev, cosine };
pub const Weighting = enum { uniform, distance };
pub const Row = struct { id: []const u8, values: []const f64, label: ?usize, target: ?f64, index: usize };
pub const Settings = struct { scalings: []const Scaling, ks: []const usize, metrics: []const Metric, weightings: []const Weighting, folds: usize, edit: usize, curve: []const usize, bins: []const f64, top: usize };
pub const Data = struct { features: Strings, labels: Strings, train: []const Row, queries: []const Row, settings: Settings };
pub fn alloc(comptime T: type, count: usize) []T { return allocator.alloc(T, count) catch @panic("allocation failed"); }
pub fn clone(comptime T: type, source: []const T) []T { return allocator.dupe(T, source) catch @panic("allocation failed"); }
pub fn append(comptime T: type, list: *std.ArrayList(T), value: T) void { list.append(allocator, value) catch @panic("allocation failed"); }
pub fn fmt(comptime pattern: []const u8, args: anytype) []const u8 { return std.fmt.allocPrint(allocator, pattern, args) catch @panic("allocation failed"); }
pub fn eq(a: []const u8, b: []const u8) bool { return std.mem.eql(u8, a, b); }
pub fn textLess(a: []const u8, b: []const u8) bool { return std.mem.order(u8, a, b) == .lt; }
pub fn join(parts: Strings, separator: []const u8) []const u8 { return std.mem.join(allocator, separator, parts) catch @panic("allocation failed"); }
pub fn split(text: []const u8, separator: u8) Strings { var result: std.ArrayList([]const u8) = .empty; var it = std.mem.splitScalar(u8, text, separator); while (it.next()) |part| append([]const u8, &result, part); return result.items; }
pub fn lines(text: []const u8) Strings { const result = split(text, '\n'); return result[0..result.len - 1]; }
pub fn natural(text: []const u8) usize { return std.fmt.parseInt(usize, text, 10) catch unreachable; }
pub fn number(text: []const u8) f64 { return std.fmt.parseFloat(f64, text) catch unreachable; }
pub fn real(value: anytype) f64 { return @floatFromInt(value); }
pub fn int(value: anytype) i64 { return @intCast(value); }
pub fn indices(count: usize) []usize { const result = alloc(usize, count); for (result, 0..) |*value, i| value.* = i; return result; }
pub fn contains(values: []const usize, value: usize) bool { return std.mem.findScalar(usize, values, value) != null; }
pub fn textIndex(names: Strings, name: []const u8) ?usize { for (names, 0..) |candidate, i| { if (eq(candidate, name)) return i; } return null; }
pub fn enumValue(comptime T: type, text: []const u8) T { inline for (@typeInfo(T).@"enum".field_names) |name| { if (eq(name, text)) return @field(T, name); } unreachable; }
fn enumList(comptime T: type, text: []const u8) []const T { const fields = split(text, ' ')[1..]; const result = alloc(T, fields.len); for (fields, result) |field, *value| value.* = enumValue(T, field); return result; }
fn naturals(text: []const u8) []const usize { const fields = split(text, ' ')[1..]; const result = alloc(usize, fields.len); for (fields, result) |field, *value| value.* = natural(field); return result; }
fn reals(text: []const u8) []const f64 { const fields = split(text, ' ')[1..]; const result = alloc(f64, fields.len); for (fields, result) |field, *value| value.* = number(field); return result; }
fn settings(text: []const u8) Settings { const all = lines(text); return .{ .scalings = enumList(Scaling, all[0]), .ks = naturals(all[1]), .metrics = enumList(Metric, all[2]), .weightings = enumList(Weighting, all[3]), .folds = naturals(all[4])[0], .edit = naturals(all[5])[0], .curve = naturals(all[6]), .bins = reals(all[7]), .top = naturals(all[8])[0] }; }
fn stringLess(_: void, a: []const u8, b: []const u8) bool { return textLess(a, b); }
fn readRows(text: []const u8, labels: Strings) []const Row {
    const all = lines(text); const result = alloc(Row, all.len - 1);
    for (all[1..], result, 0..) |line, *row, i| { const fields = split(line, ','); const values = alloc(f64, fields.len - 3); for (fields[1..fields.len - 2], values) |field, *value| value.* = number(field); row.* = .{ .id = fields[0], .values = values, .label = if (fields[fields.len - 2].len == 0) null else textIndex(labels, fields[fields.len - 2]).?, .target = if (fields[fields.len - 1].len == 0) null else number(fields[fields.len - 1]), .index = i }; }
    return result;
}
pub fn read(train_text: []const u8, query_text: []const u8, params_text: []const u8) Data {
    const all = lines(train_text); const header = split(all[0], ','); var labels: std.ArrayList([]const u8) = .empty;
    for (all[1..]) |line| { const fields = split(line, ','); const label = fields[fields.len - 2]; if (textIndex(labels.items, label) == null) append([]const u8, &labels, label); }
    std.mem.sort([]const u8, labels.items, {}, stringLess);
    return .{ .features = header[1..header.len - 2], .labels = labels.items, .train = readRows(train_text, labels.items), .queries = readRows(query_text, labels.items), .settings = settings(params_text) };
}
