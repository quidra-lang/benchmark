const std = @import("std");
const c = @import("network.zig");
const clock = @import("clocks.zig");
const p = @import("processes.zig");
const snap = @import("snapshot.zig");
const analysis = @import("analysis.zig");
const Compare = struct { first: []const u8, second: []const u8 };
const Params = struct {
    seed: i64 = 0,
    end: i64 = 0,
    cutcount: i64 = 0,
    compare: std.ArrayList(Compare) = .empty,
    cuts: std.ArrayList(c.Vec) = .empty,
    predicates: std.ArrayList(i64) = .empty,
};
fn parameters(io: std.Io) !Params {
    var out: Params = .{};
    for (try c.readLines(io, "input/params.txt")) |line| {
        const row = c.words(line);
        if (c.eq(row[0], "SEED")) out.seed = c.number(row[1]) else if (c.eq(row[0], "END")) out.end = c.number(row[1]) else if (c.eq(row[0], "CUTCOUNT")) out.cutcount = c.number(row[1]) else if (c.eq(row[0], "COMPARE")) c.append(Compare, &out.compare, .{ .first = row[1], .second = row[2] }) else if (c.eq(row[0], "CUT")) {
            var cut = c.zero;
            for (row[1..], 0..) |field, i| cut[i] = c.number(field);
            c.append(c.Vec, &out.cuts, cut);
        } else if (c.eq(row[0], "PREDICATE")) c.append(i64, &out.predicates, c.number(row[1]));
    }
    return out;
}
const Item = struct {
    time: i64,
    process: usize,
    creation: i64 = 0,
    packet: ?usize = null,
    action: ?p.Action = null,
    fn earlier(a: Item, b: Item) bool {
        if (a.time != b.time) return a.time < b.time;
        if (a.process != b.process) return a.process < b.process;
        return a.creation < b.creation;
    }
};
const Timeline = struct { snapshot: bool, process: usize, index: usize, time: i64 };
const Simulation = struct {
    topology: c.Topology,
    scripts: []const p.Script,
    params: Params,
    raw: bool,
    random: c.Random,
    time: i64 = 0,
    creation: i64 = 0,
    processes: []p.Process,
    events: std.ArrayList(p.Event) = .empty,
    messages: std.ArrayList(p.Message) = .empty,
    copies: std.ArrayList(p.Copy) = .empty,
    packets: std.ArrayList(p.Packet) = .empty,
    snapshots: std.ArrayList(*snap.Snapshot) = .empty,
    timeline: std.ArrayList(Timeline) = .empty,
    queue: std.ArrayList(Item) = .empty,
    fn init(topology: c.Topology, scripts: []const p.Script, params: Params, raw: bool) Simulation {
        return .{ .topology = .{ .names = topology.names, .channels = c.dupe(c.Channel, topology.channels) }, .scripts = scripts, .params = params, .raw = raw, .random = .{ .state = params.seed }, .processes = p.initialize(scripts) };
    }
    fn enqueue(self: *Simulation, value: Item) void {
        var item = value;
        self.creation += 1;
        item.creation = self.creation;
        c.append(Item, &self.queue, item);
        var index = self.queue.items.len - 1;
        while (index > 0) {
            const parent = (index - 1) / 2;
            if (!Item.earlier(item, self.queue.items[parent])) break;
            self.queue.items[index] = self.queue.items[parent];
            index = parent;
        }
        self.queue.items[index] = item;
    }
    fn dequeue(self: *Simulation) Item {
        const first = self.queue.items[0];
        const last = self.queue.pop().?;
        if (self.queue.items.len > 0) {
            var index: usize = 0;
            while (2 * index + 1 < self.queue.items.len) {
                var child = 2 * index + 1;
                if (child + 1 < self.queue.items.len and Item.earlier(self.queue.items[child + 1], self.queue.items[child])) child += 1;
                if (!Item.earlier(self.queue.items[child], last)) break;
                self.queue.items[index] = self.queue.items[child];
                index = child;
            }
            self.queue.items[index] = last;
        }
        return first;
    }
    fn record(self: *Simulation, own: usize, kind: p.EventKind, peer: ?usize, message: ?usize, copy: ?usize, label: []const u8, amount: i64) usize {
        const state = &self.processes[own];
        if (kind == .recv) {
            const sent = self.events.items[self.messages.items[self.copies.items[copy.?].message].send];
            clock.receive(&state.lamport, &state.clock, own, sent.lamport, sent.clock, self.processes.len);
        } else clock.local(&state.lamport, &state.clock, own);
        const index = self.events.items.len;
        c.append(p.Event, &self.events, .{ .process = own, .local = state.events.items.len + 1, .time = self.time, .kind = kind, .peer = peer, .message = message, .copy = copy, .lamport = state.lamport, .balance = state.balance, .amount = amount, .clock = state.clock, .label = label });
        c.append(usize, &state.events, index);
        state.counts[@intFromEnum(kind)] += 1;
        state.minimum = @min(state.minimum, state.balance);
        c.append(Timeline, &self.timeline, .{ .snapshot = false, .process = own, .index = index, .time = self.time });
        return index;
    }
    fn sendPacket(self: *Simulation, source: usize, destination: usize, copy: ?usize, snapshot: ?usize) void {
        const sent_clock = if (copy) |index| self.events.items[self.messages.items[self.copies.items[index].message].send].clock else c.zero;
        const arrival = c.dispatch(&self.topology.channels[source * self.processes.len + destination], self.time, snapshot != null, sent_clock, self.processes.len, &self.random);
        const index = self.packets.items.len;
        c.append(p.Packet, &self.packets, .{ .source = source, .destination = destination, .sequence = arrival.sequence, .dispatch = self.time, .arrival = arrival.time, .copy = copy, .snapshot = snapshot });
        if (copy) |id| self.copies.items[id].packet = index;
        self.enqueue(.{ .time = arrival.time, .process = destination, .packet = index });
    }
    fn recordSnapshot(self: *Simulation, index: usize, own: usize, reason: []const u8) void {
        const snapshot = self.snapshots.items[index];
        snap.recordState(snapshot, own, self.processes[own], self.time, reason);
        c.append(Timeline, &self.timeline, .{ .snapshot = true, .process = own, .index = index, .time = self.time });
        for (0..self.processes.len) |destination| if (destination != own) {
            self.sendPacket(own, destination, null, index);
            snapshot.channels[own * self.processes.len + destination].sent = self.time;
        };
    }
    fn initiate(self: *Simulation, own: usize, name: []const u8) void {
        var index: usize = 0;
        while (index < self.snapshots.items.len and !c.eq(self.snapshots.items[index].name, name)) : (index += 1) {}
        if (index == self.snapshots.items.len) c.append(*snap.Snapshot, &self.snapshots, snap.init(name, self.time, self.processes.len));
        if (self.snapshots.items[index].records[own].present) c.append(snap.Ignored, &self.snapshots.items[index].ignored, .{ .process = own, .time = self.time }) else self.recordSnapshot(index, own, "initiate");
    }
    fn action(self: *Simulation, own: usize, value: p.Action, sender: ?usize) void {
        if (value.kind == .local) {
            _ = self.record(own, .local, null, null, null, value.argument, 0);
            return;
        }
        if (value.kind == .snapshot) {
            self.initiate(own, value.argument);
            return;
        }
        const state = &self.processes[own];
        const broadcast = value.kind == .broadcast;
        const destination: ?usize = if (broadcast) null else if (c.eq(value.argument, "SENDER")) sender.? else self.topology.index(value.argument);
        const amount = if (value.kind == .transfer) value.amount else 0;
        if (value.kind == .transfer and amount > state.balance) {
            state.refused += 1;
            _ = self.record(own, .nofunds, destination, null, null, "", amount);
            return;
        }
        state.balance -= amount;
        state.out += amount;
        if (broadcast) state.broadcast[own] += 1;
        const message = self.messages.items.len;
        c.append(p.Message, &self.messages, .{ .source = own, .tag = if (broadcast) value.argument else if (value.kind == .transfer) "transfer" else value.tag, .amount = amount, .broadcast = broadcast, .stamp = if (broadcast) state.broadcast else c.zero });
        self.messages.items[message].send = self.record(own, if (broadcast) .bcast else .send, destination, message, null, "", 0);
        for (0..self.processes.len) |target| if (if (broadcast) target != own else target == destination.?) {
            const copy = self.copies.items.len;
            c.append(p.Copy, &self.copies, .{ .message = message, .source = own, .destination = target });
            c.append(usize, &self.messages.items[message].copies, copy);
            self.sendPacket(own, target, copy, null);
        };
    }
    fn deliver(self: *Simulation, index: usize) void {
        const copy = self.copies.items[index];
        const message = self.messages.items[copy.message];
        const state = &self.processes[copy.destination];
        if (message.broadcast) state.broadcast[copy.source] += 1;
        state.balance += message.amount;
        state.in += message.amount;
        self.copies.items[index].delivery = self.time;
        self.copies.items[index].received = self.record(copy.destination, .recv, copy.source, copy.message, index, "", 0);
        c.append(usize, &state.delivered, index);
        for (self.scripts[copy.destination].on.items) |rule| if (c.eq(rule.tag, message.tag)) self.action(copy.destination, rule.action, copy.source);
    }
    fn canDeliver(self: *const Simulation, index: usize) bool {
        const copy = self.copies.items[index];
        return clock.deliverable(self.messages.items[copy.message].stamp, self.processes[copy.destination].broadcast, copy.source, self.processes.len);
    }
    fn accept(self: *Simulation, index: usize) void {
        const packet = self.packets.items[index];
        const state = &self.processes[packet.destination];
        state.next[packet.source] += 1;
        if (packet.snapshot) |id| {
            const snapshot = self.snapshots.items[id];
            if (!snapshot.records[packet.destination].present) self.recordSnapshot(id, packet.destination, c.fmt("marker {s}", .{self.topology.names[packet.source]}));
            snap.acceptMarker(snapshot, packet.source, packet.destination, self.time, self.processes.len);
            return;
        }
        for (self.snapshots.items) |snapshot| {
            const channel = &snapshot.channels[packet.source * self.processes.len + packet.destination];
            if (snapshot.records[packet.destination].present and channel.accepted == null) c.append(usize, &channel.copies, packet.copy.?);
        }
        const copy = self.copies.items[packet.copy.?];
        const message = self.messages.items[copy.message];
        if (self.raw or !message.broadcast) {
            self.deliver(packet.copy.?);
            return;
        }
        if (self.canDeliver(packet.copy.?)) {
            self.deliver(packet.copy.?);
            while (true) {
                var ready: ?usize = null;
                for (state.hold.items, 0..) |candidate, i| if (self.canDeliver(candidate)) {
                    ready = i;
                    break;
                };
                const position = ready orelse break;
                const candidate = state.hold.orderedRemove(position);
                self.deliver(candidate);
            }
        } else {
            self.copies.items[packet.copy.?].causal_wait = true;
            self.copies.items[packet.copy.?].missing = clock.missing(message.stamp, state.broadcast, copy.source, self.processes.len);
            c.append(usize, &state.hold, packet.copy.?);
        }
    }
    fn arrival(self: *Simulation, index: usize) void {
        const packet = self.packets.items[index];
        const state = &self.processes[packet.destination];
        if (self.raw) self.accept(index) else if (packet.sequence != state.next[packet.source]) {
            c.append(usize, &state.reorder[packet.source], index);
            self.topology.channels[packet.source * self.processes.len + packet.destination].buffered += 1;
            if (packet.copy) |copy| self.copies.items[copy].fifo_wait = true;
        } else {
            self.accept(index);
            while (true) {
                const buffer = &state.reorder[packet.source];
                var ready: ?usize = null;
                for (buffer.items, 0..) |candidate, i| if (self.packets.items[candidate].sequence == state.next[packet.source]) {
                    ready = i;
                    break;
                };
                const position = ready orelse break;
                const following = buffer.orderedRemove(position);
                self.accept(following);
            }
        }
        var held = state.hold.items.len;
        for (state.reorder) |buffer| held += buffer.items.len;
        state.max_held = @max(state.max_held, held);
    }
    fn run(self: *Simulation) void {
        for (p.expand(self.scripts, self.params.end)) |scheduled| self.enqueue(.{ .time = scheduled.time, .process = scheduled.process, .action = scheduled.action });
        while (self.queue.items.len > 0 and self.queue.items[0].time <= self.params.end) {
            const item = self.dequeue();
            self.time = item.time;
            if (item.packet) |index| self.arrival(index) else self.action(item.process, item.action.?, null);
        }
    }
    fn eventName(self: *const Simulation, index: usize) []const u8 {
        const event = self.events.items[index];
        return c.fmt("{s}.{d}", .{ self.topology.names[event.process], event.local });
    }
    fn copyName(self: *const Simulation, index: usize) []const u8 {
        const copy = self.copies.items[index];
        return c.fmt("m{d}->{s}", .{ copy.message + 1, self.topology.names[copy.destination] });
    }
    fn processNames(self: *const Simulation, indices: []const usize) []const u8 {
        var out: c.Text = .{};
        for (indices, 0..) |index, i| out.add("{s}{s}", .{ if (i > 0) "," else "", self.topology.names[index] });
        return out.value();
    }
    fn initial(self: *const Simulation) i64 {
        var out: i64 = 0;
        for (self.processes) |state| out += state.initial;
        return out;
    }
    fn delivered(self: *const Simulation) usize {
        var out: usize = 0;
        for (self.copies.items) |copy| {
            if (copy.received != null) out += 1;
        }
        return out;
    }
    fn cutDetails(self: *const Simulation, cut: c.Vec) snap.Details {
        return snap.details(cut, self.processes, self.events.items, self.messages.items, self.copies.items);
    }
    fn vector(self: *const Simulation, value: c.Vec) []const u8 {
        return clock.text(value[0..self.processes.len]);
    }
};
fn yes(value: bool) []const u8 {
    return if (value) "yes" else "no";
}
fn relationName(value: i64) []const u8 {
    return if (value > 0) "->" else if (value < 0) "<-" else "||";
}
fn messageName(index: usize) []const u8 {
    return c.fmt("m{d}", .{index + 1});
}
fn save(io: std.Io, name: []const u8, lines: c.Lines) !void {
    var out: c.Text = .{};
    for (lines.data.items) |line| out.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = c.fmt("output/{s}", .{name}), .data = out.value() });
}
fn ranges(s: *const Simulation, path: []const usize) []const u8 {
    var out: c.Text = .{};
    var i: usize = 0;
    while (i < path.len) {
        var j = i;
        while (j + 1 < path.len and s.events.items[path[j + 1]].process == s.events.items[path[j]].process and s.events.items[path[j + 1]].local == s.events.items[path[j]].local + 1) : (j += 1) {}
        out.add("{s}{s}", .{ if (i > 0) " " else "", s.eventName(path[i]) });
        if (j > i) out.add("-{d}", .{s.events.items[path[j]].local});
        i = j + 1;
    }
    return out.value();
}
fn traceReport(s: *const Simulation) c.Lines {
    const types = [_][]const u8{ "LOCAL", "NOFUNDS", "SEND", "BCAST", "RECV" };
    var out: c.Lines = .{};
    for (s.events.items, 0..) |event, i| {
        var detail: c.Text = .{};
        if (event.kind == .local) detail.add("{s}", .{event.label}) else if (event.kind == .nofunds) detail.add("to {s} amount {d} balance {d}", .{ s.topology.names[event.peer.?], event.amount, event.balance }) else {
            const message = s.messages.items[event.message.?];
            detail.add("{s}", .{messageName(event.message.?)});
            if (event.kind == .send) detail.add(" to {s}", .{s.topology.names[event.peer.?]}) else if (event.kind == .recv) detail.add(" from {s}", .{s.topology.names[event.peer.?]});
            detail.add(" tag {s}", .{message.tag});
            if (c.eq(message.tag, "transfer")) detail.add(" amount {d} balance {d}", .{ message.amount, event.balance });
        }
        out.add("{d} t={d} {s} {s} {s} L={d} V={s}", .{ i + 1, event.time, s.eventName(i), types[@intFromEnum(event.kind)], detail.value(), event.lamport, s.vector(event.clock) });
    }
    out.add("SUMMARY events {d} messages {d} copies {d} delivered {d} undelivered {d} draws {d}", .{ s.events.items.len, s.messages.items.len, s.copies.items.len, s.delivered(), s.copies.items.len - s.delivered(), s.random.draws });
    for (s.processes, 0..) |state, own| out.add("FINAL {s} events {d} L={d} V={s} B={s} balance {d} in {d} out {d} refused {d} min {d}", .{ s.topology.names[own], state.events.items.len, state.lamport, s.vector(state.clock), s.vector(state.broadcast), state.balance, state.in, state.out, state.refused, state.minimum });
    for (s.processes, 0..) |state, own| out.add("COUNTS {s} local {d} nofunds {d} send {d} bcast {d} recv {d}", .{ s.topology.names[own], state.counts[0], state.counts[1], state.counts[2], state.counts[3], state.counts[4] });
    return out;
}
fn copyDetails(s: *const Simulation, index: usize) []const u8 {
    const copy = s.copies.items[index];
    const message = s.messages.items[copy.message];
    return c.fmt("m{d} from {s} {s} tag {s} sent {d}", .{ copy.message + 1, s.topology.names[copy.source], if (message.broadcast) "BCAST" else "P2P", message.tag, s.events.items[message.send].time });
}
fn broadcastList(s: *const Simulation, own: usize) []const usize {
    var out: std.ArrayList(usize) = .empty;
    for (s.processes[own].events.items) |index| {
        const event = s.events.items[index];
        if (event.kind == .bcast or (event.kind == .recv and s.messages.items[event.message.?].broadcast)) c.append(usize, &out, event.message.?);
    }
    return out.items;
}
const Tag = struct {
    name: []const u8,
    copies: i64 = 0,
    delivered: i64 = 0,
    latency: i64 = 0,
    maximum: i64 = 0,
    fn less(_: void, a: Tag, b: Tag) bool {
        return std.mem.lessThan(u8, a.name, b.name);
    }
};
fn deliveryReport(s: *const Simulation) c.Lines {
    var out: c.Lines = .{};
    const broadcasts = c.alloc([]const usize, s.processes.len);
    for (s.processes, 0..) |state, own| {
        out.add("PROCESS {s}", .{s.topology.names[own]});
        var counts = [_]i64{0} ** 4;
        var total_wait: i64 = 0;
        var max_wait: i64 = 0;
        for (state.delivered.items, 0..) |index, i| {
            const copy = s.copies.items[index];
            const packet = s.packets.items[copy.packet];
            const mode = @as(usize, @intFromBool(copy.fifo_wait)) + 2 * @as(usize, @intFromBool(copy.causal_wait));
            counts[mode] += 1;
            const wait = copy.delivery - packet.arrival;
            total_wait += wait;
            max_wait = @max(max_wait, wait);
            const mode_text = if (mode == 0) "direct" else if (mode == 1) "fifo" else c.fmt("{s} {s}", .{ if (mode == 2) "causal" else "fifo+causal", s.processNames(copy.missing) });
            out.add("{d} {s} arrived {d} delivered {d} wait {d} {s}", .{ i + 1, copyDetails(s, index), packet.arrival, copy.delivery, wait, mode_text });
        }
        for (s.copies.items, 0..) |copy, i| if (copy.destination == own and copy.received == null and s.packets.items[copy.packet].arrival <= s.params.end) out.add("HELD {s} arrived {d} {s}", .{ copyDetails(s, i), s.packets.items[copy.packet].arrival, if (copy.causal_wait) c.fmt("causal {s}", .{s.processNames(copy.missing)}) else "fifo" });
        for (s.copies.items, 0..) |copy, i| if (copy.destination == own and s.packets.items[copy.packet].arrival > s.params.end) out.add("TRANSIT {s} arrival {d}", .{ copyDetails(s, i), s.packets.items[copy.packet].arrival });
        out.add("TOTAL delivered {d} direct {d} fifo {d} causal {d} both {d} wait {d} max_wait {d} max_held {d}", .{ state.delivered.items.len, counts[0], counts[1], counts[2], counts[3], total_wait, max_wait, state.max_held });
        broadcasts[own] = broadcastList(s, own);
        var list: c.Text = .{};
        for (broadcasts[own]) |message| list.add(" m{d}", .{message + 1});
        out.add("BCASTS{s}", .{if (list.value().len == 0) " none" else list.value()});
    }
    for (0..s.processes.len) |source| for (0..s.processes.len) |destination| if (source != destination) {
        const channel = s.topology.channels[source * s.processes.len + destination];
        out.add("CHANNEL {s}->{s} {s} {s} messages {d} markers {d} buffered {d} max_delay {d} entries {d}", .{ s.topology.names[source], s.topology.names[destination], if (channel.fifo) "FIFO" else "NONFIFO", c.delayText(channel), channel.messages, channel.markers, channel.buffered, channel.max_delay, channel.entries });
    };
    var tags: std.ArrayList(Tag) = .empty;
    for (s.copies.items) |copy| {
        const message = s.messages.items[copy.message];
        var index: usize = 0;
        while (index < tags.items.len and !c.eq(tags.items[index].name, message.tag)) : (index += 1) {}
        if (index == tags.items.len) c.append(Tag, &tags, .{ .name = message.tag });
        const tag = &tags.items[index];
        tag.copies += 1;
        if (copy.received != null) {
            tag.delivered += 1;
            const latency = copy.delivery - s.events.items[message.send].time;
            tag.latency += latency;
            tag.maximum = @max(tag.maximum, latency);
        }
    }
    std.mem.sort(Tag, tags.items, {}, Tag.less);
    for (tags.items) |tag| out.add("TAG {s} copies {d} delivered {d} latency {d} max {d}", .{ tag.name, tag.copies, tag.delivered, tag.latency, tag.maximum });
    var messages: std.ArrayList(usize) = .empty;
    for (s.messages.items, 0..) |message, i| if (message.broadcast) {
        c.append(usize, &messages, i);
        var stable = true;
        var time: i64 = 0;
        for (message.copies.items) |index| {
            const copy = s.copies.items[index];
            stable = stable and copy.received != null;
            if (copy.received != null) time = @max(time, copy.delivery);
        }
        out.add("STABLE m{d} {s} tag {s} sent {d} stable {s}", .{ i + 1, s.topology.names[message.source], message.tag, s.events.items[message.send].time, if (stable) c.fmt("{d}", .{time}) else "none" });
    };
    var disagreements: i64 = 0;
    for (messages.items, 0..) |a, i| for (messages.items[i + 1 ..]) |b| {
        var earlier: std.ArrayList(usize) = .empty;
        var later: std.ArrayList(usize) = .empty;
        for (broadcasts, 0..) |list, own| {
            var x: ?usize = null;
            var y: ?usize = null;
            for (list, 0..) |message, j| {
                if (message == a) x = j;
                if (message == b) y = j;
            }
            if (x != null and y != null) {
                if (x.? < y.?) c.append(usize, &earlier, own) else c.append(usize, &later, own);
            }
        }
        if (earlier.items.len > 0 and later.items.len > 0) {
            disagreements += 1;
            out.add("DISAGREE m{d} m{d} {s} {s}", .{ a + 1, b + 1, s.processNames(earlier.items), s.processNames(later.items) });
        }
    };
    out.add("DISAGREEMENTS {d}", .{disagreements});
    return out;
}
fn verdict(s: *const Simulation, details: snap.Details) []const u8 {
    var out: c.Text = .{};
    out.add("{s}", .{yes(details.orphans.items.len == 0)});
    for (details.orphans.items) |index| out.add(" {s}", .{s.copyName(index)});
    return out.value();
}
fn snapshotReport(s: *const Simulation, raw: *const Simulation) c.Lines {
    var out: c.Lines = .{};
    const n = s.processes.len;
    for (s.snapshots.items) |snapshot| {
        out.add("SNAPSHOT {s} started {d} completed {d}", .{ snapshot.name, snapshot.start, snapshot.complete });
        var balances: i64 = 0;
        var channel_money: i64 = 0;
        var recorded: std.ArrayList(usize) = .empty;
        var pending: std.ArrayList(usize) = .empty;
        for (snapshot.records, 0..) |record, own| {
            balances += record.balance;
            var list: c.Text = .{};
            for (record.pending) |index| {
                list.add(" m{d}", .{s.copies.items[index].message + 1});
                c.append(usize, &pending, index);
            }
            out.add("RECORD {s} t={d} {s} balance {d} L={d} V={s} pending{s}", .{ s.topology.names[own], record.time, record.reason, record.balance, record.lamport, s.vector(record.clock), if (list.value().len == 0) " none" else list.value() });
        }
        for (0..n) |source| for (0..n) |destination| if (source != destination) {
            const channel = snapshot.channels[source * n + destination];
            var list: c.Text = .{};
            for (channel.copies.items) |index| {
                const message = s.messages.items[s.copies.items[index].message];
                c.append(usize, &recorded, index);
                channel_money += message.amount;
                list.add(" m{d}", .{s.copies.items[index].message + 1});
                if (message.amount > 0) list.add(":{d}", .{message.amount});
            }
            out.add("CHANNEL {s}->{s} marker {d} {d} state{s}", .{ s.topology.names[source], s.topology.names[destination], channel.sent, channel.accepted.?, if (list.value().len == 0) " empty" else list.value() });
        };
        for (snapshot.ignored.items) |ignored| out.add("IGNORED {s} t={d}", .{ s.topology.names[ignored.process], ignored.time });
        const cut = snap.cut(snapshot);
        const details = s.cutDetails(cut);
        var vector_good = true;
        for (snapshot.records) |record| {
            if (!clock.lessEqual(record.clock, cut, n)) vector_good = false;
        }
        out.add("CUT {s} consistent {s} vector {s}", .{ s.vector(cut), verdict(s, details), yes(vector_good) });
        var all: std.ArrayList(usize) = .empty;
        for (recorded.items) |index| c.append(usize, &all, index);
        for (pending.items) |index| c.append(usize, &all, index);
        const transit = c.dupe(usize, details.transit.items);
        std.mem.sort(usize, all.items, {}, std.sort.asc(usize));
        std.mem.sort(usize, transit, {}, std.sort.asc(usize));
        out.add("TRANSIT channels {d} pending {d} cut {d} match {s}", .{ recorded.items.len, pending.items.len, transit.len, yes(std.mem.eql(usize, all.items, transit)) });
        out.add("MONEY balances {d} channels {d} total {d} initial {d} conserved {s}", .{ balances, channel_money, balances + channel_money, s.initial(), yes(balances + channel_money == s.initial()) });
    }
    for (raw.snapshots.items) |snapshot| {
        const cut = snap.cut(snapshot);
        const details = raw.cutDetails(cut);
        var money: i64 = 0;
        for (snapshot.records) |record| money += record.balance;
        for (snapshot.channels) |channel| for (channel.copies.items) |index| {
            money += raw.messages.items[raw.copies.items[index].message].amount;
        };
        out.add("RAW {s} completed {d} cut {s} consistent {s} money {d} conserved {s}", .{ snapshot.name, snapshot.complete, raw.vector(cut), verdict(raw, details), money, yes(money == raw.initial()) });
    }
    return out;
}
fn findEvent(s: *const Simulation, name: []const u8) usize {
    const dot = std.mem.indexOfScalar(u8, name, '.').?;
    const own = s.topology.index(name[0..dot]);
    return s.processes[own].events.items[c.u(c.number(name[dot + 1 ..]) - 1)];
}
fn longestChain(s: *const Simulation) []const usize {
    var out: std.ArrayList(usize) = .empty;
    if (s.events.items.len == 0) return out.items;
    var current: usize = 0;
    for (s.events.items, 0..) |event, i| if (event.lamport > s.events.items[current].lamport) {
        current = i;
    };
    while (true) {
        c.append(usize, &out, current);
        const event = s.events.items[current];
        if (event.lamport <= 1) break;
        const sender: ?usize = if (event.kind == .recv) s.messages.items[s.copies.items[event.copy.?].message].send else null;
        current = if (sender != null and s.events.items[sender.?].lamport == event.lamport - 1) sender.? else s.processes[event.process].events.items[event.local - 2];
    }
    std.mem.reverse(usize, out.items);
    return out.items;
}
fn analysisReport(s: *const Simulation, raw: *const Simulation) c.Lines {
    var out: c.Lines = .{};
    const n = s.processes.len;
    const graph = analysis.graphEdges(s.events.items, s.copies.items, s.messages.items, s.processes);
    for (s.params.compare.items) |comparison| {
        const a = findEvent(s, comparison.first);
        const b = findEvent(s, comparison.second);
        const e = s.events.items[a];
        const f = s.events.items[b];
        const rel = clock.relation(e.clock, f.clock, n);
        var path = analysis.graphPath(a, b, graph);
        var graph_relation: i64 = if (path.len > 0) 1 else 0;
        if (path.len == 0) {
            path = analysis.graphPath(b, a, graph);
            if (path.len > 0) graph_relation = -1;
        }
        out.add("COMPARE {s} {s} {s} L={d},{d} graph {s} agree {s}", .{ comparison.first, relationName(rel), comparison.second, e.lamport, f.lamport, relationName(graph_relation), yes(rel == graph_relation) });
        if (path.len > 0) {
            var messages: i64 = 0;
            for (path[1..], path[0 .. path.len - 1]) |x, y| messages += @intFromBool(s.events.items[x].process != s.events.items[y].process);
            out.add("PATH length {d} messages {d} {s}", .{ path.len, messages, ranges(s, path) });
        }
        for ([_]usize{ a, b }) |index| {
            const event = s.events.items[index];
            var future = c.zero;
            for (s.events.items) |candidate| if (candidate.clock[event.process] < c.n(event.local)) {
                future[candidate.process] += 1;
            };
            out.add("WINDOW {s} past {s} future {s}", .{ s.eventName(index), s.vector(event.clock), s.vector(future) });
        }
    }
    const counts = analysis.concurrency(s.events.items, n);
    const event_count = c.n(s.events.items.len);
    out.add("CONCURRENCY events {d} pairs {d} ordered {d} concurrent {d} same_lamport {d} inversions {d}", .{ event_count, @divTrunc(event_count * (event_count - 1), 2), counts.ordered, counts.concurrent, counts.same, counts.inversions });
    for (0..n) |a| for (a + 1..n) |b| out.add("PAIR {s} {s} {d}", .{ s.topology.names[a], s.topology.names[b], counts.pairs[a][b] });
    const chain = longestChain(s);
    out.add("CHAIN length {d} {s}", .{ chain.len, ranges(s, chain) });
    const ordered = analysis.orders(s.processes, s.copies.items, s.messages.items, s.events.items);
    for (ordered.races.items) |value| {
        const a = s.copies.items[value.first];
        const b = s.copies.items[value.second];
        out.add("RACE {s} m{d} {s} m{d} {s}", .{ s.topology.names[value.process], a.message + 1, s.topology.names[a.source], b.message + 1, s.topology.names[b.source] });
    }
    out.add("RACES {d}", .{ordered.races.items.len});
    for (ordered.violations.items) |value| {
        const a = s.copies.items[value.first];
        const b = s.copies.items[value.second];
        out.add("VIOLATION {s} m{d} {s} overtook m{d} {s}", .{ s.topology.names[value.process], a.message + 1, s.topology.names[a.source], b.message + 1, s.topology.names[b.source] });
    }
    out.add("VIOLATIONS causal {d} fifo {d}", .{ ordered.violations.items.len, ordered.fifo });
    const raw_ordered = analysis.orders(raw.processes, raw.copies.items, raw.messages.items, raw.events.items);
    out.add("RAW events {d} delivered {d} causal {d} fifo {d}", .{ raw.events.items.len, raw.delivered(), raw_ordered.violations.items.len, raw_ordered.fifo });
    for (s.params.cuts.items) |cut| {
        const details = s.cutDetails(cut);
        var status: c.Text = .{};
        status.add("{s}", .{if (details.orphans.items.len == 0) "consistent" else "inconsistent orphans"});
        for (details.orphans.items) |index| status.add(" {s}", .{s.copyName(index)});
        out.add("CUT {s} {s} transit {d} money {d} initial {d}", .{ s.vector(cut), status.value(), details.transit.items.len, details.money, s.initial() });
    }
    const cuts = analysis.enumerate(s.processes, s.events.items, s.params.cutcount, s.params.predicates.items);
    out.add("CUTCOUNT t={d} events {s} product {d} consistent {d}", .{ s.params.cutcount, s.vector(cuts.limits), cuts.product, cuts.consistent });
    var levels: c.Text = .{};
    levels.add("LEVELS", .{});
    for (cuts.levels) |value| levels.add(" {d}", .{value});
    out.add("{s}", .{levels.value()});
    for (s.params.predicates.items, cuts.predicates) |threshold, predicate| out.add("PREDICATE transit>={d} cuts {d} possibly {s} definitely {s}", .{ threshold, predicate.cuts, yes(predicate.cuts > 0), yes(predicate.definite) });
    return out;
}
fn writeAt(row: *std.ArrayList(u8), position: usize, text: []const u8) void {
    while (row.items.len < position + text.len) c.append(u8, row, ' ');
    @memcpy(row.items[position .. position + text.len], text);
}
fn trimmed(row: *std.ArrayList(u8)) []const u8 {
    while (row.items.len > 0 and row.items[row.items.len - 1] == ' ') _ = row.pop();
    return row.items;
}
fn diagramHeader(s: *const Simulation, kind: u8) []const u8 {
    var row: std.ArrayList(u8) = .empty;
    writeAt(&row, 0, c.fmt("    {c}", .{kind}));
    for (s.topology.names, 0..) |name, own| writeAt(&row, 6 + 8 * own, name);
    return trimmed(&row);
}
fn diagramLine(s: *const Simulation, own: usize, value: i64, kind: p.EventKind, message: ?usize, source: ?usize, snapshot: []const u8) []const u8 {
    var row: std.ArrayList(u8) = .empty;
    writeAt(&row, 0, c.fmt("{d: >5} ", .{value}));
    for (0..s.processes.len) |index| writeAt(&row, 6 + 8 * index, "|");
    const position = 6 + 8 * own;
    if (snapshot.len > 0) {
        row.items[position] = '#';
        writeAt(&row, position + 1, snapshot);
    } else if (kind == .local) row.items[position] = '*' else if (kind == .nofunds) row.items[position] = 'x' else if (kind == .send or kind == .bcast) {
        row.items[position] = if (kind == .send) 'S' else 'B';
        writeAt(&row, position + 1, messageName(message.?));
    } else {
        row.items[position] = 'R';
        const origin = 6 + 8 * source.?;
        const first = @min(origin, position);
        const last = @max(origin, position);
        for (first + 1..last) |index| row.items[index] = if ((index - 6) % 8 == 0) '+' else '-';
        if (origin < position) row.items[last - 1] = '>' else row.items[first + 1] = '<';
        writeAt(&row, first + 2, messageName(message.?));
    }
    return trimmed(&row);
}
fn diagramReport(s: *const Simulation) c.Lines {
    var out: c.Lines = .{};
    out.add("{s}", .{diagramHeader(s, 't')});
    for (s.timeline.items) |item| {
        if (item.snapshot) out.add("{s}", .{diagramLine(s, item.process, item.time, .local, null, null, s.snapshots.items[item.index].name)}) else {
            const event = s.events.items[item.index];
            out.add("{s}", .{diagramLine(s, event.process, event.time, event.kind, event.message, event.peer, "")});
        }
    }
    out.add("{s}", .{diagramHeader(s, 'L')});
    const ordered = c.alloc(usize, s.events.items.len);
    for (ordered, 0..) |*index, i| index.* = i;
    const CompareEvents = struct {
        fn less(events: []const p.Event, a: usize, b: usize) bool {
            return if (events[a].lamport != events[b].lamport) events[a].lamport < events[b].lamport else events[a].process < events[b].process;
        }
    };
    std.mem.sort(usize, ordered, @as([]const p.Event, s.events.items), CompareEvents.less);
    for (ordered) |index| {
        const event = s.events.items[index];
        out.add("{s}", .{diagramLine(s, event.process, event.lamport, event.kind, event.message, event.peer, "")});
    }
    return out;
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    c.allocator = arena.allocator();
    const io = init.io;
    const topology = try c.load(io);
    const scripts = try p.load(io, topology);
    const params = try parameters(io);
    var main_run = Simulation.init(topology, scripts, params, false);
    var raw_run = Simulation.init(topology, scripts, params, true);
    main_run.run();
    raw_run.run();
    try std.Io.Dir.cwd().createDirPath(io, "output");
    try save(io, "trace.txt", traceReport(&main_run));
    try save(io, "deliveries.txt", deliveryReport(&main_run));
    try save(io, "snapshots.txt", snapshotReport(&main_run, &raw_run));
    try save(io, "analysis.txt", analysisReport(&main_run, &raw_run));
    try save(io, "diagram.txt", diagramReport(&main_run));
}
