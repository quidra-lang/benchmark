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

pub const Path = []const usize;
pub const Plan = []const Path;
pub const Agent = struct { id: usize, start: usize, goal: usize, name: u8 };
pub const Destinations = struct { cells: [5]usize = undefined, count: usize = 0 };
pub const Grid = struct {
    width: usize,
    height: usize,
    rows: Names,
    pub fn size(self: Grid) usize {
        return self.width * self.height;
    }
    pub fn free(self: Grid, cell: usize) bool {
        return cell < self.size() and self.rows[cell / self.width][cell % self.width] == '.';
    }
    pub fn destinations(self: Grid, cell: usize) Destinations {
        var out: Destinations = .{};
        const x = cell % self.width;
        const y = cell / self.width;
        const deltas = [5][2]i64{ .{ 0, 0 }, .{ 0, -1 }, .{ 1, 0 }, .{ 0, 1 }, .{ -1, 0 } };
        for (deltas) |delta| {
            const nx = n(x) + delta[0];
            const ny = n(y) + delta[1];
            if (nx < 0 or ny < 0 or nx >= n(self.width) or ny >= n(self.height)) continue;
            const next = u(ny) * self.width + u(nx);
            if (self.free(next)) {
                out.cells[out.count] = next;
                out.count += 1;
            }
        }
        return out;
    }
    pub fn degree(self: Grid, cell: usize) usize {
        return self.destinations(cell).count - 1;
    }
    pub fn distanceTable(self: Grid, goal: usize) []const i64 {
        const distances = zero(i64, self.size(), -1);
        var queue: [1024]usize = undefined;
        var read_index: usize = 0;
        var count: usize = 1;
        queue[0] = goal;
        distances[goal] = 0;
        while (read_index < count) : (read_index += 1) {
            const cell = queue[read_index];
            const destinations_value = self.destinations(cell);
            for (destinations_value.cells[1..destinations_value.count]) |next| if (distances[next] < 0) {
                distances[next] = distances[cell] + 1;
                queue[count] = next;
                count += 1;
            };
        }
        return distances;
    }
};
pub fn read(io: std.Io) !Grid {
    const lines = try readLines(io, "input/map.txt");
    const dimensions = words(lines[0]);
    return .{ .width = u(number(dimensions[0])), .height = u(number(dimensions[1])), .rows = lines[1..] };
}
pub fn readAgents(io: std.Io, grid: Grid) ![]const Agent {
    const lines = try readLines(io, "input/agents.csv");
    const agents = alloc(Agent, lines.len - 1);
    for (lines[1..], agents) |line, *agent| {
        const f = split(line, ',');
        const id = u(number(f[0]));
        agent.* = .{ .id = id, .start = u(number(f[2])) * grid.width + u(number(f[1])), .goal = u(number(f[4])) * grid.width + u(number(f[3])),
             .name = 'A' + @as(u8, @intCast(id)) };
    }
    return agents;
}
