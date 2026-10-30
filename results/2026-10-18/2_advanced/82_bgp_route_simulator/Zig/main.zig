const std = @import("std");
const t = @import("topology.zig");
const p = @import("policy.zig");
const d = @import("decision.zig");
const sim = @import("simulator.zig");
const report = @import("report.zig");
const Session = struct { owner: usize, link: usize, incoming: []?*const d.Attribute, outgoing: []?*const d.Attribute,
     pending: []bool, timer: ?i64 = null, sent: i64 = 0, received: i64 = 0 };
const Router = struct { origination: []?d.Route, rib: []?d.Route, sessions: []const usize, changes: i64 = 0 };
const BestLine = struct { time: i64, owner: usize, prefix: usize, route: ?d.Route };
const Divergence = struct { first: i64, repeat: i64, cycle: []const BestLine };
const Period = struct { number: usize, event: sim.Event, convergence_time: i64 = 0, updates: i64 = 0,
     withdrawals: i64 = 0, drops: i64 = 0, best_changes: i64 = 0, routes_changed: i64 = 0,
     max_exploration: i64 = 0, delivery_times: i64 = 0, exploration: []i64, best_lines: std.ArrayList(BestLine) = .empty,
     divergence: ?Divergence = null, status: []const u8 = "" };
const Hop = struct { owner: usize, prefix: usize, link: ?usize };
const Forwarding = struct {
    result: enum { delivered, unreachable_result, blackhole, loop },
    visits: [51]usize = @splat(0),
    visit_count: usize = 0,
    hops: [51]Hop = undefined,
    hop_count: usize = 0,
    count: usize = 0,
    arrival: ?usize = null,
    fn path(self: *const Forwarding) []const usize {
        return self.visits[0..self.visit_count];
    }
};
const result_names = [_][]const u8{ "DELIVERED", "UNREACHABLE", "BLACKHOLE", "LOOP" };
const Loop = struct {
    nodes: [50]usize = @splat(0),
    count: usize = 0,
    fn same(self: Loop, other: Loop) bool {
        return self.count == other.count and std.mem.eql(usize, self.nodes[0..self.count], other.nodes[0..other.count]);
    }
};
const Loops = struct { items: [25]Loop = undefined, count: usize = 0 };
const TraceRecord = struct { index: usize, result: @FieldType(Forwarding, "result"), visits: [51]usize,
     visit_count: usize, start: i64, end: ?i64 = null };
