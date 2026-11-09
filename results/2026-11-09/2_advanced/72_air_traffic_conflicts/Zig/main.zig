const std = @import("std");
const d = @import("flight_plans.zig");
const t = @import("trajectory.zig");
const c = @import("conflict.zig");
const resolution = @import("resolution.zig");
const report = @import("report.zig");
const f = d.f;
const n = d.n;
const u = d.u;
const dec = report.dec;
const decimal = report.decimal;
const pi = 3.141592653589793;
const geometry_names = [_][]const u8{ "head_on", "crossing", "trailing" };
const severity_names = [_][]const u8{ "HIGH", "MEDIUM", "LOW" };
const outcomes = [_][]const u8{ "remaining", "resolved", "indirect" };
const Summary = struct { pair: c.Pair, start: f64, end: f64, distance: f64 };
fn summary(item: c.Conflict) Summary {
    return .{ .pair = item.pair, .start = item.start, .end = item.end, .distance = item.closest.loss.distance };
}
fn summaryBefore(left: Summary, right: Summary) bool {
    return left.start < right.start or (left.start == right.start and (left.pair[0] < right.pair[0] or (left.pair[0] == right.pair[0] and left.pair[1] < right.pair[1])));
}
fn pairEqual(left: c.Pair, right: c.Pair) bool {
    return left[0] == right[0] and left[1] == right[1];
}
const TrialStatus = enum { infeasible, blocked, accepted };
const Trial = struct { flight: usize, name: []const u8, status: TrialStatus = .infeasible, blocker: ?Summary = null };
const Round = struct { target: Summary, trials: std.ArrayList(Trial) = .empty, accepted: ?Trial = null };
const Transit = struct { flight: usize, sector: usize, entry: f64, exit: f64, previous: ?usize = null,
     next: ?usize = null };
const Period = struct { sector: usize, number: usize, start: i64, end: i64, entries: [2]usize = .{ 0,
     0 }, peak: [2]i64 = .{ 0, 0 }, mean: f64 = 0, status: usize = 0 };
const Alert = struct { pair: c.Pair, first: i64, last: i64, samples: usize = 1, predicted: f64,
     distance: f64, lead: ?f64 = null };
const LevelUsage = struct { level: i64, flights: [2][100]bool = [_][100]bool{[_]bool{false} ** 100} ** 2,
     time: [2]f64 = .{ 0, 0 } };
