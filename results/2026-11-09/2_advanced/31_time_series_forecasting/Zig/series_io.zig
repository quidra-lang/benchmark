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
pub fn f(value: anytype) f64 {
    return @floatFromInt(value);
}
pub fn u(value: i64) usize {
    return @intCast(value);
}
pub fn number(text: []const u8) usize {
    return std.fmt.parseInt(usize, text, 10) catch unreachable;
}
pub fn floating(text: []const u8) f64 {
    return std.fmt.parseFloat(f64, text) catch unreachable;
}
pub fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
pub fn split(text: []const u8, delimiter: u8) []const []const u8 {
    var result: std.ArrayList([]const u8) = .empty;
    var fields = std.mem.splitScalar(u8, text, delimiter);
    while (fields.next()) |field| append([]const u8, &result, field);
    return result.items;
}
pub fn zeros(count: usize) []f64 {
    const values = alloc(f64, count);
    @memset(values, 0);
    return values;
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
    pub fn extend(self: *Lines, other: Lines) void {
        for (other.data.items) |line| self.add("{s}", .{line});
    }
};
pub fn readLines(io: std.Io, name: []const u8) ![]const []const u8 {
    const text = try std.Io.Dir.cwd().readFileAlloc(io, fmt("input/{s}", .{name}), allocator, .unlimited);
    const lines = split(text, '\n');
    return lines[0 .. lines.len - 1];
}
pub fn writeLines(io: std.Io, name: []const u8, lines: Lines) !void {
    var text: Text = .{};
    for (lines.data.items) |line| text.add("{s}\n", .{line});
    try std.Io.Dir.cwd().createDirPath(io, "output");
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = fmt("output/{s}", .{name}), .data = text.value() });
}
pub fn real(value: f64) []const u8 {
    const text = fmt("{d:.4}", .{value});
    return if (eq(text, "-0.0000")) "0.0000" else text;
}
pub fn nextMonth(period: []const u8) []const u8 {
    var year = number(period[0..4]);
    var month = number(period[5..7]) + 1;
    if (month == 13) {
        month = 1;
        year += 1;
    }
    return fmt("{d:0>4}-{d:0>2}", .{ year, month });
}
pub const Params = struct { season: usize, holdout: usize, horizon: usize, cv_start: usize, combo: usize,
     alpha: []f64, beta: []f64, gamma: []f64, phi: []f64, max_ar: usize, max_lag: usize, ljung_box: []usize,
     outlier: f64, z80: f64, z95: f64 };
pub const Series = struct { name: []const u8, periods: []const []const u8, raw: []f64, missing: []bool };
pub const Inventory = struct { on_hand: i64, lead_time: usize, review: usize, service: f64 };
pub const Event = struct { series: []const u8, period: []const u8, kind: []const u8 };
pub const Input = struct {
    params: Params,
    series: []Series,
    events: []Event,
    inventory: []Inventory,
    pub fn event(self: *const Input, name: []const u8, period: []const u8) ?[]const u8 {
        for (self.events) |item| if (eq(item.series, name) and eq(item.period, period)) return item.kind;
        return null;
    }
};
const Builder = struct { name: []const u8, periods: std.ArrayList([]const u8) = .empty, raw: std.ArrayList(f64) = .empty,
     missing: std.ArrayList(bool) = .empty };
pub fn readInput(io: std.Io) !Input {
    const lines = try readLines(io, "params.txt");
    var fields: [14][]const []const u8 = undefined;
    for (lines, &fields) |line, *field| field.* = split(line, ' ')[1..];
    var candidates: [4][]f64 = undefined;
    for (&candidates, 5..) |*values, row| {
        values.* = alloc(f64, fields[row].len);
        for (fields[row], values.*) |field, *value| value.* = floating(field);
    }
    const lags = alloc(usize, fields[11].len);
    for (fields[11], lags) |field, *lag| lag.* = number(field);
    const params: Params = .{ .season = number(fields[0][0]), .holdout = number(fields[1][0]), .horizon = number(fields[2][0]),
         .cv_start = number(fields[3][0]), .combo = number(fields[4][0]), .alpha = candidates[0],
         .beta = candidates[1], .gamma = candidates[2], .phi = candidates[3], .max_ar = number(fields[9][0]),
         .max_lag = number(fields[10][0]), .ljung_box = lags, .outlier = floating(fields[12][0]),
         .z80 = floating(fields[13][0]), .z95 = floating(fields[13][1]) };
    const observations = try readLines(io, "series.csv");
    var builders: std.ArrayList(Builder) = .empty;
    for (observations[1..]) |line| {
        const values = split(line, ',');
        if (builders.items.len == 0 or !eq(builders.items[builders.items.len - 1].name, values[0])) append(Builder,
             &builders, .{ .name = values[0] });
        const item = &builders.items[builders.items.len - 1];
        append([]const u8, &item.periods, values[1]);
        const missing = eq(values[2], "NA");
        append(bool, &item.missing, missing);
        append(f64, &item.raw, if (missing) 0 else floating(values[2]));
    }
    const series = alloc(Series, builders.items.len);
    for (builders.items, series) |item, *target| target.* = .{ .name = item.name, .periods = item.periods.items,
         .raw = item.raw.items, .missing = item.missing.items };
    const event_lines = try readLines(io, "events.csv");
    const events = alloc(Event, event_lines.len - 1);
    for (event_lines[1..], events) |line, *event| {
        const values = split(line, ',');
        event.* = .{ .series = values[0], .period = values[1], .kind = values[2] };
    }
    const policies = try readLines(io, "inventory.csv");
    const inventory = alloc(Inventory, series.len);
    for (policies[1..]) |line| {
        const values = split(line, ',');
        for (series, inventory) |item, *policy| if (eq(item.name, values[0])) {
            policy.* = .{ .on_hand = n(number(values[1])), .lead_time = number(values[2]), .review = number(values[3]),
                 .service = floating(values[4]) };
            break;
        };
    }
    return .{ .params = params, .series = series, .events = events, .inventory = inventory };
}
