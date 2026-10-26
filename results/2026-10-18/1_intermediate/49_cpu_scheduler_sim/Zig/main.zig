const std = @import("std");
const Text = []const u8;
const I = i64;
const algorithms = [_]Text{ "FCFS", "SJF", "SRTF", "RR", "PRIORITY", "HRRN", "EDF", "LOTTERY", "MLFQ" };
const keys = [_]Text{ "cs", "q", "k", "s", "seed" };
const metrics = [_]Text{ "turnaround", "waiting", "response", "end", "switches", "missed" };
const states = [_]Text{ "FUTURE", "READY", "SWITCH", "RUN", "IO", "DONE" };
const lower = [_]I{ 0, 1, 1, 0, 1 };
const upper = [_]I{ 5, 20, 50, 500, 2147483646 };
const Process = struct {
    id: Text = "",
    arrival: I = 0,
    priority: I = 0,
    deadline: I = 0,
    bursts: [15]I = @splat(0),
    count: usize = 0,
};
const Job = struct {
    state: usize = 0,
    burst: usize = 0,
    left: I = 0,
    effective: I = 0,
    wait: I = 0,
    level: usize = 0,
    used: I = 0,
    enqueued: I = 0,
    start: I = -1,
    finish: I = 0,
    slices: I = 0,
    ready: [8]I = @splat(0),
    began: [8]I = @splat(-1),
    ended: [8]I = @splat(0),
    selections: [8]I = @splat(0),
};
const Queue = struct {
    ids: [10]usize = undefined,
    count: usize = 0,

    fn append(q: *Queue, i: usize) void {
        q.ids[q.count] = i;
        q.count += 1;
    }

    fn remove(q: *Queue, position: usize) usize {
        const result = q.ids[position];
        for (position + 1..q.count) |i| q.ids[i - 1] = q.ids[i];
        q.count -= 1;
        return result;
    }
};

fn eq(a: Text, b: Text) bool {
    return std.mem.eql(u8, a, b);
}

fn number(text: Text) I {
    return std.fmt.parseInt(I, text, 10) catch unreachable;
}

fn index(value: I) usize {
    return @intCast(value);
}

fn lookup(text: Text, names: []const Text) ?usize {
    for (names, 0..) |name, i| if (eq(text, name)) return i;
    return null;
}

fn uses(a: ?usize, key: usize) bool {
    const algorithm = a orelse return true;
    return key == 0 or (key == 1 and (algorithm == 3 or algorithm == 7)) or (key == 2 and algorithm == 4) or (key == 3 and algorithm == 8) or (key == 4 and algorithm == 7);
}

