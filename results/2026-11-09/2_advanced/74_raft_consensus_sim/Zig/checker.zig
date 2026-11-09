const std = @import("std");
const r = @import("raft_node.zig");
pub const Commit = struct { term: i64, time: i64 };
pub const Applied = struct { entry: r.Entry, result: r.Result };
pub const Checker = struct {
    violations: [5]usize = [_]usize{0} ** 5,
    leaders: std.AutoHashMapUnmanaged(i64, usize) = .empty,
    committed: std.AutoHashMapUnmanaged(usize, Commit) = .empty,
    applied: std.AutoHashMapUnmanaged(usize, Applied) = .empty,
    elected: usize = 0,
    log_checks: usize = 0,
    pair_checks: usize = 0,
    applies: usize = 0,
    truncations: usize = 0,
    removed: usize = 0,
    pub fn leader(self: *Checker, node: *const r.Node) void {
        self.elected += 1;
        if (self.leaders.get(node.term)) |old| {
            if (old != node.number) self.violations[0] += 1;
        } else self.leaders.put(r.allocator, node.term, node.number) catch @panic("allocation failed");
        var records = self.committed.iterator();
        while (records.next()) |record| {
            if (record.key_ptr.* > node.lastIndex() or node.termAt(record.key_ptr.*) != record.value_ptr.term) {
                self.violations[1] += 1;
                break;
            }
        }
    }
    pub fn commit(self: *Checker, index: usize, term: i64, time: i64) void {
        if (!self.committed.contains(index)) self.committed.put(r.allocator, index, .{ .term = term,
             .time = time }) catch @panic("allocation failed");
    }
    pub fn apply(self: *Checker, index: usize, entry: r.Entry, result: r.Result) void {
        self.applies += 1;
        if (self.applied.get(index)) |old| {
            if (!old.entry.same(entry)) self.violations[3] += 1;
        } else self.applied.put(r.allocator, index, .{ .entry = entry, .result = result }) catch @panic("allocation failed");
    }
    pub fn truncate(self: *Checker, first: usize, entries: []const r.Entry) void {
        self.truncations += 1;
        self.removed += entries.len;
        for (entries, first..) |entry, index| if (self.committed.get(index)) |old| {
            if (old.term == entry.term) self.violations[4] += 1;
        };
    }
    pub fn checkLogs(self: *Checker, nodes: []const r.Node) void {
        self.log_checks += 1;
        for (1..nodes.len) |a| for (a + 1..nodes.len) |b| {
            self.pair_checks += 1;
            const limit = @min(nodes[a].lastIndex(), nodes[b].lastIndex());
            var greatest: usize = 0;
            var k = limit;
            while (k > 0) : (k -= 1) {
                if (nodes[a].termAt(k) == nodes[b].termAt(k)) {
                    greatest = k;
                    break;
                }
            }
            for (nodes[a].log.items[0..greatest], nodes[b].log.items[0..greatest]) |left, right| if (!left.same(right)) {
                self.violations[2] += 1;
                break;
            };
        };
    }
    pub fn lines(self: *const Checker, maximum_term: i64) r.Lines {
        const names = [_][]const u8{ "ELECTION_SAFETY", "LEADER_COMPLETENESS", "LOG_MATCHING",
             "STATE_MACHINE_SAFETY", "COMMITTED_KEPT" };
        const details = [_][]const u8{ r.fmt("terms {d} leaders {d} elected {d}", .{ maximum_term,
             self.leaders.count(), self.elected }), r.fmt("checks {d} committed {d}", .{ self.elected,
             self.committed.count() }), r.fmt("checks {d} pairs {d}", .{ self.log_checks, self.pair_checks }),
             r.fmt("applies {d} indices {d}", .{ self.applies, self.applied.count() }), r.fmt("truncations {d} removed {d}",
             .{ self.truncations, self.removed }) };
        var out: r.Lines = .{};
        for (names, self.violations, details) |name, count, detail| out.add("{s} {s} violations {d} {s}",
             .{ name, if (count == 0) "OK" else "FAIL", count, detail });
        return out;
    }
};
