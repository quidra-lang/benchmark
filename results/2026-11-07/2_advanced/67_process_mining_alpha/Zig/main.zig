const std = @import("std");
const d = @import("eventlog.zig");
const graph = @import("dfg.zig");
const alpha = @import("alpha_miner.zig");
const heuristic = @import("heuristic_miner.zig");
const conformance = @import("conformance.zig");
const report = @import("report.zig");
const Fraction = d.Fraction;
const n = d.n;
const u = d.u;
const bit = d.bit;
const Net = conformance.Net;
const Replay = conformance.Replay;
const Variant = struct { trace: []const usize, cases: std.ArrayList(usize) = .empty, keep: bool = true };
const Discovery = struct { net: Net, pairs: []const alpha.Candidate, candidates: usize, causal: usize,
     activities: u16, starts: u16, ends: u16 };
const Exploration = struct { markings: usize = 0, edges: usize = 0, unsafe: usize = 0, deadlocks: usize = 0,
     stuck: usize = 0, final: bool = false, dead: u16 = 0, follows: graph.Counts = std.mem.zeroes(graph.Counts) };
const Prefix = struct { trace: []const usize, weight: i64 = 0, followers: u16 = 0 };
const CaseReplay = struct { missing: i64, remaining: i64, consumed: i64, produced: i64, skipped: i64,
     fitness: Fraction };