fn draw(random: *I, modulus: I) I {
    random.* = @mod(48271 * random.*, 2147483647);
    return @mod(random.*, modulus);
}
const Scheduler = struct {
    gpa: std.mem.Allocator,
    out: *std.Io.Writer,
    registry: [10]Process = @splat(.{}),
    count: usize = 0,

    fn line(s: *Scheduler, comptime f: Text, args: anytype) !void {
        try s.out.print(f ++ "\n", args);
    }

    fn format(s: *Scheduler, comptime f: Text, args: anytype) !Text {
        return std.fmt.allocPrint(s.gpa, f, args);
    }

    fn decimal(s: *Scheduler, numerator: I, denominator: I) !Text {
        const value = @divTrunc(numerator * 100, denominator);
        return s.format("{d}.{d:0>2}", .{ @divTrunc(value, 100), @mod(value, 100) });
    }

    fn notation(s: *Scheduler, p: [5]I, a: ?usize) !Text {
        var buffer: std.Io.Writer.Allocating = .init(s.gpa);
        var first = true;
        for (keys, 0..) |key, k| if (uses(a, k)) {
            if (!first) try buffer.writer.writeByte(' ');
            first = false;
            try buffer.writer.print("{s}={d}", .{ key, p[k] });
        };
        return buffer.toOwnedSlice();
    }

    fn find(s: *Scheduler, id: Text) ?usize {
        for (s.registry[0..s.count], 0..) |p, i| if (eq(p.id, id)) return i;
        return null;
    }

    fn describe(s: *Scheduler, p: Process) !void {
        try s.out.print("{s} arrival={d} priority={d} deadline=", .{ p.id, p.arrival, p.priority });
        if (p.deadline == 0) try s.out.writeAll("none") else try s.out.print("{d}", .{p.deadline});
        try s.out.writeAll(" bursts=");
        for (p.bursts[0..p.count], 0..) |length, i| try s.out.print("{s}{s}{d}", .{ if (i == 0) "" else ",", if (i % 2 == 0) "C" else "I", length });
        try s.out.writeByte('\n');
    }

    fn sorted(s: *Scheduler) [10]Process {
        var result = s.registry;
        for (0..s.count) |i| {
            const value = result[i];
            var j = i;
            while (j > 0 and std.mem.order(u8, result[j - 1].id, value.id) == .gt) : (j -= 1) result[j] = result[j - 1];
            result[j] = value;
        }
        return result;
    }

    fn parameters(s: *Scheduler, words: []const Text, algorithm: ?usize, preset: ?usize) !?[5]I {
        var p: [5]I = .{ 0, 4, 5, 0, 1 };
        var seen: [5]bool = @splat(false);
        if (preset) |k| seen[k] = true;
        for (words) |word| {
            const split = std.mem.findScalar(u8, word, '=').?;
            const name = word[0..split];
            const value = number(word[split + 1 ..]);
            const key = lookup(name, &keys) orelse {
                try s.line("ERROR unknown key {s}", .{name});
                return null;
            };
            if (!uses(algorithm, key)) {
                try s.line("ERROR key {s} not allowed for {s}", .{ name, algorithms[algorithm.?] });
                return null;
            }
            if (seen[key]) {
                try s.line("ERROR duplicate key {s}", .{name});
                return null;
            }
            if (value < lower[key] or value > upper[key]) {
                try s.line("ERROR invalid {s}", .{name});
                return null;
            }
            seen[key] = true;
            p[key] = value;
        }
        if (s.count == 0) {
            try s.line("ERROR no processes", .{});
            return null;
        }
        return p;
    }

    fn simulate(s: *Scheduler, algorithm: usize, p: [5]I, snapshot: ?I, trace: bool) !*Simulation {
        const result = try std.heap.page_allocator.create(Simulation);
        result.* = .{ .scheduler = s, .algorithm = algorithm, .p = s.sorted(), .count = s.count, .param = p, .random = p[4], .trace = trace };
        for (0..s.count) |i| {
            result.j[i].left = result.p[i].bursts[0];
            result.j[i].effective = result.p[i].priority;
        }
        try result.runSimulation(snapshot);
        return result;
    }

    fn command(s: *Scheduler, w: []const Text) !void {
        const c = w[0];
        if (eq(c, "PROC")) {
            if (s.find(w[1]) != null) return s.line("ERROR duplicate process {s}", .{w[1]});
            if (s.count == 10) return s.line("ERROR too many processes", .{});
            const arrival = number(w[2]);
            const priority = number(w[3]);
            if (arrival > 200) return s.line("ERROR invalid arrival {s}", .{w[1]});
            if (priority > 9) return s.line("ERROR invalid priority {s}", .{w[1]});
            var p: Process = .{ .id = w[1], .arrival = arrival, .priority = priority, .count = w.len - 4 };
            var valid = p.count % 2 == 1;
            var cpu: I = 0;
            var io: I = 0;
            for (w[4..], 0..) |word, i| {
                const length = number(word[1..]);
                if (word[0] != (if (i % 2 == 0) @as(u8, 'C') else @as(u8, 'I')) or length < 1 or length > 30) valid = false;
                p.bursts[i] = length;
                if (i % 2 == 0) cpu += length else io += length;
            }
            if (!valid) return s.line("ERROR invalid bursts {s}", .{w[1]});
            s.registry[s.count] = p;
            s.count += 1;
            return s.line("PROC {s} cpu={d} io={d}", .{ p.id, cpu, io });
        }
        if (eq(c, "GEN")) {
            const amount = index(number(w[2]));
            for (1..amount + 1) |i| {
                const id = try s.format("{s}{d}", .{ w[1], i });
                if (s.find(id) != null) return s.line("ERROR duplicate process {s}", .{id});
            }
            if (s.count + amount > 10) return s.line("ERROR too many processes", .{});
            var random = number(w[3]);
            try s.line("GEN count={d}", .{amount});
            for (1..amount + 1) |i| {
                const arrival = draw(&random, 21);
                const priority = draw(&random, 10);
                var p: Process = .{ .id = try s.format("{s}{d}", .{ w[1], i }), .arrival = arrival, .priority = priority };
                const bursts = index(1 + draw(&random, 3));
                for (0..bursts) |b| {
                    if (b > 0) {
                        p.bursts[p.count] = 1 + draw(&random, 8);
                        p.count += 1;
                    }
                    p.bursts[p.count] = 1 + draw(&random, 9);
                    p.count += 1;
                }
                s.registry[s.count] = p;
                s.count += 1;
                try s.describe(p);
            }
            return;
        }
        if (eq(c, "SETPRIO") or eq(c, "DEADLINE") or eq(c, "DROP")) {
            const i = s.find(w[1]) orelse return s.line("ERROR unknown process {s}", .{w[1]});
            if (eq(c, "DROP")) {
                for (i + 1..s.count) |j| s.registry[j - 1] = s.registry[j];
                s.count -= 1;
                return s.line("DROP {s}", .{w[1]});
            }
            const value = number(w[2]);
            const priority = eq(c, "SETPRIO");
            if (value > (if (priority) @as(I, 9) else @as(I, 1000))) return s.line("ERROR invalid {s} {s}", .{ if (priority) "priority" else "deadline", w[1] });
            if (priority) {
                s.registry[i].priority = value;
                return s.line("SETPRIO {s} priority={d}", .{ w[1], value });
            }
            s.registry[i].deadline = value;
            if (value == 0) return s.line("DEADLINE {s} none", .{w[1]});
            return s.line("DEADLINE {s} {d}", .{ w[1], value });
        }
        if (eq(c, "CLEAR")) {
            try s.line("CLEAR count={d}", .{s.count});
            s.count = 0;
            return;
        }
        if (eq(c, "LIST")) {
            try s.line("LIST count={d}", .{s.count});
            const list = s.sorted();
            for (list[0..s.count]) |p| try s.describe(p);
            return;
        }
        const all = eq(c, "COMPARE") or eq(c, "RANK");
        const diff = eq(c, "DIFF");
        var algorithm: ?usize = null;
        var second: usize = 0;
        var metric_index: ?usize = null;
        var offset: usize = 2;
        if (!all) {
            algorithm = lookup(w[1], &algorithms) orelse return s.line("ERROR unknown algorithm {s}", .{w[1]});
            if (diff) {
                second = lookup(w[2], &algorithms) orelse return s.line("ERROR unknown algorithm {s}", .{w[2]});
                offset = 3;
            }
        } else if (eq(c, "RANK")) metric_index = lookup(w[1], &metrics) orelse return s.line("ERROR unknown metric {s}", .{w[1]}) else offset = 1;
        var argument: I = -1;
        var preset: ?usize = null;
        var lo: I = 0;
        var hi: I = 0;
        if (eq(c, "WINDOW") or eq(c, "SNAPSHOT")) {
            argument = number(w[2]);
            offset = 3;
            if (eq(c, "WINDOW") and (argument < 1 or argument > 1000)) return s.line("ERROR invalid window", .{});
        }
        if (eq(c, "SWEEP")) {
            const key = lookup(w[2], &keys) orelse return s.line("ERROR unknown key {s}", .{w[2]});
            preset = key;
            if (!uses(algorithm, key)) return s.line("ERROR key {s} not allowed for {s}", .{ w[2], algorithms[algorithm.?] });
            lo = number(w[3]);
            hi = number(w[4]);
            if (lo > hi or lo < lower[key] or hi > upper[key] or hi - lo > 20) return s.line("ERROR invalid range", .{});
            offset = 5;
        }
        var p = (try s.parameters(w[offset..], if (all or diff) null else algorithm, preset)) orelse return;
        const note = try s.notation(p, if (all or diff) null else algorithm);
        if (preset) |key| {
            try s.line("SWEEP {s} {s} {d} {d}", .{ algorithms[algorithm.?], keys[key], lo, hi });
            var best_total: ?I = null;
            var best_value = lo;
            var value = lo;
            while (value <= hi) : (value += 1) {
                p[key] = value;
                const simulation = try s.simulate(algorithm.?, p, null, false);
                try s.line("{s} turnaround={s} waiting={s} response={s} util={s} end={d} switches={d}", .{ try s.notation(p, algorithm), try s.decimal(simulation.totals[0], @intCast(s.count)), try s.decimal(simulation.totals[1], @intCast(s.count)), try s.decimal(simulation.totals[2], @intCast(s.count)), try simulation.util(), simulation.end, simulation.switches });
                if (best_total == null or simulation.totals[1] < best_total.?) {
                    best_total = simulation.totals[1];
                    best_value = value;
                }
                std.heap.page_allocator.destroy(simulation);
            }
            return s.line("BEST {s}={d}", .{ keys[key], best_value });
        }
        if (diff) {
            const one = try s.simulate(algorithm.?, p, null, false);
            defer std.heap.page_allocator.destroy(one);
            const two = try s.simulate(second, p, null, false);
            defer std.heap.page_allocator.destroy(two);
            try s.line("DIFF {s} {s} {s}", .{ w[1], w[2], note });
            var wins: I = 0;
            var losses: I = 0;
            var ties: I = 0;
            for (0..s.count) |i| {
                try s.line("{s} turnaround={d}/{d} waiting={d}/{d} response={d}/{d}", .{ one.p[i].id, one.metric(i, 0), two.metric(i, 0), one.metric(i, 1), two.metric(i, 1), one.metric(i, 2), two.metric(i, 2) });
                if (one.metric(i, 0) < two.metric(i, 0)) wins += 1 else if (one.metric(i, 0) > two.metric(i, 0)) losses += 1 else ties += 1;
            }
            return s.line("WINS {s}={d} {s}={d} ties={d}", .{ w[1], wins, w[2], losses, ties });
        }
        if (all) {
            var totals: [9][3]I = undefined;
            var values: [9]I = undefined;
            var texts: [9]Text = undefined;
            if (metric_index) |_| try s.line("RANK {s} {s}", .{ w[1], note }) else {
                try s.line("COMPARE {s}", .{note});
                try s.line("{s: <8} {s: >8} {s: >8} {s: >8} {s: >8} {s: >8} {s: >8} {s: >8}", .{ "ALGO", "TURN", "WAIT", "RESP", "UTIL", "END", "SWITCH", "MISS" });
            }
            for (0..9) |a| {
                const simulation = try s.simulate(a, p, null, false);
                totals[a] = simulation.totals;
                if (metric_index) |m| {
                    values[a] = simulation.rankValue(m);
                    texts[a] = if (m < 3) try s.decimal(values[a], @intCast(s.count)) else try s.format("{d}", .{values[a]});
                } else try s.line("{s: <8} {s: >8} {s: >8} {s: >8} {s: >8} {s: >8} {s: >8} {s: >8}", .{ algorithms[a], try s.decimal(totals[a][0], @intCast(s.count)), try s.decimal(totals[a][1], @intCast(s.count)), try s.decimal(totals[a][2], @intCast(s.count)), try simulation.util(), try s.format("{d}", .{simulation.end}), try s.format("{d}", .{simulation.switches}), try s.format("{d}", .{simulation.missed}) });
                std.heap.page_allocator.destroy(simulation);
            }
            if (metric_index == null) {
                var best: [3]usize = @splat(0);
                for (0..3) |m| for (1..9) |a| {
                    if (totals[a][m] < totals[best[m]][m]) best[m] = a;
                };
                return s.line("BEST turnaround={s} waiting={s} response={s}", .{ algorithms[best[0]], algorithms[best[1]], algorithms[best[2]] });
            }
            var ids: [9]usize = undefined;
            for (0..9) |i| {
                var j = i;
                while (j > 0 and values[ids[j - 1]] > values[i]) : (j -= 1) ids[j] = ids[j - 1];
                ids[j] = i;
            }
            for (ids) |i| {
                var rank: usize = 1;
                for (values) |v| if (v < values[i]) {
                    rank += 1;
                };
                try s.line("{d} {s} {s}", .{ rank, algorithms[i], texts[i] });
            }
            return;
        }
        const trace = eq(c, "TRACE");
        if (trace) try s.line("TRACE {s} {s}", .{ algorithms[algorithm.?], note });
        const simulation = try s.simulate(algorithm.?, p, if (eq(c, "SNAPSHOT")) argument else null, trace);
        defer std.heap.page_allocator.destroy(simulation);
        try simulation.output(c, argument);
    }
};
const Simulation = struct {
    scheduler: *Scheduler,
    algorithm: usize,
    p: [10]Process,
    count: usize,
    param: [5]I,
    random: I,
    trace: bool,
    j: [10]Job = @splat(.{}),
    q: [3]Queue = @splat(.{}),
    cpu: usize = 0,
    current: usize = 0,
    previous: ?usize = null,
    switch_left: I = 0,
    run: I = 0,
    switches: I = 0,
    end: I = 0,
    busy: I = 0,
    switching: I = 0,
    idle: I = 0,
    maxq: usize = 0,
    sumq: I = 0,
    events: [5]I = @splat(0),
    labels: [20000]I = undefined,
    timeline: [10][20000]u8 = undefined,
    snapshot: Text = "",
    totals: [3]I = @splat(0),
    missed: I = 0,
    met: I = 0,

    fn event(s: *Simulation, t: I, kind: usize, id: ?usize, value: ?I) !void {
        const names = [_]Text{ "PREEMPT", "EXPIRE", "DEMOTE", "BOOST", "AGE", "ARRIVE", "IODONE", "START", "DONE", "IO", "SWITCH", "DISPATCH" };
        if (kind < 5) s.events[kind] += 1;
        if (s.trace) {
            try s.scheduler.out.print("{d} {s}", .{ t, names[kind] });
            if (id) |i| try s.scheduler.out.print(" {s}", .{s.p[i].id});
            if (value) |v| try s.scheduler.out.print(" {d}", .{v});
            try s.scheduler.out.writeByte('\n');
        }
    }

    fn enqueue(s: *Simulation, i: usize, t: I) void {
        s.j[i].state = 1;
        s.j[i].enqueued = t;
        s.q[if (s.algorithm == 8) s.j[i].level else 0].append(i);
    }

    fn start(s: *Simulation, i: usize, t: I) void {
        s.cpu = 3;
        s.current = i;
        s.run = 0;
        s.j[i].state = 3;
        if (s.j[i].start < 0) s.j[i].start = t;
        if (s.j[i].began[s.j[i].burst / 2] < 0) s.j[i].began[s.j[i].burst / 2] = t;
    }

    fn deadline(s: *Simulation, i: usize) I {
        return if (s.p[i].deadline == 0) 1000000000 else s.p[i].arrival + s.p[i].deadline;
    }

    fn preempts(s: *Simulation, i: usize) bool {
        for (s.q, 0..) |queue, level| for (queue.ids[0..queue.count]) |other| {
            if ((s.algorithm == 2 and s.j[other].left < s.j[i].left) or (s.algorithm == 4 and s.j[other].effective < s.j[i].effective) or (s.algorithm == 6 and s.deadline(other) < s.deadline(i)) or (s.algorithm == 8 and level < s.j[i].level)) return true;
        };
        return false;
    }

    fn choose(s: *Simulation, queue: *Queue, t: I) usize {
        if (s.algorithm == 7) {
            var total: I = 0;
            for (queue.ids[0..queue.count]) |i| total += 10 - s.p[i].priority;
            var target = draw(&s.random, total);
            for (queue.ids[0..queue.count], 0..) |i, position| {
                target -= 10 - s.p[i].priority;
                if (target < 0) return position;
            }
        }
        var selected: usize = 0;
        for (queue.ids[0..queue.count], 0..) |i, position| {
            const other = queue.ids[selected];
            const a = s.j[i];
            const b = s.j[other];
            const better = switch (s.algorithm) {
                1, 2 => a.left < b.left,
                4 => a.effective < b.effective,
                5 => (t - a.enqueued + a.left) * b.left > (t - b.enqueued + b.left) * a.left,
                6 => s.deadline(i) < s.deadline(other),
                else => false,
            };
            if (better) selected = position;
        }
        return selected;
    }

    fn capture(s: *Simulation) !void {
        var buffer: std.Io.Writer.Allocating = .init(s.scheduler.gpa);
        const out = &buffer.writer;
        if (s.cpu == 0) try out.writeAll("CPU IDLE\n") else try out.print("CPU {s} {s}\n", .{ states[s.cpu], s.p[s.current].id });
        for (0..(if (s.algorithm == 8) @as(usize, 3) else @as(usize, 1))) |level| {
            if (s.algorithm == 8) try out.print("QUEUE{d}", .{level}) else try out.writeAll("QUEUE");
            const queue = s.q[level];
            if (queue.count == 0) try out.writeAll(" none");
            for (queue.ids[0..queue.count]) |i| try out.print(" {s}", .{s.p[i].id});
            try out.writeByte('\n');
        }
        for (0..s.count) |i| {
            const j = s.j[i];
            try out.print("{s} {s}", .{ s.p[i].id, states[j.state] });
            if (j.state == 0) try out.print(" at={d}", .{s.p[i].arrival}) else if (j.state == 5) try out.print(" at={d}", .{j.finish}) else {
                try out.print(" burst={d} left={d}", .{ j.burst + 1, j.left });
                if (s.algorithm == 4) try out.print(" prio={d}", .{j.effective});
                if (s.algorithm == 8) try out.print(" level={d} used={d}", .{ j.level, j.used });
            }
            try out.writeByte('\n');
        }
        s.snapshot = try buffer.toOwnedSlice();
    }

    fn runSimulation(s: *Simulation, snapshot_time: ?I) !void {
        var t: I = 0;
        while (true) : (t += 1) {
            if (s.algorithm == 4) for (s.q[0].ids[0..s.q[0].count]) |i| {
                s.j[i].wait += 1;
                if (s.j[i].wait == s.param[2]) {
                    s.j[i].wait = 0;
                    if (s.j[i].effective > 0) {
                        s.j[i].effective -= 1;
                        try s.event(t, 4, i, s.j[i].effective);
                    }
                }
            };
            for (0..s.count) |i| if (s.j[i].state == 4 and s.j[i].left == 0) {
                s.j[i].burst += 1;
                s.j[i].left = s.p[i].bursts[s.j[i].burst];
                s.j[i].ready[s.j[i].burst / 2] = t;
                s.enqueue(i, t);
                try s.event(t, 6, i, null);
            };
            for (0..s.count) |i| if (s.j[i].state == 0 and s.p[i].arrival == t) {
                s.j[i].ready[0] = t;
                s.enqueue(i, t);
                try s.event(t, 5, i, null);
            };
            if (s.cpu == 2 and s.switch_left == 0) {
                s.start(s.current, t);
                try s.event(t, 7, s.current, null);
            } else if (s.cpu == 3) {
                const i = s.current;
                const j = &s.j[i];
                if (j.left == 0 and j.burst + 1 == s.p[i].count) {
                    j.state = 5;
                    j.finish = t;
                    try s.event(t, 8, i, null);
                    s.cpu = 0;
                } else {
                    const demoted = s.algorithm == 8 and j.level < 2 and j.used == (if (j.level == 0) @as(I, 4) else @as(I, 8));
                    if (demoted) {
                        j.level += 1;
                        j.used = 0;
                        try s.event(t, 2, i, @intCast(j.level));
                    }
                    if (j.left == 0) {
                        j.burst += 1;
                        j.left = s.p[i].bursts[j.burst];
                        j.state = 4;
                        try s.event(t, 9, i, j.left);
                        s.cpu = 0;
                    } else if (demoted) {
                        s.enqueue(i, t);
                        s.cpu = 0;
                    } else if ((s.algorithm == 3 or s.algorithm == 7) and s.run == s.param[1]) {
                        s.enqueue(i, t);
                        try s.event(t, 1, i, null);
                        s.cpu = 0;
                    } else if (s.preempts(i)) {
                        s.enqueue(i, t);
                        try s.event(t, 0, i, null);
                        s.cpu = 0;
                    }
                }
            }
            var done: usize = 0;
            for (s.j[0..s.count]) |j| if (j.state == 5) {
                done += 1;
            };
            if (done == s.count) {
                s.end = t;
                if (snapshot_time != null and s.snapshot.len == 0) try s.capture();
                break;
            }
            if (s.algorithm == 8 and s.param[3] > 0 and t > 0 and @mod(t, s.param[3]) == 0) {
                for (1..3) |level| {
                    for (s.q[level].ids[0..s.q[level].count]) |i| s.q[0].append(i);
                    s.q[level].count = 0;
                }
                for (s.j[0..s.count]) |*j| {
                    j.level = 0;
                    j.used = 0;
                }
                try s.event(t, 3, null, null);
            }
            if (s.cpu == 0) {
                var selected_level: ?usize = null;
                for (0..3) |level| if (s.q[level].count > 0) {
                    selected_level = level;
                    break;
                };
                if (selected_level) |level| {
                    const queue = &s.q[level];
                    const position = s.choose(queue, t);
                    const i = queue.remove(position);
                    const j = &s.j[i];
                    j.effective = s.p[i].priority;
                    j.wait = 0;
                    j.slices += 1;
                    j.selections[j.burst / 2] += 1;
                    const changed = s.previous == null or i != s.previous.?;
                    if (changed) s.switches += 1;
                    if (changed and s.param[0] > 0) {
                        s.cpu = 2;
                        s.current = i;
                        s.switch_left = s.param[0];
                        j.state = 2;
                        try s.event(t, 10, i, null);
                    } else {
                        s.start(i, t);
                        try s.event(t, 11, i, null);
                    }
                }
            }
            if (snapshot_time != null and t == snapshot_time.?) try s.capture();
            const qlen = s.q[0].count + s.q[1].count + s.q[2].count;
            s.sumq += @intCast(qlen);
            s.maxq = @max(s.maxq, qlen);
            for (0..s.count) |i| s.timeline[i][index(t)] = "-.s#i-"[s.j[i].state];
            if (s.cpu == 3) {
                const j = &s.j[s.current];
                j.left -= 1;
                j.used += 1;
                s.run += 1;
                s.previous = s.current;
                s.labels[index(t)] = @intCast(s.current);
                s.busy += 1;
                if (j.left == 0) j.ended[j.burst / 2] = t + 1;
            } else if (s.cpu == 2) {
                s.switch_left -= 1;
                s.labels[index(t)] = -2;
                s.switching += 1;
            } else {
                s.labels[index(t)] = -1;
                s.idle += 1;
            }
            for (s.j[0..s.count]) |*j| if (j.state == 4) {
                j.left -= 1;
            };
        }
        for (0..s.count) |i| {
            for (0..3) |m| s.totals[m] += s.metric(i, m);
            if (s.p[i].deadline > 0) {
                if (s.j[i].finish > s.deadline(i)) s.missed += 1 else s.met += 1;
            }
        }
    }

    fn metric(s: *Simulation, i: usize, m: usize) I {
        const turnaround = s.j[i].finish - s.p[i].arrival;
        if (m == 0) return turnaround;
        if (m == 2) return s.j[i].start - s.p[i].arrival;
        var total: I = 0;
        for (s.p[i].bursts[0..s.p[i].count]) |length| total += length;
        return turnaround - total;
    }

    fn rankValue(s: *Simulation, m: usize) I {
        return if (m < 3) s.totals[m] else if (m == 3) s.end else if (m == 4) s.switches else s.missed;
    }

    fn label(s: *Simulation, time: usize) Text {
        const i = s.labels[time];
        return if (i == -1) "IDLE" else if (i == -2) "CS" else s.p[index(i)].id;
    }

    fn util(s: *Simulation) !Text {
        return s.scheduler.decimal(s.busy * 100, s.end);
    }

    fn output(s: *Simulation, command: Text, argument: I) !void {
        const host = s.scheduler;
        const out = host.out;
        const note = try host.notation(s.param, s.algorithm);
        if (eq(command, "TRACE")) return host.line("END {d}", .{s.end});
        if (eq(command, "TIMELINE")) {
            if (s.end > 100) return host.line("ERROR too long {d}", .{s.end});
            try host.line("TIMELINE {s} {s} end={d}", .{ algorithms[s.algorithm], note, s.end });
            for (0..s.count) |i| try host.line("{s: <8} {s}", .{ s.p[i].id, s.timeline[i][0..index(s.end)] });
            return;
        }
        if (eq(command, "SNAPSHOT")) {
            try host.line("SNAPSHOT {s} {s} t={d}", .{ algorithms[s.algorithm], note, argument });
            return out.writeAll(s.snapshot);
        }
        if (eq(command, "WINDOW")) {
            try host.line("WINDOW {s} {s} width={d}", .{ algorithms[s.algorithm], note, argument });
            var begin: I = 0;
            while (begin < s.end) : (begin += argument) {
                const end = @min(begin + argument, s.end);
                var busy: I = 0;
                var cs: I = 0;
                var idle: I = 0;
                var hits: [10]I = @splat(0);
                for (s.labels[index(begin)..index(end)]) |i| {
                    if (i == -1) idle += 1 else if (i == -2) cs += 1 else {
                        busy += 1;
                        hits[index(i)] += 1;
                    }
                }
                var top: ?usize = null;
                for (0..s.count) |i| if (hits[i] > 0 and (top == null or hits[i] > hits[top.?])) {
                    top = i;
                };
                try host.line("{d}-{d} busy={d} switch={d} idle={d} util={s} top={s}", .{ begin, end, busy, cs, idle, try host.decimal(busy * 100, end - begin), if (top) |i| s.p[i].id else "none" });
            }
            return;
        }
        try host.line("{s} {s} {s}", .{ command, algorithms[s.algorithm], note });
        if (eq(command, "BURSTS")) {
            for (0..s.count) |i| {
                var b: usize = 0;
                while (b < s.p[i].count) : (b += 2) {
                    const k = b / 2;
                    const j = s.j[i];
                    const length = s.p[i].bursts[b];
                    try host.line("{s} #{d} len={d} ready={d} start={d} end={d} wait={d} slices={d}", .{ s.p[i].id, k + 1, length, j.ready[k], j.began[k], j.ended[k], j.ended[k] - j.ready[k] - length, j.selections[k] });
                }
            }
            return;
        }
        if (eq(command, "STATS")) {
            for (0..3) |m| {
                var values: [10]I = undefined;
                var lo: usize = 0;
                var hi: usize = 0;
                for (0..s.count) |i| {
                    values[i] = s.metric(i, m);
                    if (values[i] < s.metric(lo, m)) lo = i;
                    if (values[i] > s.metric(hi, m)) hi = i;
                }
                for (0..s.count) |i| {
                    const value = values[i];
                    var j = i;
                    while (j > 0 and values[j - 1] > value) : (j -= 1) values[j] = values[j - 1];
                    values[j] = value;
                }
                const middle = s.count / 2;
                const doubled = if (s.count % 2 == 1) 2 * values[middle] else values[middle - 1] + values[middle];
                try host.line("{s} min={d} ({s}) max={d} ({s}) median={d}.{d} total={d}", .{ metrics[m], s.metric(lo, m), s.p[lo].id, s.metric(hi, m), s.p[hi].id, @divTrunc(doubled, 2), 5 * @mod(doubled, 2), s.totals[m] });
            }
            return;
        }
        var begin: usize = 0;
        var segments: usize = 0;
        var t: usize = 1;
        while (t <= index(s.end)) : (t += 1) if (t == index(s.end) or !eq(s.label(t), s.label(begin))) {
            if (segments % 8 == 0) try out.writeAll("GANTT ");
            try out.print("[{d}-{d} {s}]", .{ begin, t, s.label(begin) });
            segments += 1;
            if (segments % 8 == 0 or t == index(s.end)) try out.writeByte('\n');
            begin = t;
        };
        for (0..s.count) |i| {
            try out.print("{s} arrival={d} done={d} turnaround={d} waiting={d} response={d} slices={d}", .{ s.p[i].id, s.p[i].arrival, s.j[i].finish, s.metric(i, 0), s.metric(i, 1), s.metric(i, 2), s.j[i].slices });
            if (s.p[i].deadline > 0) try out.print(" deadline={d} late={d}", .{ s.deadline(i), @max(0, s.j[i].finish - s.deadline(i)) });
            try out.writeByte('\n');
        }
        try host.line("AVERAGE turnaround={s} waiting={s} response={s}", .{ try host.decimal(s.totals[0], @intCast(s.count)), try host.decimal(s.totals[1], @intCast(s.count)), try host.decimal(s.totals[2], @intCast(s.count)) });
        try host.line("CPU end={d} busy={d} switch={d} idle={d} switches={d} util={s}", .{ s.end, s.busy, s.switching, s.idle, s.switches, try s.util() });
        try host.line("QUEUE max={d} avg={s}", .{ s.maxq, try host.decimal(s.sumq, s.end) });
        try host.line("EVENTS preempt={d} expire={d} demote={d} boost={d} age={d}", .{ s.events[0], s.events[1], s.events[2], s.events[3], s.events[4] });
        try host.line("DEADLINE met={d} missed={d}", .{ s.met, s.missed });
    }
};

