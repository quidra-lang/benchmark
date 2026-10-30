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
pub const Vec = [6]i64;
pub const zero: Vec = .{ 0, 0, 0, 0, 0, 0 };
pub const Random = struct {
    state: i64,
    draws: i64 = 0,
    pub fn draw(self: *Random) i64 {
        self.state = @mod(48271 * self.state, 2147483647);
        self.draws += 1;
        return self.state;
    }
};
pub const Channel = struct { source: usize = 0, destination: usize = 0, minimum: i64 = 0, maximum: i64 = 0,
     sequence: i64 = 0, last_arrival: i64 = 0, messages: i64 = 0, markers: i64 = 0, buffered: i64 = 0,
     max_delay: i64 = 0, entries: i64 = 0, fifo: bool = false, previous: Vec = zero };
pub const Topology = struct {
    names: []const []const u8,
    channels: []Channel,
    pub fn index(self: Topology, name: []const u8) usize {
        for (self.names, 0..) |value, i| if (eq(name, value)) return i;
        unreachable;
    }
};
pub fn load(io: std.Io) !Topology {
    const lines = try readLines(io, "input/topology.txt");
    const header = words(lines[0]);
    const names = header[1..];
    const channels = alloc(Channel, names.len * names.len);
    @memset(channels, .{});
    const out: Topology = .{ .names = names, .channels = channels };
    for (lines[1..]) |line| {
        const row = words(line);
        const source = out.index(row[1]);
        const destination = out.index(row[2]);
        channels[source * names.len + destination] = .{ .source = source, .destination = destination,
             .minimum = number(row[4]), .maximum = number(row[row.len - 1]), .fifo = eq(row[3],
             "FIFO") };
    }
    return out;
}
pub const Arrival = struct { sequence: i64, time: i64 };
pub fn dispatch(channel: *Channel, time: i64, marker: bool, clock: Vec, count: usize, random: *Random) Arrival {
    channel.sequence += 1;
    const delay = channel.minimum + (if (channel.minimum == channel.maximum) @as(i64, 0) else @mod(random.draw(),
         channel.maximum - channel.minimum + 1));
    var arrival = time + delay;
    if (channel.fifo) arrival = @max(arrival, channel.last_arrival);
    channel.last_arrival = @max(channel.last_arrival, arrival);
    channel.max_delay = @max(channel.max_delay, arrival - time);
    if (marker) channel.markers += 1 else {
        channel.messages += 1;
        for (0..count) |i| channel.entries += @intFromBool(clock[i] != channel.previous[i]);
        channel.previous = clock;
    }
    return .{ .sequence = channel.sequence, .time = arrival };
}
pub fn delayText(channel: Channel) []const u8 {
    return if (channel.minimum == channel.maximum) fmt("{d}", .{channel.minimum}) else fmt("{d}-{d}",
         .{ channel.minimum, channel.maximum });
}
