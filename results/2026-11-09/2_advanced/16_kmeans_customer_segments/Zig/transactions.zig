const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub const Strings = []const []const u8;
pub fn alloc(comptime T: type, count: usize) []T { return allocator.alloc(T, count) catch @panic("allocation failed"); }
pub fn append(comptime T: type, list: *std.ArrayList(T), value: T) void { list.append(allocator, value) catch @panic("allocation failed"); }
pub fn fmt(comptime pattern: []const u8, args: anytype) []const u8 { return std.fmt.allocPrint(allocator, pattern, args) catch @panic("allocation failed"); }
pub fn eq(first: []const u8, second: []const u8) bool { return std.mem.eql(u8, first, second); }
pub fn number(word: []const u8) i64 { return std.fmt.parseInt(i64, word, 10) catch unreachable; }
pub fn integer(word: []const u8) usize { return @intCast(number(word)); }
pub fn decimal(word: []const u8) f64 { return std.fmt.parseFloat(f64, word) catch unreachable; }
pub fn n(value: anytype) i64 { return @intCast(value); }
pub fn real(value: anytype) f64 { return @floatFromInt(value); }
pub fn abs(value: i64) i64 { return if (value < 0) -value else value; }
pub fn copy(comptime T: type, values: []const T) []T { const result = alloc(T, values.len); @memcpy(result, values); return result; }
pub fn split(source: []const u8, separator: u8) Strings {
    var result: std.ArrayList([]const u8) = .empty;
    var iterator = std.mem.splitScalar(u8, source, separator);
    while (iterator.next()) |part| append([]const u8, &result, part);
    return result.items;
}
pub fn lines(source: []const u8) Strings { const result = split(source, '\n'); return result[0 .. result.len - 1]; }
pub fn stringIndex(values: Strings, value: []const u8) ?usize {
    for (values, 0..) |candidate, i| { if (eq(candidate, value)) return i; }
    return null;
}
pub fn textLess(_: void, first: []const u8, second: []const u8) bool { return std.mem.order(u8, first, second) == .lt; }
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
    pub fn blank(self: *Lines) void { self.write(""); }
};
pub const Method = enum { forgy, maximin, kmeanspp };
pub const Settings = struct {
    reference: i64, snapshot: i64, outcome_days: i64, min_k: usize, max_k: usize, methods: []Method,
    restarts: usize, iterations: usize, seed: i64, subsamples: usize, percent: usize, outlier_sd: f64,
    overdue_factor: i64, order_bins: []i64, top_categories: usize, top_customers: usize, period_days: i64, periods: usize,
};
pub const Row = struct { customer: usize, day: i64, order_id: []const u8, category: usize, amount: i64 };
pub const Transactions = struct { settings: Settings, rows: []Row, ids: Strings, categories: Strings, row_count: usize, duplicates: usize, free_rows: usize };
pub const Order = struct { customer: usize, day: i64, id: []const u8, net: i64, rows: []const *const Row };
fn readSettings(source: []const u8) Settings {
    const entries = lines(source);
    var values: [17]Strings = undefined;
    for (entries, &values) |line, *fields| fields.* = split(line, ' ')[1..];
    const methods = alloc(Method, values[4].len);
    for (values[4], methods) |word, *method| method.* = std.meta.stringToEnum(Method, word).?;
    const bins = alloc(i64, values[12].len);
    for (values[12], bins) |word, *value| value.* = number(word);
    return .{ .reference = number(values[0][0]), .snapshot = number(values[1][0]), .outcome_days = number(values[2][0]), .min_k = integer(values[3][0]), .max_k = integer(values[3][1]), .methods = methods, .restarts = integer(values[5][0]), .iterations = integer(values[6][0]), .seed = number(values[7][0]), .subsamples = integer(values[8][0]), .percent = integer(values[9][0]), .outlier_sd = decimal(values[10][0]), .overdue_factor = number(values[11][0]), .order_bins = bins, .top_categories = integer(values[13][0]), .top_customers = integer(values[14][0]), .period_days = number(values[15][0]), .periods = integer(values[16][0]) };
}
pub fn load(io: std.Io) !Transactions {
    const directory = std.Io.Dir.cwd();
    const settings = readSettings(try directory.readFileAlloc(io, "input/params.txt", allocator, .unlimited));
    const entries = lines(try directory.readFileAlloc(io, "input/transactions.csv", allocator, .unlimited))[1..];
    var ids: std.ArrayList([]const u8) = .empty;
    var categories: std.ArrayList([]const u8) = .empty;
    var fields_list: std.ArrayList(Strings) = .empty;
    var duplicates: usize = 0;
    var free_rows: usize = 0;
    for (entries, 0..) |line, i| {
        const fields = split(line, ',');
        if (stringIndex(ids.items, fields[0]) == null) append([]const u8, &ids, fields[0]);
        if (stringIndex(entries[0..i], line) != null) { duplicates += 1; continue; }
        if (number(fields[4]) == 0) { free_rows += 1; continue; }
        append(Strings, &fields_list, fields);
        if (stringIndex(categories.items, fields[3]) == null) append([]const u8, &categories, fields[3]);
    }
    std.mem.sort([]const u8, ids.items, {}, textLess);
    std.mem.sort([]const u8, categories.items, {}, textLess);
    const rows = alloc(Row, fields_list.items.len);
    for (fields_list.items, rows) |fields, *row| row.* = .{ .customer = stringIndex(ids.items, fields[0]).?, .day = number(fields[1]), .order_id = fields[2], .category = stringIndex(categories.items, fields[3]).?, .amount = number(fields[4]) };
    return .{ .settings = settings, .rows = rows, .ids = ids.items, .categories = categories.items, .row_count = entries.len, .duplicates = duplicates, .free_rows = free_rows };
}
pub fn groupOrders(data: *const Transactions, first: i64, last: i64) []Order {
    const Pending = struct { customer: usize, day: i64, id: []const u8, net: i64 = 0, rows: std.ArrayList(*const Row) = .empty };
    var pending: std.ArrayList(Pending) = .empty;
    for (data.rows) |*row| {
        if (row.day < first or row.day > last) continue;
        var index: ?usize = null;
        for (pending.items, 0..) |order, i| { if (eq(order.id, row.order_id)) { index = i; break; } }
        if (index == null) {
            index = pending.items.len;
            append(Pending, &pending, .{ .customer = row.customer, .day = row.day, .id = row.order_id });
        }
        const order = &pending.items[index.?];
        order.day = @min(order.day, row.day);
        order.net += row.amount;
        append(*const Row, &order.rows, row);
    }
    const result = alloc(Order, pending.items.len);
    for (pending.items, result) |order, *destination| destination.* = .{ .customer = order.customer, .day = order.day, .id = order.id, .net = order.net, .rows = order.rows.items };
    return result;
}