fn readLine(reader: *std.Io.Reader, gpa: std.mem.Allocator) !?Text {
    var buffer: std.Io.Writer.Allocating = .init(gpa);
    defer buffer.deinit();
    _ = try reader.streamDelimiterEnding(&buffer.writer, '\n');
    if (reader.bufferedLen() == 0 and buffer.written().len == 0) return null;
    if (reader.bufferedLen() > 0) reader.toss(1);
    return buffer.toOwnedSlice();
}

pub fn main(init: std.process.Init) !void {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var ib: [4096]u8 = undefined;
    var ob: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &ib);
    var output = std.Io.File.stdout().writerStreaming(init.io, &ob);
    var scheduler: Scheduler = .{ .gpa = gpa, .out = &output.interface };
    const first = std.mem.trim(u8, (try readLine(&input.interface, gpa)).?, "\r");
    const count = index(number(first));
    for (0..count) |_| {
        const text = std.mem.trim(u8, (try readLine(&input.interface, gpa)).?, "\r");
        var words: std.ArrayList(Text) = .empty;
        defer words.deinit(gpa);
        var it = std.mem.splitScalar(u8, text, ' ');
        while (it.next()) |word| try words.append(gpa, word);
        try scheduler.command(words.items);
    }
    try output.interface.flush();
}
