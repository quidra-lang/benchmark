const std = @import("std");
const c = @import("network.zig");
const p = @import("processes.zig");
const clock = @import("clocks.zig");
pub fn graphEdges(events: []const p.Event, copies: []const p.Copy, messages: []const p.Message, processes: []const p.Process) []std.ArrayList(usize) {
    const out = c.alloc(std.ArrayList(usize), events.len);
    @memset(out, .empty);
    for (events, 0..) |event, i| {
        const local = processes[event.process].events.items;
        if (event.local < local.len) c.append(usize, &out[i], local[event.local]);
    }
    for (copies) |copy| if (copy.received) |received| c.append(usize, &out[messages[copy.message].send], received);
    return out;
}
pub fn graphPath(source: usize, target: usize, graph: []const std.ArrayList(usize)) []const usize {
    const parent = c.alloc(?usize, graph.len);
    @memset(parent, null);
    var queue: std.ArrayList(usize) = .empty;
    c.append(usize, &queue, source);
    parent[source] = source;
    var head: usize = 0;
    while (head < queue.items.len and parent[target] == null) : (head += 1) {
        for (graph[queue.items[head]].items) |next| if (parent[next] == null) {
            parent[next] = queue.items[head];
            c.append(usize, &queue, next);
        };
    }
    var out: std.ArrayList(usize) = .empty;
    if (parent[target] == null) return out.items;
    var cursor = target;
    while (true) {
        c.append(usize, &out, cursor);
        if (cursor == source) break;
        cursor = parent[cursor].?;
    }
    std.mem.reverse(usize, out.items);
    return out.items;
}
pub const Concurrency = struct { ordered: i64 = 0, concurrent: i64 = 0, same: i64 = 0, inversions: i64 = 0, pairs: [6][6]i64 = [_][6]i64{c.zero} ** 6 };
pub fn concurrency(events: []const p.Event, count: usize) Concurrency {
    var out: Concurrency = .{};
    for (events, 0..) |a, i| for (events[i + 1 ..]) |b| {
        if (clock.relation(a.clock, b.clock, count) == 0) {
            out.concurrent += 1;
            out.same += @intFromBool(a.lamport == b.lamport);
            out.pairs[@min(a.process, b.process)][@max(a.process, b.process)] += 1;
        } else out.ordered += 1;
        if (a.time != b.time and a.lamport != b.lamport and ((a.time < b.time) != (a.lamport < b.lamport))) out.inversions += 1;
    };
    return out;
}
pub const Violation = struct { process: usize, first: usize, second: usize };
pub const Orders = struct { races: std.ArrayList(Violation) = .empty, violations: std.ArrayList(Violation) = .empty, fifo: i64 = 0 };
pub fn orders(processes: []const p.Process, copies: []const p.Copy, messages: []const p.Message, events: []const p.Event) Orders {
    var out: Orders = .{};
    for (processes, 0..) |process, own| {
        const delivered = process.delivered.items;
        if (delivered.len > 0) for (delivered[0 .. delivered.len - 1], delivered[1..]) |a, b| {
            if (clock.relation(events[messages[copies[a].message].send].clock, events[messages[copies[b].message].send].clock, processes.len) == 0) c.append(Violation, &out.races, .{ .process = own, .first = a, .second = b });
        };
        for (delivered, 0..) |a, i| for (delivered[i + 1 ..]) |b| if (clock.relation(events[messages[copies[b].message].send].clock, events[messages[copies[a].message].send].clock, processes.len) == 1) {
            c.append(Violation, &out.violations, .{ .process = own, .first = a, .second = b });
            out.fifo += @intFromBool(copies[a].source == copies[b].source);
        };
    }
    return out;
}
pub const Predicate = struct { cuts: i64 = 0, definite: bool = false };
pub const Enumeration = struct { limits: c.Vec = c.zero, levels: []i64, product: usize = 1, consistent: i64 = 0, predicates: []Predicate };
pub fn enumerate(processes: []const p.Process, events: []const p.Event, time: i64, thresholds: []const i64) Enumeration {
    const n = processes.len;
    var out: Enumeration = .{ .levels = undefined, .predicates = c.alloc(Predicate, thresholds.len) };
    @memset(out.predicates, .{});
    var strides = [_]usize{0} ** 6;
    var level_max: usize = 0;
    var initial: i64 = 0;
    var pindex = n;
    while (pindex > 0) {
        pindex -= 1;
        for (processes[pindex].events.items) |index| out.limits[pindex] += @intFromBool(events[index].time <= time);
        strides[pindex] = out.product;
        out.product *= c.u(out.limits[pindex] + 1);
        level_max += c.u(out.limits[pindex]);
        initial += processes[pindex].initial;
    }
    out.levels = c.alloc(i64, level_max + 1);
    @memset(out.levels, 0);
    const consistent = c.alloc(bool, out.product);
    @memset(consistent, false);
    const transit = c.alloc(i64, out.product);
    @memset(transit, 0);
    for (0..out.product) |index| {
        var cut = c.zero;
        var level: usize = 0;
        var balance: i64 = 0;
        for (0..n) |own| {
            cut[own] = c.n(index / strides[own] % c.u(out.limits[own] + 1));
            level += c.u(cut[own]);
            balance += p.balanceAtCut(processes[own], events, cut[own]);
        }
        var good = true;
        for (0..n) |own| if (cut[own] > 0 and !clock.lessEqual(events[processes[own].events.items[c.u(cut[own] - 1)]].clock, cut, n)) {
            good = false;
        };
        if (!good) continue;
        consistent[index] = true;
        out.consistent += 1;
        out.levels[level] += 1;
        transit[index] = initial - balance;
        for (thresholds, out.predicates) |threshold, *predicate| predicate.cuts += @intFromBool(transit[index] >= threshold);
    }
    const reachable = c.alloc(bool, out.product);
    for (thresholds, out.predicates) |threshold, *predicate| {
        @memset(reachable, false);
        for (0..out.product) |index| {
            if (!consistent[index] or transit[index] >= threshold) continue;
            if (index == 0) reachable[0] = true;
            for (0..n) |own| if (index / strides[own] % c.u(out.limits[own] + 1) > 0 and reachable[index - strides[own]]) {
                reachable[index] = true;
            };
        }
        predicate.definite = !reachable[out.product - 1];
    }
    return out;
}
