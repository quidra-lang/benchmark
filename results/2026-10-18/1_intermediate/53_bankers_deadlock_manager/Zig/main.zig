const std = @import("std");
const Text = []const u8;
const I = i64;
const Vec = [8]I;
fn eq(a: Text, b: Text) bool {
    return std.mem.eql(u8, a, b);
}
fn number(a: Text) I {
    return std.fmt.parseInt(I, a, 10) catch unreachable;
}
fn index(a: I) usize {
    return @intCast(a);
}
fn sum(v: Vec) I {
    var answer: I = 0;
    for (v) |item| answer += item;
    return answer;
}
fn fits(a: Vec, b: Vec) bool {
    for (a, b) |left, right| if (left > right) return false;
    return true;
}
fn combine(a: Vec, b: Vec, sign: I) Vec {
    var answer = a;
    for (&answer, b) |*left, right| left.* += sign * right;
    return answer;
}
const Ids = struct {
    values: [100]usize = undefined,
    len: usize = 0,
    fn add(s: *Ids, who: usize) void {
        s.values[s.len] = who;
        s.len += 1;
    }
    fn items(s: *const Ids) []const usize {
        return s.values[0..s.len];
    }
    fn contains(s: *const Ids, who: usize) bool {
        for (s.items()) |item| if (item == who) return true;
        return false;
    }
};
const Host = struct {
    a: std.mem.Allocator,
    out: *std.Io.Writer,
    fn text(h: Host, comptime f: Text, args: anytype) !Text {
        return std.fmt.allocPrint(h.a, f, args);
    }
    fn line(h: Host, comptime f: Text, args: anytype) !void {
        try h.out.print(f ++ "\n", args);
    }
    fn vector(h: Host, v: Vec, m: usize) !Text {
        var b: std.Io.Writer.Allocating = .init(h.a);
        try b.writer.writeByte('(');
        for (v[0..m], 0..) |item, j| {
            if (j > 0) try b.writer.writeByte(',');
            try b.writer.print("{d}", .{item});
        }
        try b.writer.writeByte(')');
        return b.toOwnedSlice();
    }
    fn people(h: Host, ids: Ids, separator: Text) !Text {
        var b: std.Io.Writer.Allocating = .init(h.a);
        for (ids.items(), 0..) |who, j| {
            if (j > 0) try b.writer.writeAll(separator);
            try b.writer.print("P{d}", .{who});
        }
        return b.toOwnedSlice();
    }
};
const Job = struct { exists: bool = false, maximum: Vec = @splat(0), allocation: Vec = @splat(0), created: I = 0 };
const Waiting = struct { who: usize, amount: Vec, since: I };
const Event = struct { stamp: I, kind: Text, who: usize, amount: Vec, waited: I = 0 };
const Model = struct {
    m: usize = 0,
    total: Vec = @splat(0),
    available: Vec = @splat(0),
    jobs: [100]Job = @splat(.{}),
    queue: std.ArrayList(Waiting) = .empty,
    events: std.ArrayList(Event) = .empty,
    fn clone(s: Model, a: std.mem.Allocator) !Model {
        var answer = s;
        answer.queue = .empty;
        answer.events = .empty;
        try answer.queue.appendSlice(a, s.queue.items);
        try answer.events.appendSlice(a, s.events.items);
        return answer;
    }
};
const Snapshot = struct { name: Text, data: Model };
const Check = struct { order: Ids = .{}, remaining: Ids = .{} };
const Status = enum { rejected, blocked, granted };
const Decision = struct { status: Status, reason: Text = "", order: Ids = .{} };
const Manager = struct {
    h: Host,
    data: Model = .{},
    mode: Text = "AVOID",
    policy: Text = "ALLOC",
    tracing: bool = false,
    autodetect: bool = false,
    stamp: I = 0,
    snapshots: std.ArrayList(Snapshot) = .empty,
    fn queued(s: *const Manager, who: usize) ?usize {
        for (s.data.queue.items, 0..) |waiting, j| if (waiting.who == who) return j;
        return null;
    }
    fn requestOf(s: *const Manager, who: usize) Vec {
        if (s.queued(who)) |at| return s.data.queue.items[at].amount;
        return @splat(0);
    }
    fn needOf(s: *const Manager, who: usize) Vec {
        return combine(s.data.jobs[who].maximum, s.data.jobs[who].allocation, -1);
    }
    fn inspect(s: *const Manager, model: Model, detection: bool, verbose: bool) !Check {
        var work = model.available;
        var done: [100]bool = undefined;
        var idle: Ids = .{};
        for (model.jobs, 0..) |job, who| {
            done[who] = !job.exists;
            if (job.exists and detection and sum(job.allocation) == 0) {
                done[who] = true;
                idle.add(who);
            }
        }
        const tag: Text = if (detection) "detect" else "safety";
        if (verbose) {
            const suffix = if (idle.len > 0) try s.h.text(" idle {s}", .{try s.h.people(idle, " ")}) else "";
            try s.h.line("[{s}] start work={s}{s}", .{ tag, try s.h.vector(work, model.m), suffix });
        }
        var result: Check = .{};
        while (true) {
            var chosen: ?usize = null;
            for (0..100) |who| {
                if (done[who]) continue;
                var requirement = combine(model.jobs[who].maximum, model.jobs[who].allocation, -1);
                if (detection) {
                    requirement = @splat(0);
                    for (model.queue.items) |waiting| {
                        if (waiting.who == who) requirement = waiting.amount;
                    }
                }
                if (fits(requirement, work)) {
                    chosen = who;
                    break;
                }
            }
            const who = chosen orelse break;
            done[who] = true;
            work = combine(work, model.jobs[who].allocation, 1);
            result.order.add(who);
            if (verbose) try s.h.line("[{s}] P{d} can finish, work={s}", .{ tag, who, try s.h.vector(work, model.m) });
        }
        for (done, 0..) |finished, who| if (!finished) {
            result.remaining.add(who);
        };
        if (verbose and result.remaining.len > 0) try s.h.line("[{s}] stuck work={s} remaining {s}", .{ tag, try s.h.vector(work, model.m), try s.h.people(result.remaining, " ") });
        return result;
    }
    fn decide(s: *const Manager, who: usize, amount: Vec, reject: bool, verbose: bool) !Decision {
        if (reject) {
            if (s.queued(who) != null) return .{ .status = .rejected, .reason = try s.h.text("process P{d} is blocked", .{who}) };
            if (sum(amount) == 0) return .{ .status = .rejected, .reason = "zero vector" };
            if (!fits(amount, s.needOf(who))) return .{ .status = .rejected, .reason = "request exceeds need" };
            if (eq(s.mode, "ORDER")) {
                var last: ?usize = null;
                for (s.data.jobs[who].allocation, 0..) |value, j| if (value > 0) {
                    last = j;
                };
                if (last) |end| for (amount[0 .. end + 1]) |value| {
                    if (value > 0) return .{ .status = .rejected, .reason = "resource order violation" };
                };
            }
        }
        if (!fits(amount, s.data.available)) return .{ .status = .blocked, .reason = "insufficient resources" };
        if (!eq(s.mode, "AVOID")) return .{ .status = .granted };
        var trial = s.data;
        trial.available = combine(trial.available, amount, -1);
        trial.jobs[who].allocation = combine(trial.jobs[who].allocation, amount, 1);
        const checked = try s.inspect(trial, false, verbose);
        return if (checked.remaining.len == 0) .{ .status = .granted, .order = checked.order } else .{ .status = .blocked, .reason = "unsafe state" };
    }
    fn record(s: *Manager, kind: Text, who: usize, amount: Vec, waited: I) !void {
        try s.data.events.append(s.h.a, .{ .stamp = s.stamp, .kind = kind, .who = who, .amount = amount, .waited = waited });
    }
    fn grant(s: *Manager, who: usize, amount: Vec) void {
        s.data.available = combine(s.data.available, amount, -1);
        s.data.jobs[who].allocation = combine(s.data.jobs[who].allocation, amount, 1);
    }
    fn retryQueue(s: *Manager) !void {
        var at: usize = 0;
        while (at < s.data.queue.items.len) {
            const waiting = s.data.queue.items[at];
            const choice = try s.decide(waiting.who, waiting.amount, false, s.tracing);
            if (choice.status == .granted) {
                s.grant(waiting.who, waiting.amount);
                _ = s.data.queue.orderedRemove(at);
                try s.h.line("unblocked P{d} {s}", .{ waiting.who, try s.h.vector(waiting.amount, s.data.m) });
                try s.record("unblocked", waiting.who, waiting.amount, s.stamp - waiting.since);
            } else at += 1;
        }
    }
    fn terminate(s: *Manager, who: usize, kind: Text, retry_after: bool) !void {
        const released = s.data.jobs[who].allocation;
        if (s.queued(who)) |at| _ = s.data.queue.orderedRemove(at);
        s.data.available = combine(s.data.available, released, 1);
        s.data.jobs[who].exists = false;
        try s.h.line("{s} P{d} released {s}", .{ kind, who, try s.h.vector(released, s.data.m) });
        try s.record(kind, who, released, 0);
        if (retry_after) try s.retryQueue();
    }
    fn permutations(s: *const Manager, work: Vec, prefix: Ids, count: *usize, limit: usize, results: *std.ArrayList(Ids)) anyerror!void {
        var complete = true;
        for (s.data.jobs, 0..) |job, who| {
            if (job.exists and !prefix.contains(who)) {
                complete = false;
                if (fits(s.needOf(who), work)) {
                    var extended = prefix;
                    extended.add(who);
                    try s.permutations(combine(work, job.allocation, 1), extended, count, limit, results);
                }
            }
        }
        if (complete) {
            count.* += 1;
            if (results.items.len < limit) try results.append(s.h.a, prefix);
        }
    }
    fn tableVector(s: *const Manager, values: Vec) !Text {
        var b: std.Io.Writer.Allocating = .init(s.h.a);
        for (0..s.data.m) |j| {
            if (j > 0) try b.writer.writeByte(' ');
            const width = (try s.h.text("{d}", .{s.data.total[j]})).len;
            const cell = try s.h.text("{d}", .{values[j]});
            try b.writer.splatByteAll(' ', width - cell.len);
            try b.writer.writeAll(cell);
        }
        return b.toOwnedSlice();
    }
    fn tableRow(s: *const Manager, heading: Text, cells: []const Text, widths: [4]usize) !void {
        var b: std.Io.Writer.Allocating = .init(s.h.a);
        try b.writer.writeAll(heading);
        try b.writer.splatByteAll(' ', 9 - heading.len);
        for (cells, 0..) |cell, j| {
            try b.writer.writeAll("  ");
            try b.writer.writeAll(cell);
            try b.writer.splatByteAll(' ', widths[j] - cell.len);
        }
        try s.h.line("{s}", .{std.mem.trimEnd(u8, b.written(), " ")});
    }
    const Cycle = struct { path: Ids, labels: [100]usize };
    fn findCycles(s: *const Manager, resource_graph: bool, path: Ids, labels: [100]usize, results: *std.ArrayList(Cycle)) anyerror!void {
        const current = path.values[path.len - 1];
        const start = path.values[0];
        const wanted = s.requestOf(current);
        for (s.data.jobs, 0..) |job, next_id| {
            if (!job.exists or (!resource_graph and current == next_id)) continue;
            for (0..s.data.m) |j| {
                if (job.allocation[j] == 0 or (if (resource_graph) wanted[j] <= 0 else wanted[j] <= s.data.available[j])) continue;
                var next_labels = labels;
                next_labels[path.len - 1] = j;
                if (next_id == start) {
                    try results.append(s.h.a, .{ .path = path, .labels = next_labels });
                } else if (next_id > start and !path.contains(next_id)) {
                    var extended = path;
                    extended.add(next_id);
                    try s.findCycles(resource_graph, extended, next_labels, results);
                }
                if (!resource_graph) break;
            }
        }
    }
    fn graph(s: *const Manager, resource_graph: bool) !void {
        var edges: usize = 0;
        if (resource_graph) {
            for (s.data.total[0..s.data.m]) |value| if (value != 1) return s.h.line("error: not single-instance", .{});
            for (0..s.data.m) |j| for (s.data.jobs, 0..) |job, who| {
                if (job.exists and job.allocation[j] > 0) try s.h.line("assign {c} -> P{d}", .{ @as(u8, 'A') + @as(u8, @intCast(j)), who });
            };
            for (0..2) |stage| for (s.data.jobs, 0..) |job, who| {
                if (!job.exists) continue;
                const wanted = s.requestOf(who);
                const needed = s.needOf(who);
                for (0..s.data.m) |j| {
                    if ((stage == 0 and wanted[j] > 0) or (stage == 1 and needed[j] > 0 and wanted[j] == 0)) try s.h.line("{s} P{d} -> {c}", .{ if (stage == 0) @as(Text, "request") else "claim", who, @as(u8, 'A') + @as(u8, @intCast(j)) });
                }
            };
        } else {
            for (s.data.jobs, 0..) |job, who| {
                if (!job.exists) continue;
                const wanted = s.requestOf(who);
                for (s.data.jobs, 0..) |other, next_id| {
                    if (!other.exists or who == next_id) continue;
                    var labels: std.Io.Writer.Allocating = .init(s.h.a);
                    for (0..s.data.m) |j| {
                        if (wanted[j] > s.data.available[j] and other.allocation[j] > 0) {
                            if (labels.written().len > 0) try labels.writer.writeByte(',');
                            try labels.writer.writeByte(@as(u8, 'A') + @as(u8, @intCast(j)));
                        }
                    }
                    if (labels.written().len > 0) {
                        edges += 1;
                        try s.h.line("P{d} -> P{d} on {s}", .{ who, next_id, labels.written() });
                    }
                }
            }
            if (edges == 0) try s.h.line("no wait edges", .{});
        }
        var results: std.ArrayList(Cycle) = .empty;
        for (s.data.jobs, 0..) |job, who| {
            if (job.exists) {
                var path: Ids = .{};
                path.add(who);
                try s.findCycles(resource_graph, path, undefined, &results);
            }
        }
        std.mem.sort(Cycle, results.items, resource_graph, struct {
            fn less(resource: bool, a: Cycle, b: Cycle) bool {
                const limit = @min(a.path.len, b.path.len);
                for (0..limit) |j| {
                    if (a.path.values[j] != b.path.values[j]) return a.path.values[j] < b.path.values[j];
                    if (resource and a.labels[j] != b.labels[j]) return a.labels[j] < b.labels[j];
                }
                return a.path.len < b.path.len;
            }
        }.less);
        if (results.items.len == 0) return s.h.line("no cycles", .{});
        for (results.items) |cycle| {
            try s.h.out.print("cycle: P{d}", .{cycle.path.values[0]});
            for (0..cycle.path.len) |j| {
                if (resource_graph) try s.h.out.print(" -> {c}", .{@as(u8, 'A') + @as(u8, @intCast(cycle.labels[j]))});
                try s.h.out.print(" -> P{d}", .{cycle.path.values[(j + 1) % cycle.path.len]});
            }
            try s.h.out.writeByte('\n');
        }
    }
    fn command(s: *Manager, tokens: []const Text) !void {
        const op = tokens[0];
        if (eq(op, "RESOURCES")) {
            s.data = .{ .m = tokens.len - 1 };
            for (tokens[1..], 0..) |token, j| s.data.total[j] = number(token);
            s.data.available = s.data.total;
            return s.h.line("resources {s}", .{try s.h.vector(s.data.total, s.data.m)});
        }
        if (eq(op, "MODE") or eq(op, "POLICY") or eq(op, "TRACE") or eq(op, "AUTODETECT")) {
            var label: Text = undefined;
            if (eq(op, "MODE")) {
                s.mode = tokens[1];
                label = "mode";
            } else if (eq(op, "POLICY")) {
                s.policy = tokens[1];
                label = "policy";
            } else if (eq(op, "TRACE")) {
                s.tracing = eq(tokens[1], "ON");
                label = "trace";
            } else {
                s.autodetect = eq(tokens[1], "ON");
                label = "autodetect";
            }
            return s.h.line("{s} {s}", .{ label, tokens[1] });
        }
        if (eq(op, "SNAPSHOT") or eq(op, "RESTORE")) {
            var at: ?usize = null;
            for (s.snapshots.items, 0..) |saved, j| if (eq(saved.name, tokens[1])) {
                at = j;
            };
            if (eq(op, "SNAPSHOT")) {
                const saved = Snapshot{ .name = tokens[1], .data = try s.data.clone(s.h.a) };
                if (at) |j| s.snapshots.items[j] = saved else try s.snapshots.append(s.h.a, saved);
                return s.h.line("saved {s}", .{tokens[1]});
            }
            const j = at orelse return s.h.line("error: unknown snapshot {s}", .{tokens[1]});
            s.data = try s.snapshots.items[j].data.clone(s.h.a);
            return s.h.line("restored {s}", .{tokens[1]});
        }
        if (eq(op, "SAFE") or eq(op, "DETECT")) {
            var any_jobs = false;
            for (s.data.jobs) |job| any_jobs = any_jobs or job.exists;
            if (eq(op, "SAFE") and !any_jobs) return s.h.line("safe: no processes", .{});
            const checked = try s.inspect(s.data, eq(op, "DETECT"), s.tracing);
            if (eq(op, "DETECT")) {
                if (checked.remaining.len == 0) return s.h.line("no deadlock", .{});
                return s.h.line("deadlocked: {s}", .{try s.h.people(checked.remaining, " ")});
            }
            if (checked.remaining.len == 0) return s.h.line("safe: {s}", .{try s.h.people(checked.order, " ")});
            return s.h.line("unsafe: {s} cannot finish", .{try s.h.people(checked.remaining, " ")});
        }
        if (eq(op, "SEQUENCES")) {
            var results: std.ArrayList(Ids) = .empty;
            var total_count: usize = 0;
            var any_jobs = false;
            for (s.data.jobs) |job| any_jobs = any_jobs or job.exists;
            if (!any_jobs) return s.h.line("safe sequences: no processes", .{});
            try s.permutations(s.data.available, .{}, &total_count, index(number(tokens[1])), &results);
            try s.h.line("safe sequences: {d}", .{total_count});
            for (results.items) |sequence| try s.h.line("{s}", .{try s.h.people(sequence, " ")});
            return;
        }
        if (eq(op, "DEFICIT")) {
            try s.h.out.writeAll("deficit: (");
            for (0..s.data.m) |j| {
                if (j > 0) try s.h.out.writeByte(',');
                var limit: I = 0;
                for (s.data.jobs, 0..) |job, who| if (job.exists) {
                    limit += s.needOf(who)[j];
                };
                var extra: I = 0;
                while (extra <= limit) : (extra += 1) {
                    var trial = s.data;
                    trial.available[j] += extra;
                    if ((try s.inspect(trial, false, false)).remaining.len == 0) break;
                }
                if (extra > limit) try s.h.out.writeByte('-') else try s.h.out.print("{d}", .{extra});
            }
            return s.h.line(")", .{});
        }
        if (eq(op, "VICTIMS")) {
            const dead = (try s.inspect(s.data, true, false)).remaining;
            if (dead.len == 0) return s.h.line("no deadlock", .{});
            var best = dead;
            var best_weight: I = std.math.maxInt(I);
            const limit = @as(usize, 1) << @as(u6, @intCast(dead.len));
            for (1..limit) |mask| {
                var selected: Ids = .{};
                var weight: I = 0;
                var trial = s.data;
                for (dead.items(), 0..) |who, j| {
                    if (mask & (@as(usize, 1) << @as(u6, @intCast(j))) != 0) {
                        selected.add(who);
                        weight += sum(s.data.jobs[who].allocation);
                        trial.available = combine(trial.available, trial.jobs[who].allocation, 1);
                        trial.jobs[who].exists = false;
                    }
                }
                if (selected.len > best.len) continue;
                var preferred = selected.len < best.len or weight < best_weight;
                if (selected.len == best.len and weight == best_weight) {
                    for (selected.items(), best.items()) |a, b| {
                        if (a != b) {
                            preferred = a < b;
                            break;
                        }
                    }
                }
                if (preferred and (try s.inspect(trial, true, false)).remaining.len == 0) {
                    best = selected;
                    best_weight = weight;
                }
            }
            return s.h.line("victims: {s}", .{try s.h.people(best, " ")});
        }
        if (eq(op, "RECOVER")) {
            var count_aborted: usize = 0;
            while (true) {
                const dead = (try s.inspect(s.data, true, s.tracing)).remaining;
                if (dead.len == 0) break;
                if (tokens.len == 2) {
                    for (dead.items()) |who| {
                        try s.terminate(who, "aborted", false);
                        count_aborted += 1;
                    }
                    try s.retryQueue();
                    break;
                }
                var chosen = dead.values[0];
                for (dead.items()) |who| {
                    const a = if (eq(s.policy, "ALLOC")) -sum(s.data.jobs[chosen].allocation) else if (eq(s.policy, "NEED")) sum(s.needOf(chosen)) else s.data.jobs[chosen].created;
                    const b = if (eq(s.policy, "ALLOC")) -sum(s.data.jobs[who].allocation) else if (eq(s.policy, "NEED")) sum(s.needOf(who)) else s.data.jobs[who].created;
                    if (b > a or (b == a and who > chosen)) chosen = who;
                }
                try s.terminate(chosen, "aborted", true);
                count_aborted += 1;
            }
            if (count_aborted == 0) return s.h.line("no deadlock", .{});
            return s.h.line("recovered: {d} aborted", .{count_aborted});
        }
        if (eq(op, "STATE")) {
            var names: std.Io.Writer.Allocating = .init(s.h.a);
            for (0..s.data.m) |j| {
                if (j > 0) try names.writer.writeByte(' ');
                const width = (try s.h.text("{d}", .{s.data.total[j]})).len;
                try names.writer.splatByteAll(' ', width - 1);
                try names.writer.writeByte(@as(u8, 'A') + @as(u8, @intCast(j)));
            }
            const row = names.written();
            const widths: [4]usize = .{ @max(10, row.len), @max(3, row.len), @max(4, row.len), @max(7, row.len) };
            try s.tableRow("Process", &.{ "Allocation", "Max", "Need", "Request" }, widths);
            try s.tableRow("", &.{ row, row, row, row }, widths);
            for (s.data.jobs, 0..) |job, who| if (job.exists) {
                try s.tableRow(try s.h.text("P{d}", .{who}), &.{ try s.tableVector(job.allocation), try s.tableVector(job.maximum), try s.tableVector(s.needOf(who)), try s.tableVector(s.requestOf(who)) }, widths);
            };
            try s.tableRow("Available", &.{try s.tableVector(s.data.available)}, widths);
            try s.tableRow("Total", &.{try s.tableVector(s.data.total)}, widths);
            if (s.data.queue.items.len == 0) return s.h.line("blocked queue: empty", .{});
            try s.h.out.writeAll("blocked queue: ");
            for (s.data.queue.items, 0..) |waiting, j| {
                if (j > 0) try s.h.out.writeAll(", ");
                try s.h.out.print("P{d} {s} since t={d}", .{ waiting.who, try s.h.vector(waiting.amount, s.data.m), waiting.since });
            }
            return s.h.out.writeByte('\n');
        }
        if (eq(op, "STATS")) {
            for (0..s.data.m) |j| {
                const used = s.data.total[j] - s.data.available[j];
                const percent = @divTrunc(used * 1000, s.data.total[j]);
                var wanted: I = 0;
                for (s.data.queue.items) |waiting| wanted += waiting.amount[j];
                try s.h.line("{c}: allocated {d}/{d} ({d}.{d}%), requested {d}", .{ @as(u8, 'A') + @as(u8, @intCast(j)), used, s.data.total[j], @divTrunc(percent, 10), @mod(percent, 10), wanted });
            }
            const kinds = [_]Text{ "granted", "blocked", "unblocked", "released", "finished", "aborted", "cancelled" };
            var counts: [7]I = @splat(0);
            var waited_sum: I = 0;
            for (s.data.events.items) |event| {
                for (kinds, 0..) |kind, j| if (eq(kind, event.kind)) {
                    counts[j] += 1;
                };
                if (eq(event.kind, "unblocked")) waited_sum += event.waited;
            }
            try s.h.out.writeAll("events: ");
            for (kinds, counts, 0..) |kind, count, j| {
                if (j > 0) try s.h.out.writeAll(", ");
                try s.h.out.print("{s} {d}", .{ kind, count });
            }
            try s.h.out.writeByte('\n');
            if (counts[2] == 0) return s.h.line("waits: none", .{});
            const average = @divTrunc(waited_sum * 100, counts[2]);
            return s.h.line("waits: {d} unblocked, total {d}, average {d}.{d:0>2}", .{ counts[2], waited_sum, @divTrunc(average, 100), @mod(average, 100) });
        }
        if (eq(op, "HISTORY")) {
            var printed = false;
            for (s.data.events.items) |event| {
                if (tokens.len == 2 and !eq(tokens[1], event.kind) and !eq(tokens[1], try s.h.text("{d}", .{event.who}))) continue;
                const suffix = if (eq(event.kind, "unblocked")) try s.h.text(" waited {d}", .{event.waited}) else "";
                try s.h.line("t={d} {s} P{d} {s}{s}", .{ event.stamp, event.kind, event.who, try s.h.vector(event.amount, s.data.m), suffix });
                printed = true;
            }
            if (!printed) try s.h.line("no events", .{});
            return;
        }
        if (eq(op, "WAITGRAPH") or eq(op, "GRAPH")) return s.graph(eq(op, "GRAPH"));
        const global_vector = eq(op, "ADD") or eq(op, "REMOVE");
        const vector_command = global_vector or eq(op, "PROCESS") or eq(op, "CLAIM") or eq(op, "REQUEST") or eq(op, "WHATIF") or eq(op, "RELEASE");
        const who: usize = if (global_vector) 0 else index(number(tokens[1]));
        var amount: Vec = @splat(0);
        if (vector_command) {
            const beginning: usize = if (global_vector) 1 else 2;
            if (tokens.len - beginning != s.data.m) return s.h.line("error: wrong vector length", .{});
            for (tokens[beginning..], 0..) |token, j| amount[j] = number(token);
        }
        if (!global_vector and !eq(op, "PROCESS") and !s.data.jobs[who].exists) return s.h.line("error: unknown process P{d}", .{who});
        if (eq(op, "PROCESS")) {
            if (s.data.jobs[who].exists) return s.h.line("error: duplicate process P{d}", .{who});
            if (!fits(amount, s.data.total)) return s.h.line("error: max exceeds total", .{});
            s.data.jobs[who] = .{ .exists = true, .maximum = amount, .created = s.stamp };
            return s.h.line("process P{d} max {s}", .{ who, try s.h.vector(amount, s.data.m) });
        }
        if (eq(op, "REQUEST") or eq(op, "WHATIF")) {
            const choice = try s.decide(who, amount, true, s.tracing);
            if (eq(op, "WHATIF")) {
                var description: Text = if (choice.status == .granted) "granted" else try s.h.text("{s} ({s})", .{ @tagName(choice.status), choice.reason });
                if (choice.status == .granted and eq(s.mode, "AVOID")) description = try s.h.text("{s}, safe sequence {s}", .{ description, try s.h.people(choice.order, " ") });
                return s.h.line("whatif P{d} {s}: {s}", .{ who, try s.h.vector(amount, s.data.m), description });
            }
            if (choice.status == .rejected) return s.h.line("error: {s}", .{choice.reason});
            if (choice.status == .granted) {
                s.grant(who, amount);
                try s.record("granted", who, amount, 0);
                return s.h.line("granted P{d} {s}", .{ who, try s.h.vector(amount, s.data.m) });
            }
            try s.data.queue.append(s.h.a, .{ .who = who, .amount = amount, .since = s.stamp });
            try s.record("blocked", who, amount, 0);
            try s.h.line("blocked P{d} {s}: {s}", .{ who, try s.h.vector(amount, s.data.m), choice.reason });
            if (s.autodetect) {
                const dead = (try s.inspect(s.data, true, s.tracing)).remaining;
                if (dead.len > 0) try s.h.line("deadlock detected: {s}", .{try s.h.people(dead, " ")});
            }
            return;
        }
        if (eq(op, "ABORT")) return s.terminate(who, "aborted", true);
        if (eq(op, "CANCEL")) {
            const at = s.queued(who) orelse return s.h.line("error: process P{d} is not blocked", .{who});
            amount = s.data.queue.orderedRemove(at).amount;
            try s.record("cancelled", who, amount, 0);
            return s.h.line("cancelled P{d} {s}", .{ who, try s.h.vector(amount, s.data.m) });
        }
        if (!global_vector and s.queued(who) != null) return s.h.line("error: process P{d} is blocked", .{who});
        if (eq(op, "FINISH")) return s.terminate(who, "finished", true);
        if (eq(op, "MAXGRANT")) {
            var answer: Vec = @splat(0);
            const needed = s.needOf(who);
            for (0..s.data.m) |j| {
                var candidate: I = 1;
                while (candidate <= needed[j]) : (candidate += 1) {
                    var trial: Vec = @splat(0);
                    trial[j] = candidate;
                    if ((try s.decide(who, trial, true, false)).status == .granted) answer[j] = candidate;
                }
            }
            return s.h.line("maxgrant P{d}: {s}", .{ who, try s.h.vector(answer, s.data.m) });
        }
        if (eq(op, "CLAIM")) {
            if (!fits(s.data.jobs[who].allocation, amount)) return s.h.line("error: claim below allocation", .{});
            if (!fits(amount, s.data.total)) return s.h.line("error: max exceeds total", .{});
            var trial = s.data;
            trial.jobs[who].maximum = amount;
            if (eq(s.mode, "AVOID") and (try s.inspect(trial, false, s.tracing)).remaining.len > 0) return s.h.line("error: claim makes state unsafe", .{});
            s.data = trial;
            try s.h.line("claim P{d} max {s}", .{ who, try s.h.vector(amount, s.data.m) });
            return s.retryQueue();
        }
        if (sum(amount) == 0) return s.h.line("error: zero vector", .{});
        if (eq(op, "RELEASE")) {
            if (!fits(amount, s.data.jobs[who].allocation)) return s.h.line("error: release exceeds allocation", .{});
            s.data.jobs[who].allocation = combine(s.data.jobs[who].allocation, amount, -1);
            s.data.available = combine(s.data.available, amount, 1);
            try s.record("released", who, amount, 0);
            try s.h.line("released P{d} {s}", .{ who, try s.h.vector(amount, s.data.m) });
            return s.retryQueue();
        }
        if (eq(op, "ADD")) {
            s.data.total = combine(s.data.total, amount, 1);
            s.data.available = combine(s.data.available, amount, 1);
            try s.h.line("added {s} total {s}", .{ try s.h.vector(amount, s.data.m), try s.h.vector(s.data.total, s.data.m) });
            return s.retryQueue();
        }
        if (!fits(amount, s.data.available)) return s.h.line("error: remove exceeds available", .{});
        const reduced = combine(s.data.total, amount, -1);
        for (reduced[0..s.data.m]) |item| if (item == 0) return s.h.line("error: total must stay positive", .{});
        for (s.data.jobs) |job| if (job.exists and !fits(job.maximum, reduced)) return s.h.line("error: max exceeds total", .{});
        var trial = s.data;
        trial.total = reduced;
        trial.available = combine(trial.available, amount, -1);
        if (eq(s.mode, "AVOID") and (try s.inspect(trial, false, s.tracing)).remaining.len > 0) return s.h.line("error: removal makes state unsafe", .{});
        s.data = trial;
        try s.h.line("removed {s} total {s}", .{ try s.h.vector(amount, s.data.m), try s.h.vector(s.data.total, s.data.m) });
    }
};
fn readLine(r: *std.Io.Reader, a: std.mem.Allocator) !?Text {
    var b: std.Io.Writer.Allocating = .init(a);
    defer b.deinit();
    _ = try r.streamDelimiterEnding(&b.writer, '\n');
    if (r.bufferedLen() == 0 and b.written().len == 0) return null;
    if (r.bufferedLen() > 0) r.toss(1);
    return b.toOwnedSlice();
}
pub fn main(init: std.process.Init) !void {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ib: [4096]u8 = undefined;
    var ob: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &ib);
    var output = std.Io.File.stdout().writerStreaming(init.io, &ob);
    var manager: Manager = .{ .h = .{ .a = a, .out = &output.interface } };
    const count = number(std.mem.trim(u8, (try readLine(&input.interface, a)).?, "\r"));
    for (0..index(count)) |j| {
        const line = std.mem.trim(u8, (try readLine(&input.interface, a)).?, "\r");
        var tokens: std.ArrayList(Text) = .empty;
        var it = std.mem.splitScalar(u8, line, ' ');
        while (it.next()) |token| try tokens.append(a, token);
        manager.stamp = @as(I, @intCast(j)) + 1;
        try manager.command(tokens.items);
    }
    try output.interface.flush();
}
