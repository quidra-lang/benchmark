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
pub fn f(value: anytype) f64 {
    return @floatFromInt(value);
}
pub fn decimal(value: []const u8) f64 {
    return std.fmt.parseFloat(f64, value) catch unreachable;
}
pub const Station = struct { code: []const u8, name: []const u8, observations: [10001]?i64 = [_]?i64{null} ** 10001,
     present: [10001]bool = [_]bool{false} ** 10001, first: usize = 10001, last: usize = 0,
     rows: usize = 0 };
pub const Constituent = struct { name: []const u8, speed: f64 };
pub const Params = struct { epoch_day: i64 = 0, flat_run: usize = 0, spike_window: usize = 0,
     spike_count: usize = 0, top: usize = 0, surge_hours: usize = 0, start: i64 = 0, length: usize = 0,
     grid: usize = 0, lag: i64 = 0, plot_hours: usize = 0, plot_top: i64 = 0, plot_bottom: i64 = 0,
     plot_step: i64 = 0, spike_factor: f64 = 0, spike_minimum: f64 = 0, rayleigh: f64 = 0,
     snr: f64 = 0, surge: f64 = 0, min_range: f64 = 0, reference: []const u8 = "", plot: []const u8 = "" };
pub const Input = struct { params: Params, stations: []Station, constituents: []const Constituent };
pub const Sample = struct { time: usize, value: f64 };
pub fn civilDay(year_value: i64, month: i64, day: i64) i64 {
    const year = year_value - @as(i64, @intFromBool(month <= 2));
    const era = @divFloor(year, 400);
    const yoe = year - era * 400;
    const doy = @divTrunc(153 * (month + (if (month > 2) @as(i64, -3) else 9)) + 2, 5) + day - 1;
    const doe = yoe * 365 + @divTrunc(yoe, 4) - @divTrunc(yoe, 100) + doy;
    return era * 146097 + doe;
}
fn civil(days: i64) [3]i64 {
    const era = @divFloor(days, 146097);
    const doe = days - era * 146097;
    const yoe = @divTrunc(doe - @divTrunc(doe, 1460) + @divTrunc(doe, 36524) - @divTrunc(doe, 146096), 365);
    var year = yoe + era * 400;
    const doy = doe - (365 * yoe + @divTrunc(yoe, 4) - @divTrunc(yoe, 100));
    const mp = @divTrunc(5 * doy + 2, 153);
    const day = doy - @divTrunc(153 * mp + 2, 5) + 1;
    const month = mp + (if (mp < 10) @as(i64, 3) else -9);
    year += @intFromBool(month <= 2);
    return .{ year, month, day };
}
pub fn parseMinutes(value: []const u8) i64 {
    const year = number(value[0..4]);
    const month = number(value[5..7]);
    const day = number(value[8..10]);
    const hour_value = number(value[11..13]);
    const minute = number(value[14..16]);
    return civilDay(year, month, day) * 1440 + hour_value * 60 + minute;
}
pub fn hour(value: []const u8, epoch_day: i64) i64 {
    return @divTrunc(parseMinutes(value) - epoch_day * 1440, 60);
}
pub fn date(day: i64, epoch_day: i64) []const u8 {
    const parts = civil(day + epoch_day);
    return fmt("{d:0>4}-{d:0>2}-{d:0>2}", .{ parts[0], parts[1], parts[2] });
}
pub fn datetime(minutes: i64, epoch_day: i64) []const u8 {
    const day = @divFloor(minutes, 1440);
    const remaining = @mod(minutes, 1440);
    return fmt("{s} {d:0>2}:{d:0>2}", .{ date(day, epoch_day), @divTrunc(remaining, 60), @mod(remaining, 60) });
}
pub fn load(io: std.Io) !Input {
    var p: Params = .{};
    var stations: std.ArrayList(Station) = .empty;
    for (try readLines(io, "input/params.txt")) |line| {
        const row = words(line);
        const key = row[0];
        if (eq(key, "epoch")) p.epoch_day = @divTrunc(parseMinutes(line[6..]), 1440) else if (eq(key,
             "station")) append(Station, &stations, .{ .code = row[1], .name = line[12..] }) else if (eq(key,
             "reference")) p.reference = row[1] else if (eq(key, "flat_run")) p.flat_run = u(number(row[1])) else if (eq(key,
             "spike")) {
            p.spike_window = u(number(row[1]));
            p.spike_count = u(number(row[2]));
            p.spike_factor = decimal(row[3]);
            p.spike_minimum = decimal(row[4]);
        } else if (eq(key, "rayleigh")) p.rayleigh = decimal(row[1]) else if (eq(key, "snr_min")) p.snr = decimal(row[1]) else if (eq(key,
             "top_residuals")) p.top = u(number(row[1])) else if (eq(key, "surge")) {
            p.surge = decimal(row[1]);
            p.surge_hours = u(number(row[2]));
        } else if (eq(key, "predict")) {
            p.start = hour(line[8..24], p.epoch_day);
            p.length = u(number(row[3]));
        } else if (eq(key, "grid_minutes")) p.grid = u(number(row[1])) else if (eq(key, "min_range")) p.min_range = decimal(row[1]) else if (eq(key,
             "correlation_lag")) p.lag = number(row[1]) else if (eq(key, "plot")) {
            p.plot = row[1];
            p.plot_hours = u(number(row[2]));
            p.plot_top = number(row[3]);
            p.plot_bottom = number(row[4]);
            p.plot_step = number(row[5]);
        }
    }
    const definitions = try readLines(io, "input/constituents.txt");
    const constituents = alloc(Constituent, u(number(definitions[0])));
    for (definitions[1..], constituents) |line, *item| {
        const row = words(line);
        item.* = .{ .name = row[0], .speed = decimal(row[1]) };
    }
    const observations = try readLines(io, "input/observations.csv");
    for (observations[1..]) |line| {
        const row = split(line, ',');
        var index: usize = 0;
        while (!eq(stations.items[index].code, row[0])) index += 1;
        const station = &stations.items[index];
        const t = u(hour(row[1], p.epoch_day));
        station.present[t] = true;
        station.rows += 1;
        if (!eq(row[2], "NA")) {
            const negative = row[2][0] == '-';
            const magnitude = if (negative) row[2][1..] else row[2];
            const parts = split(magnitude, '.');
            const milli = 1000 * number(parts[0]) + number(parts[1]);
            station.observations[t] = if (negative) -milli else milli;
            station.first = @min(station.first, t);
            station.last = @max(station.last, t);
        }
    }
    return .{ .params = p, .stations = stations.items, .constituents = constituents };
}