fn active(item: c.Conflict, time: f64) bool {
    return item.start <= time and time < item.end;
}
fn track(segment: t.Segment) f64 {
    const angle = std.math.atan2(segment.velocity[0], segment.velocity[1]) * 180 / pi;
    return if (angle < 0) angle + 360 else angle;
}
fn contains(sector: d.Sector, point: t.Point) bool {
    return f(sector.x1) / 10 <= point[0] and point[0] < f(sector.x2) / 10 and f(sector.y1) / 10 <= point[1] and point[1] < f(sector.y2) / 10 and f(sector.lower) * 100 <= point[2] and point[2] < f(sector.upper) * 100;
}
fn inside(segment: t.Segment, sector: d.Sector) ?[2]f64 {
    const low = [_]f64{ f(sector.x1) / 10, f(sector.y1) / 10, f(sector.lower) * 100 };
    const high = [_]f64{ f(sector.x2) / 10, f(sector.y2) / 10, f(sector.upper) * 100 };
    var first = segment.start_time;
    var last = segment.end_time;
    for (0..3) |axis| {
        const p = segment.start[axis];
        const v = segment.velocity[axis];
        if (v == 0) {
            if (!(low[axis] <= p and p < high[axis])) return null;
        } else {
            const r1 = (low[axis] - p) / v;
            const r2 = (high[axis] - p) / v;
            first = @max(first, segment.start_time + @min(r1, r2));
            last = @min(last, segment.start_time + @max(r1, r2));
        }
    }
    return if (last - first > 1e-6) .{ first, last } else null;
}
fn grid(width: usize, height: usize, character: u8) [][]u8 {
    const out = d.alloc([]u8, height);
    for (out) |*row| {
        row.* = d.alloc(u8, width);
        @memset(row.*, character);
    }
    return out;
}
const Traffic = struct {
    input: d.Input,
    work: std.mem.Allocator,
    plans: [2][]d.Plan,
    trajectories: [2][]t.Trajectory,
    conflicts: [2][]c.Conflict = .{ &.{}, &.{} },
    unresolved: [100][100]bool = [_][100]bool{[_]bool{false} ** 100} ** 100,
    resolved: [100][100]bool = [_][100]bool{[_]bool{false} ** 100} ** 100,
    final_pairs: [100][100]bool = [_][100]bool{[_]bool{false} ** 100} ** 100,
    rounds: std.ArrayList(Round) = .empty,
    unresolved_conflicts: std.ArrayList(Summary) = .empty,
    transits: [2]std.ArrayList(Transit) = .{ .empty, .empty },
    occupancy: [2][][]i64 = undefined,
    periods: std.ArrayList(Period) = .empty,
    samples: []const i64,
    fn init(input: d.Input, work: std.mem.Allocator) Traffic {
        const count = input.plans.len;
        var samples: std.ArrayList(i64) = .empty;
        var time = input.params.sample_start;
        while (time < input.params.sample_end) : (time += 60) d.append(i64, &samples, time);
        const self: Traffic = .{ .input = input, .work = work, .plans = .{ d.dupe(d.Plan, input.plans),
             d.dupe(d.Plan, input.plans) }, .trajectories = .{ d.alloc(t.Trajectory, count),
             d.alloc(t.Trajectory, count) }, .samples = samples.items };
        for (0..2) |state| for (self.plans[state], self.trajectories[state]) |plan, *trajectory| {
            trajectory.* = t.build(plan, input.types);
        };
        return self;
    }
    fn callsign(self: *const Traffic, flight: usize) []const u8 {
        return self.input.plans[flight].callsign;
    }
    fn pairName(self: *const Traffic, pair: c.Pair) []const u8 {
        return d.fmt("{s}-{s}", .{ self.callsign(pair[0]), self.callsign(pair[1]) });
    }
    fn sectorName(self: *const Traffic, sector: ?usize) []const u8 {
        return if (sector) |index| self.input.sectors[index].name else "-";
    }
    fn history(self: *const Traffic, flight: usize) []const u8 {
        const values = self.plans[1][flight].history;
        return if (values.len == 0) "-" else report.joined(values);
    }
    fn findBlocker(self: *const Traffic, changed: usize, candidate: *const t.Trajectory, partner: usize,
         start: f64) ?Summary {
        var arena = std.heap.ArenaAllocator.init(self.work);
        defer arena.deinit();
        var out: ?Summary = null;
        for (0..self.input.plans.len) |other| {
            if (other == changed) continue;
            const pair: c.Pair = .{ @min(changed, other), @max(changed, other) };
            if (self.unresolved[pair[0]][pair[1]]) continue;
            const first = if (pair[0] == changed) candidate else &self.trajectories[1][pair[0]];
            const second = if (pair[1] == changed) candidate else &self.trajectories[1][pair[1]];
            for (c.pairConflicts(arena.allocator(), pair[0], first, pair[1], second, self.input.params)) |item| {
                if (other == partner or item.start < start + f(self.input.params.lookahead)) {
                    const value = summary(item);
                    if (out == null or summaryBefore(value, out.?)) out = value;
                }
            }
        }
        return out;
    }
    fn resolve(self: *Traffic) void {
        const choices = resolution.manoeuvres(self.input.params.max_delay);
        while (true) {
            var arena = std.heap.ArenaAllocator.init(self.work);
            defer arena.deinit();
            const current = c.allConflicts(arena.allocator(), self.trajectories[1], self.input.params);
            var target: ?Summary = null;
            for (current) |item| if (!self.unresolved[item.pair[0]][item.pair[1]]) {
                target = summary(item);
                break;
            };
            if (target == null) break;
            const chosen = target.?;
            var record: Round = .{ .target = chosen };
            const priority = resolution.priorityOrder(chosen.pair[0], chosen.pair[1], self.plans[1]);
            for (0..2) |index| {
                if (record.accepted != null) break;
                const flight = priority[index];
                const partner = priority[1 - index];
                for (choices) |choice| {
                    var trial: Trial = .{ .flight = flight, .name = choice.name };
                    if (resolution.propose(self.plans[1][flight], choice, self.input.types,
                         self.input.params)) |proposal| {
                        var changed = proposal;
                        const candidate = t.build(changed, self.input.types);
                        trial.blocker = self.findBlocker(flight, &candidate, partner, chosen.start);
                        if (trial.blocker != null) trial.status = .blocked else {
                            trial.status = .accepted;
                            const names = d.alloc([]const u8, changed.history.len + 1);
                            @memcpy(names[0..changed.history.len], changed.history);
                            names[names.len - 1] = choice.name;
                            changed.history = names;
                            self.plans[1][flight] = changed;
                            self.trajectories[1][flight] = candidate;
                            record.accepted = trial;
                        }
                    }
                    d.append(Trial, &record.trials, trial);
                    if (record.accepted != null) break;
                }
            }
            if (record.accepted != null) self.resolved[chosen.pair[0]][chosen.pair[1]] = true else {
                self.unresolved[chosen.pair[0]][chosen.pair[1]] = true;
                d.append(Summary, &self.unresolved_conflicts, chosen);
            }
            d.append(Round, &self.rounds, record);
        }
    }
    fn classify(self: *Traffic, state: usize) void {
        for (self.conflicts[state]) |*item| {
            const piece = item.closest;
            const a = self.trajectories[state][item.pair[0]].segments[piece.first_segment];
            const b = self.trajectories[state][item.pair[1]].segments[piece.second_segment];
            const pa = t.position(a, piece.loss.time);
            const pb = t.position(b, piece.loss.time);
            var middle: t.Point = undefined;
            item.first_level = pa[2] / 100;
            item.second_level = pb[2] / 100;
            item.first_track = track(a);
            item.second_track = track(b);
            const gap = @abs(item.first_track - item.second_track);
            item.angle = if (gap > 180) 360 - gap else gap;
            const dot = a.velocity[0] * b.velocity[0] + a.velocity[1] * b.velocity[1];
            const cross = a.velocity[0] * b.velocity[1] - a.velocity[1] * b.velocity[0];
            item.geometry = if (dot * dot > cross * cross) (if (dot < 0) @as(usize, 0) else 2) else 1;
            item.severity = if (10 * piece.loss.distance < 4 * f(self.input.params.horizontal)) 0 else if (10 * piece.loss.distance < 7 * f(self.input.params.horizontal)) 1 else 2;
            for (0..3) |axis| middle[axis] = (pa[axis] + pb[axis]) / 2;
            item.sector = null;
            for (self.input.sectors, 0..) |sector, i| if (contains(sector, middle)) {
                item.sector = i;
                break;
            };
            item.outcome = if (state == 1 or self.final_pairs[item.pair[0]][item.pair[1]]) 0 else if (self.resolved[item.pair[0]][item.pair[1]]) 1 else 2;
        }
    }
    fn trajectoryReport(self: *const Traffic) d.Lines {
        var out: d.Lines = .{};
        out.add("callsign,segment,leg,phase,t_start,t_end,x_start,y_start,fl_start,x_end,y_end,fl_end", .{});
        for (self.trajectories[1], 0..) |trajectory, flight| for (trajectory.segments[0..trajectory.count]) |segment| out.add("{s},{d},{d},{s},{s},{s},{s},{s},{d},{s},{s},{d}",
             .{ self.callsign(flight), segment.number, segment.leg, t.phaseName(segment.phase),
             dec(segment.start_time), dec(segment.end_time), dec(segment.start[0]), dec(segment.start[1]),
             @as(i64, @intFromFloat(segment.start[2] / 100)), dec(segment.end[0]), dec(segment.end[1]),
             @as(i64, @intFromFloat(segment.end[2] / 100)) });
        return out;
    }
    fn counts(self: *const Traffic, state: usize) [100]usize {
        var out = [_]usize{0} ** 100;
        for (self.conflicts[state]) |item| {
            out[item.pair[0]] += 1;
            out[item.pair[1]] += 1;
        }
        return out;
    }
    fn conflictReport(self: *const Traffic, state: usize, out: *d.Lines) void {
        const list = self.conflicts[state];
        out.add("CONFLICTS plan={s} count={d}", .{ if (state == 1) "final" else "initial", list.len });
        var duration: f64 = 0;
        var minimum: f64 = 0;
        var geometry = [_]usize{0} ** 3;
        var severity = [_]usize{0} ** 3;
        for (list, 1..) |item, i| {
            const piece = item.closest;
            const a = self.trajectories[state][item.pair[0]].segments[piece.first_segment];
            const b = self.trajectories[state][item.pair[1]].segments[piece.second_segment];
            out.add("CONFLICT {d} {s} start={s} end={s} duration={s} outcome={s}", .{ i, self.pairName(item.pair),
                 dec(item.start), dec(item.end), dec(item.end - item.start), outcomes[item.outcome] });
            out.add("  CPA t={s} dist={s} vert={s} levels={s}/{s} tracks={s}/{s} angle={s}",
                 .{ dec(piece.loss.time), dec(piece.loss.distance), decimal(piece.loss.vertical,
                 1), decimal(item.first_level, 2), decimal(item.second_level, 2), decimal(item.first_track,
                 1), decimal(item.second_track, 1), decimal(item.angle, 1) });
            out.add("  TYPE geometry={s} phases={s}/{s} segments={d}/{d} sector={s} severity={s}",
                 .{ geometry_names[item.geometry], t.phaseName(a.phase), t.phaseName(b.phase),
                 a.number, b.number, self.sectorName(item.sector), severity_names[item.severity] });
            for (item.pieces) |part| out.add("  PIECE {d}/{d} {s} {s}", .{ part.first_segment + 1,
                 part.second_segment + 1, dec(part.loss.low), dec(part.loss.high) });
            duration += item.end - item.start;
            if (i == 1 or piece.loss.distance < minimum) minimum = piece.loss.distance;
            geometry[item.geometry] += 1;
            severity[item.severity] += 1;
        }
        out.add("SUMMARY count={d} total={s} min_dist={s} head_on={d} crossing={d} trailing={d} high={d} medium={d} low={d}",
             .{ list.len, dec(duration), if (list.len == 0) "-" else dec(minimum), geometry[0],
             geometry[1], geometry[2], severity[0], severity[1], severity[2] });
        const involved = self.counts(state);
        for (0..self.input.plans.len) |flight| {
            if (involved[flight] == 0) continue;
            var partners = [_]bool{false} ** 100;
            var first: ?f64 = null;
            for (list) |item| if (item.pair[0] == flight or item.pair[1] == flight) {
                partners[if (item.pair[0] == flight) item.pair[1] else item.pair[0]] = true;
                if (first == null) first = item.start;
            };
            var names: std.ArrayList([]const u8) = .empty;
            for (0..self.input.plans.len) |other| if (partners[other]) d.append([]const u8,
                 &names, self.callsign(other));
            out.add("FLIGHT {s} conflicts={d} first={s} partners={s}", .{ self.callsign(flight),
                 involved[flight], dec(first.?), report.joined(names.items) });
        }
        out.add("TIMELINE from={d} to={d} step=60", .{ self.input.params.sample_start, self.input.params.sample_end });
        for (0..self.input.plans.len) |flight| {
            if (involved[flight] == 0) continue;
            const text = d.alloc(u8, self.samples.len);
            for (self.samples, text) |time, *character| {
                character.* = if (t.activeSegment(&self.trajectories[state][flight], f(time)) != null) '-' else '.';
                if (character.* == '-') for (list) |item| {
                    if ((item.pair[0] == flight or item.pair[1] == flight) and active(item, f(time))) {
                        character.* = 'X';
                        break;
                    }
                };
            }
            out.add("{s} {s}", .{ self.callsign(flight), text });
        }
    }
    fn resolutionReport(self: *const Traffic) d.Lines {
        var out: d.Lines = .{};
        var accepted: usize = 0;
        var level: usize = 0;
        var speed: usize = 0;
        var delay: usize = 0;
        var trials: usize = 0;
        var infeasible: usize = 0;
        var blocked: usize = 0;
        for (self.rounds.items, 1..) |record, i| {
            const target = record.target;
            out.add("ROUND {d} {s} start={s} end={s} dist={s}", .{ i, self.pairName(target.pair),
                 dec(target.start), dec(target.end), dec(target.distance) });
            for (record.trials.items) |trial| {
                var text: d.Text = .{};
                text.add("  TRY {s} {s} {s}", .{ self.callsign(trial.flight), trial.name, @tagName(trial.status) });
                if (trial.blocker) |item| text.add(" {s} start={s}", .{ self.pairName(item.pair), dec(item.start) });
                out.add("{s}", .{text.value()});
                trials += 1;
                infeasible += @intFromBool(trial.status == .infeasible);
                blocked += @intFromBool(trial.status == .blocked);
            }
            if (record.accepted) |trial| {
                out.add("  RESULT resolved {s} {s}", .{ self.callsign(trial.flight), trial.name });
                accepted += 1;
                level += @intFromBool(d.eq(trial.name, "level_up") or d.eq(trial.name, "level_down"));
                speed += @intFromBool(d.eq(trial.name, "speed_down"));
                delay += @intFromBool(std.mem.startsWith(u8, trial.name, "delay_"));
            } else out.add("  RESULT unresolved", .{});
        }
        const initial = self.counts(0);
        const final = self.counts(1);
        var total_extra: f64 = 0;
        var total_delay: i64 = 0;
        for (self.plans[0], self.plans[1], 0..) |old, plan, flight| {
            const before = self.trajectories[0][flight].arrival;
            const after = self.trajectories[1][flight].arrival;
            const extra = after - before;
            total_extra += extra;
            total_delay += plan.delay;
            out.add("FLIGHT {s} departure={d} delay={d} level={s} speed={d}->{d} arrival={s}->{s} extra={s} length={s} conflicts={d}->{d} manoeuvres={s}",
                 .{ plan.callsign, plan.departure + plan.delay, plan.delay, report.signedInteger(plan.offset),
                 old.speed, plan.speed, dec(before), dec(after), dec(extra), dec(self.trajectories[1][flight].length),
                 initial[flight], final[flight], self.history(flight) });
        }
        for (self.unresolved_conflicts.items) |item| out.add("UNRESOLVED {s} start={s} dist={s}",
             .{ self.pairName(item.pair), dec(item.start), dec(item.distance) });
        out.add("TOTAL rounds={d} resolved={d} unresolved={d} level={d} speed={d} delay={d} total_delay={d} total_extra={s} trials={d} infeasible={d} blocked={d}",
             .{ self.rounds.items.len, accepted, self.unresolved_conflicts.items.len, level,
             speed, delay, total_delay, dec(total_extra), trials, infeasible, blocked });
        return out;
    }
    fn computeTransits(self: *Traffic, state: usize) void {
        for (self.trajectories[state], 0..) |trajectory, flight| {
            var list: std.ArrayList(Transit) = .empty;
            for (self.input.sectors, 0..) |sector, s| {
                var combined: std.ArrayList([2]f64) = .empty;
                for (trajectory.segments[0..trajectory.count]) |segment| if (inside(segment, sector)) |interval| {
                    if (combined.items.len > 0 and interval[0] - combined.items[combined.items.len - 1][1] <= 1e-6) combined.items[combined.items.len - 1][1] = interval[1] else d.append([2]f64,
                         &combined, interval);
                };
                for (combined.items) |interval| d.append(Transit, &list, .{ .flight = flight,
                     .sector = s, .entry = interval[0], .exit = interval[1] });
            }
            const Context = struct {
                fn less(_: void, left: Transit, right: Transit) bool {
                    return left.entry < right.entry or (left.entry == right.entry and left.sector < right.sector);
                }
            };
            std.mem.sort(Transit, list.items, {}, Context.less);
            if (list.items.len > 0) for (1..list.items.len) |i| {
                if (@abs(list.items[i].entry - list.items[i - 1].exit) <= 1e-6) {
                    list.items[i - 1].next = list.items[i].sector;
                    list.items[i].previous = list.items[i - 1].sector;
                }
            };
            for (list.items) |item| d.append(Transit, &self.transits[state], item);
        }
    }
    fn transitReport(self: *const Traffic) d.Lines {
        var out: d.Lines = .{};
        out.add("callsign,sector,entry,exit,duration,from,to", .{});
        for (self.transits[1].items) |item| out.add("{s},{s},{s},{s},{s},{s},{s}", .{ self.callsign(item.flight),
             self.sectorName(item.sector), dec(item.entry), dec(item.exit), dec(item.exit - item.entry),
             self.sectorName(item.previous), self.sectorName(item.next) });
        return out;
    }
    fn computeOccupancy(self: *Traffic, state: usize) void {
        self.occupancy[state] = d.alloc([]i64, self.input.sectors.len);
        for (self.occupancy[state]) |*row| {
            row.* = d.alloc(i64, self.samples.len);
            @memset(row.*, 0);
        }
        for (self.samples, 0..) |time, i| for (self.trajectories[state]) |*trajectory| {
            if (t.activeSegment(trajectory, f(time))) |segment| {
                const point = t.position(segment, f(time));
                for (self.input.sectors, 0..) |sector, s| if (contains(sector, point)) {
                    self.occupancy[state][s][i] += 1;
                };
            }
        };
    }
    fn computePeriods(self: *Traffic) void {
        for (self.input.sectors, 0..) |sector, s| {
            var i: usize = 0;
            while (i < self.samples.len) : (i += 5) {
                var period: Period = .{ .sector = s, .number = i / 5 + 1, .start = self.samples[i],
                     .end = self.samples[i] + 300 };
                var sum: i64 = 0;
                for (0..2) |state| {
                    for (i..i + 5) |j| {
                        const value = self.occupancy[state][s][j];
                        period.peak[state] = @max(period.peak[state], value);
                        if (state == 1) sum += value;
                    }
                    for (self.transits[state].items) |item| if (item.sector == s and f(period.start) <= item.entry and item.entry < f(period.end)) {
                        period.entries[state] += 1;
                    };
                }
                period.mean = f(sum) / 5;
                period.status = if (period.peak[1] > sector.capacity) 0 else if (period.peak[0] > sector.capacity) 1 else 2;
                d.append(Period, &self.periods, period);
            }
        }
    }
    fn sectorLoadReport(self: *const Traffic) d.Lines {
        var out: d.Lines = .{};
        out.add("sector,period,start,end,entries_initial,entries_final,peak_initial,peak_final,mean_final,capacity,status",
             .{});
        const status = [_][]const u8{ "OVER", "RELIEVED", "OK" };
        for (self.periods.items) |period| out.add("{s},{d},{d},{d},{d},{d},{d},{d},{s},{d},{s}",
             .{ self.sectorName(period.sector), period.number, period.start, period.end, period.entries[0],
             period.entries[1], period.peak[0], period.peak[1], decimal(period.mean, 1), self.input.sectors[period.sector].capacity,
             status[period.status] });
        return out;
    }
    fn sectorReport(self: *const Traffic) d.Lines {
        var out: d.Lines = .{};
        for (self.input.sectors, 0..) |sector, s| {
            out.add("SECTOR {s} x={d}..{d} y={d}..{d} fl={d}..{d} capacity={d}", .{ sector.name,
                 sector.x1, sector.x2, sector.y1, sector.y2, sector.lower, sector.upper, sector.capacity });
            var height = sector.capacity + 1;
            for (0..2) |state| {
                var entries: usize = 0;
                var dwell: f64 = 0;
                var peak: i64 = 0;
                var over: usize = 0;
                var conflict_count: usize = 0;
                for (self.transits[state].items) |item| if (item.sector == s) {
                    entries += 1;
                    dwell += item.exit - item.entry;
                };
                for (self.occupancy[state][s]) |value| peak = @max(peak, value);
                for (self.periods.items) |period| if (period.sector == s and period.peak[state] > sector.capacity) {
                    over += 1;
                };
                for (self.conflicts[state]) |item| if (item.sector == s) {
                    conflict_count += 1;
                };
                out.add("{s} entries={d} time={s} mean={s} peak={d} over={d} conflicts={d}",
                     .{ if (state == 0) "INITIAL" else "FINAL", entries, dec(dwell), if (entries > 0) dec(dwell / f(entries)) else "-",
                     peak, over, conflict_count });
                if (state == 1) height = @max(height, peak);
            }
            const cells = grid(self.samples.len, u(height), '.');
            for (cells, 0..) |row, index| {
                const k = height - n(index);
                for (row, self.occupancy[1][s]) |*character, value| character.* = if (value >= k) '#' else if (k == sector.capacity) '-' else '.';
            }
            report.frame(&out, cells);
        }
        var levels: std.ArrayList(LevelUsage) = .empty;
        for (0..2) |state| for (self.trajectories[state], 0..) |trajectory, flight| {
            for (trajectory.segments[0..trajectory.count]) |segment| {
                if (segment.phase != .level) continue;
                const level: i64 = @intFromFloat(segment.start[2] / 100);
                var i: usize = 0;
                while (i < levels.items.len and levels.items[i].level != level) : (i += 1) {}
                if (i == levels.items.len) d.append(LevelUsage, &levels, .{ .level = level });
                levels.items[i].flights[state][flight] = true;
                levels.items[i].time[state] += segment.end_time - segment.start_time;
            }
        };
        const Context = struct {
            fn less(_: void, left: LevelUsage, right: LevelUsage) bool {
                return left.level > right.level;
            }
        };
        std.mem.sort(LevelUsage, levels.items, {}, Context.less);
        out.add("LEVELS", .{});
        for (levels.items) |usage| {
            var counts_by_state = [_]usize{ 0, 0 };
            for (0..2) |state| for (0..self.input.plans.len) |flight| {
                counts_by_state[state] += @intFromBool(usage.flights[state][flight]);
            };
            out.add("LEVEL {d} flights={d}->{d} time={s}->{s}", .{ usage.level, counts_by_state[0],
                 counts_by_state[1], dec(usage.time[0]), dec(usage.time[1]) });
        }
        var handoffs = [_][20]usize{[_]usize{0} ** 20} ** 20;
        var total: usize = 0;
        for (self.transits[1].items) |item| if (item.next) |next| {
            handoffs[item.sector][next] += 1;
            total += 1;
        };
        out.add("HANDOFFS plan=final count={d}", .{total});
        for (0..self.input.sectors.len) |first| for (0..self.input.sectors.len) |second| {
            if (handoffs[first][second] > 0) out.add("HANDOFF {s} {s} {d}", .{ self.sectorName(first),
                 self.sectorName(second), handoffs[first][second] });
        };
        return out;
    }
    fn alertReport(self: *const Traffic, state: usize, out: *d.Lines) void {
        var alerts: std.ArrayList(Alert) = .empty;
        for (0..self.input.plans.len) |first| for (first + 1..self.input.plans.len) |second| {
            var previous = false;
            for (self.samples) |time| {
                const a = t.activeSegment(&self.trajectories[state][first], f(time)) orelse continue;
                const b = t.activeSegment(&self.trajectories[state][second], f(time)) orelse continue;
                const pa = t.position(a, f(time));
                const pb = t.position(b, f(time));
                var relative: t.Point = undefined;
                var velocity: t.Point = undefined;
                for (0..3) |axis| {
                    relative[axis] = pa[axis] - pb[axis];
                    velocity[axis] = a.velocity[axis] - b.velocity[axis];
                }
                const loss = c.lossInterval(relative, velocity, 0, f(self.input.params.alert),
                     f(self.input.params.horizontal), f(self.input.params.vertical)) orelse continue;
                if (previous and time - alerts.items[alerts.items.len - 1].last == 60) {
                    const item = &alerts.items[alerts.items.len - 1];
                    item.last = time;
                    item.samples += 1;
                    item.distance = @min(item.distance, loss.distance);
                } else {
                    d.append(Alert, &alerts, .{ .pair = .{ first, second }, .first = time,
                         .last = time, .predicted = f(time) + loss.low, .distance = loss.distance });
                    previous = true;
                }
            }
        };
        const Context = struct {
            fn less(_: void, left: Alert, right: Alert) bool {
                return left.first < right.first or (left.first == right.first and (left.pair[0] < right.pair[0] or (left.pair[0] == right.pair[0] and left.pair[1] < right.pair[1])));
            }
        };
        std.mem.sort(Alert, alerts.items, {}, Context.less);
        const detected = d.alloc(bool, self.conflicts[state].len);
        @memset(detected, false);
        for (alerts.items) |*alert| for (self.conflicts[state], 0..) |item, i| {
            if (pairEqual(alert.pair, item.pair) and item.start < f(alert.last + self.input.params.alert) and item.end > f(alert.first)) {
                detected[i] = true;
                if (alert.lead == null) alert.lead = item.start - f(alert.first);
            }
        };
        out.add("ALERTS plan={s} horizon={d} count={d}", .{ if (state == 0) "initial" else "final",
             self.input.params.alert, alerts.items.len });
        var lead_sum: f64 = 0;
        var true_count: usize = 0;
        var missed: usize = 0;
        for (alerts.items, 1..) |alert, i| {
            out.add("ALERT {d} {s} first={d} last={d} samples={d} predicted={s} min_dist={s} status={s} lead={s}",
                 .{ i, self.pairName(alert.pair), alert.first, alert.last, alert.samples, dec(alert.predicted),
                 dec(alert.distance), if (alert.lead != null) "true" else "false", if (alert.lead) |lead| dec(lead) else "-" });
            if (alert.lead) |lead| {
                lead_sum += lead;
                true_count += 1;
            }
        }
        for (self.conflicts[state], detected) |item, found| if (!found) {
            missed += 1;
            out.add("MISSED {s} start={s} end={s}", .{ self.pairName(item.pair), dec(item.start), dec(item.end) });
        };
        out.add("SUMMARY alerts={d} true={d} false={d} missed={d} mean_lead={s}", .{ alerts.items.len,
             true_count, alerts.items.len - true_count, missed, if (true_count > 0) dec(lead_sum / f(true_count)) else "-" });
    }
    fn cell(self: *const Traffic, point: t.Point) ?[2]usize {
        const radar = self.input.params.radar;
        const column: i64 = @intFromFloat(@floor((10 * point[0] - f(radar[0])) * f(radar[4]) / f(radar[2] - radar[0])));
        const bottom: i64 = @intFromFloat(@floor((10 * point[1] - f(radar[1])) * f(radar[5]) / f(radar[3] - radar[1])));
        return if (column >= 0 and column < radar[4] and bottom >= 0 and bottom < radar[5]) .{ u(column),
             u(radar[5] - 1 - bottom) } else null;
    }
    fn radarSnapshot(self: *const Traffic, state: usize, time: i64, out: *d.Lines) void {
        const width = u(self.input.params.radar[4]);
        const height = u(self.input.params.radar[5]);
        const cells = grid(width, height, '.');
        var counts_by_cell = [_]usize{0} ** 6400;
        var first_flight: [6400]usize = undefined;
        var positions = [_]?t.Point{null} ** 100;
        var segments: [100]t.Segment = undefined;
        var conflicted = [_]bool{false} ** 100;
        var active_count: usize = 0;
        var aircraft: usize = 0;
        for (self.conflicts[state]) |item| if (active(item, f(time))) {
            active_count += 1;
            conflicted[item.pair[0]] = true;
            conflicted[item.pair[1]] = true;
        };
        for (self.trajectories[state], 0..) |*trajectory, flight| if (t.activeSegment(trajectory, f(time))) |segment| {
            const point = t.position(segment, f(time));
            aircraft += 1;
            segments[flight] = segment;
            positions[flight] = point;
            if (self.cell(point)) |location| {
                const index = location[1] * width + location[0];
                counts_by_cell[index] += 1;
                first_flight[index] = flight;
            }
        };
        for (cells, 0..) |row, r| for (row, 0..) |*character, column| {
            const index = r * width + column;
            const count = counts_by_cell[index];
            if (count > 1) character.* = '0' + @as(u8, @intCast(count)) else if (count == 1) {
                const flight = first_flight[index];
                const ch = self.callsign(flight)[0];
                character.* = if (conflicted[flight]) ch - 'A' + 'a' else ch;
            }
        };
        for (0..self.input.plans.len) |flight| if (positions[flight] != null) {
            const future = f(time + self.input.params.leader);
            if (t.activeSegment(&self.trajectories[state][flight], future)) |segment| if (self.cell(t.position(segment,
                 future))) |location| {
                if (cells[location[1]][location[0]] == '.') cells[location[1]][location[0]] = '*';
            };
        };
        out.add("RADAR plan={s} t={d} aircraft={d} conflicts={d}", .{ if (state == 0) "initial" else "final",
             time, aircraft, active_count });
        report.frame(out, cells);
        for (0..self.input.plans.len) |flight| if (positions[flight]) |point| {
            const location_text = if (self.cell(point)) |location| d.fmt("{d},{d}", .{ location[0],
                 location[1] }) else "outside";
            out.add("{s} x={s} y={s} fl={s} track={s} phase={s} cell={s}", .{ self.callsign(flight),
                 dec(point[0]), dec(point[1]), decimal(point[2] / 100, 2), decimal(track(segments[flight]),
                 1), t.phaseName(segments[flight].phase), location_text });
        };
        for (self.conflicts[state]) |item| if (active(item, f(time))) {
            const pa = positions[item.pair[0]].?;
            const pb = positions[item.pair[1]].?;
            const dx = pa[0] - pb[0];
            const dy = pa[1] - pb[1];
            out.add("CONFLICT {s} dist={s} vert={s}", .{ self.pairName(item.pair), dec(@sqrt(dx * dx + dy * dy)),
                 decimal(@abs(pa[2] - pb[2]), 1) });
        };
    }
    fn densityReport(self: *const Traffic, state: usize, out: *d.Lines) void {
        const width = u(self.input.params.radar[4]);
        const height = u(self.input.params.radar[5]);
        const counts_by_cell = d.alloc(i64, width * height);
        @memset(counts_by_cell, 0);
        for (self.samples) |time| for (self.trajectories[state]) |*trajectory| {
            if (t.activeSegment(trajectory, f(time))) |segment| if (self.cell(t.position(segment,
                 f(time)))) |location| {
                counts_by_cell[location[1] * width + location[0]] += 1;
            };
        };
        const cells = grid(width, height, '.');
        var maximum: i64 = 0;
        for (cells, 0..) |row, r| for (row, 0..) |*character, column| {
            const count = counts_by_cell[r * width + column];
            maximum = @max(maximum, count);
            character.* = if (count == 0) '.' else if (count < 10) '0' + @as(u8, @intCast(count)) else '#';
        };
        out.add("DENSITY plan={s} from={d} to={d} step=60 max={d}", .{ if (state == 0) "initial" else "final",
             self.input.params.sample_start, self.input.params.sample_end, maximum });
        report.frame(out, cells);
    }
    fn stripsReport(self: *const Traffic) d.Lines {
        var out: d.Lines = .{};
        for (self.plans[1], 0..) |plan, flight| {
            const before = &self.trajectories[0][flight];
            const after = &self.trajectories[1][flight];
            out.add("STRIP {s} type={s} waypoints={d} length={s} manoeuvres={s}", .{ plan.callsign,
                 self.input.types[plan.type_index].name, plan.waypoints.len, dec(after.length),
                 self.history(flight) });
            for (plan.waypoints, 0..) |point, k| out.add("WPT {d} at={d}:{d} eta={s}->{s} fl={d}->{d}",
                 .{ k, point.x, point.y, dec(before.passing[k].time), dec(after.passing[k].time),
                 before.passing[k].level, after.passing[k].level });
            var sequence: std.ArrayList([]const u8) = .empty;
            for (self.transits[1].items) |item| if (item.flight == flight) d.append([]const u8,
                 &sequence, d.fmt("{s}@{s}", .{ self.sectorName(item.sector), dec(item.entry) }));
            out.add("SECTORS {s}", .{if (sequence.items.len == 0) "-" else report.joined(sequence.items)});
        }
        return out;
    }
    fn run(self: *Traffic, io: std.Io) !void {
        self.conflicts[0] = c.allConflicts(d.allocator, self.trajectories[0], self.input.params);
        self.resolve();
        self.conflicts[1] = c.allConflicts(d.allocator, self.trajectories[1], self.input.params);
        for (self.conflicts[1]) |item| self.final_pairs[item.pair[0]][item.pair[1]] = true;
        for (0..2) |state| {
            self.classify(state);
            self.computeTransits(state);
            self.computeOccupancy(state);
        }
        self.computePeriods();
        try std.Io.Dir.cwd().createDirPath(io, "output");
        try report.writeLines(io, "trajectories.csv", self.trajectoryReport());
        var conflicts: d.Lines = .{};
        self.conflictReport(0, &conflicts);
        self.conflictReport(1, &conflicts);
        try report.writeLines(io, "conflicts.txt", conflicts);
        try report.writeLines(io, "resolutions.txt", self.resolutionReport());
        try report.writeLines(io, "sector_transits.csv", self.transitReport());
        try report.writeLines(io, "sector_load.csv", self.sectorLoadReport());
        try report.writeLines(io, "sector_report.txt", self.sectorReport());
        var alerts: d.Lines = .{};
        self.alertReport(0, &alerts);
        self.alertReport(1, &alerts);
        try report.writeLines(io, "alerts.txt", alerts);
        var radar: d.Lines = .{};
        for (self.input.params.snapshots) |time| {
            self.radarSnapshot(0, time, &radar);
            self.radarSnapshot(1, time, &radar);
        }
        self.densityReport(0, &radar);
        self.densityReport(1, &radar);
        try report.writeLines(io, "radar.txt", radar);
        try report.writeLines(io, "strips.txt", self.stripsReport());
    }
};
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    d.allocator = arena.allocator();
    var traffic = Traffic.init(try d.readInputs(init.io), init.gpa);
    try traffic.run(init.io);
}
