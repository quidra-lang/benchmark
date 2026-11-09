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

pub const Operation = enum { noop, set, add, delete, get };
pub const Command = struct {
    kind: Operation = .noop,
    key: []const u8 = "",
    value: i64 = 0,
    pub fn same(self: Command, other: Command) bool {
        return self.kind == other.kind and eq(self.key, other.key) and self.value == other.value;
    }
};
pub fn commandText(command: Command) []const u8 {
    return switch (command.kind) {
        .noop => "NOOP",
        .set => fmt("SET {s} {d}", .{ command.key, command.value }),
        .add => fmt("ADD {s} {d}", .{ command.key, command.value }),
        .delete => fmt("DEL {s}", .{command.key}),
        .get => fmt("GET {s}", .{command.key}),
    };
}
pub const Entry = struct {
    term: i64,
    command: Command = .{},
    request: usize = 0,
    pub fn same(self: Entry, other: Entry) bool {
        return self.term == other.term and self.request == other.request and self.command.same(other.command);
    }
};
pub const Result = union(enum) { none, ok, deleted, missing, number: i64 };
pub fn resultText(result: Result) []const u8 {
    return switch (result) {
        .none => "",
        .ok => "ok",
        .deleted => "deleted",
        .missing => "missing",
        .number => |value| fmt("{d}", .{value}),
    };
}
pub const KeyValue = struct { key: []const u8, value: i64 };
pub const Store = struct {
    items: std.ArrayList(KeyValue) = .empty,
    pub fn get(self: Store, key: []const u8) ?i64 {
        for (self.items.items) |entry| if (eq(entry.key, key)) return entry.value;
        return null;
    }
    pub fn set(self: *Store, key: []const u8, value: i64) void {
        var i: usize = 0;
        while (i < self.items.items.len and std.mem.lessThan(u8, self.items.items[i].key, key)) : (i += 1) {}
        if (i < self.items.items.len and eq(self.items.items[i].key, key)) self.items.items[i].value = value else self.items.insert(allocator,
             i, .{ .key = key, .value = value }) catch @panic("allocation failed");
    }
    pub fn remove(self: *Store, key: []const u8) bool {
        for (self.items.items, 0..) |entry, i| if (eq(entry.key, key)) {
            _ = self.items.orderedRemove(i);
            return true;
        };
        return false;
    }
    pub fn clone(self: Store) Store {
        const copy = dupe(KeyValue, self.items.items);
        return .{ .items = .{ .items = copy, .capacity = copy.len } };
    }
    pub fn same(self: Store, other: Store) bool {
        if (self.items.items.len != other.items.items.len) return false;
        for (self.items.items, other.items.items) |a, b| if (!eq(a.key, b.key) or a.value != b.value) return false;
        return true;
    }
};
pub fn applyCommand(store: *Store, command: Command) Result {
    return switch (command.kind) {
        .noop => .none,
        .set => blk: {
            store.set(command.key, command.value);
            break :blk .ok;
        },
        .add => blk: {
            const value = (store.get(command.key) orelse 0) + command.value;
            store.set(command.key, value);
            break :blk .{ .number = value };
        },
        .delete => if (store.remove(command.key)) .deleted else .missing,
        .get => if (store.get(command.key)) |value| .{ .number = value } else .missing,
    };
}
pub const Role = enum { follower, candidate, leader };
pub fn roleName(role: Role) []const u8 {
    return switch (role) {
        .follower => "FOLLOWER",
        .candidate => "CANDIDATE",
        .leader => "LEADER",
    };
}
pub const Statistics = struct { elections: usize = 0, leader_terms: usize = 0, votes_granted: usize = 0,
     leader_ticks: usize = 0, ae_ok: usize = 0, ae_fail: usize = 0, appended: usize = 0, truncated: usize = 0,
     applies: usize = 0 };
pub const Node = struct {
    number: usize,
    term: i64 = 0,
    voted_for: ?usize = null,
    log: std.ArrayList(Entry) = .empty,
    up: bool = true,
    stats: Statistics = .{},
    role: Role = .follower,
    commit: usize = 0,
    applied: usize = 0,
    store: Store = .{},
    known_leader: ?usize = null,
    votes: u8 = 0,
    election_deadline: ?i64 = null,
    election_record: ?usize = null,
    next: [8]usize = [_]usize{0} ** 8,
    match: [8]usize = [_]usize{0} ** 8,
    heartbeat_deadline: ?i64 = null,
    quorum_deadline: ?i64 = null,
    heard: u8 = 0,
    transfer_target: ?usize = null,
    transfer_deadline: ?i64 = null,
    transfer_sent: bool = false,
    pub fn cancelTransfer(self: *Node) void {
        self.transfer_target = null;
        self.transfer_deadline = null;
        self.transfer_sent = false;
    }
    pub fn resetVolatile(self: *Node) void {
        self.role = .follower;
        self.commit = 0;
        self.applied = 0;
        self.store = .{};
        self.known_leader = null;
        self.votes = 0;
        self.election_deadline = null;
        self.election_record = null;
        self.next = [_]usize{0} ** 8;
        self.match = [_]usize{0} ** 8;
        self.heartbeat_deadline = null;
        self.quorum_deadline = null;
        self.heard = 0;
        self.cancelTransfer();
    }
    pub fn crash(self: *Node) void {
        self.up = false;
        self.resetVolatile();
    }
    pub fn lastIndex(self: *const Node) usize {
        return self.log.items.len;
    }
    pub fn lastTerm(self: *const Node) i64 {
        return if (self.log.items.len == 0) 0 else self.log.items[self.log.items.len - 1].term;
    }
    pub fn termAt(self: *const Node, index: usize) i64 {
        return if (index == 0) 0 else self.log.items[index - 1].term;
    }
    pub fn acceptsLog(self: *const Node, index: usize, term: i64) bool {
        const own_term = self.lastTerm();
        return term > own_term or (term == own_term and index >= self.lastIndex());
    }
};
pub fn bit(node: usize) u8 {
    return @as(u8, 1) << @intCast(node - 1);
}
pub fn nodeSet(mask: u8) []const u8 {
    var out: Text = .{};
    for (1..8) |node| if (mask & bit(node) != 0) {
        if (out.value().len > 0) out.add(",", .{});
        out.add("n{d}", .{node});
    };
    return if (out.value().len == 0) "-" else out.value();
}
pub fn nodeName(node: ?usize) []const u8 {
    return if (node) |number_value| fmt("n{d}", .{number_value}) else "-";
}