const Ranked = struct { a: usize, b: usize = 0, count: i64 };
fn rankLess(_: void, a: Ranked, b: Ranked) bool {
    if (a.count != b.count) return a.count > b.count;
    return if (a.a != b.a) a.a < b.a else a.b < b.b;
}
fn rankCounts(comptime size: usize, counts: *const [size][size]i64) []const Ranked {
    var out: std.ArrayList(Ranked) = .empty;
    for (0..size) |a| for (0..size) |b| {
        if (counts[a][b] > 0) d.append(Ranked, &out, .{ .a = a, .b = b, .count = counts[a][b] });
    };
    std.mem.sort(Ranked, out.items, {}, rankLess);
    return out.items;
}
fn rankVector(values: []const i64) []const Ranked {
    var out: std.ArrayList(Ranked) = .empty;
    for (values, 0..) |count, a| if (count > 0) d.append(Ranked, &out, .{ .a = a, .count = count });
    std.mem.sort(Ranked, out.items, {}, rankLess);
    return out.items;
}
fn traceOrder(a: []const usize, b: []const usize) std.math.Order {
    for (a[0..@min(a.len, b.len)], b[0..@min(a.len, b.len)]) |left, right| {
        if (left != right) return if (left < right) .lt else .gt;
    }
    return if (a.len < b.len) .lt else if (a.len > b.len) .gt else .eq;
}
fn variantLess(_: void, a: Variant, b: Variant) bool {
    return if (a.cases.items.len != b.cases.items.len) a.cases.items.len > b.cases.items.len else traceOrder(a.trace,
         b.trace) == .lt;
}
fn mean(values: []const i64) Fraction {
    var total: i64 = 0;
    for (values) |value| total += value;
    return Fraction.init(total, n(values.len));
}
fn parseFraction(value: []const u8) Fraction {
    const fields = d.split(value, '/');
    return Fraction.init(d.number(fields[0]), if (fields.len == 2) d.number(fields[1]) else 1);
}
fn relations(counts: *const graph.Counts, triangles: ?*const graph.Counts) graph.Relations {
    var out: graph.Relations = undefined;
    for (0..12) |a| for (0..12) |b| {
        out[a][b] = if (triangles) |tri| alpha.plusRelation(counts, tri, a, b) else graph.basicRelation(counts, a, b);
    };
    return out;
}
fn maskIds(mask: u16) []const usize {
    var out: std.ArrayList(usize) = .empty;
    for (0..12) |i| if (mask & bit(i) != 0) d.append(usize, &out, i);
    return out.items;
}
fn selectedNames(values: []const []const u8, mask: u16) []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (values, 0..) |value, i| if (mask & bit(i) != 0) d.append([]const u8, &out, value);
    return report.names(out.items);
}
fn placeNames(net: Net, arcs: []const bool, t: usize) []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (net.places, 0..) |place, p| if (arcs[t * net.places.len + p]) d.append([]const u8, &out, place);
    return report.names(out.items);
}
const Study = struct {
    input: d.Input,
    reference: Net,
    events: []const d.Event,
    cases: []d.Case,
    activities: []const []const u8,
    resources: []const []const u8,
    minimum: i64,
    limit: i64,
    positive: i64,
    dependency_threshold: Fraction,
    relative: Fraction,
    loop1_threshold: Fraction,
    loop2_threshold: Fraction,
    and_threshold: Fraction,
    errors: d.Lines,
    log: []const graph.Trace,
    counts: graph.Counts,
    variants: []Variant = &.{},
    variant_by_case: []usize = &.{},
    filtered: []const graph.Trace = &.{},
    kept_cases: i64 = 0,
    kept_events: i64 = 0,
    nets: [3]Net = undefined,
    prefixes: []const Prefix = &.{},
    reference_replays: []CaseReplay = &.{},
    fn init(io: std.Io) !Study {
        const input = try d.readInputs(io);
        const reference = try conformance.readModel(io);
        var errors: d.Lines = .{};
        var events: std.ArrayList(d.Event) = .empty;
        var activity_names: std.ArrayList([]const u8) = .empty;
        var resource_names: std.ArrayList([]const u8) = .empty;
        for (input.rows) |row| {
            const time = d.timestampMinutes(row.timestamp) orelse {
                errors.add("ERROR line {d}: bad timestamp {s}", .{ row.line, row.timestamp });
                continue;
            };
            var duplicate = false;
            for (events.items) |old| {
                if (d.eq(old.row.case_id, row.case_id) and d.eq(old.row.activity, row.activity) and d.eq(old.row.timestamp,
                     row.timestamp)) {
                    duplicate = true;
                    break;
                }
            }
            if (duplicate) {
                errors.add("ERROR line {d}: duplicate event {s} {s} {s}", .{ row.line, row.case_id,
                     row.activity, row.timestamp });
                continue;
            }
            d.append(d.Event, &events, .{ .row = row, .time = time });
            d.append([]const u8, &activity_names, row.activity);
            d.append([]const u8, &resource_names, row.resource);
        }
        const activities = d.uniqueNames(activity_names.items);
        const resources = d.uniqueNames(resource_names.items);
        const cases = d.groupCases(events.items);
        const log = d.alloc(graph.Trace, cases.len);
        for (cases, log) |*item, *trace| {
            const ids = d.alloc(usize, item.events.items.len);
            for (item.events.items, ids) |event, *id| id.* = d.indexOf(activities, event.row.activity).?;
            item.trace = ids;
            trace.* = .{ .activities = ids };
        }
        const p = input.parameters;
        return .{ .input = input, .reference = reference, .events = events.items, .cases = cases,
             .activities = activities, .resources = resources, .minimum = d.number(p[0]), .limit = d.number(p[1]),
             .positive = d.number(p[2]), .dependency_threshold = parseFraction(p[3]), .relative = parseFraction(p[4]),
             .loop1_threshold = parseFraction(p[5]), .loop2_threshold = parseFraction(p[6]),
             .and_threshold = parseFraction(p[7]), .errors = errors, .log = log, .counts = graph.directlyFollows(log) };
    }
    fn buildVariants(self: *Study) void {
        var variants: std.ArrayList(Variant) = .empty;
        for (self.cases, 0..) |item, c| {
            var found: ?usize = null;
            for (variants.items, 0..) |v, i| {
                if (traceOrder(v.trace, item.trace) == .eq) {
                    found = i;
                    break;
                }
            }
            if (found == null) {
                found = variants.items.len;
                var keep = true;
                var i: usize = 1;
                while (i < item.trace.len) : (i += 1) {
                    if (self.counts[item.trace[i - 1]][item.trace[i]] < self.minimum) keep = false;
                }
                d.append(Variant, &variants, .{ .trace = item.trace, .keep = keep });
            }
            d.append(usize, &variants.items[found.?].cases, c);
        }
        std.mem.sort(Variant, variants.items, {}, variantLess);
        self.variants = variants.items;
        self.variant_by_case = d.alloc(usize, self.cases.len);
        var filtered: std.ArrayList(graph.Trace) = .empty;
        for (self.variants, 0..) |v, i| {
            for (v.cases.items) |c| self.variant_by_case[c] = i + 1;
            if (v.keep) {
                d.append(graph.Trace, &filtered, .{ .activities = v.trace, .weight = n(v.cases.items.len) });
                self.kept_cases += n(v.cases.items.len);
                self.kept_events += n(v.trace.len) * n(v.cases.items.len);
            }
        }
        self.filtered = filtered.items;
    }
    fn summary(self: *const Study) d.Lines {
        var out = self.errors;
        var first = self.events[0];
        var last = first;
        for (self.events) |event| {
            if (event.time < first.time) first = event;
            if (event.time > last.time) last = event;
        }
        out.add("LOG rows {d} adopted {d} rejected {d} cases {d} activities {d} resources {d} first {s} last {s}",
             .{ self.input.rows.len, self.events.len, self.errors.data.items.len, self.cases.len,
             self.activities.len, self.resources.len, first.row.timestamp, last.row.timestamp });
        var events = [_]i64{0} ** 12;
        var cases = [_]i64{0} ** 12;
        var starts = [_]i64{0} ** 12;
        var ends = [_]i64{0} ** 12;
        var rework = [_]i64{0} ** 12;
        var wait_count = [_]i64{0} ** 12;
        var wait_sum = [_]i64{0} ** 12;
        var workers = [_]u32{0} ** 12;
        var weekday_events = [_]i64{0} ** 7;
        var weekday_starts = [_]i64{0} ** 7;
        var weekday_ends = [_]i64{0} ** 7;
        const lengths = d.alloc(i64, self.cases.len);
        const durations = d.alloc(i64, self.cases.len);
        var days = [_]i64{0} ** 366;
        var maxday: usize = 0;
        var late: i64 = 0;
        for (self.cases, 0..) |item, c| {
            var occurrences = [_]usize{0} ** 12;
            starts[item.trace[0]] += 1;
            ends[item.trace[item.trace.len - 1]] += 1;
            weekday_starts[u(@mod(@divTrunc(item.events.items[0].time, 1440) + 3, 7))] += 1;
            weekday_ends[u(@mod(@divTrunc(item.events.items[item.events.items.len - 1].time, 1440) + 3, 7))] += 1;
            for (item.events.items, item.trace, 0..) |event, a, i| {
                events[a] += 1;
                occurrences[a] += 1;
                workers[a] |= @as(u32, 1) << @intCast(d.indexOf(self.resources, event.row.resource).?);
                weekday_events[u(@mod(@divTrunc(event.time, 1440) + 3, 7))] += 1;
                if (i > 0) {
                    wait_count[a] += 1;
                    wait_sum[a] += event.time - item.events.items[i - 1].time;
                }
            }
            for (0..self.activities.len) |a| {
                cases[a] += @intFromBool(occurrences[a] > 0);
                rework[a] += @intFromBool(occurrences[a] >= 2);
            }
            lengths[c] = n(item.events.items.len);
            durations[c] = item.duration;
            const day = u(@divTrunc(item.duration, 1440));
            days[day] += 1;
            maxday = @max(maxday, day);
            late += @intFromBool(item.duration > self.limit);
        }
        for (self.activities, 0..) |activity, a| out.add("ACTIVITY {s} events {d} cases {d} start {d} end {d} rework {d} wait {s} resources {d} model {s}",
             .{ activity, events[a], cases[a], starts[a], ends[a], rework[a], if (wait_count[a] > 0) report.fraction(Fraction.init(wait_sum[a],
             wait_count[a])) else "-", @popCount(workers[a]), if (d.indexOf(self.reference.transitions,
             activity) != null) "yes" else "no" });
        for ([_][]const i64{ lengths, durations }, 0..) |values, i| out.add("{s} min {d} max {d} mean {s} median {s}",
             .{ if (i == 0) "LENGTH" else "DURATION", std.mem.min(i64, values), std.mem.max(i64,
             values), report.fraction(mean(values)), report.fraction(d.median(values)) });
        for (0..maxday + 1) |day| out.add("DAYS {d} cases {d} share {s}", .{ day, days[day],
             report.percentage(days[day], n(self.cases.len)) });
        out.add("SLA limit {d} late {d} share {s}", .{ self.limit, late, report.percentage(late, n(self.cases.len)) });
        for ([_][]const u8{ "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }, 0..) |weekday,
             i| out.add("WEEKDAY {s} events {d} starts {d} ends {d}", .{ weekday, weekday_events[i],
             weekday_starts[i], weekday_ends[i] });
        return out;
    }
    fn traceNames(self: *const Study, trace: []const usize) []const u8 {
        const names = d.alloc([]const u8, trace.len);
        for (trace, names) |a, *name| name.* = self.activities[a];
        return report.names(names);
    }
    fn variantReport(self: *const Study) d.Lines {
        var out: d.Lines = .{};
        for (self.variants, 0..) |v, i| {
            var duration: i64 = 0;
            var late: i64 = 0;
            for (v.cases.items) |c| {
                duration += self.cases[c].duration;
                late += @intFromBool(self.cases[c].duration > self.limit);
            }
            const first = v.cases.items[0];
            out.add("VARIANT {d} count {d} share {s} length {d} first {s} duration {s} late {d} fitness {s} {s} {s}",
                 .{ i + 1, v.cases.items.len, report.percentage(n(v.cases.items.len), n(self.cases.len)),
                 v.trace.len, self.cases[first].id, report.fraction(Fraction.init(duration,
                 n(v.cases.items.len))), late, report.fraction(self.reference_replays[first].fitness),
                 if (v.keep) "KEEP" else "DROP", self.traceNames(v.trace) });
        }
        out.add("FILTER min_follows {d} variants {d} of {d} cases {d} of {d} events {d} of {d}",
             .{ self.minimum, self.filtered.len, self.variants.len, self.kept_cases, self.cases.len,
             self.kept_events, self.events.len });
        return out;
    }
    fn dfgReport(self: *const Study) d.Lines {
        var out: d.Lines = .{};
        var starts = [_]i64{0} ** 12;
        var ends = [_]i64{0} ** 12;
        var duration = [_]i64{0} ** 12;
        var edge_cases: graph.Counts = std.mem.zeroes(graph.Counts);
        var wait_sum: graph.Counts = std.mem.zeroes(graph.Counts);
        var wait_min: graph.Counts = [_][12]i64{[_]i64{std.math.maxInt(i64)} ** 12} ** 12;
        var wait_max: graph.Counts = std.mem.zeroes(graph.Counts);
        for (self.cases) |item| {
            starts[item.trace[0]] += 1;
            const last = item.trace[item.trace.len - 1];
            ends[last] += 1;
            duration[last] += item.duration;
            var seen = [_][12]bool{[_]bool{false} ** 12} ** 12;
            var i: usize = 1;
            while (i < item.trace.len) : (i += 1) {
                const a = item.trace[i - 1];
                const b = item.trace[i];
                const wait = item.events.items[i].time - item.events.items[i - 1].time;
                wait_sum[a][b] += wait;
                wait_min[a][b] = @min(wait_min[a][b], wait);
                wait_max[a][b] = @max(wait_max[a][b], wait);
                seen[a][b] = true;
            }
            for (0..self.activities.len) |a| for (0..self.activities.len) |b| {
                edge_cases[a][b] += @intFromBool(seen[a][b]);
            };
        }
        for (rankVector(starts[0..self.activities.len])) |r| out.add("START {s} count {d}",
             .{ self.activities[r.a], r.count });
        for (rankVector(ends[0..self.activities.len])) |r| out.add("END {s} count {d} duration {s}",
             .{ self.activities[r.a], r.count, report.fraction(Fraction.init(duration[r.a],
             r.count)) });
        for (rankCounts(12, &self.counts)) |r| out.add("EDGE {s} {s} count {d} cases {d} mean {s} min {d} max {d}",
             .{ self.activities[r.a], self.activities[r.b], r.count, edge_cases[r.a][r.b],
             report.fraction(Fraction.init(wait_sum[r.a][r.b], r.count)), wait_min[r.a][r.b],
             wait_max[r.a][r.b] });
        const relation = relations(&self.counts, null);
        out.extend(graph.footprint(self.activities, maskIds((bit(self.activities.len - 1) << 1) - 1), &relation));
        return out;
    }
    fn discover(self: *const Study, log: []const graph.Trace, activities: u16, relation: *const graph.Relations) Discovery {
        var candidates: std.ArrayList(alpha.Candidate) = .empty;
        var seen: std.AutoHashMapUnmanaged(u32, void) = .empty;
        var causal: usize = 0;
        for (maskIds(activities)) |a| for (maskIds(activities)) |b| {
            if (relation[a][b] != .forward) continue;
            causal += 1;
            if (relation[a][a] == .unrelated and relation[b][b] == .unrelated) {
                const pair: alpha.Candidate = .{ .first = bit(a), .second = bit(b) };
                const key = (@as(u32, pair.first) << 12) | pair.second;
                if (!seen.contains(key)) {
                    seen.put(d.allocator, key, {}) catch @panic("allocation failed");
                    d.append(alpha.Candidate, &candidates, pair);
                }
            }
        };
        var i: usize = 0;
        while (i < candidates.items.len) : (i += 1) for (maskIds(activities)) |a| for (0..2) |side| {
            if (alpha.extendPair(candidates.items[i], a, side, relation)) |pair| {
                const key = (@as(u32, pair.first) << 12) | pair.second;
                if (!seen.contains(key)) {
                    seen.put(d.allocator, key, {}) catch @panic("allocation failed");
                    d.append(alpha.Candidate, &candidates, pair);
                }
            }
        };
        var maximal: std.ArrayList(alpha.Candidate) = .empty;
        for (candidates.items) |pair| {
            var extension = false;
            for (maskIds(activities)) |a| for (0..2) |side| {
                if (alpha.extendPair(pair, a, side, relation) != null) extension = true;
            };
            if (!extension) d.append(alpha.Candidate, &maximal, pair);
        }
        std.mem.sort(alpha.Candidate, maximal.items, {}, alpha.pairLess);
        var starts: u16 = 0;
        var ends: u16 = 0;
        for (log) |trace| {
            starts |= bit(trace.activities[0]);
            ends |= bit(trace.activities[trace.activities.len - 1]);
        }
        const places = d.alloc([]const u8, maximal.items.len + 2);
        places[0] = "start";
        for (1..places.len - 1) |p| places[p] = d.fmt("p{d}", .{p});
        places[places.len - 1] = "end";
        var transitions: std.ArrayList([]const u8) = .empty;
        for (maskIds(activities)) |a| d.append([]const u8, &transitions, self.activities[a]);
        var net = Net.init(places, transitions.items, "start", "end");
        for (maskIds(starts)) |a| net.arc("start", self.activities[a]);
        for (maskIds(ends)) |a| net.arc(self.activities[a], "end");
        for (maximal.items, 1..) |pair, p| {
            for (maskIds(pair.first)) |a| net.arc(self.activities[a], places[p]);
            for (maskIds(pair.second)) |b| net.arc(places[p], self.activities[b]);
        }
        return .{ .net = net, .pairs = maximal.items, .candidates = candidates.items.len, .causal = causal,
             .activities = activities, .starts = starts, .ends = ends };
    }
    fn pairLine(out: *d.Lines, discovery: Discovery) void {
        out.add("PAIRS causal {d} candidates {d} maximal {d}", .{ discovery.causal, discovery.candidates,
             discovery.pairs.len });
    }
    fn netLines(self: *const Study, out: *d.Lines, discovery: Discovery) void {
        const net = discovery.net;
        out.add("PLACE start - {s}", .{selectedNames(self.activities, discovery.starts)});
        for (discovery.pairs, 1..) |pair, p| out.add("PLACE p{d} {s} {s}", .{ p, selectedNames(self.activities,
             pair.first), selectedNames(self.activities, pair.second) });
        out.add("PLACE end {s} -", .{selectedNames(self.activities, discovery.ends)});
        for (net.transitions, 0..) |transition, t| out.add("TRANSITION {s} in {s} out {s}",
             .{ transition, placeNames(net, net.inputs, t), placeNames(net, net.outputs, t) });
        out.add("NET places {d} transitions {d} arcs {d}", .{ net.places.len, net.transitions.len, net.arc_count });
    }
    fn mineWorkflows(self: *Study) d.Lines {
        const counts = graph.directlyFollows(self.filtered);
        var activities: u16 = 0;
        for (self.filtered) |trace| for (trace.activities) |a| {
            activities |= bit(a);
        };
        var loops: u16 = 0;
        for (self.activities, 0..) |_, a| if (counts[a][a] > 0) {
            loops |= bit(a);
        };
        const retained = activities & ~loops;
        const basic = relations(&counts, null);
        const discovered = self.discover(self.filtered, activities, &basic);
        var out: d.Lines = .{};
        out.add("LOG variants {d} cases {d} activities {s}", .{ self.filtered.len, self.kept_cases,
             selectedNames(self.activities, activities) });
        out.add("LOOPS {s}", .{selectedNames(self.activities, loops)});
        out.add("MINER alpha", .{});
        out.extend(graph.footprint(self.activities, maskIds(activities), &basic));
        pairLine(&out, discovered);
        self.netLines(&out, discovered);
        const reduced = d.alloc(graph.Trace, self.filtered.len);
        for (self.filtered, reduced) |original, *trace| {
            var list: std.ArrayList(usize) = .empty;
            for (original.activities) |a| if (loops & bit(a) == 0) d.append(usize, &list, a);
            trace.* = .{ .activities = list.items, .weight = original.weight };
        }
        const reduced_counts = graph.directlyFollows(reduced);
        const triangles = alpha.triangleCounts(reduced);
        const plus = relations(&reduced_counts, &triangles);
        var plus_discovery = self.discover(reduced, retained, &plus);
        out.add("MINER alpha_plus", .{});
        for (0..self.activities.len) |a| for (0..self.activities.len) |b| {
            if (triangles[a][b] > 0) out.add("TRIANGLE {s} {s} count {d}", .{ self.activities[a],
                 self.activities[b], triangles[a][b] });
        };
        out.extend(graph.footprint(self.activities, maskIds(retained), &plus));
        pairLine(&out, plus_discovery);
        var transitions: std.ArrayList([]const u8) = .empty;
        for (maskIds(activities)) |a| d.append([]const u8, &transitions, self.activities[a]);
        var net = Net.init(plus_discovery.net.places, transitions.items, "start", "end");
        for (plus_discovery.net.transitions, 0..) |transition, t| for (net.places, 0..) |place, p| {
            if (plus_discovery.net.inputs[t * net.places.len + p]) net.arc(place, transition);
            if (plus_discovery.net.outputs[t * net.places.len + p]) net.arc(transition, place);
        };
        for (maskIds(loops)) |a| {
            var before: u16 = 0;
            var after: u16 = 0;
            for (maskIds(retained)) |b| {
                if (counts[b][a] > 0) before |= bit(b);
                if (counts[a][b] > 0) after |= bit(b);
            }
            var place: []const u8 = "-";
            for (plus_discovery.pairs, 1..) |pair, p| {
                if (pair.first == before and pair.second == after) {
                    place = net.places[p];
                    net.arc(place, self.activities[a]);
                    net.arc(self.activities[a], place);
                    break;
                }
            }
            out.add("LOOP {s} before {s} after {s} place {s}", .{ self.activities[a], selectedNames(self.activities,
                 before), selectedNames(self.activities, after), place });
        }
        plus_discovery.net = net;
        self.netLines(&out, plus_discovery);
        self.nets = .{ self.reference, discovered.net, net };
        return out;
    }
    fn heuristicReport(self: *const Study) d.Lines {
        var out: d.Lines = .{};
        const triangles = alpha.triangleCounts(self.log);
        var loops1: u16 = 0;
        var loops2 = [_][12]bool{[_]bool{false} ** 12} ** 12;
        var edges = loops2;
        var loop2_count: usize = 0;
        var best_out = [_]Fraction{Fraction.init(-1, 1)} ** 12;
        var best_in = best_out;
        for (self.activities, 0..) |activity, a| {
            const count = self.counts[a][a];
            if (count == 0) continue;
            const measure = heuristic.loopMeasure(count);
            const accept = count >= self.positive and measure.cmp(self.loop1_threshold) != .lt;
            if (accept) {
                loops1 |= bit(a);
                edges[a][a] = true;
            }
            out.add("L1 {s} count {d} measure {s} {s}", .{ activity, count, report.fraction(measure),
                 if (accept) "ACCEPT" else "REJECT" });
        }
        for (0..self.activities.len) |a| for (a + 1..self.activities.len) |b| {
            const count = triangles[a][b] + triangles[b][a];
            if (count == 0 or loops1 & (bit(a) | bit(b)) != 0) continue;
            const measure = heuristic.loopMeasure(count);
            const accept = count >= self.positive and measure.cmp(self.loop2_threshold) != .lt;
            if (accept) {
                loops2[a][b] = true;
                loops2[b][a] = true;
                loop2_count += 1;
            }
            out.add("L2 {s} {s} count {d} measure {s} {s}", .{ self.activities[a], self.activities[b],
                 count, report.fraction(measure), if (accept) "ACCEPT" else "REJECT" });
        };
        for (0..self.activities.len) |a| for (0..self.activities.len) |b| {
            if (a != b and self.counts[a][b] > 0) {
                const measure = heuristic.dependency(&self.counts, a, b);
                if (measure.cmp(best_out[a]) == .gt) best_out[a] = measure;
                if (measure.cmp(best_in[b]) == .gt) best_in[b] = measure;
            }
        };
        for (0..self.activities.len) |a| for (0..self.activities.len) |b| {
            if (a == b or self.counts[a][b] == 0) continue;
            const measure = heuristic.dependency(&self.counts, a, b);
            const verdict: []const u8 = if (loops2[a][b]) "LOOP2" else if (self.counts[a][b] < self.positive) "REJECT_COUNT" else if (measure.cmp(self.dependency_threshold) == .lt) "REJECT_MEASURE" else if (best_out[a].sub(measure).cmp(self.relative) == .gt and best_in[b].sub(measure).cmp(self.relative) == .gt) "REJECT_BEST" else "ACCEPT";
            if (d.eq(verdict, "LOOP2") or d.eq(verdict, "ACCEPT")) edges[a][b] = true;
            out.add("DEP {s} {s} count {d} reverse {d} measure {s} {s}", .{ self.activities[a],
                 self.activities[b], self.counts[a][b], self.counts[b][a], report.fraction(measure),
                 verdict });
        };
        var edge_count: usize = 0;
        for (self.activities, 0..) |activity, a| {
            var in: u16 = 0;
            var out_mask: u16 = 0;
            for (0..self.activities.len) |b| {
                if (edges[b][a]) in |= bit(b);
                if (edges[a][b]) {
                    out_mask |= bit(b);
                    edge_count += 1;
                }
            }
            out.add("NODE {s} in {s} out {s}", .{ activity, selectedNames(self.activities,
                 in), selectedNames(self.activities, out_mask) });
        }
        for (0..self.activities.len) |a| for (0..2) |direction| for (0..self.activities.len) |b| {
            if (a == b or !(if (direction == 0) edges[a][b] else edges[b][a])) continue;
            for (b + 1..self.activities.len) |c| {
                if (a == c or !(if (direction == 0) edges[a][c] else edges[c][a])) continue;
                const measure = if (direction == 0) heuristic.splitMeasure(&self.counts, a,
                     b, c) else heuristic.joinMeasure(&self.counts, a, b, c);
                out.add("{s} {s} {s} {s} measure {s} {s}", .{ if (direction == 0) "SPLIT" else "JOIN",
                     self.activities[a], self.activities[b], self.activities[c], report.fraction(measure),
                     if (measure.cmp(self.and_threshold) != .lt) "AND" else "XOR" });
            }
        };
        out.add("GRAPH activities {d} edges {d} loops1 {d} loops2 {d}", .{ self.activities.len,
             edge_count, @popCount(loops1), loop2_count });
        return out;
    }
    fn explore(net: Net) Exploration {
        var result: Exploration = .{};
        var markings: std.ArrayList([]const u8) = .empty;
        var indices: std.StringHashMapUnmanaged(usize) = .empty;
        const first = net.initialMarking();
        d.append([]const u8, &markings, first);
        indices.put(d.allocator, first, 0) catch @panic("allocation failed");
        const StateEdge = struct { from: usize, to: usize, transition: usize };
        var edges: std.ArrayList(StateEdge) = .empty;
        var enabled_at: std.ArrayList(u16) = .empty;
        var ever: u16 = 0;
        const after = d.alloc(u8, net.places.len);
        const final = net.finalMarking();
        var from: usize = 0;
        while (from < markings.items.len) : (from += 1) {
            const before = markings.items[from];
            var active: u16 = 0;
            for (0..net.transitions.len) |t| if (net.enabled(before, t)) {
                active |= bit(t);
            };
            d.append(u16, &enabled_at, active);
            ever |= active;
            if (active == 0 and !std.mem.eql(u8, before, final)) result.deadlocks += 1;
            for (maskIds(active)) |t| {
                net.fire(before, t, after);
                if (std.mem.max(u8, after) > 1) {
                    result.unsafe += 1;
                    continue;
                }
                var to = indices.get(after);
                if (to == null) {
                    const saved = d.dupe(u8, after);
                    to = markings.items.len;
                    indices.put(d.allocator, saved, to.?) catch @panic("allocation failed");
                    d.append([]const u8, &markings, saved);
                }
                d.append(StateEdge, &edges, .{ .from = from, .to = to.?, .transition = t });
            }
        }
        const reaches = d.alloc(bool, markings.items.len);
        @memset(reaches, false);
        var pending: std.ArrayList(usize) = .empty;
        if (indices.get(final)) |index| {
            result.final = true;
            reaches[index] = true;
            d.append(usize, &pending, index);
        }
        var i: usize = 0;
        while (i < pending.items.len) : (i += 1) for (edges.items) |edge| {
            if (edge.to == pending.items[i] and !reaches[edge.from]) {
                reaches[edge.from] = true;
                d.append(usize, &pending, edge.from);
            }
        };
        result.markings = markings.items.len;
        result.edges = edges.items.len;
        result.stuck = markings.items.len - pending.items.len;
        for (0..net.transitions.len) |t| if (ever & bit(t) == 0) {
            result.dead |= bit(t);
        };
        for (edges.items) |edge| for (maskIds(enabled_at.items[edge.to])) |t| {
            result.follows[edge.transition][t] = 1;
        };
        return result;
    }
    fn buildPrefixes(self: *Study) void {
        var prefixes: std.ArrayList(Prefix) = .empty;
        var indices: std.StringHashMapUnmanaged(usize) = .empty;
        for (self.cases) |item| for (0..item.trace.len + 1) |length| {
            const trace = item.trace[0..length];
            const key = std.mem.sliceAsBytes(trace);
            var index = indices.get(key);
            if (index == null) {
                index = prefixes.items.len;
                d.append(Prefix, &prefixes, .{ .trace = trace });
                indices.put(d.allocator, key, index.?) catch @panic("allocation failed");
            }
            const p = &prefixes.items[index.?];
            p.weight += 1;
            if (length < item.trace.len) p.followers |= bit(item.trace[length]);
        };
        self.prefixes = prefixes.items;
    }
    fn precisionReport(self: *const Study, name: []const u8, net: Net) d.Lines {
        var fitted: i64 = 0;
        var allowed: i64 = 0;
        var escaping: i64 = 0;
        var escapes = [_]i64{0} ** 12;
        const marking = d.alloc(u8, net.places.len);
        const after = d.alloc(u8, net.places.len);
        for (self.prefixes) |prefix| {
            @memset(marking, 0);
            marking[net.initial] = 1;
            var fit = true;
            for (prefix.trace) |a| {
                const t = d.indexOf(net.transitions, self.activities[a]) orelse {
                    fit = false;
                    break;
                };
                if (!net.enabled(marking, t)) {
                    fit = false;
                    break;
                }
                net.fire(marking, t, after);
                @memcpy(marking, after);
            }
            if (!fit) continue;
            fitted += 1;
            for (net.transitions, 0..) |transition, t| if (net.enabled(marking, t)) {
                allowed += prefix.weight;
                const a = d.indexOf(self.activities, transition);
                if (a == null or prefix.followers & bit(a.?) == 0) {
                    escaping += prefix.weight;
                    escapes[t] += prefix.weight;
                }
            };
        }
        var out: d.Lines = .{};
        out.add("PRECISION {s} prefixes {d} allowed {d} escaping {d} precision {s}", .{ name,
             fitted, allowed, escaping, report.fraction(if (allowed == 0) Fraction.init(1,
             1) else Fraction.init(allowed - escaping, allowed)) });
        for (rankVector(escapes[0..net.transitions.len])) |r| out.add("ESCAPE {s} {s} weight {d}",
             .{ name, net.transitions[r.a], r.count });
        return out;
    }
    const Tokens = struct { values: [52]i64 = undefined, head: usize = 0, tail: usize = 0 };
    fn replayCase(net: Net, item: d.Case, result: *Replay, tokens: []Tokens) void {
        result.clear();
        for (tokens) |*queue| {
            queue.head = 0;
            queue.tail = 0;
        }
        tokens[net.initial].values[0] = item.events.items[0].time;
        tokens[net.initial].tail = 1;
        result.produced = 1;
        for (item.events.items) |event| {
            const t = d.indexOf(net.transitions, event.row.activity) orelse {
                result.skipped += 1;
                continue;
            };
            for (tokens, 0..) |*queue, p| if (net.inputs[t * net.places.len + p]) {
                result.consumed += 1;
                if (queue.head < queue.tail) {
                    const wait = event.time - queue.values[queue.head];
                    queue.head += 1;
                    result.wait_count[p] += 1;
                    result.wait_sum[p] += wait;
                    result.wait_max[p] = @max(result.wait_max[p], wait);
                    result.routes[p * net.transitions.len + t] += 1;
                } else {
                    result.missing += 1;
                    result.place_missing[p] += 1;
                }
            };
            for (tokens, 0..) |*queue, p| if (net.outputs[t * net.places.len + p]) {
                queue.values[queue.tail] = event.time;
                queue.tail += 1;
                result.produced += 1;
            };
        }
        result.consumed += 1;
        if (tokens[net.final].head < tokens[net.final].tail) tokens[net.final].head += 1 else {
            result.missing += 1;
            result.place_missing[net.final] += 1;
        }
        for (tokens, 0..) |queue, p| {
            result.place_remaining[p] = n(queue.tail - queue.head);
            result.remaining += result.place_remaining[p];
            result.deviating[p] = @intFromBool(result.place_missing[p] > 0 or result.place_remaining[p] > 0);
        }
    }
    fn aggregate(total: *Replay, result: Replay, net: Net) void {
        total.missing += result.missing;
        total.remaining += result.remaining;
        total.consumed += result.consumed;
        total.produced += result.produced;
        total.skipped += result.skipped;
        for (0..net.places.len) |p| {
            total.place_missing[p] += result.place_missing[p];
            total.place_remaining[p] += result.place_remaining[p];
            total.deviating[p] += result.deviating[p];
            total.wait_count[p] += result.wait_count[p];
            total.wait_sum[p] += result.wait_sum[p];
            total.wait_max[p] = @max(total.wait_max[p], result.wait_max[p]);
        }
        for (total.routes, result.routes) |*count, value| count.* += value;
    }
    fn conformanceReport(self: *Study) d.Lines {
        var out: d.Lines = .{};
        const net_names = [_][]const u8{ "reference", "alpha", "alpha_plus" };
        var explored: [3]Exploration = undefined;
        out.add("MODEL places {d} transitions {d} arcs {d}", .{ self.reference.places.len,
             self.reference.transitions.len, self.reference.arc_count });
        for (self.nets, net_names, &explored) |net, name, *result| {
            result.* = explore(net);
            out.add("REACHABILITY {s} markings {d} edges {d} unsafe {d} deadlocks {d} stuck {d} final {s} dead {s} sound {s}",
                 .{ name, result.markings, result.edges, result.unsafe, result.deadlocks, result.stuck,
                 if (result.final) "yes" else "no", selectedNames(net.transitions, result.dead),
                 if (result.unsafe == 0 and result.stuck == 0 and result.dead == 0) "yes" else "no" });
        }
        for (self.nets, net_names, explored, 0..) |net, name, result, i| {
            var all: std.ArrayList([]const u8) = .empty;
            for (self.activities) |activity| d.append([]const u8, &all, activity);
            for (net.transitions) |transition| d.append([]const u8, &all, transition);
            const universe = d.uniqueNames(all.items);
            var differing: i64 = 0;
            var differences: d.Lines = .{};
            for (universe, 0..) |a, ai| for (universe, 0..) |b, bi| {
                const la = d.indexOf(self.activities, a);
                const lb = d.indexOf(self.activities, b);
                const ma = d.indexOf(net.transitions, a);
                const mb = d.indexOf(net.transitions, b);
                const observed: graph.Relation = if (la == null or lb == null) .unrelated else graph.basicRelation(&self.counts,
                     la.?, lb.?);
                const modeled: graph.Relation = if (ma == null or mb == null) .unrelated else graph.basicRelation(&result.follows,
                     ma.?, mb.?);
                if (observed != modeled) {
                    differing += 1;
                    if (i == 0 and ai <= bi) differences.add("DIFF {s} {s} log {s} model {s}",
                         .{ a, b, graph.symbol(observed), graph.symbol(modeled) });
                }
            };
            const cells = n(universe.len) * n(universe.len);
            out.add("FOOTPRINT {s} activities {d} cells {d} differing {d} fitness {s}", .{ name,
                 universe.len, cells, differing, report.fraction(Fraction.init(cells - differing,
                 cells)) });
            out.extend(differences);
        }
        self.buildPrefixes();
        for (self.nets, net_names) |net, name| out.extend(self.precisionReport(name, net));
        self.reference_replays = d.alloc(CaseReplay, self.cases.len);
        for (self.nets, net_names, 0..) |net, name, index| {
            var total = Replay.init(net);
            var result = Replay.init(net);
            const tokens = d.alloc(Tokens, net.places.len);
            var fitting: usize = 0;
            for (self.cases, 0..) |item, c| {
                replayCase(net, item, &result, tokens);
                fitting += @intFromBool(result.missing == 0 and result.remaining == 0);
                aggregate(&total, result, net);
                if (index == 0) self.reference_replays[c] = .{ .missing = result.missing, .remaining = result.remaining,
                     .consumed = result.consumed, .produced = result.produced, .skipped = result.skipped,
                     .fitness = result.fitness() };
            }
            out.add("REPLAY {s} cases {d} fitting {d} skipped {d} missing {d} remaining {d} consumed {d} produced {d} fitness {s}",
                 .{ name, self.cases.len, fitting, total.skipped, total.missing, total.remaining,
                 total.consumed, total.produced, report.fraction(total.fitness()) });
            for (net.places, 0..) |place, p| out.add("PLACE {s} {s} missing {d} remaining {d} deviating {d} tokens {d} mean {s} max {s}",
                 .{ name, place, total.place_missing[p], total.place_remaining[p], total.deviating[p],
                 total.wait_count[p], if (total.wait_count[p] > 0) report.fraction(Fraction.init(total.wait_sum[p],
                 total.wait_count[p])) else "-", if (total.wait_count[p] > 0) d.fmt("{d}",
                 .{total.wait_max[p]}) else "-" });
            for (net.places, 0..) |place, p| {
                var routes: std.ArrayList([]const u8) = .empty;
                for (net.transitions, 0..) |transition, t| if (net.inputs[t * net.places.len + p]) d.append([]const u8,
                     &routes, d.fmt("{s}={d}", .{ transition, total.routes[p * net.transitions.len + t] }));
                if (routes.items.len >= 2) out.add("ROUTE {s} {s} {s}", .{ name, place, report.names(routes.items) });
            }
        }
        return out;
    }
    fn conformanceCsv(self: *const Study) d.Lines {
        var out: d.Lines = .{};
        out.add("case_id,variant,events,skipped,missing,remaining,consumed,produced,fitness", .{});
        for (self.cases, self.reference_replays, 0..) |item, result, c| out.add("{s},{d},{d},{d},{d},{d},{d},{d},{s}",
             .{ item.id, self.variant_by_case[c], item.events.items.len, result.skipped, result.missing,
             result.remaining, result.consumed, result.produced, report.fraction(result.fitness) });
        return out;
    }
    fn resourceReport(self: *const Study) d.Lines {
        var out: d.Lines = .{};
        var events = [_]i64{0} ** 20;
        var cases = [_]i64{0} ** 20;
        var work = [_][12]i64{[_]i64{0} ** 12} ** 20;
        var handovers = [_][20]i64{[_]i64{0} ** 20} ** 20;
        var handover_cases = handovers;
        var subcontract = handovers;
        var together = handovers;
        for (self.cases) |item| {
            var workers: [50]usize = undefined;
            var present = [_]bool{false} ** 20;
            var pairs = [_][20]bool{[_]bool{false} ** 20} ** 20;
            for (item.events.items, item.trace, 0..) |event, a, i| {
                const r = d.indexOf(self.resources, event.row.resource).?;
                workers[i] = r;
                present[r] = true;
                events[r] += 1;
                work[r][a] += 1;
                if (i > 0) {
                    handovers[workers[i - 1]][r] += 1;
                    pairs[workers[i - 1]][r] = true;
                }
                if (i >= 2 and workers[i - 2] == r and workers[i - 1] != r) subcontract[r][workers[i - 1]] += 1;
            }
            for (0..self.resources.len) |a| {
                cases[a] += @intFromBool(present[a]);
                for (0..self.resources.len) |b| {
                    handover_cases[a][b] += @intFromBool(pairs[a][b]);
                    if (a < b and present[a] and present[b]) together[a][b] += 1;
                }
            }
        }
        for (self.resources, 0..) |resource, r| {
            var list: std.ArrayList([]const u8) = .empty;
            for (self.activities, 0..) |activity, a| if (work[r][a] > 0) d.append([]const u8,
                 &list, d.fmt("{s}={d}", .{ activity, work[r][a] }));
            out.add("RESOURCE {d} {s} events {d} cases {d} work {s}", .{ r + 1, resource, events[r],
                 cases[r], report.names(list.items) });
        }
        for (rankCounts(20, &handovers)) |r| if (r.a != r.b) out.add("HANDOVER {s} {s} count {d} cases {d}",
             .{ self.resources[r.a], self.resources[r.b], r.count, handover_cases[r.a][r.b] });
        const rows = d.alloc([]const []const u8, self.resources.len);
        for (rows, 0..) |*row, a| {
            const cells = d.alloc([]const u8, self.resources.len);
            for (cells, 0..) |*cell, b| cell.* = d.fmt("{d}", .{handovers[a][b]});
            row.* = cells;
        }
        out.extend(graph.table(rows, 5));
        for (rankCounts(20, &subcontract)) |r| out.add("SUBCONTRACT {s} {s} count {d}", .{ self.resources[r.a],
             self.resources[r.b], r.count });
        for (rankCounts(20, &together)) |r| out.add("TOGETHER {s} {s} cases {d}", .{ self.resources[r.a],
             self.resources[r.b], r.count });
        var total: i64 = 0;
        var own: i64 = 0;
        for (0..self.resources.len) |a| for (0..self.resources.len) |b| {
            total += handovers[a][b];
            if (a == b) own += handovers[a][b];
        };
        out.add("TOTAL handovers {d} self {d} other {d}", .{ total, own, total - own });
        return out;
    }
    fn run(self: *Study, io: std.Io) !void {
        self.buildVariants();
        const workflows = self.mineWorkflows();
        const checked = self.conformanceReport();
        try std.Io.Dir.cwd().createDirPath(io, "output");
        try report.save(io, "log_summary.txt", self.summary());
        try report.save(io, "variants.txt", self.variantReport());
        try report.save(io, "dfg.txt", self.dfgReport());
        try report.save(io, "alpha_net.txt", workflows);
        try report.save(io, "heuristic_net.txt", self.heuristicReport());
        try report.save(io, "conformance.csv", self.conformanceCsv());
        try report.save(io, "conformance.txt", checked);
        try report.save(io, "resources.txt", self.resourceReport());
    }
};
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    d.allocator = arena.allocator();
    var study = try Study.init(init.io);
    try study.run(init.io);
}
