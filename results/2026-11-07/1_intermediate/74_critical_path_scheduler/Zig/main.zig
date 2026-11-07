const std = @import("std");
const Allocator = std.mem.Allocator;
const Text = []const u8;
const Int = i64;
const Error = Allocator.Error || error{Invalid};
var failure: Text = "";

fn equal(a: Text, b: Text) bool {
    return std.mem.eql(u8, a, b);
}
fn number(text: Text) Int {
    return std.fmt.parseInt(Int, text, 10) catch unreachable;
}
fn bad(gpa: Allocator, comptime pattern: Text, args: anytype) Error {
    failure = std.fmt.allocPrint(gpa, pattern, args) catch return error.OutOfMemory;
    return error.Invalid;
}
const Builder = struct {
    gpa: Allocator,
    bytes: std.ArrayList(u8) = .empty,
    fn add(self: *Builder, text: Text) Allocator.Error!void {
        try self.bytes.appendSlice(self.gpa, text);
    }
    fn print(self: *Builder, comptime pattern: Text, args: anytype) Allocator.Error!void {
        try self.add(try std.fmt.allocPrint(self.gpa, pattern, args));
    }
    fn line(self: *Builder, comptime pattern: Text, args: anytype) Allocator.Error!void {
        try self.print(pattern ++ "\n", args);
    }
};
fn signed(gpa: Allocator, value: Int) Allocator.Error!Text {
    return if (value >= 0) std.fmt.allocPrint(gpa, "+{d}", .{value}) else std.fmt.allocPrint(gpa, "{d}", .{value});
}
fn decimal(gpa: Allocator, numerator: Int, denominator: Int) Allocator.Error!Text {
    const value = @divTrunc(numerator * 100, denominator);
    return std.fmt.allocPrint(gpa, "{d}.{d:0>2}", .{ @divTrunc(value, 100), @mod(value, 100) });
}
fn textLess(_: void, a: Text, b: Text) bool {
    return std.mem.order(u8, a, b) == .lt;
}
fn keys(gpa: Allocator, map: anytype) Allocator.Error![]Text {
    var result: std.ArrayList(Text) = .empty;
    var iterator = map.keyIterator();
    while (iterator.next()) |key| try result.append(gpa, key.*);
    std.mem.sort(Text, result.items, {}, textLess);
    return result.items;
}
fn join(gpa: Allocator, parts: []const Text, separator: Text) Allocator.Error!Text {
    var out: Builder = .{ .gpa = gpa };
    for (parts, 0..) |part, i| {
        if (i > 0) try out.add(separator);
        try out.add(part);
    }
    return out.bytes.items;
}
fn leap(year: Int) bool {
    return @mod(year, 4) == 0 and @mod(year, 100) != 0 or @mod(year, 400) == 0;
}
fn monthDays(year: Int, month: Int) Int {
    const days = [_]Int{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    return if (month == 2 and leap(year)) 29 else days[@intCast(month - 1)];
}
fn dateValue(text: Text) ?Int {
    const year = number(text[0..4]);
    const month = number(text[5..7]);
    const day = number(text[8..10]);
    if (month < 1 or month > 12 or day < 1 or day > monthDays(year, month)) return null;
    var total = day - 1;
    var y: Int = 2000;
    while (y < year) : (y += 1) total += if (leap(y)) @as(Int, 366) else 365;
    var m: Int = 1;
    while (m < month) : (m += 1) total += monthDays(year, m);
    return total;
}
fn dateText(gpa: Allocator, ordinal: Int) Allocator.Error!Text {
    var remaining = ordinal;
    var year: Int = 2000;
    var month: Int = 1;
    while (true) {
        const count: Int = if (leap(year)) 366 else 365;
        if (remaining < count) break;
        remaining -= count;
        year += 1;
    }
    while (remaining >= monthDays(year, month)) {
        remaining -= monthDays(year, month);
        month += 1;
    }
    const weekdays = [_]Text{ "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" };
    return std.fmt.allocPrint(gpa, "{d:0>4}-{d:0>2}-{d:0>2} {s}", .{ year, month, remaining + 1, weekdays[@intCast(@mod(ordinal + 5, 7))] });
}
const Crash = struct { limit: Int, cost: Int };
const Task = struct {
    name: Text,
    resource: Text,
    slot: usize,
    base: Int,
    units: Int,
    not_before: Int = 0,
    crashed: Int = 0,
    crash: ?Crash = null,
    estimate: ?[3]Int = null,
    fn duration(self: *const Task) Int {
        return self.base - self.crashed;
    }
};
const Dependency = struct { from: *Task, to: *Task, kind: Text, lag: Int };
const Timing = struct { es: Int = 0, ef: Int = 0, ls: Int = 0, lf: Int = 0, tf: Int = 0, free: Int = 0 };
const Schedule = struct { times: [30]Timing = @splat(.{}), total: Int = 0 };
const Baseline = struct { times: std.StringHashMapUnmanaged([2]Int) = .empty, total: Int };
const Topology = struct { order: []*Task, cycle: ?Text = null };
fn taskLess(_: void, a: *Task, b: *Task) bool {
    return std.mem.order(u8, a.name, b.name) == .lt;
}
fn margin(dep: Dependency, schedule: Schedule) Int {
    const a = schedule.times[dep.from.slot];
    const b = schedule.times[dep.to.slot];
    if (equal(dep.kind, "SS")) return b.es - a.es - dep.lag;
    if (equal(dep.kind, "FF")) return b.ef - a.ef - dep.lag;
    return b.es - a.ef - dep.lag;
}
const Project = struct {
    gpa: Allocator,
    out: *Builder,
    tasks: std.StringHashMapUnmanaged(*Task) = .empty,
    deps: std.ArrayList(Dependency) = .empty,
    capacities: std.StringHashMapUnmanaged(Int) = .empty,
    holidays: std.AutoHashMapUnmanaged(Int, void) = .empty,
    start: ?Int = null,
    deadline: ?Int = null,
    baseline: ?Baseline = null,
    fn get(self: *Project, name: Text) Error!*Task {
        return self.tasks.get(name) orelse return bad(self.gpa, "unknown task {s}", .{name});
    }
    fn sorted(self: *const Project, gpa: Allocator) Allocator.Error![]*Task {
        var result: std.ArrayList(*Task) = .empty;
        var iterator = self.tasks.valueIterator();
        while (iterator.next()) |task| try result.append(gpa, task.*);
        std.mem.sort(*Task, result.items, {}, taskLess);
        return result.items;
    }
    fn relations(self: *const Project, gpa: Allocator, task: *Task, predecessors: bool) Allocator.Error![]Dependency {
        var result: std.ArrayList(Dependency) = .empty;
        for (self.deps.items) |dep| {
            if ((predecessors and dep.to == task) or (!predecessors and dep.from == task)) try result.append(gpa, dep);
        }
        const Less = struct {
            fn less(before: bool, a: Dependency, b: Dependency) bool {
                return std.mem.order(u8, if (before) a.from.name else a.to.name, if (before) b.from.name else b.to.name) == .lt;
            }
        };
        std.mem.sort(Dependency, result.items, predecessors, Less.less);
        return result.items;
    }
    fn topology(self: *const Project, gpa: Allocator) Allocator.Error!Topology {
        const names = try self.sorted(gpa);
        var removed: [30]bool = @splat(false);
        var order: std.ArrayList(*Task) = .empty;
        while (true) {
            var selected: ?*Task = null;
            for (names) |task| {
                if (removed[task.slot]) continue;
                var ready = true;
                for (self.deps.items) |dep| {
                    if (dep.to == task and !removed[dep.from.slot]) {
                        ready = false;
                        break;
                    }
                }
                if (ready) {
                    selected = task;
                    break;
                }
            }
            const task = selected orelse break;
            removed[task.slot] = true;
            try order.append(gpa, task);
        }
        if (order.items.len == names.len) return .{ .order = order.items };
        var current: *Task = undefined;
        for (names) |task| if (!removed[task.slot]) {
            current = task;
            break;
        };
        var visited: [30]?usize = @splat(null);
        var chain: std.ArrayList(*Task) = .empty;
        while (true) {
            if (visited[current.slot]) |at| {
                var cycle: std.ArrayList(*Task) = .empty;
                try cycle.append(gpa, current);
                var i = chain.items.len;
                while (i > at + 1) {
                    i -= 1;
                    try cycle.append(gpa, chain.items[i]);
                }
                var first: usize = 0;
                for (cycle.items, 0..) |task, j| if (taskLess({}, task, cycle.items[first])) {
                    first = j;
                };
                var text: std.ArrayList(Text) = .empty;
                for (cycle.items[first..]) |task| try text.append(gpa, task.name);
                for (cycle.items[0..first]) |task| try text.append(gpa, task.name);
                try text.append(gpa, text.items[0]);
                return .{ .order = order.items, .cycle = try join(gpa, text.items, " -> ") };
            }
            visited[current.slot] = chain.items.len;
            try chain.append(gpa, current);
            var predecessor: ?*Task = null;
            for (self.deps.items) |dep| {
                if (dep.to == current and !removed[dep.from.slot] and
                    (predecessor == null or taskLess({}, dep.from, predecessor.?))) predecessor = dep.from;
            }
            current = predecessor.?;
        }
    }
    fn compute(self: *const Project, order: []const *Task, changed: ?*Task, replacement: Int) Schedule {
        var result: Schedule = .{};
        for (order) |task| {
            const d = if (task == changed) replacement else task.duration();
            var earliest = task.not_before;
            for (self.deps.items) |dep| {
                if (dep.to != task) continue;
                const a = result.times[dep.from.slot];
                const value = if (equal(dep.kind, "SS")) a.es + dep.lag else if (equal(dep.kind, "FF")) a.ef + dep.lag - d else a.ef + dep.lag;
                earliest = @max(earliest, value);
            }
            result.times[task.slot] = .{ .es = earliest, .ef = earliest + d };
            result.total = @max(result.total, earliest + d);
        }
        var i = order.len;
        while (i > 0) {
            i -= 1;
            const task = order[i];
            const d = if (task == changed) replacement else task.duration();
            const value = &result.times[task.slot];
            var finish = result.total;
            for (self.deps.items) |dep| {
                if (dep.from != task) continue;
                const b = result.times[dep.to.slot];
                const candidate = if (equal(dep.kind, "SS")) b.ls - dep.lag + d else if (equal(dep.kind, "FF")) b.lf - dep.lag else b.ls - dep.lag;
                finish = @min(finish, candidate);
            }
            value.lf = finish;
            value.ls = finish - d;
            value.tf = value.ls - value.es;
            value.free = result.total - value.ef;
        }
        for (order) |task| {
            for (self.deps.items) |dep| {
                if (dep.from == task) result.times[task.slot].free = @min(result.times[task.slot].free, margin(dep, result));
            }
        }
        return result;
    }
    fn critical(self: *const Project, gpa: Allocator, schedule: Schedule) Allocator.Error![]*Task {
        var result: std.ArrayList(*Task) = .empty;
        for (try self.sorted(gpa)) |task| if (schedule.times[task.slot].tf == 0) {
            try result.append(gpa, task);
        };
        return result.items;
    }
    fn visitPath(self: *const Project, gpa: Allocator, schedule: Schedule, task: *Task, prefix: []const *Task, result: *std.ArrayList([]*Task)) Allocator.Error!void {
        var path: std.ArrayList(*Task) = .empty;
        try path.appendSlice(gpa, prefix);
        try path.append(gpa, task);
        var children: std.ArrayList(*Task) = .empty;
        for (self.deps.items) |dep| {
            if (dep.from == task and schedule.times[dep.to.slot].tf == 0 and margin(dep, schedule) == 0) try children.append(gpa, dep.to);
        }
        std.mem.sort(*Task, children.items, {}, taskLess);
        if (children.items.len == 0) try result.append(gpa, path.items) else {
            for (children.items) |child| try self.visitPath(gpa, schedule, child, path.items, result);
        }
    }
    fn criticalPaths(self: *const Project, gpa: Allocator, schedule: Schedule) Allocator.Error![][]*Task {
        var result: std.ArrayList([]*Task) = .empty;
        for (try self.critical(gpa, schedule)) |task| {
            var incoming = false;
            for (self.deps.items) |dep| {
                if (dep.to == task and schedule.times[dep.from.slot].tf == 0 and margin(dep, schedule) == 0) {
                    incoming = true;
                    break;
                }
            }
            if (!incoming) try self.visitPath(gpa, schedule, task, &.{}, &result);
        }
        return result.items;
    }
    fn resources(self: *const Project, gpa: Allocator) Allocator.Error![]Text {
        var all: std.StringHashMapUnmanaged(void) = .empty;
        var iterator = self.tasks.valueIterator();
        while (iterator.next()) |task| try all.put(gpa, task.*.resource, {});
        return keys(gpa, all);
    }
    fn usage(self: *const Project, gpa: Allocator, schedule: Schedule, resource: Text) Allocator.Error![]Int {
        const result = try gpa.alloc(Int, @intCast(schedule.total));
        @memset(result, 0);
        var iterator = self.tasks.valueIterator();
        while (iterator.next()) |task| {
            if (equal(task.*.resource, resource)) {
                const value = schedule.times[task.*.slot];
                for (@as(usize, @intCast(value.es))..@as(usize, @intCast(value.ef))) |day| result[day] += task.*.units;
            }
        }
        return result;
    }
    fn workingDay(self: *const Project, day: Int) bool {
        return @mod(day + 5, 7) < 5 and !self.holidays.contains(day);
    }
    fn startOrder(self: *const Project, gpa: Allocator, schedule: Schedule) Allocator.Error![]*Task {
        const result = try self.sorted(gpa);
        const Less = struct {
            fn less(s: Schedule, a: *Task, b: *Task) bool {
                const x = s.times[a.slot].es;
                const y = s.times[b.slot].es;
                return if (x != y) x < y else taskLess({}, a, b);
            }
        };
        std.mem.sort(*Task, result, schedule, Less.less);
        return result;
    }
    fn calendar(self: *Project, scratch: Allocator, schedule: Schedule) Allocator.Error!void {
        var days: std.ArrayList(Int) = .empty;
        var day = self.start.?;
        while (days.items.len < @as(usize, @intCast(schedule.total))) : (day += 1) {
            if (self.workingDay(day)) try days.append(scratch, day);
        }
        for (try self.startOrder(scratch, schedule)) |task| {
            const value = schedule.times[task.slot];
            try self.out.line("{s} {s} - {s}", .{ task.name, try dateText(scratch, days.items[@intCast(value.es)]), try dateText(scratch, days.items[@intCast(value.ef - 1)]) });
        }
        const first = days.items[0];
        const last = days.items[days.items.len - 1];
        try self.out.line("project {s} - {s}, {d} working days, {d} calendar days", .{ try dateText(scratch, first), try dateText(scratch, last), schedule.total, last - first + 1 });
        if (self.deadline) |date| {
            var count: usize = 0;
            day = @min(date, last) + 1;
            while (day <= @max(date, last)) : (day += 1) if (self.workingDay(day)) {
                count += 1;
            };
            if (last <= date) try self.out.line("deadline {s} met, {d} working days to spare", .{ try dateText(scratch, date), count }) else try self.out.line("deadline {s} missed by {d} working days", .{ try dateText(scratch, date), count });
        }
        var selected: std.ArrayList(Int) = .empty;
        var iterator = self.holidays.keyIterator();
        while (iterator.next()) |date| {
            if (date.* >= first and date.* <= last and @mod(date.* + 5, 7) < 5) try selected.append(scratch, date.*);
        }
        const Less = struct {
            fn less(_: void, a: Int, b: Int) bool {
                return a < b;
            }
        };
        std.mem.sort(Int, selected.items, {}, Less.less);
        try self.out.add("holidays in span: ");
        if (selected.items.len == 0) try self.out.add("none");
        for (selected.items, 0..) |date, i| {
            if (i > 0) try self.out.add(", ");
            try self.out.add(try dateText(scratch, date));
        }
        try self.out.add("\n");
    }
    fn capacity(self: *const Project, resource: Text, limit: Int) Int {
        return self.capacities.get(resource) orelse limit;
    }
    fn level(self: *Project, scratch: Allocator, order: []const *Task, schedule: Schedule, limit: Int) Error!void {
        const names = try self.sorted(scratch);
        for (names) |task| {
            const cap = self.capacity(task.resource, limit);
            if (task.units > cap) return bad(self.gpa, "capacity {d} too small for {s}", .{ cap, task.name });
        }
        var decided: [30]?Timing = @splat(null);
        var loads: std.StringHashMapUnmanaged(std.ArrayList(Int)) = .empty;
        var sequence: std.ArrayList(*Task) = .empty;
        var total: Int = 0;
        while (sequence.items.len < order.len) {
            var selected: ?*Task = null;
            for (names) |task| {
                if (decided[task.slot] != null) continue;
                var ready = true;
                for (self.deps.items) |dep| if (dep.to == task and decided[dep.from.slot] == null) {
                    ready = false;
                    break;
                };
                if (ready and (selected == null or schedule.times[task.slot].ls < schedule.times[selected.?.slot].ls)) selected = task;
            }
            const task = selected.?;
            const d = task.duration();
            var earliest = task.not_before;
            for (self.deps.items) |dep| {
                if (dep.to != task) continue;
                const a = decided[dep.from.slot].?;
                const value = if (equal(dep.kind, "SS")) a.es + dep.lag else if (equal(dep.kind, "FF")) a.ef + dep.lag - d else a.ef + dep.lag;
                earliest = @max(earliest, value);
            }
            var load = loads.get(task.resource) orelse std.ArrayList(Int).empty;
            while (true) {
                var valid = true;
                var day = earliest;
                while (day < earliest + d) : (day += 1) {
                    const used = if (@as(usize, @intCast(day)) < load.items.len) load.items[@intCast(day)] else 0;
                    if (used + task.units > self.capacity(task.resource, limit)) {
                        valid = false;
                        break;
                    }
                }
                if (valid) break;
                earliest += 1;
            }
            while (load.items.len < @as(usize, @intCast(earliest + d))) try load.append(scratch, 0);
            for (@as(usize, @intCast(earliest))..@as(usize, @intCast(earliest + d))) |day| load.items[day] += task.units;
            try loads.put(scratch, task.resource, load);
            decided[task.slot] = .{ .es = earliest, .ef = earliest + d };
            try sequence.append(scratch, task);
            total = @max(total, earliest + d);
        }
        try self.out.line("level capacity {d}: duration {d} -> {d}", .{ limit, schedule.total, total });
        for (sequence.items) |task| {
            const value = decided[task.slot].?;
            try self.out.line("{s} start {d} finish {d} shift {d}", .{ task.name, value.es, value.ef, value.es - schedule.times[task.slot].es });
        }
        for (try self.resources(scratch)) |resource| try self.out.line("resource {s} capacity {d} peak {d} -> {d}", .{ resource, self.capacity(resource, limit), peak(try self.usage(scratch, schedule, resource)), peak(loads.get(resource).?.items) });
    }
    fn command(self: *Project, scratch: Allocator, w: []const Text) Error!void {
        const cmd = w[0];
        if (equal(cmd, "TASK")) {
            if (self.tasks.contains(w[1])) return bad(self.gpa, "task {s} already exists", .{w[1]});
            var occupied: [30]bool = @splat(false);
            var iterator = self.tasks.valueIterator();
            while (iterator.next()) |task| occupied[task.*.slot] = true;
            const slot = std.mem.findScalar(bool, &occupied, false).?;
            const task = try self.gpa.create(Task);
            task.* = .{ .name = w[1], .slot = slot, .base = number(w[2]), .resource = w[3], .units = number(w[4]) };
            try self.tasks.put(self.gpa, task.name, task);
            try self.out.line("task {s} added", .{task.name});
            return;
        } else if (equal(cmd, "DEP") or equal(cmd, "UNDEP")) {
            const a = try self.get(w[1]);
            const b = try self.get(w[2]);
            var existing: ?usize = null;
            for (self.deps.items, 0..) |dep, i| if (dep.from == a and dep.to == b) {
                existing = i;
                break;
            };
            if (equal(cmd, "DEP")) {
                if (a == b) return bad(self.gpa, "self dependency {s}", .{a.name});
                if (existing != null) return bad(self.gpa, "dependency {s} -> {s} already exists", .{ a.name, b.name });
                try self.deps.append(self.gpa, .{ .from = a, .to = b, .kind = w[3], .lag = number(w[4]) });
                try self.out.line("dependency {s} -> {s} {s}{s} added", .{ a.name, b.name, w[3], try signed(scratch, number(w[4])) });
            } else {
                const at = existing orelse return bad(self.gpa, "no dependency {s} -> {s}", .{ a.name, b.name });
                _ = self.deps.orderedRemove(at);
                try self.out.line("dependency {s} -> {s} removed", .{ a.name, b.name });
            }
            return;
        } else if (equal(cmd, "REMOVE") or equal(cmd, "NOTBEFORE") or equal(cmd, "CRASHCOST") or equal(cmd, "UNCRASH") or
            equal(cmd, "PERT") or equal(cmd, "SHOW") or equal(cmd, "IMPACT"))
        {
            const task = try self.get(w[1]);
            if (equal(cmd, "REMOVE")) {
                var count: usize = 0;
                var i: usize = 0;
                while (i < self.deps.items.len) {
                    const dep = self.deps.items[i];
                    if (dep.from == task or dep.to == task) {
                        _ = self.deps.orderedRemove(i);
                        count += 1;
                    } else i += 1;
                }
                _ = self.tasks.remove(task.name);
                try self.out.line("task {s} removed with {d} dependencies", .{ task.name, count });
            } else if (equal(cmd, "NOTBEFORE")) {
                task.not_before = number(w[2]);
                try self.out.line("notbefore {s} {s}", .{ task.name, w[2] });
            } else if (equal(cmd, "CRASHCOST")) {
                const limit = number(w[2]);
                if (limit >= task.base) return bad(self.gpa, "crash limit too large for {s}", .{task.name});
                if (limit < task.crashed) return bad(self.gpa, "crash limit below used days for {s}", .{task.name});
                task.crash = .{ .limit = limit, .cost = number(w[3]) };
                try self.out.line("crash {s} max {d} cost {d}", .{ task.name, limit, task.crash.?.cost });
            } else if (equal(cmd, "UNCRASH")) {
                try self.out.line("uncrash {s} restored {d} days", .{ task.name, task.crashed });
                task.crashed = 0;
            } else if (equal(cmd, "PERT")) {
                const o = number(w[2]);
                const m = number(w[3]);
                const p = number(w[4]);
                if (o > m or m > p) return bad(self.gpa, "invalid estimate", .{});
                task.estimate = .{ o, m, p };
                try self.out.line("pert {s} expected {s} variance {s}", .{ task.name, try decimal(scratch, o + 4 * m + p, 6), try decimal(scratch, (p - o) * (p - o), 36) });
            } else if (equal(cmd, "IMPACT")) {
                var reached: [30]bool = @splat(false);
                reached[task.slot] = true;
                var queue: std.ArrayList(*Task) = .empty;
                try queue.append(scratch, task);
                var at: usize = 0;
                while (at < queue.items.len) : (at += 1) {
                    for (self.deps.items) |dep| {
                        if (dep.from == queue.items[at] and !reached[dep.to.slot]) {
                            reached[dep.to.slot] = true;
                            try queue.append(scratch, dep.to);
                        }
                    }
                }
                reached[task.slot] = false;
                try self.out.print("impact {s}:", .{task.name});
                var count: usize = 0;
                for (try self.sorted(scratch)) |other| if (reached[other.slot]) {
                    try self.out.print(" {s}", .{other.name});
                    count += 1;
                };
                if (count == 0) try self.out.add(" none");
                try self.out.add("\n");
            } else {
                try self.out.print("task {s} duration {d} resource {s} units {d}", .{ task.name, task.duration(), task.resource, task.units });
                if (task.not_before != 0) try self.out.print(" notbefore {d}", .{task.not_before});
                try self.out.add("\n");
                for ([_]bool{ true, false }) |before| {
                    const deps = try self.relations(scratch, task, before);
                    try self.out.print("{s}: ", .{if (before) @as(Text, "preds") else "succs"});
                    if (deps.len == 0) try self.out.add("none");
                    for (deps, 0..) |dep, i| {
                        if (i > 0) try self.out.add(", ");
                        try self.out.print("{s} {s}{s}", .{ if (before) dep.from.name else dep.to.name, dep.kind, try signed(scratch, dep.lag) });
                    }
                    try self.out.add("\n");
                }
                if (task.crash) |data| try self.out.line("crash: max {d} used {d} cost {d}", .{ data.limit, task.crashed, data.cost }) else try self.out.add("crash: none\n");
                if (task.estimate) |values| try self.out.line("pert: {d} {d} {d}", .{ values[0], values[1], values[2] }) else try self.out.add("pert: none\n");
                const topo = try self.topology(scratch);
                if (topo.cycle != null) try self.out.add("schedule: unavailable\n") else {
                    const value = self.compute(topo.order, null, 0).times[task.slot];
                    try self.out.line("schedule: ES {d} EF {d} LS {d} LF {d} TF {d} FF {d}{s}", .{ value.es, value.ef, value.ls, value.lf, value.tf, value.free, if (value.tf == 0) @as(Text, " critical") else "" });
                }
            }
            return;
        } else if (equal(cmd, "CAPACITY")) {
            try self.capacities.put(self.gpa, w[1], number(w[2]));
            try self.out.line("capacity {s} {s}", .{ w[1], w[2] });
            return;
        } else if (equal(cmd, "START") or equal(cmd, "HOLIDAY") or equal(cmd, "DEADLINE")) {
            const date = dateValue(w[1]) orelse return bad(self.gpa, "invalid date {s}", .{w[1]});
            if (equal(cmd, "HOLIDAY")) {
                if (self.holidays.contains(date)) return bad(self.gpa, "duplicate holiday {s}", .{w[1]});
                try self.holidays.put(self.gpa, date, {});
            } else if (equal(cmd, "START")) self.start = date else self.deadline = date;
            const verb: Text = if (equal(cmd, "START")) "start" else if (equal(cmd, "HOLIDAY")) "holiday" else "deadline";
            try self.out.line("{s} {s}", .{ verb, try dateText(scratch, date) });
            return;
        } else if (equal(cmd, "LIST")) {
            try self.out.line("tasks {d}, dependencies {d}, holidays {d}", .{ self.tasks.count(), self.deps.items.len, self.holidays.count() });
            for (try self.sorted(scratch)) |task| {
                try self.out.print("{s} duration {d} resource {s} units {d} preds", .{ task.name, task.duration(), task.resource, task.units });
                const previous = try self.relations(scratch, task, true);
                if (previous.len == 0) try self.out.add(" none");
                for (previous) |dep| try self.out.print(" {s}", .{dep.from.name});
                try self.out.add("\n");
            }
            return;
        }
        if (self.tasks.count() == 0) return bad(self.gpa, "no tasks", .{});
        const topo = try self.topology(scratch);
        if (topo.cycle) |cycle| return bad(self.gpa, "cycle {s}", .{cycle});
        if (equal(cmd, "CALENDAR") and self.start == null) return bad(self.gpa, "no start date", .{});
        if (equal(cmd, "WHATIF")) _ = try self.get(w[1]);
        if (equal(cmd, "VARIANCE") and self.baseline == null) return bad(self.gpa, "no baseline", .{});
        if (equal(cmd, "LOAD")) {
            var found = false;
            for (try self.sorted(scratch)) |task| if (equal(task.resource, w[1])) {
                found = true;
                break;
            };
            if (!found) return bad(self.gpa, "unknown resource {s}", .{w[1]});
        }
        var schedule = self.compute(topo.order, null, 0);
        const names = try self.sorted(scratch);
        if (equal(cmd, "CPM")) {
            var width: usize = 4;
            for (names) |task| width = @max(width, task.name.len);
            try padded(self.out, scratch, "TASK", width, false);
            for ([_]Text{ "DUR", "ES", "EF", "LS", "LF", "TF", "FF" }) |column| try padded(self.out, scratch, column, 5, true);
            try self.out.add("\n");
            for (names) |task| {
                const value = schedule.times[task.slot];
                try padded(self.out, scratch, task.name, width, false);
                for ([_]Int{ task.duration(), value.es, value.ef, value.ls, value.lf, value.tf, value.free }) |amount| {
                    try padded(self.out, scratch, try std.fmt.allocPrint(scratch, "{d}", .{amount}), 5, true);
                }
                if (value.tf == 0) try self.out.add(" *");
                try self.out.add("\n");
            }
            try self.out.line("project duration {d}", .{schedule.total});
        } else if (equal(cmd, "CRITICAL") or equal(cmd, "PERTSUM")) {
            const paths = try self.criticalPaths(scratch, schedule);
            if (equal(cmd, "CRITICAL")) try self.out.line("critical paths: {d}", .{paths.len});
            for (paths) |path| {
                const text = try taskNames(scratch, path, " -> ");
                if (equal(cmd, "CRITICAL")) try self.out.line("{s}", .{text}) else {
                    var expected: Int = 0;
                    var variance: Int = 0;
                    for (path) |task| {
                        const d = task.duration();
                        const values = task.estimate orelse [3]Int{ d, d, d };
                        expected += values[0] + 4 * values[1] + values[2];
                        variance += (values[2] - values[0]) * (values[2] - values[0]);
                    }
                    try self.out.line("{s}: expected {s} variance {s}", .{ text, try decimal(scratch, expected, 6), try decimal(scratch, variance, 36) });
                }
            }
        } else if (equal(cmd, "SLACK")) {
            const values = try scratch.alloc(Int, names.len);
            for (names, 0..) |task, i| values[i] = schedule.times[task.slot].tf;
            const Less = struct {
                fn less(_: void, a: Int, b: Int) bool {
                    return a < b;
                }
            };
            std.mem.sort(Int, values, {}, Less.less);
            for (values, 0..) |value, i| {
                if (i > 0 and value == values[i - 1]) continue;
                try self.out.print("float {d}:", .{value});
                for (names) |task| if (schedule.times[task.slot].tf == value) {
                    try self.out.print(" {s}", .{task.name});
                };
                try self.out.add("\n");
            }
        } else if (equal(cmd, "DRAG")) {
            for (try self.critical(scratch, schedule)) |task| {
                const after = self.compute(topo.order, task, 0);
                try self.out.line("{s} drag {d}", .{ task.name, schedule.total - after.total });
            }
        } else if (equal(cmd, "STATS")) {
            var counts = [_]usize{ 0, 0, 0 };
            for (self.deps.items) |dep| counts[if (equal(dep.kind, "FS")) @as(usize, 0) else if (equal(dep.kind, "SS")) 1 else 2] += 1;
            const count = (try self.critical(scratch, schedule)).len;
            try self.out.line("tasks {d}, critical {d}, dependencies {d} (FS {d}, SS {d}, FF {d})", .{ names.len, count, self.deps.items.len, counts[0], counts[1], counts[2] });
            try self.out.add("work ");
            for (try self.resources(scratch), 0..) |resource, i| {
                var work: Int = 0;
                for (names) |task| if (equal(task.resource, resource)) {
                    work += task.duration() * task.units;
                };
                if (i > 0) try self.out.add(", ");
                try self.out.print("{s} {d}", .{ resource, work });
            }
            var total: Int = 0;
            for (names) |task| total += schedule.times[task.slot].tf;
            try self.out.line("\nfloat total {d}, average {s}", .{ total, try decimal(scratch, total, @intCast(names.len)) });
            try self.out.line("duration {d}, critical share {s}%", .{ schedule.total, try decimal(scratch, @as(Int, @intCast(count)) * 100, @intCast(names.len)) });
        } else if (equal(cmd, "CALENDAR")) {
            try self.calendar(scratch, schedule);
        } else if (equal(cmd, "GANTT")) {
            if (schedule.total > 60) return bad(self.gpa, "chart too wide ({d} days)", .{schedule.total});
            var width: usize = 0;
            for (names) |task| width = @max(width, task.name.len);
            for (0..width) |_| try self.out.add(" ");
            try self.out.add(" |");
            for (0..@as(usize, @intCast(schedule.total))) |day| try self.out.print("{d}", .{day % 10});
            try self.out.add("|\n");
            for (try self.startOrder(scratch, schedule)) |task| {
                const value = schedule.times[task.slot];
                try padded(self.out, scratch, task.name, width, false);
                try self.out.add(" |");
                var day: Int = 0;
                while (day < schedule.total) : (day += 1) {
                    const symbol: Text = if (value.es <= day and day < value.ef) (if (value.tf == 0) "=" else "-") else if (value.ef <= day and day < value.lf) "." else " ";
                    try self.out.add(symbol);
                }
                try self.out.add("|\n");
            }
        } else if (equal(cmd, "LEVEL")) {
            try self.level(scratch, topo.order, schedule, number(w[1]));
        } else if (equal(cmd, "LOAD")) {
            const values = try self.usage(scratch, schedule, w[1]);
            const highest = peak(values);
            const first = std.mem.findScalar(Int, values, highest).?;
            try self.out.print("load {s}:", .{w[1]});
            for (values) |value| try self.out.print(" {d}", .{value});
            try self.out.line("\npeak {d} on day {d}", .{ highest, first });
            if (self.capacities.get(w[1])) |cap| {
                var count: usize = 0;
                for (values) |value| if (value > cap) {
                    count += 1;
                };
                try self.out.line("capacity {d} exceeded on {d} days", .{ cap, count });
            }
        } else if (equal(cmd, "CRASH")) {
            const initial = schedule.total;
            var remaining = number(w[1]);
            var steps: usize = 0;
            var spent: Int = 0;
            var reason: Text = "";
            while (true) {
                schedule = self.compute(topo.order, null, 0);
                var chosen: ?*Task = null;
                for (names) |task| {
                    if (schedule.times[task.slot].tf != 0) continue;
                    if (task.crash) |data| {
                        if (task.crashed < data.limit and self.compute(topo.order, task, task.duration() - 1).total < schedule.total and
                            (chosen == null or data.cost < chosen.?.crash.?.cost)) chosen = task;
                    }
                }
                const task = chosen orelse {
                    reason = "no candidate";
                    break;
                };
                const cost = task.crash.?.cost;
                if (cost > remaining) {
                    reason = "insufficient budget";
                    break;
                }
                const before = task.duration();
                task.crashed += 1;
                remaining -= cost;
                spent += cost;
                steps += 1;
                try self.out.line("step {d}: {s} {d} -> {d}, cost {d}, project {d}", .{ steps, task.name, before, before - 1, cost, self.compute(topo.order, null, 0).total });
            }
            try self.out.line("crash done: {d} days, cost {d}, project {d} -> {d}, budget left {d}, {s}", .{ steps, spent, initial, schedule.total, remaining, reason });
        } else if (equal(cmd, "WHATIF")) {
            const changed = try self.get(w[1]);
            const after = self.compute(topo.order, changed, number(w[2]));
            try self.out.line("whatif {s} {d} -> {s}: project {d} -> {d}", .{ changed.name, changed.duration(), w[2], schedule.total, after.total });
            for (names) |task| {
                const a = schedule.times[task.slot];
                const b = after.times[task.slot];
                if (a.es == b.es and a.ef == b.ef and a.tf == b.tf) continue;
                try self.out.add(task.name);
                if (a.es != b.es) try self.out.print(" ES {d}->{d}", .{ a.es, b.es });
                if (a.ef != b.ef) try self.out.print(" EF {d}->{d}", .{ a.ef, b.ef });
                if (a.tf != b.tf) try self.out.print(" TF {d}->{d}", .{ a.tf, b.tf });
                try self.out.add("\n");
            }
            const before_names = try taskNames(scratch, try self.critical(scratch, schedule), " ");
            const after_names = try taskNames(scratch, try self.critical(scratch, after), " ");
            if (!equal(before_names, after_names)) try self.out.line("critical {s} -> {s}", .{ before_names, after_names });
        } else if (equal(cmd, "BASELINE")) {
            var saved: Baseline = .{ .total = schedule.total };
            for (names) |task| {
                const value = schedule.times[task.slot];
                try saved.times.put(self.gpa, task.name, .{ value.es, value.ef });
            }
            self.baseline = saved;
            try self.out.line("baseline saved: {d} tasks, duration {d}", .{ names.len, schedule.total });
        } else if (equal(cmd, "VARIANCE")) {
            const old = self.baseline.?;
            try self.out.line("variance: duration {d} -> {d} ({s})", .{ old.total, schedule.total, try signed(scratch, schedule.total - old.total) });
            var all: std.StringHashMapUnmanaged(void) = .empty;
            for (try keys(scratch, old.times)) |name| try all.put(scratch, name, {});
            for (names) |task| try all.put(scratch, task.name, {});
            var count: usize = 0;
            for (try keys(scratch, all)) |name| {
                const before = old.times.get(name);
                if (self.tasks.get(name)) |task| {
                    const after = schedule.times[task.slot];
                    if (before) |value| {
                        if (value[0] == after.es and value[1] == after.ef) continue;
                        try self.out.line("{s} start {s} finish {s}", .{ name, try signed(scratch, after.es - value[0]), try signed(scratch, after.ef - value[1]) });
                    } else try self.out.line("{s} new", .{name});
                } else try self.out.line("{s} removed", .{name});
                count += 1;
            }
            if (count == 0) try self.out.add("no task changes\n");
        }
    }
};

fn peak(values: []const Int) Int {
    var result: Int = 0;
    for (values) |value| result = @max(result, value);
    return result;
}
fn padded(out: *Builder, scratch: Allocator, text: Text, width: usize, left: bool) Allocator.Error!void {
    _ = scratch;
    const count = width - @min(width, text.len);
    if (left) for (0..count) |_| {
        try out.add(" ");
    };
    try out.add(text);
    if (!left) for (0..count) |_| {
        try out.add(" ");
    };
}
fn taskNames(gpa: Allocator, tasks: []const *Task, separator: Text) Allocator.Error!Text {
    var parts: std.ArrayList(Text) = .empty;
    for (tasks) |task| try parts.append(gpa, task.name);
    return join(gpa, parts.items, separator);
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var input_buffer: [8192]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    const text = try input.interface.allocRemaining(gpa, .unlimited);
    var lines = std.mem.splitScalar(u8, text, '\n');
    const count: usize = @intCast(number(lines.next().?));
    var out: Builder = .{ .gpa = gpa };
    var project: Project = .{ .gpa = gpa, .out = &out };
    for (0..count) |_| {
        var scratch_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer scratch_arena.deinit();
        const scratch = scratch_arena.allocator();
        var words: std.ArrayList(Text) = .empty;
        var iterator = std.mem.splitScalar(u8, lines.next().?, ' ');
        while (iterator.next()) |word| try words.append(scratch, word);
        project.command(scratch, words.items) catch |err| switch (err) {
            error.Invalid => try out.line("error: {s}", .{failure}),
            else => return err,
        };
    }
    var output_buffer: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    try output.interface.writeAll(out.bytes.items);
    try output.interface.flush();
}
