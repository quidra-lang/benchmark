const std = @import("std");
const r = @import("raft_node.zig");
const cl = @import("cluster.zig");
const net = @import("network.zig");
const minstd = @import("minstd.zig");
const checks = @import("checker.zig");
const n = r.n;
const u = r.u;
const Election = struct { time: i64, node: usize, term: i64, trigger: []const u8, votes: u8, won: ?i64 = null };
const Reason = enum { active, crash, stepdown, quorum };
fn reasonName(reason: Reason) []const u8 {
    return switch (reason) {
        .active => "ACTIVE",
        .crash => "CRASH",
        .stepdown => "STEPDOWN",
        .quorum => "QUORUM",
    };
}
const Leader = struct { node: usize, elected: i64, votes: u8, appended: usize = 1, ended: ?i64 = null,
     reason: Reason = .active, commit: usize = 0 };
const Term = struct { started: i64, candidates: u8 = 0 };
const KeyCount = struct { key: []const u8, requests: usize = 0, committed: usize = 0 };
const Simulator = struct {
    input: cl.Input,
    settings: cl.Settings,
    nodes: []r.Node,
    network: net.Network,
    random: minstd.Minstd,
    work: std.mem.Allocator,
    checker: checks.Checker = .{},
    time: i64 = 0,
    trace: r.Lines = .{},
    timelines: r.Lines = .{},
    elections: std.ArrayList(Election) = .empty,
    leaders: std.AutoHashMapUnmanaged(i64, Leader) = .empty,
    terms: std.AutoHashMapUnmanaged(i64, Term) = .empty,
    gaps: std.ArrayList([2]i64) = .empty,
    gap_start: ?i64 = null,
    leader_ticks: usize = 0,
    multi_ticks: usize = 0,
    maximum_term: i64 = 0,
    committed_count: usize = 0,
    reference: r.Store = .{},
    snapshots: std.AutoHashMapUnmanaged(usize, r.Store) = .empty,
    status_counts: [5]usize = [_]usize{0} ** 5,
    latencies: std.ArrayList(i64) = .empty,
    keys: std.ArrayList(KeyCount) = .empty,
    fn init(io: std.Io, input: cl.Input, work: std.mem.Allocator) !Simulator {
        const nodes = r.alloc(r.Node, input.settings.nodes + 1);
        for (nodes, 0..) |*node, i| node.* = .{ .number = i };
        return .{ .input = input, .settings = input.settings, .nodes = nodes, .network = try net.Network.init(io,
             input.settings.nodes, work), .random = .{ .state = input.settings.seed }, .work = work };
    }
    fn log(self: *Simulator, comptime pattern: []const u8, args: anytype) void {
        self.trace.add("{d} {s}", .{ self.time, r.fmt(pattern, args) });
    }
    fn majority(self: *const Simulator, count: usize) bool {
        return 2 * count > self.settings.nodes;
    }
    fn setTimer(self: *Simulator, node: *r.Node) void {
        node.election_deadline = self.time + self.random.between(self.settings.election_min,
             self.settings.election_max);
    }
    fn message(_: *const Simulator, node: *const r.Node, destination: usize, kind: net.Type) net.Message {
        return .{ .kind = kind, .source = node.number, .destination = destination, .term = node.term };
    }
    fn sendAppend(self: *Simulator, node: *r.Node, destination: usize) void {
        var out = self.message(node, destination, .ae);
        out.previous = node.next[destination] - 1;
        out.previous_term = node.termAt(out.previous);
        const last = @min(out.previous + self.settings.batch, node.lastIndex());
        out.entries = self.work.dupe(r.Entry, node.log.items[out.previous..last]) catch @panic("allocation failed");
        out.commit = node.commit;
        self.network.send(self.time, out);
    }
    fn broadcastAppend(self: *Simulator, node: *r.Node) void {
        for (1..self.nodes.len) |other| if (other != node.number) self.sendAppend(node, other);
    }
    fn endLeadership(self: *Simulator, node: *r.Node, reason: Reason) void {
        const record = self.leaders.getPtr(node.term).?;
        record.ended = self.time;
        record.reason = reason;
        record.commit = node.commit;
        node.cancelTransfer();
    }
    fn sendTimeoutNow(self: *Simulator, node: *r.Node) void {
        const destination = node.transfer_target.?;
        self.log("TIMEOUTNOW n{d} n{d} term {d} index {d}", .{ node.number, destination, node.term, node.lastIndex() });
        node.transfer_sent = true;
        self.network.send(self.time, self.message(node, destination, .tn));
    }
    fn startTransfer(self: *Simulator, node: *r.Node, destination: usize) void {
        if (!node.up or node.role != .leader or node.transfer_target != null or node.number == destination) {
            self.log("TRANSFER n{d} n{d} ignored", .{ node.number, destination });
            return;
        }
        self.log("TRANSFER n{d} n{d} start match {d}/{d}", .{ node.number, destination, node.match[destination],
             node.lastIndex() });
        node.transfer_target = destination;
        node.transfer_sent = false;
        node.transfer_deadline = self.time + self.settings.election_min;
        if (node.match[destination] == node.lastIndex()) self.sendTimeoutNow(node) else self.sendAppend(node,
             destination);
    }
    fn control(self: *Simulator, event: cl.Control) void {
        switch (event.kind) {
            .crash => {
                const node = &self.nodes[event.first];
                self.log("CRASH n{d} {s} term {d}", .{ node.number, r.roleName(node.role), node.term });
                if (node.role == .leader) self.endLeadership(node, .crash);
                node.crash();
            },
            .restart => {
                const node = &self.nodes[event.first];
                node.up = true;
                self.setTimer(node);
                self.log("RESTART n{d} term {d} length {d} deadline {d}", .{ node.number, node.term,
                     node.lastIndex(), node.election_deadline.? });
            },
            .partition => {
                self.network.partition(event.groups);
                var text: r.Text = .{};
                text.add("PARTITION", .{});
                for (event.groups) |group| {
                    var mask: u8 = 0;
                    for (group) |node| mask |= r.bit(node);
                    text.add(" {s}", .{r.nodeSet(mask)});
                }
                self.log("{s}", .{text.value()});
            },
            .heal => {
                self.network.heal();
                self.log("HEAL", .{});
            },
            .transfer => self.startTransfer(&self.nodes[event.first], event.second),
        }
    }
    fn attempt(self: *Simulator, request: *cl.Request) void {
        request.attempts += 1;
        var destination = request.destination;
        var redirected: usize = 0;
        var reason: []const u8 = undefined;
        while (true) {
            const node = &self.nodes[destination];
            if (!node.up) {
                reason = "down";
                break;
            }
            if (node.role == .leader) {
                if (node.transfer_target != null) {
                    reason = "transfer";
                    break;
                }
                r.append(r.Entry, &node.log, .{ .term = node.term, .command = request.command,
                     .request = request.number });
                self.leaders.getPtr(node.term).?.appended += 1;
                request.accepted = .{ .index = node.lastIndex(), .term = node.term };
                request.scheduled = null;
                self.log("ACCEPT r{d} n{d} index {d} term {d}", .{ request.number, node.number,
                     node.lastIndex(), node.term });
                return;
            }
            if (node.known_leader == null or redirected >= self.settings.nodes - 1) {
                reason = "noleader";
                break;
            }
            destination = node.known_leader.?;
            self.log("REDIRECT r{d} n{d} n{d}", .{ request.number, node.number, destination });
            redirected += 1;
            request.redirects += 1;
        }
        if (request.attempts < self.settings.attempts) {
            request.destination = destination % self.settings.nodes + 1;
            request.scheduled = self.time + self.settings.retry;
            self.log("REJECT r{d} n{d} {s} retry n{d} at {d}", .{ request.number, destination,
                 reason, request.destination, request.scheduled.? });
        } else {
            request.abandoned = true;
            request.scheduled = null;
            self.log("REJECT r{d} n{d} {s} giveup", .{ request.number, destination, reason });
        }
    }
    fn startElection(self: *Simulator, node: *r.Node, trigger: []const u8) void {
        node.term += 1;
        node.role = .candidate;
        node.voted_for = node.number;
        node.votes = r.bit(node.number);
        node.known_leader = null;
        self.setTimer(node);
        node.stats.elections += 1;
        node.election_record = self.elections.items.len;
        r.append(Election, &self.elections, .{ .time = self.time, .node = node.number, .term = node.term,
             .trigger = trigger, .votes = node.votes });
        const term = self.terms.getOrPut(r.allocator, node.term) catch @panic("allocation failed");
        if (!term.found_existing) term.value_ptr.* = .{ .started = self.time };
        term.value_ptr.candidates |= r.bit(node.number);
        self.log("ELECTION n{d} term {d} last {d}/{d} deadline {d}", .{ node.number, node.term,
             node.lastIndex(), node.lastTerm(), node.election_deadline.? });
        for (1..self.nodes.len) |other| if (other != node.number) {
            var out = self.message(node, other, .rv);
            out.last_index = node.lastIndex();
            out.last_term = node.lastTerm();
            self.network.send(self.time, out);
        };
    }
    fn becomeLeader(self: *Simulator, node: *r.Node) void {
        node.role = .leader;
        node.known_leader = node.number;
        for (1..self.nodes.len) |other| if (other != node.number) {
            node.next[other] = node.lastIndex() + 1;
            node.match[other] = 0;
        };
        r.append(r.Entry, &node.log, .{ .term = node.term });
        node.stats.leader_terms += 1;
        self.elections.items[node.election_record.?].won = self.time;
        self.checker.leader(node);
        self.leaders.put(r.allocator, node.term, .{ .node = node.number, .elected = self.time,
             .votes = node.votes }) catch @panic("allocation failed");
        self.log("LEADER n{d} term {d} votes {s} noop {d}", .{ node.number, node.term, r.nodeSet(node.votes),
             node.lastIndex() });
        self.broadcastAppend(node);
        node.heartbeat_deadline = self.time + self.settings.heartbeat;
        node.quorum_deadline = self.time + self.settings.quorum;
        node.heard = 0;
    }
    fn voteRequest(self: *Simulator, node: *r.Node, incoming: net.Message) void {
        const reason: ?[]const u8 = if (incoming.term < node.term) "term" else if (node.voted_for != null and node.voted_for != incoming.source) "voted" else if (!node.acceptsLog(incoming.last_index,
             incoming.last_term)) "log" else null;
        if (reason) |why| self.log("DENY n{d} n{d} term {d} {s}", .{ node.number, incoming.source,
             node.term, why }) else {
            node.voted_for = incoming.source;
            node.stats.votes_granted += 1;
            self.setTimer(node);
            self.log("VOTE n{d} n{d} term {d} deadline {d}", .{ node.number, incoming.source,
                 node.term, node.election_deadline.? });
        }
        var out = self.message(node, incoming.source, .rvr);
        out.granted = reason == null;
        self.network.send(self.time, out);
    }
    fn voteResponse(self: *Simulator, node: *r.Node, incoming: net.Message) void {
        if (node.role != .candidate or incoming.term != node.term or !incoming.granted) return;
        node.votes |= r.bit(incoming.source);
        self.elections.items[node.election_record.?].votes = node.votes;
        if (self.majority(@popCount(node.votes))) self.becomeLeader(node);
    }
    fn truncate(self: *Simulator, node: *r.Node, first: usize) void {
        const removed = node.log.items[first - 1 ..];
        node.stats.truncated += removed.len;
        self.checker.truncate(first, removed);
        self.log("TRUNCATE n{d} from {d} removed {d}", .{ node.number, first, removed.len });
        node.log.items.len = first - 1;
    }
    fn advanceCommit(self: *Simulator, node: *r.Node, index: usize) void {
        for (node.commit + 1..index + 1) |k| self.checker.commit(k, node.termAt(k), self.time);
        node.commit = index;
        const first = node.applied + 1;
        for (first..index + 1) |k| {
            const entry = node.log.items[k - 1];
            const result = r.applyCommand(&node.store, entry.command);
            node.stats.applies += 1;
            self.checker.apply(k, entry, result);
        }
        node.applied = index;
        self.log("APPLY n{d} {d}-{d}", .{ node.number, first, index });
    }
    fn checkCommit(self: *Simulator, node: *r.Node) void {
        var index = node.lastIndex();
        while (index > node.commit) : (index -= 1) {
            if (node.termAt(index) != node.term) return;
            var count: usize = 1;
            for (1..self.nodes.len) |other| if (other != node.number and node.match[other] >= index) {
                count += 1;
            };
            if (self.majority(count)) {
                self.log("COMMIT n{d} {d}-{d} term {d}", .{ node.number, node.commit + 1, index, node.term });
                self.advanceCommit(node, index);
                return;
            }
        }
    }
    fn appendRequest(self: *Simulator, node: *r.Node, incoming: net.Message) void {
        var out = self.message(node, incoming.source, .aer);
        if (incoming.term < node.term) {
            self.network.send(self.time, out);
            return;
        }
        if (node.role == .candidate) {
            node.role = .follower;
            self.log("YIELD n{d} term {d} n{d}", .{ node.number, node.term, incoming.source });
        }
        node.known_leader = incoming.source;
        self.setTimer(node);
        const previous = incoming.previous;
        if (previous > node.lastIndex() or node.termAt(previous) != incoming.previous_term) {
            node.stats.ae_fail += 1;
            out.confirmed = if (previous > node.lastIndex()) node.lastIndex() else previous - 1;
            self.network.send(self.time, out);
            return;
        }
        node.stats.ae_ok += 1;
        for (incoming.entries, previous + 1..) |entry, index| {
            if (index <= node.lastIndex() and node.termAt(index) != entry.term) self.truncate(node, index);
            if (index > node.lastIndex()) {
                r.append(r.Entry, &node.log, entry);
                node.stats.appended += 1;
            }
        }
        const confirmed = previous + incoming.entries.len;
        const commit = @min(incoming.commit, confirmed);
        if (commit > node.commit) self.advanceCommit(node, commit);
        out.success = true;
        out.confirmed = confirmed;
        self.network.send(self.time, out);
    }
    fn appendResponse(self: *Simulator, node: *r.Node, incoming: net.Message) void {
        if (node.role != .leader or incoming.term != node.term) return;
        const source = incoming.source;
        node.heard |= r.bit(source);
        if (incoming.success) {
            node.match[source] = @max(node.match[source], incoming.confirmed);
            node.next[source] = @max(node.next[source], incoming.confirmed + 1);
            self.checkCommit(node);
            if (node.transfer_target == source and !node.transfer_sent and node.match[source] == node.lastIndex()) self.sendTimeoutNow(node) else if (node.next[source] <= node.lastIndex()) self.sendAppend(node,
                 source);
        } else {
            node.next[source] = @max(node.match[source] + 1, @min(node.next[source] - 1, incoming.confirmed + 1));
            self.log("BACKTRACK n{d} n{d} next {d}", .{ node.number, source, node.next[source] });
            self.sendAppend(node, source);
        }
    }
    fn receive(self: *Simulator, incoming: net.Message) void {
        const node = &self.nodes[incoming.destination];
        if (incoming.term > node.term) {
            const previous = node.role;
            self.log("TERM n{d} {d}->{d} {s} n{d} {s}", .{ node.number, node.term, incoming.term,
                 net.typeName(incoming.kind), incoming.source, r.roleName(previous) });
            if (previous == .leader) self.endLeadership(node, .stepdown);
            node.term = incoming.term;
            node.voted_for = null;
            node.known_leader = null;
            node.role = .follower;
            if (previous == .leader) self.setTimer(node);
        }
        switch (incoming.kind) {
            .rv => self.voteRequest(node, incoming),
            .rvr => self.voteResponse(node, incoming),
            .ae => self.appendRequest(node, incoming),
            .aer => self.appendResponse(node, incoming),
            .tn => {
                if (incoming.term != node.term or node.role != .follower) self.log("IGNORE n{d} TN n{d} term {d}",
                     .{ node.number, incoming.source, incoming.term }) else self.startElection(node,
                     "transfer");
            },
        }
    }
    fn timers(self: *Simulator, node: *r.Node) void {
        if (node.role == .leader) {
            if (node.quorum_deadline == self.time) {
                if (!self.majority(1 + @as(usize, @popCount(node.heard)))) {
                    self.log("STEPDOWN n{d} term {d} heard {s}", .{ node.number, node.term, r.nodeSet(node.heard) });
                    self.endLeadership(node, .quorum);
                    node.role = .follower;
                    node.known_leader = null;
                    self.setTimer(node);
                    return;
                }
                node.heard = 0;
                node.quorum_deadline = self.time + self.settings.quorum;
            }
            if (node.transfer_target != null and node.transfer_deadline == self.time) {
                self.log("TRANSFER n{d} n{d} abort", .{ node.number, node.transfer_target.? });
                node.cancelTransfer();
            }
            if (node.heartbeat_deadline == self.time) {
                self.broadcastAppend(node);
                node.heartbeat_deadline = self.time + self.settings.heartbeat;
            }
        } else if (node.election_deadline == self.time) self.startElection(node, "timeout");
    }
    fn endTick(self: *Simulator) void {
        self.checker.checkLogs(self.nodes);
        var count: usize = 0;
        for (self.nodes[1..]) |*node| if (node.up and node.role == .leader) {
            node.stats.leader_ticks += 1;
            count += 1;
        };
        if (count > 0) {
            self.leader_ticks += 1;
            self.multi_ticks += @intFromBool(count >= 2);
            if (self.gap_start) |first| {
                r.append([2]i64, &self.gaps, .{ first, self.time - 1 });
                self.gap_start = null;
            }
        } else if (self.gap_start == null) self.gap_start = self.time;
        if (@mod(self.time, self.settings.sample) == 0) {
            var text: r.Text = .{};
            text.add("TIMELINE {d}", .{self.time});
            for (self.nodes[1..]) |node| text.add(" {c}{d}", .{ if (node.up) r.roleName(node.role)[0] else @as(u8,
                 'D'), node.term });
            self.timelines.add("{s}", .{text.value()});
        }
    }
    fn keyIndex(self: *Simulator, key: []const u8) usize {
        var index: usize = 0;
        while (index < self.keys.items.len and std.mem.lessThan(u8, self.keys.items[index].key, key)) : (index += 1) {}
        if (index < self.keys.items.len and r.eq(self.keys.items[index].key, key)) return index;
        self.keys.insert(r.allocator, index, .{ .key = key }) catch @panic("allocation failed");
        return index;
    }
    fn finishStatistics(self: *Simulator) void {
        for (self.nodes[1..]) |node| self.maximum_term = @max(self.maximum_term, node.term);
        self.committed_count = self.checker.committed.count();
        self.snapshots.put(r.allocator, 0, .{}) catch @panic("allocation failed");
        for (1..self.committed_count + 1) |index| {
            _ = r.applyCommand(&self.reference, self.checker.applied.get(index).?.entry.command);
            var needed = false;
            for (self.nodes[1..]) |node| if (node.applied == index) {
                needed = true;
            };
            if (needed) self.snapshots.put(r.allocator, index, self.reference.clone()) catch @panic("allocation failed");
        }
        for (self.input.requests) |*request| {
            const key = self.keyIndex(request.command.key);
            self.keys.items[key].requests += 1;
            if (request.accepted) |accepted| {
                const committed = self.checker.committed.get(accepted.index);
                if (committed != null and committed.?.term == accepted.term) {
                    request.status = .committed;
                    request.latency = committed.?.time - request.time;
                    request.result = self.checker.applied.get(accepted.index).?.result;
                    r.append(i64, &self.latencies, request.latency);
                    self.keys.items[key].committed += 1;
                } else {
                    var retained = false;
                    for (self.nodes[1..]) |node| if (node.lastIndex() >= accepted.index and node.termAt(accepted.index) == accepted.term) {
                        retained = true;
                    };
                    request.status = if (retained) .uncommitted else .lost;
                }
            } else request.status = if (request.abandoned) .failed else .waiting;
            self.status_counts[@intFromEnum(request.status)] += 1;
        }
    }
    fn leaderLines(self: *const Simulator) r.Lines {
        var out: r.Lines = .{};
        for (self.elections.items) |record| out.add("ELECTION {d} n{d} term {d} trigger {s} votes {d} {s}",
             .{ record.time, record.node, record.term, record.trigger, @popCount(record.votes),
             if (record.won) |time| r.fmt("WON {d}", .{time}) else "LOST" });
        var term: i64 = 1;
        while (term <= self.maximum_term) : (term += 1) {
            const meta = self.terms.get(term);
            const candidates = if (meta) |value| value.candidates else 0;
            if (self.leaders.get(term)) |record| {
                const started = meta.?.started;
                const commit = if (record.ended == null) self.nodes[record.node].commit else record.commit;
                out.add("TERM {d} LEADER n{d} elected {d} votes {s} ended {s} {s} appended {d} commit {d} candidates {s} started {d} wait {d}",
                     .{ term, record.node, record.elected, r.nodeSet(record.votes), if (record.ended) |time| r.fmt("{d}",
                     .{time}) else "-", reasonName(record.reason), record.appended, commit,
                     r.nodeSet(candidates), started, record.elected - started });
            } else out.add("TERM {d} NONE candidates {s}", .{ term, r.nodeSet(candidates) });
        }
        for (self.nodes[1..]) |node| {
            const s = node.stats;
            out.add("NODE n{d} elections {d} leader_terms {d} leader_ticks {d} votes_granted {d}",
                 .{ node.number, s.elections, s.leader_terms, s.leader_ticks, s.votes_granted });
        }
        out.extend(self.timelines);
        var longest: i64 = 0;
        for (self.gaps.items) |gap| {
            const length = gap[1] - gap[0] + 1;
            longest = @max(longest, length);
            out.add("GAP {d}-{d} length {d}", .{ gap[0], gap[1], length });
        }
        out.add("SUMMARY terms {d} leaders {d} elections {d} leader_ticks {d} multi_ticks {d} ticks {d} gaps {d} longest {d}",
             .{ self.maximum_term, self.leaders.count(), self.elections.items.len, self.leader_ticks,
             self.multi_ticks, self.settings.end + 1, self.gaps.items.len, longest });
        return out;
    }
    fn logLines(self: *const Simulator) r.Lines {
        var out: r.Lines = .{};
        for (self.nodes[1..]) |node| {
            out.add("NODE n{d} {s} term {d} voted {s} commit {d} applied {d} length {d}", .{ node.number,
                 if (node.up) r.roleName(node.role) else "DOWN", node.term, r.nodeName(node.voted_for),
                 node.commit, node.applied, node.lastIndex() });
            for (node.log.items, 1..) |entry, index| {
                var text: r.Text = .{};
                text.add("{d} {d} {s}", .{ index, entry.term, r.commandText(entry.command) });
                if (entry.request != 0) text.add(" r{d}", .{entry.request});
                out.add("{s}", .{text.value()});
            }
        }
        var limit = self.nodes[1].lastIndex();
        for (self.nodes[2..]) |node| limit = @min(limit, node.lastIndex());
        var prefix: usize = 0;
        for (0..limit) |i| {
            var agree = true;
            for (self.nodes[2..]) |node| if (!node.log.items[i].same(self.nodes[1].log.items[i])) {
                agree = false;
            };
            if (!agree) break;
            prefix = i + 1;
        }
        out.add("AGREE prefix {d} committed {d}", .{ prefix, self.committed_count });
        for (self.nodes[1..]) |node| {
            var common: usize = 0;
            for (1..@min(node.lastIndex(), self.committed_count) + 1) |index| {
                if (node.termAt(index) != self.checker.committed.get(index).?.term) break;
                common = index;
            }
            const s = node.stats;
            out.add("DIFF n{d} common {d} behind {d} extra {d} ae_ok {d} ae_fail {d} appended {d} truncated {d} applies {d}",
                 .{ node.number, common, self.committed_count - common, node.lastIndex() - common,
                 s.ae_ok, s.ae_fail, s.appended, s.truncated, s.applies });
        }
        return out;
    }
    fn stateLines(self: *const Simulator) r.Lines {
        var out: r.Lines = .{};
        for (self.nodes[1..]) |node| {
            out.add("NODE n{d} {s} applied {d} keys {d} replay {s}", .{ node.number, if (node.up) "UP" else "DOWN",
                 node.applied, node.store.items.items.len, if (node.store.same(self.snapshots.get(node.applied).?)) "match" else "mismatch" });
            for (node.store.items.items) |entry| out.add("{s} {d}", .{ entry.key, entry.value });
        }
        for (self.input.requests) |request| {
            var text: r.Text = .{};
            text.add("REQUEST r{d} at {d} n{d} {s} attempts {d} redirects {d} {s}", .{ request.number,
                 request.time, request.initial_destination, r.commandText(request.command),
                 request.attempts, request.redirects, cl.statusName(request.status) });
            if (request.accepted) |accepted| {
                text.add(" index {d} term {d}", .{ accepted.index, accepted.term });
                if (request.status == .committed) text.add(" latency {d} result {s}", .{ request.latency,
                     r.resultText(request.result) });
            } else if (request.status == .waiting) text.add(" next {d}", .{request.scheduled.?});
            out.add("{s}", .{text.value()});
        }
        for (self.keys.items) |key| out.add("KEY {s} requests {d} committed {d} final {s}",
             .{ key.key, key.requests, key.committed, if (self.reference.get(key.key)) |value| r.fmt("{d}",
             .{value}) else "missing" });
        out.add("REQUESTS total {d} committed {d} uncommitted {d} lost {d} failed {d} waiting {d}",
             .{ self.input.requests.len, self.status_counts[0], self.status_counts[1], self.status_counts[2],
             self.status_counts[3], self.status_counts[4] });
        var total: i64 = 0;
        var minimum: i64 = 0;
        var maximum: i64 = 0;
        for (self.latencies.items, 0..) |latency, i| {
            total += latency;
            if (i == 0 or latency < minimum) minimum = latency;
            if (i == 0 or latency > maximum) maximum = latency;
        }
        out.add("LATENCY count {d} total {d} min {d} max {d}", .{ self.latencies.items.len, total, minimum, maximum });
        return out;
    }
    fn appendCounters(_: *const Simulator, out: *r.Lines, prefix: []const u8, counters: net.Counters) void {
        var text: r.Text = .{};
        text.add("{s}", .{prefix});
        for (net.counter_names, counters) |name, value| text.add(" {s} {d}", .{ name, value });
        out.add("{s}", .{text.value()});
    }
    fn safetyLines(self: *const Simulator) r.Lines {
        var out = self.checker.lines(self.maximum_term);
        self.appendCounters(&out, "MESSAGES", self.network.total);
        for (0..5) |i| {
            const kind: net.Type = @enumFromInt(i);
            self.appendCounters(&out, r.fmt("TYPE {s}", .{net.typeName(kind)}), self.network.by_type[i]);
        }
        for (1..self.nodes.len) |a| for (1..self.nodes.len) |b| {
            if (a == b) continue;
            const link = self.network.links[a][b];
            var dropped: i64 = 0;
            for (link.stats[3..]) |value| dropped += value;
            out.add("LINK n{d}->n{d} delay {d} loss {d} sent {d} delivered {d} dropped {d}",
                 .{ a, b, link.delay, link.loss, link.stats[0], link.stats[1], dropped });
        };
        out.add("DRAWS {d}", .{self.random.draws});
        var unsafe = false;
        for (self.checker.violations) |count| if (count != 0) {
            unsafe = true;
        };
        out.add("RESULT {s}", .{if (unsafe) "UNSAFE" else "SAFE"});
        return out;
    }
    fn save(_: *const Simulator, io: std.Io, name: []const u8, lines: r.Lines) !void {
        var text: r.Text = .{};
        for (lines.data.items) |line| text.add("{s}\n", .{line});
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = r.fmt("output/{s}", .{name}), .data = text.value() });
    }
    fn run(self: *Simulator, io: std.Io) !void {
        for (self.nodes[1..]) |*node| {
            self.setTimer(node);
            self.log("START n{d} deadline {d}", .{ node.number, node.election_deadline.? });
        }
        self.time = 0;
        while (self.time <= self.settings.end) : (self.time += 1) {
            for (self.input.controls) |event| if (event.time == self.time) self.control(event);
            for (self.input.requests) |*request| if (request.scheduled == self.time) self.attempt(request);
            while (self.network.arrival(self.time)) |incoming| {
                defer self.network.freeMessage(incoming);
                if (self.network.deliver(incoming, self.nodes[incoming.destination].up)) self.receive(incoming);
            }
            for (self.nodes[1..]) |*node| if (node.up) self.timers(node);
            self.endTick();
        }
        if (self.gap_start) |first| r.append([2]i64, &self.gaps, .{ first, self.settings.end });
        self.finishStatistics();
        try std.Io.Dir.cwd().createDirPath(io, "output");
        try self.save(io, "trace.txt", self.trace);
        try self.save(io, "leaders.txt", self.leaderLines());
        try self.save(io, "logs.txt", self.logLines());
        try self.save(io, "state.txt", self.stateLines());
        try self.save(io, "safety.txt", self.safetyLines());
    }
};
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    r.allocator = arena.allocator();
    var simulation = try Simulator.init(init.io, try cl.readInputs(init.io), init.gpa);
    defer simulation.network.deinit();
    try simulation.run(init.io);
}
