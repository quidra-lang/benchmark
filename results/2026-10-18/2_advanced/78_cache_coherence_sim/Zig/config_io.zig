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

pub fn join(values: []const []const u8, separator: []const u8) []const u8 {
    return std.mem.join(allocator, separator, values) catch @panic("allocation failed");
}
pub fn zero(comptime T: type, count: usize, value: T) []T {
    const out = alloc(T, count);
    @memset(out, value);
    return out;
}
pub fn decimalInteger(value: []const u8, maximum: usize) bool {
    if (value.len == 0 or value.len > maximum or (value.len > 1 and value[0] == '0')) return false;
    for (value) |c| if (c < '0' or c > '9') return false;
    return true;
}
pub fn validHexAddress(value: []const u8) bool {
    if (value.len != 8) return false;
    for (value) |c| if (!((c >= '0' and c <= '9') or (c >= 'a' and c <= 'f'))) return false;
    return true;
}
pub fn hexValue(value: []const u8) i64 {
    return std.fmt.parseInt(i64, value, 16) catch unreachable;
}
pub fn hexAddress(value: i64) []const u8 {
    return fmt("{x:0>8}", .{value});
}
pub const Protocol = enum { vi, msi, mesi, moesi };
pub const Replacement = enum { lru, fifo, plru };
pub const protocol_names = [_][]const u8{ "VI", "MSI", "MESI", "MOESI" };
pub const replacement_names = [_][]const u8{ "LRU", "FIFO", "PLRU" };
fn lookup(value: []const u8, names: []const []const u8) usize {
    for (names, 0..) |name, i| if (eq(value, name)) return i;
    unreachable;
}
pub const Scenario = struct { name: []const u8, protocol: Protocol, l1: Replacement, l2: Replacement, order: usize };
pub const Region = struct { name: []const u8, first: i64, last: i64 };
pub const Config = struct {
    cores: usize = 0,
    line_size: i64 = 0,
    l1_size: i64 = 0,
    l1_ways: usize = 0,
    l2_size: i64 = 0,
    l2_ways: usize = 0,
    l1_sets: usize = 0,
    l2_sets: usize = 0,
    cap: i64 = 0,
    t1: i64 = 0,
    t2: i64 = 0,
    tm: i64 = 0,
    tb: i64 = 0,
    interval: i64 = 0,
    top: usize = 0,
    scenarios: std.ArrayList(Scenario) = .empty,
    primary: []const u8 = "",
    regions: std.ArrayList(Region) = .empty,
    watch: std.ArrayList(i64) = .empty,
};
pub fn readConfig(io: std.Io) !Config {
    var c: Config = .{};
    for (try readLines(io, "input/config.txt")) |line| {
        const f = words(line);
        const kind = f[0];
        if (eq(kind, "CORES")) c.cores = u(number(f[1])) else if (eq(kind, "LINE")) c.line_size = number(f[1]) else if (eq(kind,
             "L1")) {
            c.l1_size = number(f[1]);
            c.l1_ways = u(number(f[2]));
        } else if (eq(kind, "L2")) {
            c.l2_size = number(f[1]);
            c.l2_ways = u(number(f[2]));
        } else if (eq(kind, "LATENCY")) {
            c.t1 = number(f[1]);
            c.t2 = number(f[2]);
            c.tm = number(f[3]);
            c.tb = number(f[4]);
        } else if (eq(kind, "SCENARIO")) append(Scenario, &c.scenarios, .{ .name = f[1], .protocol = @enumFromInt(lookup(f[2],
             &protocol_names)), .l1 = @enumFromInt(lookup(f[3], &replacement_names)), .l2 = @enumFromInt(lookup(f[4],
             &replacement_names)), .order = c.scenarios.items.len }) else if (eq(kind, "PRIMARY")) c.primary = f[1] else if (eq(kind,
             "INTERVAL")) c.interval = number(f[1]) else if (eq(kind, "TOP")) c.top = u(number(f[1])) else if (eq(kind,
             "REGION")) append(Region, &c.regions, .{ .name = f[1], .first = hexValue(f[2]),
             .last = hexValue(f[3]) }) else if (eq(kind, "WATCH")) append(i64, &c.watch, @divTrunc(hexValue(f[1]),
             c.line_size));
    }
    c.l1_sets = u(@divTrunc(c.l1_size, c.line_size * n(c.l1_ways)));
    c.l2_sets = u(@divTrunc(c.l2_size, c.line_size * n(c.l2_ways)));
    c.cap = n(c.l1_sets * c.l1_ways);
    return c;
}
pub fn writeLines(io: std.Io, filename: []const u8, lines: Lines) !void {
    try std.Io.Dir.cwd().createDirPath(io, "output");
    var out: Text = .{};
    for (lines.data.items) |line| out.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = fmt("output/{s}", .{filename}), .data = out.value() });
}
