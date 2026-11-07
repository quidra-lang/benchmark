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
pub const AircraftType = struct { name: []const u8, climb: i64, descent: i64, minimum: i64 };
pub const Waypoint = struct { x: i64, y: i64, level: ?i64 };
pub const Plan = struct { callsign: []const u8, type_index: usize, departure: i64, delay: i64 = 0,
     level: i64, offset: i64 = 0, speed_initial: i64, speed: i64, waypoints: []const Waypoint,
     history: []const []const u8 = &.{} };
pub const Sector = struct { name: []const u8, x1: i64, y1: i64, x2: i64, y2: i64, lower: i64,
     upper: i64, capacity: i64 };
pub const Params = struct { horizontal: i64, vertical: i64, lookahead: i64, max_delay: i64,
     level_min: i64, level_max: i64, sample_start: i64, sample_end: i64, radar: [6]i64, snapshots: []const i64,
     leader: i64, alert: i64 };
pub const Input = struct { plans: []const Plan, types: []const AircraftType, sectors: []const Sector, params: Params };
fn typeIndex(types: []const AircraftType, name: []const u8) usize {
    for (types, 0..) |value, i| if (eq(value.name, name)) return i;
    unreachable;
}
pub fn readInputs(io: std.Io) !Input {
    var types: std.ArrayList(AircraftType) = .empty;
    var sectors: std.ArrayList(Sector) = .empty;
    var plans: std.ArrayList(Plan) = .empty;
    for (try readLines(io, "input/aircraft.txt")) |line| {
        const row = words(line);
        append(AircraftType, &types, .{ .name = row[0], .climb = number(row[1]), .descent = number(row[2]),
             .minimum = number(row[3]) });
    }
    for (try readLines(io, "input/sectors.txt")) |line| {
        const row = words(line);
        append(Sector, &sectors, .{ .name = row[0], .x1 = number(row[1]), .y1 = number(row[2]),
             .x2 = number(row[3]), .y2 = number(row[4]), .lower = number(row[5]), .upper = number(row[6]),
             .capacity = number(row[7]) });
    }
    const flights = try readLines(io, "input/flights.csv");
    for (flights[1..]) |line| {
        const row = split(line, ',');
        const points = words(row[5]);
        const waypoints = alloc(Waypoint, points.len);
        for (points, waypoints) |point, *waypoint| {
            const values = split(point, ':');
            waypoint.* = .{ .x = number(values[0]), .y = number(values[1]), .level = if (values.len == 3) number(values[2]) else null };
        }
        append(Plan, &plans, .{ .callsign = row[0], .type_index = typeIndex(types.items, row[1]),
             .departure = number(row[2]), .level = number(row[3]), .speed_initial = number(row[4]),
             .speed = number(row[4]), .waypoints = waypoints });
    }
    const Context = struct {
        fn less(_: void, left: Plan, right: Plan) bool {
            return std.mem.lessThan(u8, left.callsign, right.callsign);
        }
    };
    std.mem.sort(Plan, plans.items, {}, Context.less);
    const settings = try readLines(io, "input/params.txt");
    var values: [9][]const i64 = undefined;
    for (settings, 0..) |line, i| {
        const row = words(line);
        const numbers = alloc(i64, row.len - 1);
        for (row[1..], numbers) |value, *destination| destination.* = number(value);
        values[i] = numbers;
    }
    var radar: [6]i64 = undefined;
    @memcpy(&radar, values[5]);
    const params: Params = .{ .horizontal = values[0][0], .vertical = values[0][1], .lookahead = values[1][0],
         .max_delay = values[2][0], .level_min = values[3][0], .level_max = values[3][1], .sample_start = values[4][0],
         .sample_end = values[4][1], .radar = radar, .snapshots = values[6], .leader = values[7][0],
         .alert = values[8][0] };
    return .{ .plans = plans.items, .types = types.items, .sectors = sectors.items, .params = params };
}
pub fn flightLevels(plan: Plan) []const i64 {
    var out: std.ArrayList(i64) = .empty;
    append(i64, &out, plan.level + plan.offset);
    for (plan.waypoints[1..]) |point| if (point.level) |level| append(i64, &out, level + plan.offset);
    return out.items;
}
