const std = @import("std");
const E = @import("enrolment.zig");
const G = @import("conflict_graph.zig");
const C = @import("coloring.zig");
const M = @import("rooms.zig");
const R = @import("report.zig");

fn ceilDiv(a: i64, b: i64) i64 { return @divFloor(a + b - 1, b); }
const Calendar = struct {
    days: usize, periods: usize, slots: usize, limit: usize,
    lengths: [5]i64 = [_]i64{0} ** 5,
    weights: [4]i64,
    front_count: usize, deadline: usize, ratio: i64,
    closed: [36]bool = [_]bool{false} ** 36,
    fixed_slots: [36]bool = [_]bool{false} ** 36,
    open: E.Indices = .{},
    orders: std.ArrayList(G.Order) = .empty,
    fn init(lines: R.Strings) Calendar {
        var settings: [6]R.Strings = undefined;
        for (lines[0..6], &settings) |line, *fields| fields.* = R.split(line, ' ')[1..];
        const days = R.integer(settings[0][0]);
        const periods = settings[1].len;
        var result: Calendar = .{
            .days = days, .periods = periods, .slots = days * periods, .limit = R.integer(settings[2][0]),
            .weights = undefined, .front_count = R.integer(settings[4][0]), .deadline = R.integer(settings[4][1]), .ratio = R.number(settings[5][0]),
        };
        for (settings[1], 0..) |value, i| result.lengths[i] = R.number(value);
        for (settings[3], &result.weights) |value, *weight| weight.* = R.number(value);
        return result;
    }
    fn day(self: *const Calendar, slot: usize) usize { return (slot - 1) / self.periods + 1; }
    fn length(self: *const Calendar, slot: usize) i64 { return self.lengths[(slot - 1) % self.periods]; }
    fn name(self: *const Calendar, slot: usize) []const u8 { return R.fmt("D{d}P{d}", .{ self.day(slot), (slot - 1) % self.periods + 1 }); }
    fn slotAt(self: *const Calendar, day_text: []const u8, period_text: []const u8) ?usize {
        const d = R.integer(day_text);
        const p = R.integer(period_text);
        if (d < 1 or d > self.days or p < 1 or p > self.periods) return null;
        return (d - 1) * self.periods + p;
    }
    fn relation(self: *const Calendar, first: usize, second: usize) ?usize {
        const low = @min(first, second);
        const high = @max(first, second);
        if (self.day(low) == self.day(high)) {
            if (high - low == 1) return 0;
            if (high - low >= 2) return 1;
        } else if (high - low == 1) return 2;
        return null;
    }
};
const Breakdown = struct {
    counts: [3]i64 = [_]i64{0} ** 3,
    late: i64 = 0, total: i64 = 0,
    fn text(self: Breakdown) []const u8 { return R.fmt("back_to_back {d} same_day {d} overnight {d} front_load {d} penalty {d}", .{ self.counts[0], self.counts[1], self.counts[2], self.late, self.total }); }
};
const AttemptRecord = struct { courses: usize, dead_ends: usize, failed_course: ?usize };
const Insertion = struct { course: usize, slot: usize, increase: i64 };
const StudentStats = struct { counts: [3]i64 = [_]i64{0} ** 3, total: i64 = 0, assigned: E.Indices = .{} };
const RoomLoads = struct { exams: [20]usize = [_]usize{0} ** 20, students: [20]i64 = [_]i64{0} ** 20 };
const Scheduler = struct {
    courses: []E.Course, students: []E.Student, rooms: []M.Room,
    calendar: Calendar, errors: R.Lines, graph: G.Graph,
    largest_room: i64, penalty: i64 = 0,
    empty: E.Indices = .{}, oversized: E.Indices = .{}, schedulable: E.Indices = .{}, front_load: E.Indices = .{},
    fixed: [100]usize = [_]usize{0} ** 100,
    assignment: [100]usize = [_]usize{0} ** 100,
    excluded: [100]bool = [_]bool{false} ** 100,
    attempts: std.ArrayList(AttemptRecord) = .empty,
    choices: [100]C.Choice = undefined, choice_count: usize = 0,
    insertions: std.ArrayList(Insertion) = .empty,
    reasons: [100][36]?[]const u8 = [_][36]?[]const u8{[_]?[]const u8{null} ** 36} ** 100,
    initial: Breakdown = .{}, exchanged: Breakdown = .{}, final: Breakdown = .{},
    exchange_log: R.Lines = .{}, swap_log: R.Lines = .{},
    packed: [36]M.Packing = [_]M.Packing{.{}} ** 36,
    placements: [100]M.Placement = undefined,
    contributions: [100]i64 = [_]i64{0} ** 100,
    statistics: []StudentStats = undefined,
    fn init(courses: []E.Course, students: []E.Student, rooms: []M.Room, calendar_lines: R.Strings, errors: R.Lines) Scheduler {
        var result: Scheduler = .{
            .courses = courses, .students = students, .rooms = rooms, .calendar = Calendar.init(calendar_lines),
            .errors = errors, .graph = G.Graph.init(courses, students), .largest_room = rooms[rooms.len - 1].capacity,
        };
        for (courses, 0..) |course, c| {
            if (course.size() == 0) result.empty.add(c)
            else if (course.size() > result.largest_room) result.oversized.add(c)
            else result.schedulable.add(c);
        }
        result.front_load = E.ordered(courses, result.schedulable, null);
        result.front_load.len = @min(result.front_load.len, result.calendar.front_count);
        result.statistics = R.alloc(StudentStats, students.len);
        for (result.statistics) |*stats| stats.* = .{};
        result.validateCalendar(calendar_lines);
        return result;
    }
    fn isSchedulable(self: *const Scheduler, c: usize) bool { return self.courses[c].size() > 0 and self.courses[c].size() <= self.largest_room; }
    fn coursesAt(self: *const Scheduler, assignment: []const usize, slot: usize) E.Indices {
        var result: E.Indices = .{};
        for (0..self.courses.len) |c| { if (assignment[c] == slot) result.add(c); }
        return result;
    }
    fn blockedStudent(self: *const Scheduler, c: usize, slot: usize) ?usize {
        for (self.courses[c].students.items) |student| { if (self.students[student].unavailable[slot]) return student; }
        return null;
    }
    fn suitable(self: *const Scheduler, c: usize, slot: usize) bool {
        return self.calendar.length(slot) >= self.courses[c].duration and self.blockedStudent(c, slot) == null;
    }
    fn orderConflict(self: *const Scheduler, c: usize, slot: usize, assignment: []const usize) ?usize {
        var result: ?usize = null;
        for (self.calendar.orders.items) |order| {
            var other: ?usize = null;
            if (order.later == c and assignment[order.earlier] > 0 and slot <= assignment[order.earlier]) other = order.earlier
            else if (order.earlier == c and assignment[order.later] > 0 and slot >= assignment[order.later]) other = order.later;
            if (other) |value| { if (result == null or value < result.?) result = value; }
        }
        return result;
    }
    fn ordersSatisfied(self: *const Scheduler, assignment: []const usize) bool {
        for (self.calendar.orders.items) |order| {
            if (assignment[order.later] > 0 and assignment[order.earlier] > 0 and assignment[order.later] <= assignment[order.earlier]) return false;
        }
        return true;
    }
    pub fn candidateSlots(self: *const Scheduler, c: usize, assignment: []const usize) E.Indices {
        var result: E.Indices = .{};
        for (self.calendar.open.slice()) |slot| {
            if (!self.suitable(c, slot) or self.orderConflict(c, slot, assignment) != null) continue;
            var clash = false;
            for (self.graph.vertices.slice()) |other| { if (self.graph.shared[c][other] > 0 and assignment[other] == slot) clash = true; }
            if (clash) continue;
            var group = self.coursesAt(assignment, slot);
            group.add(c);
            if (M.pack(self.rooms, self.courses, group) != null) result.add(slot);
        }
        return result;
    }
    fn acceptClosed(self: *Scheduler, fields: R.Strings) ?[]const u8 {
        const slot = self.calendar.slotAt(fields[1], fields[2]) orelse return R.fmt("slot {s} {s} outside calendar", .{ fields[1], fields[2] });
        if (self.calendar.closed[slot]) return R.fmt("duplicate closed {s}", .{self.calendar.name(slot)});
        self.calendar.closed[slot] = true;
        return null;
    }
    fn acceptUnavailable(self: *Scheduler, fields: R.Strings) ?[]const u8 {
        const student = E.findStudent(self.students, fields[1]) orelse return R.fmt("unknown student {s}", .{fields[1]});
        const slot = self.calendar.slotAt(fields[2], fields[3]) orelse return R.fmt("slot {s} {s} outside calendar", .{ fields[2], fields[3] });
        if (self.students[student].unavailable[slot]) return R.fmt("duplicate unavailable {s} {s}", .{ fields[1], self.calendar.name(slot) });
        self.students[student].unavailable[slot] = true;
        return null;
    }
    fn acceptFixed(self: *Scheduler, fields: R.Strings) ?[]const u8 {
        const id = fields[1];
        const c = E.findCourse(self.courses, id) orelse return R.fmt("unknown course {s}", .{id});
        if (!self.isSchedulable(c)) return R.fmt("course {s} not schedulable", .{id});
        const slot = self.calendar.slotAt(fields[2], fields[3]) orelse return R.fmt("slot {s} {s} outside calendar", .{ fields[2], fields[3] });
        if (self.calendar.closed[slot]) return R.fmt("slot {s} closed", .{self.calendar.name(slot)});
        if (!self.suitable(c, slot)) return R.fmt("slot {s} unsuitable for {s}", .{ self.calendar.name(slot), id });
        if (self.fixed[c] > 0) return R.fmt("duplicate fixed {s}", .{id});
        var group = self.coursesAt(&self.fixed, slot);
        for (group.slice()) |other| { if (self.graph.shared[c][other] > 0) return R.fmt("conflict {s} {s}", .{ id, self.courses[other].id }); }
        group.add(c);
        if (M.pack(self.rooms, self.courses, group) == null) return R.fmt("rooms full {s}", .{self.calendar.name(slot)});
        self.fixed[c] = slot;
        return null;
    }
    fn acceptAfter(self: *Scheduler, fields: R.Strings) ?[]const u8 {
        const a = E.findCourse(self.courses, fields[1]) orelse return R.fmt("unknown course {s}", .{fields[1]});
        const b = E.findCourse(self.courses, fields[2]) orelse return R.fmt("unknown course {s}", .{fields[2]});
        if (!self.isSchedulable(a)) return R.fmt("course {s} not schedulable", .{fields[1]});
        if (!self.isSchedulable(b)) return R.fmt("course {s} not schedulable", .{fields[2]});
        if (a == b) return R.fmt("bad order {s} {s}", .{ fields[1], fields[2] });
        for (self.calendar.orders.items) |order| { if (order.later == a and order.earlier == b) return R.fmt("duplicate order {s} {s}", .{ fields[1], fields[2] }); }
        if (G.reachable(self.calendar.orders.items, b, a)) return R.fmt("cycle {s} {s}", .{ fields[1], fields[2] });
        if (self.fixed[a] > 0 and self.fixed[b] > 0 and self.fixed[a] <= self.fixed[b]) return R.fmt("fixed order {s} {s}", .{ fields[1], fields[2] });
        R.append(G.Order, &self.calendar.orders, .{ .later = a, .earlier = b });
        return null;
    }
    fn validateCalendar(self: *Scheduler, lines: R.Strings) void {
        for (lines[6..], 7..) |line, line_number| {
            const fields = R.split(line, ' ');
            const message = if (R.eq(fields[0], "closed")) self.acceptClosed(fields)
                else if (R.eq(fields[0], "unavailable")) self.acceptUnavailable(fields)
                else if (R.eq(fields[0], "fixed")) self.acceptFixed(fields)
                else self.acceptAfter(fields);
            if (message) |value| self.errors.add("calendar.txt line {d}: {s}", .{ line_number, value });
        }
        for (1..self.calendar.slots + 1) |slot| { if (!self.calendar.closed[slot]) self.calendar.open.add(slot); }
        for (self.fixed) |slot| { if (slot > 0) self.calendar.fixed_slots[slot] = true; }
    }
    fn buildTimetable(self: *Scheduler) void {
        while (true) {
            var pending: E.Indices = .{};
            for (self.schedulable.slice()) |c| { if (self.fixed[c] == 0 and !self.excluded[c]) pending.add(c); }
            self.assignment = self.fixed;
            var attempt: C.Attempt = .{ .pending = pending, .limit = self.calendar.limit };
            const success = attempt.search(self);
            R.append(AttemptRecord, &self.attempts, .{ .courses = pending.len, .dead_ends = attempt.dead_ends, .failed_course = if (success) null else attempt.dead_end_course });
            if (success) {
                self.choice_count = attempt.choice_count;
                @memcpy(self.choices[0..self.choice_count], attempt.choices[0..self.choice_count]);
                return;
            }
            self.excluded[attempt.dead_end_course.?] = true;
        }
    }
    fn breakdown(self: *const Scheduler, assignment: []const usize) Breakdown {
        var result: Breakdown = .{};
        for (self.graph.vertices.slice()) |a| {
            if (assignment[a] == 0) continue;
            for (self.graph.vertices.slice()) |b| {
                if (a >= b or assignment[b] == 0 or self.graph.shared[a][b] == 0) continue;
                if (self.calendar.relation(assignment[a], assignment[b])) |kind| result.counts[kind] += self.graph.shared[a][b];
            }
        }
        for (self.front_load.slice()) |c| { if (assignment[c] > self.calendar.deadline) result.late += 1; }
        result.total = result.late * self.calendar.weights[3];
        for (result.counts, self.calendar.weights[0..3]) |count, weight| result.total += count * weight;
        return result;
    }
    fn blockingReason(self: *const Scheduler, c: usize, slot: usize) []const u8 {
        if (self.calendar.closed[slot]) return "closed";
        if (self.calendar.length(slot) < self.courses[c].duration) return "too_short";
        if (self.blockedStudent(c, slot)) |student| return R.fmt("unavailable {s}", .{self.students[student].id});
        var clash: ?usize = null;
        for (self.graph.vertices.slice()) |other| {
            if (self.assignment[other] == slot and self.graph.shared[c][other] > 0 and (clash == null or self.graph.shared[c][other] > self.graph.shared[c][clash.?])) clash = other;
        }
        if (clash) |other| return R.fmt("conflict {s} shared {d}", .{ self.courses[other].id, self.graph.shared[c][other] });
        if (self.orderConflict(c, slot, &self.assignment)) |other| return R.fmt("order {s}", .{self.courses[other].id});
        return "rooms";
    }
    fn insertExcluded(self: *Scheduler) void {
        for (0..self.courses.len) |c| {
            if (!self.excluded[c]) continue;
            const candidates = self.candidateSlots(c, &self.assignment);
            if (candidates.len == 0) {
                for (1..self.calendar.slots + 1) |slot| self.reasons[c][slot] = self.blockingReason(c, slot);
                continue;
            }
            const before = self.breakdown(&self.assignment).total;
            var best_slot: usize = 0;
            var best_total: i64 = 0;
            for (candidates.slice()) |slot| {
                var trial = self.assignment;
                trial[c] = slot;
                const total = self.breakdown(&trial).total;
                if (best_slot == 0 or total < best_total) { best_slot = slot; best_total = total; }
            }
            self.assignment[c] = best_slot;
            R.append(Insertion, &self.insertions, .{ .course = c, .slot = best_slot, .increase = best_total - before });
        }
        self.initial = self.breakdown(&self.assignment);
        self.penalty = self.initial.total;
    }
    fn validTrial(self: *const Scheduler, trial: []const usize) bool {
        for (0..self.courses.len) |c| { if (trial[c] != self.assignment[c] and !self.suitable(c, trial[c])) return false; }
        return self.ordersSatisfied(trial);
    }
    fn exchangeSlots(self: *Scheduler) void {
        var round: usize = 0;
        var serial: usize = 0;
        while (true) {
            round += 1;
            var tally = [_]usize{0} ** 4;
            var pairs: usize = 0;
            var records: R.Lines = .{};
            for (self.calendar.open.slice(), 0..) |home, i| {
                for (self.calendar.open.slice()[i + 1 ..]) |target| {
                    pairs += 1;
                    if (self.calendar.fixed_slots[home] or self.calendar.fixed_slots[target]) { tally[0] += 1; continue; }
                    var trial = self.assignment;
                    for (&trial) |*slot| { if (slot.* == home) slot.* = target else if (slot.* == target) slot.* = home; }
                    if (!self.validTrial(&trial)) { tally[1] += 1; continue; }
                    const total = self.breakdown(&trial).total;
                    if (total >= self.penalty) { tally[2] += 1; continue; }
                    tally[3] += 1;
                    serial += 1;
                    records.add("EXCHANGE {d} {s} {s} penalty {d} -> {d}", .{ serial, self.calendar.name(home), self.calendar.name(target), self.penalty, total });
                    self.assignment = trial;
                    self.penalty = total;
                }
            }
            self.exchange_log.add("ROUND {d} pairs {d} fixed {d} invalid {d} worse {d} applied {d}", .{ round, pairs, tally[0], tally[1], tally[2], tally[3] });
            self.exchange_log.extend(records);
            if (tally[3] == 0) break;
        }
        self.exchanged = self.breakdown(&self.assignment);
    }
    fn swapChains(self: *Scheduler) void {
        var pass: usize = 0;
        var serial: usize = 0;
        while (true) {
            pass += 1;
            var tally = [_]usize{0} ** 5;
            var candidates: usize = 0;
            var records: R.Lines = .{};
            var movable: E.Indices = .{};
            for (0..self.courses.len) |c| { if (self.assignment[c] > 0 and self.fixed[c] == 0) movable.add(c); }
            for (movable.slice()) |c| {
                const home = self.assignment[c];
                for (self.calendar.open.slice()) |target| {
                    if (target == home) continue;
                    candidates += 1;
                    const chain = self.graph.kempeChain(&self.assignment, c, home, target);
                    var fixed = false;
                    for (chain.slice()) |member| { if (self.fixed[member] > 0) fixed = true; }
                    if (fixed) { tally[0] += 1; continue; }
                    var trial = self.assignment;
                    for (chain.slice()) |member| trial[member] = if (self.assignment[member] == home) target else home;
                    if (!self.validTrial(&trial)) { tally[1] += 1; continue; }
                    if (M.pack(self.rooms, self.courses, self.coursesAt(&trial, home)) == null or M.pack(self.rooms, self.courses, self.coursesAt(&trial, target)) == null) { tally[2] += 1; continue; }
                    const total = self.breakdown(&trial).total;
                    if (total >= self.penalty) { tally[3] += 1; continue; }
                    tally[4] += 1;
                    serial += 1;
                    records.add("SWAP {d} {s} {s} {s} chain {d} penalty {d} -> {d}", .{ serial, self.courses[c].id, self.calendar.name(home), self.calendar.name(target), chain.len, self.penalty, total });
                    for (chain.slice()) |member| records.add("  MOVE {s} {s} -> {s}", .{ self.courses[member].id, self.calendar.name(self.assignment[member]), self.calendar.name(trial[member]) });
                    self.assignment = trial;
                    self.penalty = total;
                    break;
                }
            }
            self.swap_log.add("PASS {d} candidates {d} fixed {d} invalid {d} rooms {d} worse {d} applied {d}", .{ pass, candidates, tally[0], tally[1], tally[2], tally[3], tally[4] });
            self.swap_log.extend(records);
            if (tally[4] == 0) break;
        }
        self.final = self.breakdown(&self.assignment);
    }
    fn assignRooms(self: *Scheduler) void {
        for (self.calendar.open.slice()) |slot| {
            self.packed[slot] = M.pack(self.rooms, self.courses, self.coursesAt(&self.assignment, slot)).?;
            for (self.packed[slot].slice()) |placement| self.placements[placement.course] = placement;
        }
    }
    fn computeStatistics(self: *Scheduler) void {
        for (self.graph.vertices.slice()) |a| {
            if (self.assignment[a] == 0) continue;
            for (self.graph.vertices.slice()) |b| {
                if (a >= b or self.assignment[b] == 0 or self.graph.shared[a][b] == 0) continue;
                if (self.calendar.relation(self.assignment[a], self.assignment[b])) |kind| {
                    const value = self.calendar.weights[kind] * self.graph.shared[a][b];
                    self.contributions[a] += value;
                    self.contributions[b] += value;
                }
            }
        }
        for (self.front_load.slice()) |c| { if (self.assignment[c] > self.calendar.deadline) self.contributions[c] += self.calendar.weights[3]; }
        for (self.students, self.statistics) |student, *stats| {
            for (student.courses.slice()) |c| {
                if (self.assignment[c] == 0) continue;
                var i = stats.assigned.len;
                stats.assigned.len += 1;
                while (i > 0 and self.assignment[stats.assigned.values[i - 1]] > self.assignment[c]) : (i -= 1) stats.assigned.values[i] = stats.assigned.values[i - 1];
                stats.assigned.values[i] = c;
            }
            for (stats.assigned.slice(), 0..) |a, i| {
                for (stats.assigned.slice()[i + 1 ..]) |b| {
                    if (self.calendar.relation(self.assignment[a], self.assignment[b])) |kind| stats.counts[kind] += 1;
                }
            }
            for (stats.counts, self.calendar.weights[0..3]) |count, weight| stats.total += count * weight;
        }
    }
    fn assignedCount(self: *const Scheduler) usize {
        var count: usize = 0;
        for (self.assignment) |slot| { if (slot > 0) count += 1; }
        return count;
    }
    fn unscheduled(self: *const Scheduler) E.Indices {
        var result: E.Indices = .{};
        for (self.courses, 0..) |course, c| { if (course.size() > 0 and self.assignment[c] == 0) result.add(c); }
        return result;
    }
    fn roomLoads(self: *const Scheduler, slot: usize) RoomLoads {
        var result: RoomLoads = .{};
        for (self.packed[slot].slice()) |placement| {
            result.exams[placement.room] += 1;
            result.students[placement.room] += self.courses[placement.course].size();
        }
        return result;
    }
    fn invigilators(self: *const Scheduler, slot: usize) i64 {
        const loads = self.roomLoads(slot);
        var total: i64 = 0;
        for (loads.students) |count| total += ceilDiv(count, self.calendar.ratio);
        return total;
    }
    fn slotStudents(self: *const Scheduler, slot: usize) i64 {
        var total: i64 = 0;
        for (self.packed[slot].slice()) |placement| total += self.courses[placement.course].size();
        return total;
    }
    fn timetableLines(self: *const Scheduler) R.Lines {
        var result: R.Lines = .{};
        result.add("TIMETABLE days {d} periods {d} open {d} courses {d} scheduled {d} unscheduled {d} empty {d}", .{ self.calendar.days, self.calendar.periods, self.calendar.open.len, self.courses.len, self.assignedCount(), self.unscheduled().len, self.empty.len });
        var cells: [6][]const u8 = undefined;
        for (1..self.calendar.periods + 1) |period| cells[period - 1] = R.fmt("P{d}", .{period});
        cells[self.calendar.periods] = "TOTAL";
        result.write(R.fixedWidth("DAY", cells[0 .. self.calendar.periods + 1], 4, 10));
        for (1..self.calendar.days + 1) |day| {
            var exams: usize = 0;
            var students: i64 = 0;
            for (1..self.calendar.periods + 1) |period| {
                const slot = (day - 1) * self.calendar.periods + period;
                if (self.calendar.closed[slot]) { cells[period - 1] = "closed"; continue; }
                const count = self.slotStudents(slot);
                cells[period - 1] = R.fmt("{d}/{d}", .{ self.packed[slot].len, count });
                exams += self.packed[slot].len;
                students += count;
            }
            cells[self.calendar.periods] = R.fmt("{d}/{d}", .{ exams, students });
            result.write(R.fixedWidth(R.fmt("D{d}", .{day}), cells[0 .. self.calendar.periods + 1], 4, 10));
        }
        var total_invigilators: i64 = 0;
        for (1..self.calendar.slots + 1) |slot| {
            if (self.calendar.closed[slot]) {
                result.add("SLOT {d} {s} minutes {d} closed", .{ slot, self.calendar.name(slot), self.calendar.length(slot) });
                continue;
            }
            const loads = self.roomLoads(slot);
            var used: usize = 0;
            var seats: i64 = 0;
            for (self.rooms, 0..) |room, r| {
                if (loads.exams[r] == 0) continue;
                used += 1;
                seats += room.capacity;
            }
            const supervisors = self.invigilators(slot);
            total_invigilators += supervisors;
            result.add("SLOT {d} {s} minutes {d} exams {d} students {d} rooms {d} seats {d} invigilators {d}", .{ slot, self.calendar.name(slot), self.calendar.length(slot), self.packed[slot].len, self.slotStudents(slot), used, seats, supervisors });
            for (self.packed[slot].slice()) |p| {
                const course = self.courses[p.course];
                result.add("  {s} {d}min students {d} room {s} seats {d}-{d}{s} {s}", .{ course.id, course.duration, course.size(), self.rooms[p.room].id, p.first, p.last, if (self.fixed[p.course] > 0) " fixed" else "", course.name });
            }
        }
        for (self.rooms, 0..) |room, r| {
            var slots: usize = 0;
            var exams: usize = 0;
            var seated: i64 = 0;
            for (self.calendar.open.slice()) |slot| {
                var used = false;
                for (self.packed[slot].slice()) |p| {
                    if (p.room != r) continue;
                    used = true;
                    exams += 1;
                    seated += self.courses[p.course].size();
                }
                if (used) slots += 1;
            }
            result.add("ROOM {s} capacity {d} slots {d} exams {d} seated {d} utilization {d}", .{ room.id, room.capacity, slots, exams, seated, R.roundedPercent(seated, room.capacity * R.n(self.calendar.open.len)) });
        }
        result.add("INVIGILATORS total {d} ratio {d}", .{ total_invigilators, self.calendar.ratio });
        return result;
    }
    fn roomLines(self: *const Scheduler) R.Lines {
        var result: R.Lines = .{};
        result.write("slot,room,course,students,first_seat,last_seat");
        for (self.calendar.open.slice()) |slot| {
            for (self.rooms, 0..) |room, r| {
                for (self.packed[slot].slice()) |p| {
                    if (p.room == r) result.add("{s},{s},{s},{d},{d},{d}", .{ self.calendar.name(slot), room.id, self.courses[p.course].id, self.courses[p.course].size(), p.first, p.last });
                }
            }
        }
        return result;
    }
    fn studentStatistics(self: *const Scheduler, result: *R.Lines) void {
        var histogram: std.AutoHashMapUnmanaged(i64, usize) = .empty;
        var gaps = [_]usize{0} ** 36;
        var day_loads = [_]usize{0} ** 13;
        const ranking = R.alloc(usize, self.students.len);
        for (self.statistics, 0..) |stats, student| {
            histogram.put(R.allocator, stats.total, (histogram.get(stats.total) orelse 0) + 1) catch @panic("allocation failed");
            ranking[student] = student;
            var daily = [_]usize{0} ** 8;
            var maximum: usize = 0;
            for (stats.assigned.slice(), 0..) |c, i| {
                const slot = self.assignment[c];
                const day = self.calendar.day(slot);
                daily[day] += 1;
                maximum = @max(maximum, daily[day]);
                if (i > 0) gaps[slot - self.assignment[stats.assigned.values[i - 1]]] += 1;
            }
            if (maximum > 0) day_loads[maximum] += 1;
        }
        const keys = R.alloc(i64, histogram.count());
        var iterator = histogram.keyIterator();
        var position: usize = 0;
        while (iterator.next()) |key| { keys[position] = key.*; position += 1; }
        std.mem.sort(i64, keys, {}, std.sort.asc(i64));
        for (keys) |key| result.add("HISTOGRAM {d} {d}", .{ key, histogram.get(key).? });
        for (gaps, 0..) |count, gap| { if (count > 0) result.add("GAP {d} {d}", .{ gap, count }); }
        for (day_loads, 0..) |count, load| { if (count > 0) result.add("DAYLOAD {d} {d}", .{ load, count }); }
        std.mem.sort(usize, ranking, self.statistics, studentPenaltyLess);
        for (ranking[0..@min(5, ranking.len)]) |student| {
            const stats = self.statistics[student];
            if (stats.total > 0) result.add("WORST {s} penalty {d} back_to_back {d} same_day {d} overnight {d}", .{ self.students[student].id, stats.total, stats.counts[0], stats.counts[1], stats.counts[2] });
        }
    }
    fn penaltyLines(self: *const Scheduler) R.Lines {
        var result: R.Lines = .{};
        result.add("WEIGHTS back_to_back {d} same_day {d} overnight {d} front_load {d}", .{ self.calendar.weights[0], self.calendar.weights[1], self.calendar.weights[2], self.calendar.weights[3] });
        result.add("FRONT_LOAD courses {d} last_slot {s}", .{ self.front_load.len, self.calendar.name(self.calendar.deadline) });
        result.add("INITIAL {s}", .{self.initial.text()});
        result.extend(self.exchange_log);
        result.add("EXCHANGED {s}", .{self.exchanged.text()});
        result.extend(self.swap_log);
        result.add("FINAL {s}", .{self.final.text()});
        result.add("SAVED {d}", .{self.initial.total - self.final.total});
        var daily = [_][3]i64{[_]i64{0} ** 3} ** 8;
        for (self.graph.vertices.slice()) |a| {
            if (self.assignment[a] == 0) continue;
            for (self.graph.vertices.slice()) |b| {
                if (a >= b or self.assignment[b] == 0 or self.graph.shared[a][b] == 0) continue;
                if (self.calendar.relation(self.assignment[a], self.assignment[b])) |kind| daily[self.calendar.day(@min(self.assignment[a], self.assignment[b]))][kind] += self.graph.shared[a][b];
            }
        }
        for (1..self.calendar.days + 1) |day| result.add("DAY D{d} back_to_back {d} same_day {d} overnight {d}", .{ day, daily[day][0], daily[day][1], daily[day][2] });
        for (self.front_load.slice()) |c| {
            if (self.assignment[c] > self.calendar.deadline) result.add("LATE {s} {s} students {d}", .{ self.courses[c].id, self.calendar.name(self.assignment[c]), self.courses[c].size() });
        }
        var assigned: E.Indices = .{};
        for (0..self.courses.len) |c| { if (self.assignment[c] > 0) assigned.add(c); }
        const ranked = E.ordered(self.courses, assigned, &self.contributions);
        for (ranked.slice()[0..@min(10, ranked.len)]) |c| {
            if (self.contributions[c] > 0) result.add("COURSE {s} {s} penalty {d}", .{ self.courses[c].id, self.calendar.name(self.assignment[c]), self.contributions[c] });
        }
        self.studentStatistics(&result);
        return result;
    }
    fn scheduleLines(self: *const Scheduler, queries: R.Strings) R.Lines {
        const classes = [_][]const u8{ "BACK_TO_BACK", "SAME_DAY", "OVERNIGHT" };
        var result: R.Lines = .{};
        for (queries) |query| {
            const student = E.findStudent(self.students, query) orelse { result.add("STUDENT {s} not found", .{query}); continue; };
            const record = self.students[student];
            const stats = self.statistics[student];
            result.add("STUDENT {s} exams {d} scheduled {d} penalty {d}", .{ query, record.courses.len, stats.assigned.len, stats.total });
            for (stats.assigned.slice()) |c| {
                const course = self.courses[c];
                const placement = self.placements[c];
                var offset: usize = 0;
                while (course.students.items[offset] != student) : (offset += 1) {}
                result.add("  {s} {s} room {s} seat {d} {s}", .{ self.calendar.name(self.assignment[c]), course.id, self.rooms[placement.room].id, placement.first + R.n(offset), course.name });
            }
            for (record.courses.slice()) |c| { if (self.assignment[c] == 0) result.add("  UNSCHEDULED {s} {s}", .{ self.courses[c].id, self.courses[c].name }); }
            for (stats.assigned.slice(), 0..) |a, i| {
                for (stats.assigned.slice()[i + 1 ..]) |b| {
                    if (self.calendar.relation(self.assignment[a], self.assignment[b])) |kind| result.add("  {s} {s} {s} {s} {s}", .{ classes[kind], self.calendar.name(self.assignment[a]), self.courses[a].id, self.calendar.name(self.assignment[b]), self.courses[b].id });
                }
            }
            for (1..self.calendar.slots + 1) |slot| { if (record.unavailable[slot]) result.add("  UNAVAILABLE {s}", .{self.calendar.name(slot)}); }
        }
        return result;
    }
    fn statusLines(self: *const Scheduler) R.Lines {
        var result: R.Lines = .{};
        result.write("course,status,slot,students,minutes,degree,penalty");
        for (self.courses, 0..) |course, c| {
            const status = if (self.fixed[c] > 0) "fixed" else if (self.assignment[c] > 0) "scheduled" else if (course.size() > self.largest_room) "too_large" else if (course.size() == 0) "empty" else "no_slot";
            result.add("{s},{s},{s},{d},{d},{d},{d}", .{ course.id, status, if (self.assignment[c] > 0) self.calendar.name(self.assignment[c]) else "-", course.size(), course.duration, self.graph.degrees[c], self.contributions[c] });
        }
        return result;
    }
    fn reportLines(self: *const Scheduler) R.Lines {
        var result: R.Lines = .{};
        var enrolments: usize = 0;
        for (self.students) |student| enrolments += student.courses.len;
        result.add("INPUT courses {d} enrolments {d} rooms {d} students {d} errors {d}", .{ self.courses.len, enrolments, self.rooms.len, self.students.len, self.errors.data.items.len });
        for (self.errors.data.items) |error_line| result.add("ERROR {s}", .{error_line});
        var edges: i64 = 0;
        var shared: i64 = 0;
        for (self.graph.vertices.slice()) |a| {
            for (self.graph.vertices.slice()) |b| {
                if (a >= b or self.graph.shared[a][b] == 0) continue;
                edges += 1;
                shared += self.graph.shared[a][b];
            }
        }
        const vertices = R.n(self.graph.vertices.len);
        const density = if (vertices >= 2) @divFloor(2000 * edges, vertices * (vertices - 1)) else 0;
        result.add("GRAPH courses {d} edges {d} shared {d} density {d}", .{ vertices, edges, shared, density });
        const degree_order = E.ordered(self.courses, self.graph.vertices, &self.graph.degrees);
        for (degree_order.slice()[0..@min(5, degree_order.len)]) |c| {
            var total: i64 = 0;
            for (self.graph.shared[c]) |value| total += value;
            result.add("DEGREE {s} neighbours {d} shared {d} students {d}", .{ self.courses[c].id, self.graph.degrees[c], total, self.courses[c].size() });
        }
        const groups = self.graph.components();
        result.add("COMPONENTS {d}", .{groups.len});
        for (groups.values[0..groups.len], 1..) |group, i| result.add("COMPONENT {d} size {d} first {s}", .{ i, group.len, self.courses[group.values[0]].id });
        const clique = self.graph.clique(self.schedulable);
        var clique_text: R.Text = .{};
        clique_text.add("CLIQUE size {d}", .{clique.len});
        for (clique.slice()) |c| clique_text.add(" {s}", .{self.courses[c].id});
        result.write(clique_text.value());
        var most: usize = 0;
        var attaining: usize = 0;
        for (self.students) |student| {
            if (student.courses.len > most) { most = student.courses.len; attaining = 0; }
            if (student.courses.len == most) attaining += 1;
        }
        var demand: i64 = 0;
        var capacity: i64 = 0;
        for (self.schedulable.slice()) |c| demand += self.courses[c].size();
        for (self.rooms) |room| capacity += room.capacity;
        result.add("LOAD max_exams {d} students {d}", .{ most, attaining });
        result.add("SEATS demand {d} capacity {d} min_slots {d}", .{ demand, capacity, ceilDiv(demand, capacity) });
        result.add("HEURISTIC largest_degree slots {d}", .{C.greedyNumbering(&self.graph, E.ordered(self.courses, self.schedulable, &self.graph.degrees))});
        result.add("HEURISTIC largest_enrolment slots {d}", .{C.greedyNumbering(&self.graph, E.ordered(self.courses, self.schedulable, null))});
        var table = E.ordered(self.courses, self.graph.vertices, null);
        table.len = @min(8, table.len);
        var cells: [8][]const u8 = undefined;
        for (table.slice(), 0..) |c, i| cells[i] = self.courses[c].id;
        result.write(R.fixedWidth("MATRIX", cells[0..table.len], 9, 9));
        for (table.slice()) |row| {
            for (table.slice(), 0..) |column, i| cells[i] = if (row == column) "-" else R.fmt("{d}", .{self.graph.shared[row][column]});
            result.write(R.fixedWidth(self.courses[row].id, cells[0..table.len], 9, 9));
        }
        for (self.empty.slice()) |c| result.add("EMPTY {s}", .{self.courses[c].id});
        for (self.oversized.slice()) |c| result.add("TOO_LARGE {s} students {d} largest_room {d}", .{ self.courses[c].id, self.courses[c].size(), self.largest_room });
        for (1..self.calendar.slots + 1) |slot| { if (self.calendar.closed[slot]) result.add("CLOSED {s}", .{self.calendar.name(slot)}); }
        for (0..self.courses.len) |c| { if (self.fixed[c] > 0) result.add("FIXED {s} {s}", .{ self.courses[c].id, self.calendar.name(self.fixed[c]) }); }
        for (self.calendar.orders.items) |order| result.add("AFTER {s} {s}", .{ self.courses[order.later].id, self.courses[order.earlier].id });
        for (self.attempts.items, 1..) |attempt, i| {
            const outcome = if (attempt.failed_course) |c| R.fmt("failed {s}", .{self.courses[c].id}) else "success";
            result.add("ATTEMPT {d} courses {d} backtracks {d} {s}", .{ i, attempt.courses, attempt.dead_ends, outcome });
        }
        for (self.choices[0..self.choice_count], 1..) |choice, i| result.add("ORDER {d} {s} {s} saturation {d} degree {d}", .{ i, self.courses[choice.course].id, self.calendar.name(choice.slot), choice.saturation, self.graph.degrees[choice.course] });
        for (self.insertions.items) |insertion| result.add("INSERTED {s} {s} penalty {d}", .{ self.courses[insertion.course].id, self.calendar.name(insertion.slot), insertion.increase });
        const missing = self.unscheduled();
        for (missing.slice()) |c| {
            result.add("UNSCHEDULED {s} reason {s} students {d}", .{ self.courses[c].id, if (self.courses[c].size() > self.largest_room) "too_large" else "no_slot", self.courses[c].size() });
            for (1..self.calendar.slots + 1) |slot| { if (self.reasons[c][slot]) |reason| result.add("  {s} {s}", .{ self.calendar.name(slot), reason }); }
        }
        var used: usize = 0;
        for (self.calendar.open.slice()) |slot| { if (self.packed[slot].len > 0) used += 1; }
        result.add("SUMMARY scheduled {d} unscheduled {d} slots_used {d} penalty {d}", .{ self.assignedCount(), missing.len, used, self.penalty });
        return result;
    }
    fn run(self: *Scheduler, io: std.Io, queries: R.Strings) !void {
        self.buildTimetable();
        self.insertExcluded();
        self.exchangeSlots();
        self.swapChains();
        self.assignRooms();
        self.computeStatistics();
        try R.writeFiles(io, &.{
            .{ .name = "timetable.txt", .lines = self.timetableLines() },
            .{ .name = "rooms.csv", .lines = self.roomLines() },
            .{ .name = "penalties.txt", .lines = self.penaltyLines() },
            .{ .name = "student_schedules.txt", .lines = self.scheduleLines(queries) },
            .{ .name = "course_status.csv", .lines = self.statusLines() },
            .{ .name = "report.txt", .lines = self.reportLines() },
        });
    }
};
fn studentPenaltyLess(statistics: []StudentStats, a: usize, b: usize) bool { return if (statistics[a].total == statistics[b].total) a < b else statistics[a].total > statistics[b].total; }
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    R.allocator = arena.allocator();
    const directory = std.Io.Dir.cwd();
    const courses_text = try directory.readFileAlloc(init.io, "input/courses.csv", R.allocator, .unlimited);
    const enrolments_text = try directory.readFileAlloc(init.io, "input/enrolments.csv", R.allocator, .unlimited);
    const rooms_text = try directory.readFileAlloc(init.io, "input/rooms.csv", R.allocator, .unlimited);
    const calendar_text = try directory.readFileAlloc(init.io, "input/calendar.txt", R.allocator, .unlimited);
    const queries_text = try directory.readFileAlloc(init.io, "input/queries.txt", R.allocator, .unlimited);
    var errors: R.Lines = .{};
    const courses = E.loadCourses(courses_text, &errors);
    const students = E.loadEnrolments(enrolments_text, courses, &errors);
    const rooms = M.loadRooms(rooms_text, &errors);
    const scheduler = try R.allocator.create(Scheduler);
    scheduler.* = Scheduler.init(courses, students, rooms, R.lines(calendar_text), errors);
    try scheduler.run(init.io, R.lines(queries_text));
}
