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
pub fn indexOf(items: anytype, name: []const u8) usize {
    for (items, 0..) |item, i| if (eq(item.name, name)) return i;
    unreachable;
}
pub fn addressValue(text: []const u8) u64 {
    var value: u64 = 0;
    for (split(text, '.')) |octet| value = value * 256 + @as(u64, @intCast(number(octet)));
    return value;
}
pub fn addressText(value: u64) []const u8 {
    return fmt("{d}.{d}.{d}.{d}", .{ (value >> 24) & 255, (value >> 16) & 255, (value >> 8) & 255, value & 255 });
}
pub const Prefix = struct {
    address: u64,
    length: usize,
    pub fn same(self: Prefix, other: Prefix) bool {
        return self.address == other.address and self.length == other.length;
    }
    pub fn contains(self: Prefix, address: u64) bool {
        const shift: u6 = @intCast(32 - self.length);
        return (self.address >> shift) == (address >> shift);
    }
    pub fn text(self: Prefix) []const u8 {
        return fmt("{s}/{d}", .{ addressText(self.address), self.length });
    }
};
pub fn parsePrefix(text: []const u8) Prefix {
    const f = split(text, '/');
    return .{ .address = addressValue(f[0]), .length = u(number(f[1])) };
}
pub fn prefixLess(_: void, a: Prefix, b: Prefix) bool {
    return if (a.address == b.address) a.length < b.length else a.address < b.address;
}
pub const Origin = enum { igp, egp, incomplete };
pub const origin_names = [_][]const u8{ "IGP", "EGP", "INCOMPLETE" };
pub fn parseOrigin(text: []const u8) Origin {
    for (origin_names, 0..) |name, i| if (eq(name, text)) return @enumFromInt(i);
    unreachable;
}
pub const AutonomousSystem = struct { number: i64, router_id: u64 };
pub const Role = enum { customer, peer, provider };
pub const role_names = [_][]const u8{ "customer", "peer", "provider" };
pub const role_symbols = "DPU";
pub const Link = struct {
    name: []const u8,
    first: usize,
    second: usize,
    peer: bool,
    delay: i64,
    mrai: i64,
    up: bool = true,
    down_count: i64 = 0,
    pub fn other(self: Link, owner: usize) usize {
        return if (owner == self.first) self.second else self.first;
    }
    pub fn role(self: Link, owner: usize) Role {
        return if (self.peer) .peer else if (owner == self.first) .customer else .provider;
    }
    pub fn direction(self: Link, owner: usize) u8 {
        return role_symbols[@intFromEnum(self.role(owner))];
    }
};
pub const Initial = struct { owner: usize, prefix: Prefix, origin: Origin, communities: Names };
pub const Topology = struct {
    ases: []const AutonomousSystem,
    links: []Link,
    initial: []const Initial,
    pub fn asIndex(self: *const Topology, number_value: i64) usize {
        for (self.ases, 0..) |owner, i| if (owner.number == number_value) return i;
        unreachable;
    }
    pub fn connecting(self: *const Topology, first: usize, second: usize) usize {
        for (self.links, 0..) |link, i| if ((link.first == first and link.second == second) or (link.first == second and link.second == first)) return i;
        unreachable;
    }
};
pub fn read(io: std.Io) !Topology {
    const lines = try readLines(io, "input/topology.txt");
    var ases: std.ArrayList(AutonomousSystem) = .empty;
    for (lines) |line| {
        const f = words(line);
        if (eq(f[0], "AS")) append(AutonomousSystem, &ases, .{ .number = number(f[1]), .router_id = addressValue(f[2]) });
    }
    std.mem.sort(AutonomousSystem, ases.items, {}, struct {
        fn less(_: void, a: AutonomousSystem, b: AutonomousSystem) bool {
            return a.number < b.number;
        }
    }.less);
    var out: Topology = .{ .ases = ases.items, .links = &.{}, .initial = &.{} };
    var links: std.ArrayList(Link) = .empty;
    var initial: std.ArrayList(Initial) = .empty;
    for (lines) |line| {
        const f = words(line);
        if (eq(f[0], "LINK")) append(Link, &links, .{ .name = f[1], .first = out.asIndex(number(f[2])),
             .second = out.asIndex(number(f[3])), .peer = eq(f[4], "P2P"), .delay = number(f[5]),
             .mrai = number(f[6]) }) else if (eq(f[0], "PREFIX")) append(Initial, &initial,
             .{ .owner = out.asIndex(number(f[1])), .prefix = parsePrefix(f[2]), .origin = parseOrigin(f[3]),
             .communities = f[4..] });
    }
    out.links = links.items;
    out.initial = initial.items;
    return out;
}
