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
pub fn indexOf(values: []const []const u8, value: []const u8) usize {
    for (values, 0..) |name, i| if (eq(name, value)) return i;
    unreachable;
}
pub fn bit(variable: usize) u16 {
    return @as(u16, 1) << @intCast(variable);
}
pub const Assignment = [15]usize;
pub const Observation = struct { variable: usize, state: usize };
pub fn evidenceState(evidence: []const Observation, variable: usize) ?usize {
    for (evidence) |entry| if (entry.variable == variable) return entry.state;
    return null;
}
pub const CPT = struct { rows: []const [4]f64, states: usize };
pub const Counts = struct { rows: [][4]i64, states: usize };
pub const Network = struct { names: []const []const u8, states: []const []const []const u8,
     sizes: []const usize, parents: []const []const usize, expert: []const ?CPT };
pub const Input = struct { network: Network, samples: []const Assignment, queries: []const []const u8,
     settings: []const []const u8 };
pub fn readInputs(io: std.Io) !Input {
    var definitions: std.ArrayList([]const u8) = .empty;
    for (try readLines(io, "input/network.txt")) |line| if (line.len > 0 and line[0] != '#') append([]const u8,
         &definitions, line);
    var names: std.ArrayList([]const u8) = .empty;
    var states: std.ArrayList([]const []const u8) = .empty;
    var sizes: std.ArrayList(usize) = .empty;
    var parents: std.ArrayList([]const usize) = .empty;
    var expert: std.ArrayList(?CPT) = .empty;
    var position: usize = 0;
    while (position < definitions.items.len) {
        const row = words(definitions.items[position]);
        position += 1;
        if (eq(row[0], "VARIABLE")) {
            append([]const u8, &names, row[1]);
            append([]const []const u8, &states, row[2..]);
            append(usize, &sizes, row.len - 2);
            append([]const usize, &parents, &.{});
            append(?CPT, &expert, null);
        } else if (eq(row[0], "PARENTS")) {
            const v = indexOf(names.items, row[1]);
            const list = alloc(usize, row.len - 2);
            for (row[2..], list) |name, *parent| parent.* = indexOf(names.items, name);
            parents.items[v] = list;
        } else {
            const v = indexOf(names.items, row[1]);
            var count: usize = 1;
            for (parents.items[v]) |parent| count *= sizes.items[parent];
            const rows = alloc([4]f64, count);
            @memset(rows, [_]f64{0} ** 4);
            for (rows) |*values| {
                const numbers = words(definitions.items[position]);
                position += 1;
                for (numbers, 0..) |number_value, state| values[state] = decimal(number_value);
            }
            expert.items[v] = .{ .rows = rows, .states = sizes.items[v] };
        }
    }
    const network: Network = .{ .names = names.items, .states = states.items, .sizes = sizes.items,
         .parents = parents.items, .expert = expert.items };
    const lines = try readLines(io, "input/samples.csv");
    const header = split(lines[0], ',');
    const columns = alloc(usize, header.len);
    for (header, columns) |name, *variable| variable.* = indexOf(network.names, name);
    const samples = alloc(Assignment, lines.len - 1);
    for (lines[1..], samples) |line, *sample| {
        sample.* = [_]usize{0} ** 15;
        const values = split(line, ',');
        for (columns, values) |variable, state| sample[variable] = indexOf(network.states[variable], state);
    }
    return .{ .network = network, .samples = samples, .queries = try readLines(io, "input/queries.txt"),
         .settings = try readLines(io, "input/params.txt") };
}
