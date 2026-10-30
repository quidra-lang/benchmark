const std = @import("std");
const r = @import("raft_node.zig");
pub const Type = enum { rv, rvr, ae, aer, tn };
pub fn typeName(kind: Type) []const u8 {
    return switch (kind) {
        .rv => "RV",
        .rvr => "RVR",
        .ae => "AE",
        .aer => "AER",
        .tn => "TN",
    };
}
pub const Message = struct { kind: Type, source: usize, destination: usize, term: i64, last_index: usize = 0,
     last_term: i64 = 0, previous: usize = 0, previous_term: i64 = 0, entries: []const r.Entry = &.{},
     commit: usize = 0, granted: bool = false, success: bool = false, confirmed: usize = 0 };
pub const Counter = enum(usize) { sent, delivered, inflight, partition, rule, loss, down };
pub const counter_names = [_][]const u8{ "sent", "delivered", "inflight", "partition", "rule", "loss", "down" };
pub const Counters = [7]i64;
pub const Drop = struct { kind: ?Type, first: i64, last: i64 };
pub const Link = struct { delay: i64 = 0, loss: i64 = 0, passed: i64 = 0, drops: std.ArrayList(Drop) = .empty,
     stats: Counters = [_]i64{0} ** 7 };
pub const Envelope = struct { arrival: i64, source: usize, serial: usize, message: Message };
fn before(a: Envelope, b: Envelope) bool {
    return a.arrival < b.arrival or (a.arrival == b.arrival and (a.source < b.source or (a.source == b.source and a.serial < b.serial)));
}
fn matches(pattern: []const u8, node: usize) bool {
    return r.eq(pattern, "*") or r.u(r.number(pattern)) == node;
}
pub const Network = struct {
    allocator: std.mem.Allocator,
    nodes: usize,
    serial: usize = 0,
    links: [8][8]Link = [_][8]Link{[_]Link{.{}} ** 8} ** 8,
    groups: [8]usize = [_]usize{0} ** 8,
    total: Counters = [_]i64{0} ** 7,
    by_type: [5]Counters = [_]Counters{[_]i64{0} ** 7} ** 5,
    queue: std.ArrayList(Envelope) = .empty,
    pub fn init(io: std.Io, nodes: usize, allocator: std.mem.Allocator) !Network {
        var out: Network = .{ .allocator = allocator, .nodes = nodes };
        const lines = try r.readLines(io, "input/network.txt");
        const delay = r.number(r.words(lines[0])[1]);
        for (1..nodes + 1) |a| for (1..nodes + 1) |b| {
            if (a != b) out.links[a][b].delay = delay;
        };
        for (lines[1..]) |line| {
            const row = r.words(line);
            for (1..nodes + 1) |a| for (1..nodes + 1) |b| {
                if (a == b or !matches(row[1], a) or !matches(row[2], b)) continue;
                const link = &out.links[a][b];
                if (r.eq(row[0], "DELAY")) link.delay = r.number(row[3]) else if (r.eq(row[0],
                     "LOSS")) link.loss = r.number(row[3]) else {
                    var kind: ?Type = null;
                    for (0..5) |i| {
                        const candidate: Type = @enumFromInt(i);
                        if (r.eq(typeName(candidate), row[3])) kind = candidate;
                    }
                    r.append(Drop, &link.drops, .{ .kind = kind, .first = r.number(row[4]), .last = r.number(row[5]) });
                }
            };
        }
        return out;
    }
    pub fn partition(self: *Network, groups: []const []const usize) void {
        for (groups, 0..) |group, i| for (group) |node| {
            self.groups[node] = i;
        };
    }
    pub fn heal(self: *Network) void {
        self.groups = [_]usize{0} ** 8;
    }
    pub fn separated(self: *const Network, first: usize, second: usize) bool {
        return self.groups[first] != self.groups[second];
    }
    pub fn count(self: *Network, message: Message, field: Counter, amount: i64) void {
        const i = @intFromEnum(field);
        self.total[i] += amount;
        self.by_type[@intFromEnum(message.kind)][i] += amount;
        self.links[message.source][message.destination].stats[i] += amount;
    }
    pub fn freeMessage(self: *Network, message: Message) void {
        self.allocator.free(message.entries);
    }
    fn push(self: *Network, value: Envelope) void {
        self.queue.append(self.allocator, value) catch @panic("allocation failed");
        var i = self.queue.items.len - 1;
        while (i > 0) {
            const parent = (i - 1) / 2;
            if (!before(value, self.queue.items[parent])) break;
            self.queue.items[i] = self.queue.items[parent];
            i = parent;
        }
        self.queue.items[i] = value;
    }
    pub fn send(self: *Network, time: i64, message: Message) void {
        self.serial += 1;
        self.count(message, .sent, 1);
        const link = &self.links[message.source][message.destination];
        if (self.separated(message.source, message.destination)) {
            self.count(message, .partition, 1);
            self.freeMessage(message);
            return;
        }
        for (link.drops.items) |drop| if ((drop.kind == null or drop.kind == message.kind) and drop.first <= time and time <= drop.last) {
            self.count(message, .rule, 1);
            self.freeMessage(message);
            return;
        };
        link.passed += 1;
        if (link.loss > 0 and @mod(link.passed, link.loss) == 0) {
            self.count(message, .loss, 1);
            self.freeMessage(message);
            return;
        }
        self.count(message, .inflight, 1);
        self.push(.{ .arrival = time + link.delay, .source = message.source, .serial = self.serial,
             .message = message });
    }
    pub fn arrival(self: *Network, time: i64) ?Message {
        if (self.queue.items.len == 0 or self.queue.items[0].arrival != time) return null;
        const message = self.queue.items[0].message;
        const value = self.queue.pop().?;
        if (self.queue.items.len > 0) {
            var i: usize = 0;
            while (2 * i + 1 < self.queue.items.len) {
                var child = 2 * i + 1;
                if (child + 1 < self.queue.items.len and before(self.queue.items[child + 1],
                     self.queue.items[child])) child += 1;
                if (!before(self.queue.items[child], value)) break;
                self.queue.items[i] = self.queue.items[child];
                i = child;
            }
            self.queue.items[i] = value;
        }
        self.count(message, .inflight, -1);
        return message;
    }
    pub fn deliver(self: *Network, message: Message, destination_up: bool) bool {
        if (!destination_up) {
            self.count(message, .down, 1);
            return false;
        }
        if (self.separated(message.source, message.destination)) {
            self.count(message, .partition, 1);
            return false;
        }
        self.count(message, .delivered, 1);
        return true;
    }
    pub fn deinit(self: *Network) void {
        for (self.queue.items) |envelope| self.freeMessage(envelope.message);
        self.queue.deinit(self.allocator);
    }
};
