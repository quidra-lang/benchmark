const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub fn alloc(comptime T: type, count: usize) []T {
    return allocator.alloc(T, count) catch @panic("allocation failed");
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
pub fn decimal(value: []const u8) f64 {
    return std.fmt.parseFloat(f64, value) catch unreachable;
}
pub const Vector = []f64;
pub const Matrix = [][]f64;
pub fn vector(count: usize) Vector {
    const out = alloc(f64, count);
    @memset(out, 0);
    return out;
}
pub fn matrix(rows: usize, columns: usize) Matrix {
    const out = alloc(Vector, rows);
    for (out) |*row| row.* = vector(columns);
    return out;
}
pub const Rating = struct { user: usize, item: usize, rating: i64, time: i64 = 0 };
pub const Item = struct { id: i64, title: []const u8, genre_list: []const u8, genres: []const []const u8 };
pub const Params = struct { neighbors: usize = 0, shrinkage: i64 = 0, factors: usize = 0, epochs: usize = 0,
     iterations: usize = 0, top: usize = 0, buckets: usize = 0, list: usize = 0, minimum: f64 = 0,
     item_reg: f64 = 0, user_reg: f64 = 0, rate: f64 = 0, regularization: f64 = 0, als_reg: f64 = 0,
     seed: i64 = 0, cutoffs: []const i64 = &.{}, grid: []const i64 = &.{}, user_groups: []const i64 = &.{},
     item_groups: []const i64 = &.{}, users: []const i64 = &.{}, items: []const i64 = &.{} };
pub const IntMatrix = [][]i64;
pub fn intMatrix(rows: usize, columns: usize) IntMatrix {
    const out = alloc([]i64, rows);
    for (out) |*row| {
        row.* = alloc(i64, columns);
        @memset(row.*, 0);
    }
    return out;
}
pub const Data = struct { train: []const Rating, test_rows: []const Rating, catalog: []const Item,
     items: []const Item, users: []const i64, user_count: []i64, item_count: []i64, user_sum: []i64,
     item_sum: []i64, user_mean: Vector, item_mean: Vector, ratings: IntMatrix, mean: f64, params: Params };
fn lessInt(_: void, a: i64, b: i64) bool {
    return a < b;
}
fn readRatings(lines: []const []const u8, times: bool) []Rating {
    const out = alloc(Rating, lines.len - 1);
    for (lines[1..], out) |line, *record| {
        const fields = split(line, ',');
        record.* = .{ .user = u(number(fields[0])), .item = u(number(fields[1])), .rating = number(fields[2]),
             .time = if (times) number(fields[3]) else 0 };
    }
    return out;
}
pub fn idIndex(values: []const i64, id: i64) usize {
    return std.mem.indexOfScalar(i64, values, id).?;
}
pub fn itemIndex(values: []const Item, id: i64) usize {
    for (values, 0..) |item, i| if (item.id == id) return i;
    unreachable;
}
pub fn has(values: []const []const u8, value: []const u8) bool {
    for (values) |field| if (eq(field, value)) return true;
    return false;
}
pub fn readInput(io: std.Io) !Data {
    const train = readRatings(try readLines(io, "input/ratings.csv"), true);
    const heldout = readRatings(try readLines(io, "input/test.csv"), false);
    const item_lines = try readLines(io, "input/items.csv");
    const catalog = alloc(Item, item_lines.len - 1);
    for (item_lines[1..], catalog) |line, *item| {
        const fields = split(line, ',');
        item.* = .{ .id = number(fields[0]), .title = fields[1], .genre_list = fields[2], .genres = split(fields[2], '|') };
    }
    var users: std.ArrayList(i64) = .empty;
    var ids: std.ArrayList(i64) = .empty;
    for (train) |record| {
        if (std.mem.indexOfScalar(i64, users.items, n(record.user)) == null) append(i64, &users, n(record.user));
        if (std.mem.indexOfScalar(i64, ids.items, n(record.item)) == null) append(i64, &ids, n(record.item));
    }
    std.mem.sort(i64, users.items, {}, lessInt);
    std.mem.sort(i64, ids.items, {}, lessInt);
    const items = alloc(Item, ids.items.len);
    for (ids.items, items) |id, *item| item.* = catalog[itemIndex(catalog, id)];
    const user_count = alloc(i64, users.items.len);
    const item_count = alloc(i64, items.len);
    const user_sum = alloc(i64, users.items.len);
    const item_sum = alloc(i64, items.len);
    @memset(user_count, 0);
    @memset(item_count, 0);
    @memset(user_sum, 0);
    @memset(item_sum, 0);
    const ratings = intMatrix(users.items.len, items.len);
    var total: i64 = 0;
    for (train) |*record| {
        record.user = idIndex(users.items, n(record.user));
        record.item = idIndex(ids.items, n(record.item));
        ratings[record.user][record.item] = record.rating;
        user_count[record.user] += 1;
        item_count[record.item] += 1;
        user_sum[record.user] += record.rating;
        item_sum[record.item] += record.rating;
        total += record.rating;
    }
    for (heldout) |*record| {
        record.user = idIndex(users.items, n(record.user));
        record.item = idIndex(ids.items, n(record.item));
    }
    const user_mean = vector(users.items.len);
    const item_mean = vector(items.len);
    for (user_mean, user_sum, user_count) |*mean, values, count| mean.* = f(values) / f(count);
    for (item_mean, item_sum, item_count) |*mean, values, count| mean.* = f(values) / f(count);
    var p: Params = .{};
    for (try readLines(io, "input/params.txt")) |line| {
        const fields = words(line);
        const key = fields[0];
        const value = decimal(fields[1]);
        if (eq(key, "NEIGHBORS")) p.neighbors = @intFromFloat(value) else if (eq(key, "SHRINKAGE")) p.shrinkage = number(fields[1]) else if (eq(key,
             "MIN_SIMILARITY")) p.minimum = value else if (eq(key, "BIAS_REG")) {
            p.item_reg = value;
            p.user_reg = decimal(fields[2]);
        } else if (eq(key, "FACTORS")) p.factors = @intFromFloat(value) else if (eq(key, "LEARNING_RATE")) p.rate = value else if (eq(key,
             "REGULARIZATION")) p.regularization = value else if (eq(key, "EPOCHS")) p.epochs = @intFromFloat(value) else if (eq(key,
             "ALS_REG")) p.als_reg = value else if (eq(key, "ALS_ITERATIONS")) p.iterations = @intFromFloat(value) else if (eq(key,
             "SEED")) p.seed = number(fields[1]) else if (eq(key, "TOP_N")) p.top = @intFromFloat(value) else if (eq(key,
             "TIME_BUCKETS")) p.buckets = @intFromFloat(value) else if (eq(key, "LIST_SIZE")) p.list = @intFromFloat(value) else {
            const values = alloc(i64, fields.len - 1);
            for (fields[1..], values) |field, *entry| entry.* = number(field);
            if (eq(key, "CUTOFFS")) p.cutoffs = values else if (eq(key, "NEIGHBOR_GRID")) p.grid = values else if (eq(key,
                 "USER_GROUPS")) p.user_groups = values else if (eq(key, "ITEM_GROUPS")) p.item_groups = values else if (eq(key,
                 "RECOMMEND_USERS")) p.users = values else p.items = values;
        }
    }
    return .{ .train = train, .test_rows = heldout, .catalog = catalog, .items = items, .users = users.items,
         .user_count = user_count, .item_count = item_count, .user_sum = user_sum, .item_sum = item_sum,
         .user_mean = user_mean, .item_mean = item_mean, .ratings = ratings, .mean = f(total) / f(train.len),
         .params = p };
}