const RingRecord = struct { prefix: usize, path: Loop, start: i64, end: ?i64 = null };
fn collapseRuns(path: []const usize, out: []usize) []const usize {
    var length: usize = 0;
    for (path) |owner| if (length == 0 or out[length - 1] != owner) {
        out[length] = owner;
        length += 1;
    };
    return out[0..length];
}
fn valleyPosition(pattern: []const u8) usize {
    var position: usize = 0;
    while (position < pattern.len and pattern[position] == 'U') : (position += 1) {}
    if (position < pattern.len and pattern[position] == 'P') position += 1;
    while (position < pattern.len and pattern[position] == 'D') : (position += 1) {}
    return position;
}
fn endText(end: ?i64) []const u8 {
    return if (end) |time| t.fmt("{d}", .{time}) else "END";
}
const Simulation = struct {
    network: t.Topology,
    policies: p.Policies,
    params: sim.Params,
    events: []const sim.Event,
    prefixes: []const t.Prefix,
    routers: []Router,
    sessions: []Session,
    by_session: [50][100]?usize = @splat(@splat(null)),
    messages: sim.MessageQueue = .{},
    time: i64 = 0,
    logs: t.Lines = .{},
    periods: std.ArrayList(*Period) = .empty,
    period: *Period = undefined,
    changed: []bool,
    trace_records: std.ArrayList(TraceRecord) = .empty,
    ongoing_traces: [20]?usize = @splat(null),
    ring_records: std.ArrayList(RingRecord) = .empty,
    ongoing_rings: std.ArrayList(usize) = .empty,
    fn read(io: std.Io) !Simulation {
        const network = try t.read(io);
        const policies = try p.read(io, &network);
        const events = try sim.readEvents(io);
        const params = try sim.readParams(io, &network);
        var prefixes: std.ArrayList(t.Prefix) = .empty;
        for (network.initial) |initial| t.append(t.Prefix, &prefixes, initial.prefix);
        for (events) |event| if (t.eq(event.kind, "ANNOUNCE") or t.eq(event.kind, "WITHDRAW")) t.append(t.Prefix,
             &prefixes, t.parsePrefix(event.fields[2]));
        std.mem.sort(t.Prefix, prefixes.items, {}, t.prefixLess);
        var length: usize = 0;
        for (prefixes.items) |prefix| if (length == 0 or !prefixes.items[length - 1].same(prefix)) {
            prefixes.items[length] = prefix;
            length += 1;
        };
        prefixes.items.len = length;
        const routers = t.alloc(Router, network.ases.len);
        var sessions: std.ArrayList(Session) = .empty;
        var by_session: [50][100]?usize = @splat(@splat(null));
        for (routers, 0..) |*router, owner| {
            var local: std.ArrayList(usize) = .empty;
            for (network.links, 0..) |link, index| if (link.first == owner or link.second == owner) {
                const session = sessions.items.len;
                by_session[owner][index] = session;
                t.append(usize, &local, session);
                t.append(Session, &sessions, .{ .owner = owner, .link = index, .incoming = t.zero(?*const d.Attribute,
                     length, null), .outgoing = t.zero(?*const d.Attribute, length, null),
                     .pending = t.zero(bool, length, false) });
            };
            router.* = .{ .origination = t.zero(?d.Route, length, null), .rib = t.zero(?d.Route,
                 length, null), .sessions = local.items };
        }
        return .{ .network = network, .policies = policies, .params = params, .events = events,
             .prefixes = prefixes.items, .routers = routers, .sessions = sessions.items, .by_session = by_session,
             .changed = t.zero(bool, length, false) };
    }
    fn prefixIndex(self: *const Simulation, prefix: t.Prefix) usize {
        for (self.prefixes, 0..) |other, index| if (other.same(prefix)) return index;
        unreachable;
    }
    fn log(self: *Simulation, comptime pattern: []const u8, args: anytype) void {
        self.logs.add("{d} {s}", .{ self.time, t.fmt(pattern, args) });
    }
    fn messageText(self: *const Simulation, message: sim.Message) []const u8 {
        return t.fmt("#{d} {d}->{d} {s} {s}", .{ message.serial, self.network.ases[message.sender].number,
             self.network.ases[message.receiver].number, self.network.links[message.link].name,
             self.prefixes[message.prefix].text() });
    }
    fn importRoute(self: *Simulation, session: *const Session, prefix: usize, attribute: *const d.Attribute) struct { route: ?d.Route,
         rule: ?usize } {
        const link = self.network.links[session.link];
        const rule_index = self.policies.applied(.import_route, session.owner, link, self.prefixes[prefix],
             attribute.path, attribute.communities);
        const rule = if (rule_index) |index| &self.policies.rules[index] else null;
        if (rule) |r| if (r.has(.deny)) return .{ .route = null, .rule = rule_index };
        const default = self.params.defaults[@intFromEnum(link.role(session.owner))];
        const edited = p.editCommunities(attribute.communities, rule);
        defer edited.deinit();
        const med = if (rule) |r| r.value(.med, attribute.med) else attribute.med;
        const local_pref = if (rule) |r| r.value(.local_pref, default) else default;
        return .{ .route = .{ .attribute = d.intern(attribute.path, attribute.origin, med,
             edited.values), .local_pref = local_pref, .link = session.link }, .rule = rule_index };
    }
    fn candidates(self: *Simulation, owner: usize, prefix: usize, out: *[100]d.Route) []const d.Route {
        var count: usize = 0;
        for (self.routers[owner].sessions) |index| {
            const session = &self.sessions[index];
            if (session.incoming[prefix]) |attribute| if (self.importRoute(session, prefix, attribute).route) |route| {
                out[count] = route;
                count += 1;
            };
        }
        return out[0..count];
    }
    fn advertised(self: *Simulation, session: *const Session, prefix: usize) struct { attribute: ?*const d.Attribute,
         rule: ?usize } {
        const route = self.routers[session.owner].rib[prefix] orelse return .{ .attribute = null, .rule = null };
        const link = self.network.links[session.link];
        const attribute = route.attribute;
        if ((!route.local() and route.neighbor() == link.other(session.owner)) or std.mem.indexOfScalar(u32,
             attribute.communities, p.no_export) != null) return .{ .attribute = null, .rule = null };
        const rule_index = self.policies.applied(.export_route, session.owner, link, self.prefixes[prefix],
             attribute.path, attribute.communities);
        const rule = if (rule_index) |index| &self.policies.rules[index] else null;
        if (rule) |r| if (r.has(.deny)) return .{ .attribute = null, .rule = rule_index };
        const allowed = if (rule) |r| r.has(.allow) else false;
        if (!allowed and !route.local() and self.network.links[route.link.?].role(session.owner) != .customer and link.role(session.owner) != .customer) return .{ .attribute = null,
             .rule = rule_index };
        const prepend: usize = t.u(1 + (if (rule) |r| r.value(.prepend, 0) else 0));
        var path: [550]usize = undefined;
        @memset(path[0..prepend], session.owner);
        @memcpy(path[prepend .. prepend + attribute.path.len], attribute.path);
        const edited = p.editCommunities(attribute.communities, rule);
        defer edited.deinit();
        const med = if (rule) |r| r.value(.med, 0) else 0;
        return .{ .attribute = d.intern(path[0 .. prepend + attribute.path.len], attribute.origin,
             med, edited.values), .rule = rule_index };
    }
    fn redecide(self: *Simulation, owner: usize, prefix: usize) void {
        const router = &self.routers[owner];
        var route = router.origination[prefix];
        if (route == null) {
            var storage: [100]d.Route = undefined;
            const routes = self.candidates(owner, prefix, &storage);
            if (routes.len > 0) route = d.bestRoute(routes, &self.network).route;
        }
        if (d.equal(router.rib[prefix], route)) return;
        router.rib[prefix] = route;
        router.changes += 1;
        self.log("BEST {d} {s} {s}", .{ self.network.ases[owner].number, self.prefixes[prefix].text(),
             report.routeText(route, &self.network) });
        self.period.best_changes += 1;
        const index = owner * self.prefixes.len + prefix;
        self.period.exploration[index] += 1;
        self.period.max_exploration = @max(self.period.max_exploration, self.period.exploration[index]);
        t.append(BestLine, &self.period.best_lines, .{ .time = self.time, .owner = owner, .prefix = prefix,
             .route = route });
        self.changed[prefix] = true;
        for (router.sessions) |session_index| {
            const session = &self.sessions[session_index];
            if (!self.network.links[session.link].up) continue;
            session.pending[prefix] = true;
            if (session.timer == null) self.processPending(session_index);
        }
    }
    fn processPending(self: *Simulation, index: usize) void {
        const session = &self.sessions[index];
        var sent: usize = 0;
        for (session.pending, 0..) |pending, prefix| {
            if (!pending) continue;
            const advertised_value = self.advertised(session, prefix);
            const content = advertised_value.attribute;
            if (session.outgoing[prefix] == content) continue;
            session.outgoing[prefix] = content;
            const message = self.messages.send(self.time, session.owner, self.network.links[session.link].other(session.owner),
                 session.link, prefix, content, &self.network);
            self.log("SEND {s} {s}", .{ self.messageText(message), if (content) |attribute| t.fmt("ANNOUNCE {s}",
                 .{report.attributeText(attribute, &self.network)}) else "WITHDRAW" });
            session.sent += 1;
            sent += 1;
            self.period.updates += 1;
            if (content == null) self.period.withdrawals += 1;
            if (advertised_value.rule) |rule| self.policies.rules[rule].hits += 1;
        }
        @memset(session.pending, false);
        const mrai = self.network.links[session.link].mrai;
        session.timer = if (sent > 0 and mrai >= 1) self.time + mrai else null;
    }
    fn receive(self: *Simulation, message: sim.Message) void {
        const session = &self.sessions[self.by_session[message.receiver][message.link].?];
        const prefix = message.prefix;
        session.received += 1;
        self.period.convergence_time = self.time - self.period.event.time;
        var result: []const u8 = undefined;
        if (message.content) |attribute| {
            if (std.mem.indexOfScalar(usize, attribute.path, message.receiver) != null) {
                session.incoming[prefix] = null;
                result = "ANNOUNCE loop";
            } else {
                session.incoming[prefix] = attribute;
                const evaluated = self.importRoute(session, prefix, attribute);
                if (evaluated.rule) |rule| self.policies.rules[rule].hits += 1;
                if (evaluated.route == null) result = t.fmt("ANNOUNCE deny {s}", .{self.policies.rules[evaluated.rule.?].name}) else if (evaluated.rule) |rule| result = t.fmt("ANNOUNCE accept {s}",
                     .{self.policies.rules[rule].name}) else result = "ANNOUNCE accept";
            }
        } else {
            session.incoming[prefix] = null;
            result = "WITHDRAW";
        }
        self.log("RECV {s} {s}", .{ self.messageText(message), result });
        self.redecide(message.receiver, prefix);
    }
    fn originate(self: *Simulation, owner: usize, prefix: usize, origin: t.Origin, communities: t.Names) void {
        self.routers[owner].origination[prefix] = .{ .attribute = d.intern(&.{}, origin, 0,
             p.parseCommunities(communities)) };
        self.redecide(owner, prefix);
    }
    fn linkDown(self: *Simulation, index: usize) void {
        const link = &self.network.links[index];
        link.up = false;
        link.down_count += 1;
        const dropped = self.messages.removeLink(index);
        defer sim.work_allocator.free(dropped);
        for (dropped) |message| {
            self.log("DROP {s}", .{self.messageText(message)});
            self.period.drops += 1;
        }
        const owners = [2]usize{ @min(link.first, link.second), @max(link.first, link.second) };
        var remembered: [2][100]bool = @splat(@splat(false));
        for (owners, 0..) |owner, side| {
            const session = &self.sessions[self.by_session[owner][index].?];
            for (session.incoming, 0..) |attribute, prefix| remembered[side][prefix] = attribute != null;
            @memset(session.incoming, null);
            @memset(session.outgoing, null);
            @memset(session.pending, false);
            session.timer = null;
        }
        for (owners, 0..) |owner, side| for (remembered[side][0..self.prefixes.len], 0..) |present,
             prefix| if (present) self.redecide(owner, prefix);
    }
    fn linkUp(self: *Simulation, index: usize) void {
        const link = &self.network.links[index];
        link.up = true;
        const owners = [2]usize{ @min(link.first, link.second), @max(link.first, link.second) };
        for (owners) |owner| {
            const session_index = self.by_session[owner][index].?;
            const session = &self.sessions[session_index];
            for (self.routers[owner].rib, session.pending) |route, *pending| pending.* = route != null;
            self.processPending(session_index);
        }
    }
    fn changePolicy(self: *Simulation, index: usize, active: bool) void {
        const rule = &self.policies.rules[index];
        rule.active = active;
        const owner = rule.owner;
        if (rule.direction == .import_route) {
            var prefixes: [100]bool = @splat(false);
            for (self.routers[owner].sessions) |session_index| for (self.sessions[session_index].incoming,
                 0..) |attribute, prefix| if (attribute != null) {
                prefixes[prefix] = true;
            };
            for (prefixes[0..self.prefixes.len], 0..) |present, prefix| if (present) self.redecide(owner, prefix);
        } else for (self.routers[owner].sessions) |session_index| {
            const session = &self.sessions[session_index];
            if (!self.network.links[session.link].up) continue;
            for (self.routers[owner].rib, session.outgoing, session.pending) |route, attribute,
                 *pending| pending.* = pending.* or route != null or attribute != null;
            if (session.timer == null) self.processPending(session_index);
        };
    }
    fn executeEvent(self: *Simulation, event: sim.Event) void {
        self.log("EVENT {d} {s}", .{ self.period.number, event.text });
        const f = event.fields;
        if (t.eq(event.kind, "INITIAL")) for (self.network.initial) |initial| {
            self.originate(initial.owner, self.prefixIndex(initial.prefix), initial.origin, initial.communities);
        } else if (t.eq(event.kind, "ANNOUNCE")) self.originate(self.network.asIndex(t.number(f[1])),
             self.prefixIndex(t.parsePrefix(f[2])), t.parseOrigin(f[3]), f[4..]) else if (t.eq(event.kind,
             "WITHDRAW")) {
            const owner = self.network.asIndex(t.number(f[1]));
            const prefix = self.prefixIndex(t.parsePrefix(f[2]));
            self.routers[owner].origination[prefix] = null;
            self.redecide(owner, prefix);
        } else if (t.eq(event.kind, "LINK_DOWN")) self.linkDown(t.indexOf(self.network.links,
             f[2])) else if (t.eq(event.kind, "LINK_UP")) self.linkUp(t.indexOf(self.network.links,
             f[2])) else self.changePolicy(t.indexOf(self.policies.rules, f[2]), t.eq(event.kind,
             "POLICY_ON"));
    }
    fn quiet(self: *const Simulation) bool {
        if (self.messages.nextTime() != null) return false;
        for (self.sessions) |session| for (session.pending) |pending| if (pending) return false;
        return true;
    }
    fn stateBytes(self: *const Simulation, session_states: *std.StringHashMapUnmanaged(u64),
         state_allocator: std.mem.Allocator) []u8 {
        const allocator = d.work_allocator;
        var out: std.ArrayList(u8) = .empty;
        var session_key: std.ArrayList(u8) = .empty;
        defer session_key.deinit(allocator);
        for (self.sessions) |session| {
            session_key.clearRetainingCapacity();
            for (session.incoming) |attribute| d.writeNumber(&session_key, allocator, if (attribute) |a| a.id else 0);
            for (session.outgoing) |attribute| d.writeNumber(&session_key, allocator, if (attribute) |a| a.id else 0);
            for (session.pending) |pending| session_key.append(allocator, @intFromBool(pending)) catch @panic("allocation failed");
            const identity = session_states.get(session_key.items) orelse identity: {
                const id: u64 = session_states.count() + 1;
                const copy = state_allocator.dupe(u8, session_key.items) catch @panic("allocation failed");
                session_states.put(state_allocator, copy, id) catch @panic("allocation failed");
                break :identity id;
            };
            d.writeNumber(&out, allocator, identity);
            d.writeNumber(&out, allocator, if (session.timer) |timer| @intCast(timer - self.time + 1) else 0);
        }
        const ordered = self.messages.ordered();
        defer sim.work_allocator.free(ordered);
        d.writeNumber(&out, allocator, ordered.len);
        for (ordered) |message| {
            d.writeNumber(&out, allocator, @intCast(message.arrival - self.time));
            d.writeNumber(&out, allocator, message.receiver);
            d.writeNumber(&out, allocator, message.sender);
            d.writeNumber(&out, allocator, message.link);
            d.writeNumber(&out, allocator, message.prefix);
            d.writeNumber(&out, allocator, if (message.content) |a| a.id else 0);
        }
        return out.toOwnedSlice(allocator) catch @panic("allocation failed");
    }
    fn detectDivergence(self: *Simulation, states: *std.StringHashMapUnmanaged(i64), session_states: *std.StringHashMapUnmanaged(u64),
         allocator: std.mem.Allocator) void {
        if (self.period.divergence != null or self.period.delivery_times > self.params.stepcap) return;
        const state = self.stateBytes(session_states, allocator);
        defer d.work_allocator.free(state);
        if (states.get(state)) |first| {
            var cycle: std.ArrayList(BestLine) = .empty;
            for (self.period.best_lines.items) |line| if (first < line.time and line.time <= self.time) t.append(BestLine,
                 &cycle, line);
            self.period.divergence = .{ .first = first, .repeat = self.time, .cycle = cycle.items };
        } else {
            const copy = allocator.dupe(u8, state) catch @panic("allocation failed");
            states.put(allocator, copy, self.time) catch @panic("allocation failed");
        }
    }
    fn runPeriod(self: *Simulation, number: usize, event: sim.Event, boundary: ?i64, work_allocator: std.mem.Allocator) void {
        var state_arena: std.heap.ArenaAllocator = .init(work_allocator);
        defer state_arena.deinit();
        var states: std.StringHashMapUnmanaged(i64) = .empty;
        var session_states: std.StringHashMapUnmanaged(u64) = .empty;
        const pair_count = self.routers.len * self.prefixes.len;
        const before = work_allocator.alloc(?d.Route, pair_count) catch @panic("allocation failed");
        defer work_allocator.free(before);
        for (self.routers, 0..) |router, owner| @memcpy(before[owner * self.prefixes.len .. (owner + 1) * self.prefixes.len],
             router.rib);
        self.period = t.create(Period, .{ .number = number, .event = event, .exploration = t.zero(i64,
             pair_count, 0) });
        t.append(*Period, &self.periods, self.period);
        self.time = event.time;
        @memset(self.changed, false);
        self.executeEvent(event);
        while (true) {
            var delivered = false;
            while (self.messages.nextTime() == self.time) {
                self.receive(self.messages.take());
                delivered = true;
            }
            for (self.sessions, 0..) |*session, index| if (session.timer == self.time) {
                session.timer = null;
                if (std.mem.indexOfScalar(bool, session.pending, true) != null) self.processPending(index);
            };
            if (std.mem.indexOfScalar(bool, self.changed, true) != null) self.forwardingChecks();
            if (delivered) {
                self.period.delivery_times += 1;
                self.detectDivergence(&states, &session_states, state_arena.allocator());
            }
            if (boundary) |end| {
                if (self.time == end) break;
            } else if (self.quiet() or self.period.divergence != null or self.period.delivery_times >= self.params.stepcap) break;
            var next: i64 = if (boundary) |end| end else std.math.maxInt(i64);
            if (self.messages.nextTime()) |time| next = @min(next, time);
            for (self.sessions) |session| if (session.timer) |time| {
                next = @min(next, time);
            };
            self.time = next;
            @memset(self.changed, false);
        }
        self.period.status = if (self.period.divergence != null) "DIVERGENT" else if (self.quiet()) "CONVERGED" else if (boundary == null) "CAPPED" else "UNSETTLED";
        for (self.routers, 0..) |router, owner| for (router.rib, 0..) |route, prefix| if (!d.equal(route,
             before[owner * self.prefixes.len + prefix])) {
            self.period.routes_changed += 1;
        };
    }

    fn trace(self: *const Simulation, source: usize, address: u64) Forwarding {
        var out: Forwarding = .{ .result = .unreachable_result };
        out.visits[0] = source;
        out.visit_count = 1;
        var visited: [50]bool = @splat(false);
        visited[source] = true;
        var owner = source;
        while (true) {
            var match: ?usize = null;
            for (self.routers[owner].rib, self.prefixes, 0..) |route, prefix, index| if (route != null and prefix.contains(address) and (match == null or prefix.length > self.prefixes[match.?].length)) {
                match = index;
            };
            if (match == null) {
                out.result = if (out.hop_count == 0) .unreachable_result else .blackhole;
                return out;
            }
            const prefix = match.?;
            const route = self.routers[owner].rib[prefix].?;
            out.hops[out.hop_count] = .{ .owner = owner, .prefix = prefix, .link = route.link };
            out.hop_count += 1;
            if (route.local()) {
                out.result = .delivered;
                out.arrival = owner;
                return out;
            }
            out.count += 1;
            owner = self.network.links[route.link.?].other(owner);
            out.visits[out.visit_count] = owner;
            out.visit_count += 1;
            if (visited[owner]) {
                out.result = .loop;
                return out;
            }
            visited[owner] = true;
        }
    }
    fn prefixLoops(self: *const Simulation, prefix: usize) Loops {
        var arrows: [50]?usize = @splat(null);
        for (self.routers, 0..) |router, owner| if (router.rib[prefix]) |route| if (!route.local()) {
            arrows[owner] = self.network.links[route.link.?].other(owner);
        };
        var finished: [50]bool = @splat(false);
        var out: Loops = .{};
        for (0..self.routers.len) |start| {
            if (finished[start]) continue;
            var path: [50]usize = undefined;
            var length: usize = 0;
            var positions: [50]?usize = @splat(null);
            var current = start;
            while (arrows[current] != null and !finished[current] and positions[current] == null) {
                positions[current] = length;
                path[length] = current;
                length += 1;
                current = arrows[current].?;
            }
            if (positions[current]) |first| {
                const cycle = path[first..length];
                var smallest: usize = 0;
                for (cycle, 0..) |owner, index| if (owner < cycle[smallest]) {
                    smallest = index;
                };
                var loop: Loop = .{ .count = cycle.len };
                for (0..cycle.len) |index| loop.nodes[index] = cycle[(smallest + index) % cycle.len];
                out.items[out.count] = loop;
                out.count += 1;
            }
            for (path[0..length]) |owner| finished[owner] = true;
        }
        std.mem.sort(Loop, out.items[0..out.count], {}, struct {
            fn less(_: void, a: Loop, b: Loop) bool {
                return a.nodes[0] < b.nodes[0];
            }
        }.less);
        return out;
    }
    fn forwardingChecks(self: *Simulation) void {
        for (self.changed, 0..) |changed, prefix| {
            if (!changed) continue;
            const loops = self.prefixLoops(prefix);
            var position: usize = 0;
            while (position < self.ongoing_rings.items.len) {
                const index = self.ongoing_rings.items[position];
                const record = &self.ring_records.items[index];
                if (record.prefix != prefix) {
                    position += 1;
                    continue;
                }
                var found = false;
                for (loops.items[0..loops.count]) |loop| found = found or record.path.same(loop);
                if (!found) {
                    record.end = self.time;
                    _ = self.ongoing_rings.orderedRemove(position);
                } else position += 1;
            }
            for (loops.items[0..loops.count]) |loop| {
                var ongoing = false;
                for (self.ongoing_rings.items) |index| {
                    const record = self.ring_records.items[index];
                    ongoing = ongoing or (record.prefix == prefix and record.path.same(loop));
                }
                if (!ongoing) {
                    t.append(usize, &self.ongoing_rings, self.ring_records.items.len);
                    t.append(RingRecord, &self.ring_records, .{ .prefix = prefix, .path = loop, .start = self.time });
                }
            }
        }
        for (self.params.traces, 0..) |spec, index| {
            const path = self.trace(spec.source, spec.value);
            const bad = path.result == .loop or path.result == .blackhole;
            if (self.ongoing_traces[index]) |record_index| {
                const record = &self.trace_records.items[record_index];
                if (!bad or record.result != path.result or !std.mem.eql(usize, record.visits[0..record.visit_count],
                     path.path())) {
                    record.end = self.time;
                    self.ongoing_traces[index] = null;
                }
            }
            if (bad and self.ongoing_traces[index] == null) {
                self.ongoing_traces[index] = self.trace_records.items.len;
                t.append(TraceRecord, &self.trace_records, .{ .index = index, .result = path.result,
                     .visits = path.visits, .visit_count = path.visit_count, .start = self.time });
            }
        }
    }
    fn ribLines(self: *Simulation) t.Lines {
        var out: t.Lines = .{};
        for (self.routers, 0..) |router, owner| {
            var routes: usize = 0;
            var local: usize = 0;
            var sent: i64 = 0;
            var received: i64 = 0;
            for (router.rib) |route| if (route) |r| {
                routes += 1;
                local += @intFromBool(r.local());
            };
            for (router.sessions) |index| {
                sent += self.sessions[index].sent;
                received += self.sessions[index].received;
            }
            out.add("AS {d} routes {d} local {d} sent {d} received {d} changes {d}", .{ self.network.ases[owner].number,
                 routes, local, sent, received, router.changes });
            for (router.sessions) |index| {
                const session = &self.sessions[index];
                const link = self.network.links[session.link];
                var incoming: usize = 0;
                var accepted: usize = 0;
                var outgoing: usize = 0;
                for (session.incoming, 0..) |attribute, prefix| if (attribute) |a| {
                    incoming += 1;
                    accepted += @intFromBool(self.importRoute(session, prefix, a).route != null);
                };
                for (session.outgoing) |attribute| outgoing += @intFromBool(attribute != null);
                out.add("SESSION {s} {d} {s} {s} in {d} accepted {d} out {d} sent {d} received {d} flaps {d}",
                     .{ link.name, self.network.ases[link.other(owner)].number, t.role_names[@intFromEnum(link.role(owner))],
                     if (link.up) "UP" else "DOWN", incoming, accepted, outgoing, session.sent,
                     session.received, link.down_count });
            }
            for (router.rib, 0..) |maybe_route, prefix| if (maybe_route) |route| {
                var storage: [100]d.Route = undefined;
                const routes_candidates = self.candidates(owner, prefix, &storage);
                if (route.local()) out.add("{s} {s} candidates {d}", .{ self.prefixes[prefix].text(),
                     report.routeText(route, &self.network), routes_candidates.len }) else out.add("{s} {s} candidates {d} reason {s}",
                     .{ self.prefixes[prefix].text(), report.routeText(route, &self.network),
                     routes_candidates.len, d.bestRoute(routes_candidates, &self.network).reason });
                var remaining: [100]d.Route = undefined;
                var count: usize = 0;
                for (routes_candidates) |candidate| if (!d.equal(candidate, route)) {
                    remaining[count] = candidate;
                    count += 1;
                };
                while (count > 0) {
                    const alternate = d.bestRoute(remaining[0..count], &self.network).route;
                    out.add("ALT {s}", .{report.routeText(alternate, &self.network)});
                    var position: usize = 0;
                    while (!d.equal(remaining[position], alternate)) position += 1;
                    std.mem.copyForwards(d.Route, remaining[position .. count - 1], remaining[position + 1 .. count]);
                    count -= 1;
                }
            };
        }
        return out;
    }
    fn traceLines(self: *const Simulation, out: *t.Lines, spec: sim.Trace) void {
        const path = self.trace(spec.source, spec.value);
        out.add("TRACE {d} {s} {s} hops {d}", .{ self.network.ases[spec.source].number, spec.address,
             result_names[@intFromEnum(path.result)], path.count });
        for (path.hops[0..path.hop_count]) |hop| {
            const owner = self.network.ases[hop.owner].number;
            if (hop.link) |index| {
                const link = self.network.links[index];
                out.add("HOP {d} {s} next {d} link {s}", .{ owner, self.prefixes[hop.prefix].text(),
                     self.network.ases[link.other(hop.owner)].number, link.name });
            } else out.add("HOP {d} {s} LOCAL", .{ owner, self.prefixes[hop.prefix].text() });
        }
        const last = self.network.ases[path.visits[path.visit_count - 1]].number;
        if (path.result == .loop) out.add("HOP {d} REVISIT", .{last}) else if (path.result != .delivered) out.add("HOP {d} NOROUTE",
             .{last});
        if (path.hop_count == 0) out.add("CONTROL NONE", .{}) else {
            const route = self.routers[spec.source].rib[path.hops[0].prefix].?;
            var collapsed: [550]usize = undefined;
            const control = collapseRuns(route.attribute.path, &collapsed);
            const matches = path.result == .delivered and std.mem.eql(usize, control, path.path()[1..]);
            out.add("CONTROL {s} {s}", .{ if (route.local()) "LOCAL" else report.pathText(route.attribute.path,
                 &self.network), if (matches) "MATCH" else "MISMATCH" });
        }
        if (path.count > 0) {
            var pattern: [50]u8 = undefined;
            var count: usize = 0;
            for (path.hops[0..path.hop_count]) |hop| if (hop.link) |link| {
                pattern[count] = self.network.links[link].direction(hop.owner);
                count += 1;
            };
            out.add("PATTERN {s} {s}", .{ pattern[0..count], if (valleyPosition(pattern[0..count]) == count) "VALLEYFREE" else "VALLEY" });
        }
    }
    fn pathLines(self: *const Simulation) t.Lines {
        var out: t.Lines = .{};
        for (self.params.traces) |spec| self.traceLines(&out, spec);
        var originated: [100]bool = @splat(false);
        for (self.routers) |router| for (router.origination, 0..) |route, prefix| if (route != null) {
            originated[prefix] = true;
        };
        var names: std.ArrayList([]const u8) = .empty;
        for (originated[0..self.prefixes.len], 0..) |present, prefix| if (present) t.append([]const u8,
             &names, self.prefixes[prefix].text());
        if (names.items.len > 0) out.add("PREFIXES {s}", .{t.join(names.items, ",")}) else out.add("PREFIXES", .{});
        for (0..self.routers.len) |source| {
            var symbols: t.Text = .{};
            for (originated[0..self.prefixes.len], 0..) |present, prefix| if (present) {
                const path = self.trace(source, self.prefixes[prefix].address);
                const symbol: u8 = switch (path.result) {
                    .delivered => if (path.count == 0) '*' else if (self.routers[path.arrival.?].origination[prefix] != null) '+' else 'X',

                    .loop => 'L',
                    .blackhole => 'B',
                    .unreachable_result => 'U',
                };
                symbols.add("{c}", .{symbol});
            };
            if (symbols.value().len > 0) out.add("REACH {d} {s}", .{ self.network.ases[source].number,
                 symbols.value() }) else out.add("REACH {d}", .{self.network.ases[source].number});
        }
        return out;
    }
    fn auditLines(self: *const Simulation) t.Lines {
        var out: t.Lines = .{};
        var loop_count: usize = 0;
        var blackholes: usize = 0;
        const traces = t.dupe(TraceRecord, self.trace_records.items);
        std.mem.sort(TraceRecord, traces, {}, struct {
            fn less(_: void, a: TraceRecord, b: TraceRecord) bool {
                return if (a.start == b.start) a.index < b.index else a.start < b.start;
            }
        }.less);
        for (traces) |record| {
            const spec = self.params.traces[record.index];
            const visits = record.visits[0..record.visit_count];
            if (record.result == .loop) {
                loop_count += 1;
                out.add("LOOP {d} {s} from {d} to {s} path {s}", .{ self.network.ases[spec.source].number,
                     spec.address, record.start, endText(record.end), report.pathText(visits,
                     &self.network) });
            } else {
                blackholes += 1;
                out.add("BLACKHOLE {d} {s} from {d} to {s} at {d} path {s}", .{ self.network.ases[spec.source].number,
                     spec.address, record.start, endText(record.end), self.network.ases[visits[visits.len - 1]].number,
                     report.pathText(visits, &self.network) });
            }
        }
        const rings = t.dupe(RingRecord, self.ring_records.items);
        std.mem.sort(RingRecord, rings, {}, struct {
            fn less(_: void, a: RingRecord, b: RingRecord) bool {
                if (a.start != b.start) return a.start < b.start;
                if (a.prefix != b.prefix) return a.prefix < b.prefix;
                return a.path.nodes[0] < b.path.nodes[0];
            }
        }.less);
        for (rings) |record| out.add("RING {s} from {d} to {s} path {s}", .{ self.prefixes[record.prefix].text(),
             record.start, endText(record.end), report.pathText(record.path.nodes[0..record.path.count],
             &self.network) });
        var routes: usize = 0;
        var valleys: usize = 0;
        for (self.routers, 0..) |router, owner| for (router.rib, 0..) |maybe_route, prefix| if (maybe_route) |route| {
            if (route.local()) continue;
            routes += 1;
            var all: [551]usize = undefined;
            all[0] = owner;
            @memcpy(all[1 .. route.attribute.path.len + 1], route.attribute.path);
            var collapsed: [551]usize = undefined;
            const path = collapseRuns(all[0 .. route.attribute.path.len + 1], &collapsed);
            var pattern: [50]u8 = undefined;
            for (0..path.len - 1) |index| pattern[index] = self.network.links[self.network.connecting(path[index],
                 path[index + 1])].direction(path[index]);
            const symbols = pattern[0 .. path.len - 1];
            const position = valleyPosition(symbols);
            if (position != symbols.len) {
                valleys += 1;
                out.add("VALLEY {d} {s} path {s} pattern {s} leaker {d}", .{ self.network.ases[owner].number,
                     self.prefixes[prefix].text(), report.pathText(route.attribute.path, &self.network),
                     symbols, self.network.ases[path[position]].number });
            }
        };
        for (self.policies.rules) |rule| out.add("RULE {s} {s} {s} hits {d}", .{ rule.name,
             p.direction_names[@intFromEnum(rule.direction)], if (rule.active) "ON" else "OFF",
             rule.hits });
        var divergent: usize = 0;
        for (self.periods.items) |period| if (period.divergence) |divergence| {
            divergent += 1;
            out.add("DIVERGENT event {d} first {d} repeat {d} period {d}", .{ period.number,
                 divergence.first, divergence.repeat, divergence.repeat - divergence.first });
            const oscillations = t.zero(i64, self.routers.len * self.prefixes.len, 0);
            for (divergence.cycle) |line| {
                out.add("CYCLE {d} {d} {s} {s}", .{ line.time, self.network.ases[line.owner].number,
                     self.prefixes[line.prefix].text(), report.routeText(line.route, &self.network) });
                oscillations[line.owner * self.prefixes.len + line.prefix] += 1;
            }
            for (0..self.routers.len) |owner| for (0..self.prefixes.len) |prefix| {
                const count = oscillations[owner * self.prefixes.len + prefix];
                if (count > 0) out.add("OSCILLATE {d} {s} changes {d}", .{ self.network.ases[owner].number,
                     self.prefixes[prefix].text(), count });
            };
        };
        out.add("SUMMARY loops {d} blackholes {d} rings {d} routes {d} valleys {d} divergent {d} end {d}",
             .{ loop_count, blackholes, rings.len, routes, valleys, divergent, self.time });
        return out;
    }
    fn convergenceLines(self: *const Simulation) t.Lines {
        var out: t.Lines = .{};
        out.add("event,time,kind,status,convergence_time,updates,withdrawals,drops,best_changes,routes_changed,max_exploration",
             .{});
        for (self.periods.items) |period| out.add("{d},{d},{s},{s},{d},{d},{d},{d},{d},{d},{d}",
             .{ period.number, period.event.time, period.event.kind, period.status, period.convergence_time,
             period.updates, period.withdrawals, period.drops, period.best_changes, period.routes_changed,
             period.max_exploration });
        return out;
    }
    fn run(self: *Simulation, io: std.Io, work_allocator: std.mem.Allocator) !void {
        for (self.events, 0..) |event, number| self.runPeriod(number, event, if (number + 1 < self.events.len) self.events[number + 1].time - 1 else null,
             work_allocator);
        try report.write(io, "updates.txt", self.logs);
        try report.write(io, "convergence.csv", self.convergenceLines());
        try report.write(io, "ribs.txt", self.ribLines());
        try report.write(io, "paths.txt", self.pathLines());
        try report.write(io, "audit.txt", self.auditLines());
    }
};
pub fn main(init: std.process.Init) !void {
    var arena: std.heap.ArenaAllocator = .init(init.gpa);
    defer arena.deinit();
    t.allocator = arena.allocator();
    d.work_allocator = init.gpa;
    p.work_allocator = init.gpa;
    sim.work_allocator = init.gpa;
    var simulation = try Simulation.read(init.io);
    try simulation.run(init.io, init.gpa);
}
