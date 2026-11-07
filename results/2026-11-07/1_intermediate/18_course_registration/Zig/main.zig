const std = @import("std");
const Allocator = std.mem.Allocator;
const Error = error{BadCommand} || Allocator.Error || std.Io.Writer.Error;
const ParseError = error{InvalidPrereq} || Allocator.Error;
const days = [_][]const u8{ "MO", "TU", "WE", "TH", "FR", "SA", "SU" };
const Command = enum { COURSE, STUDENT, ENROLL, CHECK, OPTIONS, DROP, SWAP, CLOSE, OPEN, CAPACITY, LIMIT, PREREQ, CANCEL, ROSTER, SCHEDULE, FREE, INFO, AUDIT, HISTORY, STUDENTS, REPORT };
fn integer(s: []const u8) i64 {
    return std.fmt.parseInt(i64, s, 10) catch unreachable;
}
fn equal(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
fn dayIndex(name: []const u8) ?usize {
    for (days, 0..) |day, i| if (equal(name, day)) return i;
    return null;
}
const Node = union(enum) {
    word: []const u8,
    all: []const *Node,
    any: []const *Node,
    fn contains(node: *const Node, code: []const u8) bool {
        switch (node.*) {
            .word => |word| return equal(word, code),
            .all, .any => |children| {
                for (children) |child| if (child.contains(code)) return true;
                return false;
            },
        }
    }
    fn satisfied(node: *const Node, s: *const Student) bool {
        switch (node.*) {
            .word => |word| return if (word.len == 2) s.year >= integer(word[1..]) else s.passed(word) != null,
            .all => |children| {
                for (children) |child| if (!child.satisfied(s)) return false;
                return true;
            },
            .any => |children| {
                for (children) |child| if (child.satisfied(s)) return true;
                return false;
            },
        }
    }
    fn write(node: *const Node, out: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (node.*) {
            .word => |word| try out.writeAll(word),
            .all, .any => |children| {
                const conjunction = node.* == .all;
                for (children, 0..) |child, i| {
                    if (i > 0) try out.writeAll(if (conjunction) "&" else "|");
                    const parens = conjunction and child.* == .any;
                    if (parens) try out.writeAll("(");
                    try child.write(out);
                    if (parens) try out.writeAll(")");
                }
            },
        }
    }
};
const Parser = struct {
    gpa: Allocator,
    text: []const u8,
    position: usize = 0,
    fn factor(self: *Parser) ParseError!*Node {
        if (self.position == self.text.len) return error.InvalidPrereq;
        if (self.text[self.position] == '(') {
            self.position += 1;
            const node = try self.expression();
            if (self.position == self.text.len or self.text[self.position] != ')') return error.InvalidPrereq;
            self.position += 1;
            return node;
        }
        const start = self.position;
        while (self.position < self.text.len and std.ascii.isAlphanumeric(self.text[self.position])) self.position += 1;
        const word = self.text[start..self.position];
        var letters: usize = 0;
        while (letters < word.len and std.ascii.isUpper(word[letters])) letters += 1;
        var course = letters >= 2 and letters <= 4 and word.len == letters + 3;
        if (course) for (word[letters..]) |ch| {
            if (!std.ascii.isDigit(ch)) course = false;
        };
        const year = word.len == 2 and word[0] == 'Y' and word[1] >= '1' and word[1] <= '9';
        if (!course and !year) return error.InvalidPrereq;
        const node = try self.gpa.create(Node);
        node.* = .{ .word = word };
        return node;
    }
    fn append(self: *Parser, children: *std.ArrayList(*Node), child: *Node, conjunction: bool) Allocator.Error!void {
        if (conjunction and child.* == .all) {
            try children.appendSlice(self.gpa, child.all);
        } else if (!conjunction and child.* == .any) {
            try children.appendSlice(self.gpa, child.any);
        } else try children.append(self.gpa, child);
    }
    fn group(self: *Parser, conjunction: bool) ParseError!*Node {
        var children: std.ArrayList(*Node) = .empty;
        try self.append(&children, if (conjunction) try self.factor() else try self.term(), conjunction);
        const separator: u8 = if (conjunction) '&' else '|';
        while (self.position < self.text.len and self.text[self.position] == separator) {
            self.position += 1;
            try self.append(&children, if (conjunction) try self.factor() else try self.term(), conjunction);
        }
        if (children.items.len == 1) return children.items[0];
        const node = try self.gpa.create(Node);
        node.* = if (conjunction) .{ .all = children.items } else .{ .any = children.items };
        return node;
    }
    fn term(self: *Parser) ParseError!*Node {
        return self.group(true);
    }
    fn expression(self: *Parser) ParseError!*Node {
        return self.group(false);
    }
};
const Prerequisite = struct {
    root: ?*Node = null,
    text: []const u8 = "-",
    fn met(p: Prerequisite, s: *const Student) bool {
        return if (p.root) |root| root.satisfied(s) else true;
    }
    fn contains(p: Prerequisite, code: []const u8) bool {
        return if (p.root) |root| root.contains(code) else false;
    }
};
const Slot = struct {
    text: []const u8,
    day: usize,
    start: usize,
    end: usize,
    fn overlaps(a: Slot, b: Slot) bool {
        return a.day == b.day and a.start < b.end and b.start < a.end;
    }
    fn less(_: void, a: Slot, b: Slot) bool {
        return if (a.day != b.day) a.day < b.day else a.start < b.start;
    }
};
const Grade = struct { code: []const u8, grade: u8, credits: i64 };
const History = struct { command: usize, event: []const u8 };
const Student = struct {
    name: []const u8,
    year: i64,
    limit: i64,
    grades: []const Grade,
    courses: std.ArrayList(*Course) = .empty,
    history: std.ArrayList(History) = .empty,
    fn passed(s: *const Student, code: []const u8) ?u8 {
        for (s.grades) |r| if (equal(r.code, code) and r.grade <= 'C') return r.grade;
        return null;
    }
    fn credits(s: *const Student, excluded: ?*Course) i64 {
        var total: i64 = 0;
        for (s.courses.items) |c| if (c != excluded) {
            total += c.credits;
        };
        return total;
    }
    fn earned(s: *const Student) i64 {
        var total: i64 = 0;
        for (s.grades) |r| if (r.grade != 'F') {
            total += r.credits;
        };
        return total;
    }
};
const Course = struct {
    name: []const u8,
    credits: i64,
    capacity: usize,
    slots: []const Slot,
    prereq: Prerequisite,
    open: bool = true,
    enrolled: std.ArrayList(*Student) = .empty,
    waiting: std.ArrayList(*Student) = .empty,
    fn weekly(c: *const Course) usize {
        var total: usize = 0;
        for (c.slots) |slot| total += slot.end - slot.start;
        return total;
    }
    fn conflicts(a: *const Course, b: *const Course) bool {
        for (a.slots) |left| for (b.slots) |right| {
            if (left.overlaps(right)) return true;
        };
        return false;
    }
    fn position(c: *const Course, s: *Student) usize {
        var index: usize = 0;
        while (index < c.waiting.items.len and c.waiting.items[index].year >= s.year) index += 1;
        return index;
    }
};
const Judgment = struct { action: enum { reason, ok, enroll, waitlist } = .reason, word: []const u8 = "", extra: []const u8 = "", position: usize = 0 };
fn remove(comptime T: type, list: *std.ArrayList(*T), value: *T) void {
    _ = list.orderedRemove(std.mem.findScalar(*T, list.items, value).?);
}
const Registration = struct {
    gpa: Allocator,
    out: *std.Io.Writer,
    error_message: []const u8 = "",
    command: usize = 0,
    courses: std.StringArrayHashMapUnmanaged(*Course) = .empty,
    students: std.StringArrayHashMapUnmanaged(*Student) = .empty,
    fn fail(self: *Registration, comptime fmt: []const u8, args: anytype) Error {
        self.error_message = std.fmt.allocPrint(self.gpa, fmt, args) catch return error.OutOfMemory;
        return error.BadCommand;
    }
    fn clock(self: *Registration, minutes: usize) Allocator.Error![]const u8 {
        return std.fmt.allocPrint(self.gpa, "{d:0>2}:{d:0>2}", .{ minutes / 60, minutes % 60 });
    }
    fn gpaText(self: *Registration, s: *Student) Allocator.Error![]const u8 {
        if (s.grades.len == 0) return "n/a";
        var points: i64 = 0;
        var credits: i64 = 0;
        for (s.grades) |r| {
            credits += r.credits;
            const p: i64 = if (r.grade == 'F') 0 else 'E' - @as(i64, r.grade);
            points += p * r.credits;
        }
        const value: u64 = @intCast(@divTrunc(200 * points + credits, 2 * credits));
        return std.fmt.allocPrint(self.gpa, "{d}.{d:0>2}", .{ value / 100, value % 100 });
    }
    fn rate(self: *Registration, enrolled: usize, capacity: usize) Allocator.Error![]const u8 {
        return if (capacity == 0) "n/a" else std.fmt.allocPrint(self.gpa, "{d}%", .{enrolled * 100 / capacity});
    }
    fn ordered(self: *Registration, comptime T: type, values: []const *T) Allocator.Error![]*T {
        const result = try self.gpa.dupe(*T, values);
        std.mem.sort(*T, result, {}, struct {
            fn less(_: void, a: *T, b: *T) bool {
                return std.mem.order(u8, a.name, b.name) == .lt;
            }
        }.less);
        return result;
    }
    fn student(self: *Registration, name: []const u8) Error!*Student {
        return self.students.get(name) orelse return self.fail("unknown student {s}", .{name});
    }
    fn course(self: *Registration, name: []const u8) Error!*Course {
        return self.courses.get(name) orelse return self.fail("unknown course {s}", .{name});
    }
    fn prerequisite(self: *Registration, name: []const u8, text: []const u8) Error!Prerequisite {
        if (equal(text, "-")) return .{};
        var parser = Parser{ .gpa = self.gpa, .text = text };
        const node = parser.expression() catch |err| {
            if (err == error.InvalidPrereq) return self.fail("invalid prereq {s}", .{name});
            return err;
        };
        if (parser.position != text.len) return self.fail("invalid prereq {s}", .{name});
        if (node.contains(name)) return self.fail("self prereq {s}", .{name});
        var out: std.Io.Writer.Allocating = .init(self.gpa);
        try node.write(&out.writer);
        return .{ .root = node, .text = out.writer.buffered() };
    }
    fn slots(self: *Registration, token: []const u8) Error![]const Slot {
        var result: std.ArrayList(Slot) = .empty;
        if (equal(token, "-")) return result.items;
        var it = std.mem.splitScalar(u8, token, ',');
        while (it.next()) |part| {
            const day = dayIndex(part[0..2]) orelse return self.fail("invalid slot {s}", .{part});
            const h1 = integer(part[2..4]);
            const m1 = integer(part[4..6]);
            const h2 = integer(part[7..9]);
            const m2 = integer(part[9..11]);
            if (h1 > 23 or h2 > 23 or m1 > 59 or m2 > 59 or h1 * 60 + m1 >= h2 * 60 + m2) return self.fail("invalid slot {s}", .{part});
            try result.append(self.gpa, .{ .text = part, .day = day, .start = @intCast(h1 * 60 + m1), .end = @intCast(h2 * 60 + m2) });
        }
        for (result.items, 0..) |left, i| for (result.items[i + 1 ..]) |right| {
            if (left.overlaps(right)) return self.fail("overlapping slots {s} {s}", .{ left.text, right.text });
        };
        return result.items;
    }
    fn grades(self: *Registration, name: []const u8, token: []const u8) Error![]const Grade {
        var result: std.ArrayList(Grade) = .empty;
        if (equal(token, "-")) return result.items;
        var it = std.mem.splitScalar(u8, token, ',');
        while (it.next()) |part| {
            const colon = std.mem.findScalar(u8, part, ':').?;
            const code = part[0..colon];
            const grade = part[colon + 1];
            if (std.mem.findScalar(u8, "ABCDF", grade) == null) return self.fail("invalid grade {s} {s} {c}", .{ name, code, grade });
            for (result.items) |r| if (equal(r.code, code)) {
                return self.fail("duplicate record {s} {s}", .{ name, code });
            };
            try result.append(self.gpa, .{ .code = code, .grade = grade, .credits = integer(part[colon + 3 ..]) });
        }
        std.mem.sort(Grade, result.items, {}, struct {
            fn less(_: void, a: Grade, b: Grade) bool {
                return std.mem.order(u8, a.code, b.code) == .lt;
            }
        }.less);
        return result.items;
    }
    fn waitCount(self: *Registration, s: *Student) usize {
        var count: usize = 0;
        for (self.courses.values()) |c| if (std.mem.findScalar(*Student, c.waiting.items, s) != null) {
            count += 1;
        };
        return count;
    }
    fn conflict(s: *Student, c: *Course, excluded: ?*Course) ?*Course {
        var first: ?*Course = null;
        for (s.courses.items) |other| {
            if (other == excluded or !c.conflicts(other)) continue;
            if (first == null or std.mem.order(u8, other.name, first.?.name) == .lt) first = other;
        }
        return first;
    }
    fn eligible(self: *Registration, s: *Student, c: *Course, excluded: ?*Course) Allocator.Error!Judgment {
        if (!c.open) return .{ .word = "course closed" };
        if (std.mem.findScalar(*Student, c.enrolled.items, s) != null) return .{ .word = "already enrolled" };
        if (std.mem.findScalar(*Student, c.waiting.items, s) != null) return .{ .word = "already waitlisted" };
        if (s.passed(c.name)) |grade| return .{ .word = "already completed", .extra = try std.fmt.allocPrint(self.gpa, "{c}", .{grade}) };
        if (!c.prereq.met(s)) return .{ .word = "prereq not met" };
        if (conflict(s, c, excluded)) |other| return .{ .word = "time conflict", .extra = other.name };
        const credits = s.credits(excluded) + c.credits;
        if (credits > s.limit) return .{ .word = "credit limit", .extra = try std.fmt.allocPrint(self.gpa, "{d} {d}", .{ credits, s.limit }) };
        return .{ .action = .ok };
    }
    fn judge(self: *Registration, s: *Student, c: *Course) Allocator.Error!Judgment {
        const result = try self.eligible(s, c, null);
        if (result.action == .reason) return result;
        if (c.enrolled.items.len < c.capacity) return .{ .action = .enroll };
        if (self.waitCount(s) >= 3) return .{ .word = "waitlist limit" };
        return .{ .action = .waitlist, .position = c.position(s) + 1 };
    }
    fn judgmentText(self: *Registration, result: Judgment) Allocator.Error![]const u8 {
        return switch (result.action) {
            .ok => "OK",
            .enroll => "enroll",
            .waitlist => std.fmt.allocPrint(self.gpa, "waitlist {d}", .{result.position}),
            .reason => if (result.extra.len == 0) result.word else std.fmt.allocPrint(self.gpa, "{s} {s}", .{ result.word, result.extra }),
        };
    }
    fn reject(self: *Registration, result: Judgment, s: *Student, c: *Course) Error {
        return self.fail("{s} {s} {s}{s}{s}", .{ result.word, s.name, c.name, if (result.extra.len == 0) "" else " ", result.extra });
    }
    fn history(self: *Registration, s: *Student, comptime fmt: []const u8, args: anytype) Error!void {
        try s.history.append(self.gpa, .{ .command = self.command, .event = try std.fmt.allocPrint(self.gpa, fmt, args) });
    }
    fn enroll(self: *Registration, s: *Student, c: *Course) Error!void {
        try s.courses.append(self.gpa, c);
        try c.enrolled.append(self.gpa, s);
    }
    fn enrollmentLine(self: *Registration, label: []const u8, s: *Student, c: *Course) Error!void {
        try self.out.print("{s} {s} {s} enrolled {d}/{d} credits {d}/{d}\n", .{ label, s.name, c.name, c.enrolled.items.len, c.capacity, s.credits(null), s.limit });
    }
    fn promote(self: *Registration) Error!void {
        for (try self.ordered(Course, self.courses.values())) |c| {
            if (!c.open) continue;
            while (c.enrolled.items.len < c.capacity) {
                var selected: ?usize = null;
                for (c.waiting.items, 0..) |s, i| {
                    if (conflict(s, c, null) == null and s.credits(null) + c.credits <= s.limit) {
                        selected = i;
                        break;
                    }
                }
                const s = c.waiting.orderedRemove(selected orelse break);
                try self.enroll(s, c);
                try self.history(s, "promote {s}", .{c.name});
                try self.enrollmentLine("  PROMOTE", s, c);
            }
        }
    }
    fn schedule(self: *Registration, s: *Student) Error!void {
        const Meeting = struct { slot: Slot, code: []const u8 };
        var meetings: std.ArrayList(Meeting) = .empty;
        var weekly: usize = 0;
        const courses = try self.ordered(Course, s.courses.items);
        for (courses) |c| {
            weekly += c.weekly();
            for (c.slots) |slot| try meetings.append(self.gpa, .{ .slot = slot, .code = c.name });
        }
        std.mem.sort(Meeting, meetings.items, {}, struct {
            fn less(_: void, a: Meeting, b: Meeting) bool {
                return Slot.less({}, a.slot, b.slot);
            }
        }.less);
        try self.out.print("SCHEDULE {s} courses {d} credits {d} weekly {s}\n", .{ s.name, s.courses.items.len, s.credits(null), try self.clock(weekly) });
        for (days, 0..) |day, i| {
            var found = false;
            for (meetings.items) |m| {
                if (m.slot.day != i) continue;
                if (!found) try self.out.print("  {s}", .{day});
                found = true;
                try self.out.print(" {s}-{s} {s}", .{ try self.clock(m.slot.start), try self.clock(m.slot.end), m.code });
            }
            if (found) try self.out.writeAll("\n");
        }
        var tba = false;
        for (courses) |c| {
            if (c.slots.len > 0) continue;
            if (!tba) try self.out.writeAll("  TBA");
            tba = true;
            try self.out.print(" {s}", .{c.name});
        }
        if (tba) try self.out.writeAll("\n");
    }
    fn freeTime(self: *Registration, s: *Student, token: []const u8) Error!void {
        const day = dayIndex(token) orelse return self.fail("invalid day {s}", .{token});
        var free: [840]bool = @splat(true);
        for (s.courses.items) |c| for (c.slots) |slot| {
            if (slot.day == day and slot.end > 480 and slot.start < 1320) @memset(free[@max(slot.start, 480) - 480 .. @min(slot.end, 1320) - 480], false);
        };
        var total: usize = 0;
        for (free) |available| if (available) {
            total += 1;
        };
        try self.out.print("FREE {s} {s} total {s}", .{ s.name, token, try self.clock(total) });
        var i: usize = 0;
        while (i < free.len) {
            if (!free[i]) {
                i += 1;
                continue;
            }
            const start = i;
            while (i < free.len and free[i]) i += 1;
            try self.out.print(" {s}-{s}", .{ try self.clock(start + 480), try self.clock(i + 480) });
        }
        try self.out.writeAll("\n");
    }
    fn report(self: *Registration) Error!void {
        const Department = struct { name: []const u8, courses: usize = 0, enrolled: usize = 0, capacity: usize = 0, waiting: usize = 0 };
        var departments: std.StringArrayHashMapUnmanaged(Department) = .empty;
        var total = Department{ .name = "" };
        const courses = try self.ordered(Course, self.courses.values());
        for (courses) |c| {
            const name = c.name[0 .. c.name.len - 3];
            const entry = try departments.getOrPut(self.gpa, name);
            if (!entry.found_existing) entry.value_ptr.* = .{ .name = name };
            const d = entry.value_ptr;
            d.courses += 1;
            d.enrolled += c.enrolled.items.len;
            d.capacity += c.capacity;
            d.waiting += c.waiting.items.len;
            total.enrolled += c.enrolled.items.len;
            total.capacity += c.capacity;
            total.waiting += c.waiting.items.len;
        }
        try self.out.print("REPORT courses {d} enrolled {d}/{d} rate {s} waitlisted {d}\n", .{ courses.len, total.enrolled, total.capacity, try self.rate(total.enrolled, total.capacity), total.waiting });
        for (courses) |c| try self.out.print("  {s} {s} {d}/{d} {s} waitlist {d}\n", .{ c.name, if (c.open) "open" else "closed", c.enrolled.items.len, c.capacity, try self.rate(c.enrolled.items.len, c.capacity), c.waiting.items.len });
        const ordered_departments = try self.gpa.dupe(Department, departments.values());
        std.mem.sort(Department, ordered_departments, {}, struct {
            fn less(_: void, a: Department, b: Department) bool {
                return std.mem.order(u8, a.name, b.name) == .lt;
            }
        }.less);
        for (ordered_departments) |d| try self.out.print("  dept {s} courses {d} enrolled {d}/{d} rate {s} waitlisted {d}\n", .{ d.name, d.courses, d.enrolled, d.capacity, try self.rate(d.enrolled, d.capacity), d.waiting });
    }
    fn execute(self: *Registration, a: []const []const u8) Error!void {
        const op = std.meta.stringToEnum(Command, a[0]).?;
        const id: []const u8 = if (a.len > 1) a[1] else "";
        switch (op) {
            .COURSE => {
                if (self.courses.contains(id)) return self.fail("duplicate course {s}", .{id});
                const meetings = try self.slots(a[4]);
                const prereq = try self.prerequisite(id, a[5]);
                const c = try self.gpa.create(Course);
                c.* = .{ .name = id, .credits = integer(a[2]), .capacity = @intCast(integer(a[3])), .slots = meetings, .prereq = prereq };
                try self.courses.put(self.gpa, id, c);
                try self.out.print("COURSE {s} credits {d} capacity {d} meetings {d} weekly {s} prereq {s}\n", .{ id, c.credits, c.capacity, meetings.len, try self.clock(c.weekly()), prereq.text });
            },
            .STUDENT => {
                if (self.students.contains(id)) return self.fail("duplicate student {s}", .{id});
                const records = try self.grades(id, a[4]);
                const s = try self.gpa.create(Student);
                s.* = .{ .name = id, .year = integer(a[2]), .limit = integer(a[3]), .grades = records };
                try self.students.put(self.gpa, id, s);
                try self.out.print("STUDENT {s} year {d} limit {d} records {d} earned {d} gpa {s}\n", .{ id, s.year, s.limit, records.len, s.earned(), try self.gpaText(s) });
            },
            .ENROLL, .CHECK, .DROP, .SWAP, .OPTIONS, .LIMIT, .SCHEDULE, .FREE, .AUDIT, .HISTORY => {
                const s = try self.student(id);
                switch (op) {
                    .ENROLL, .CHECK => {
                        const c = try self.course(a[2]);
                        const result = try self.judge(s, c);
                        if (op == .CHECK) {
                            try self.out.print("CHECK {s} {s} {s}\n", .{ id, c.name, try self.judgmentText(result) });
                        } else if (result.action == .reason) {
                            return self.reject(result, s, c);
                        } else if (result.action == .enroll) {
                            try self.enroll(s, c);
                            try self.history(s, "enroll {s}", .{c.name});
                            try self.enrollmentLine("ENROLL", s, c);
                        } else {
                            try c.waiting.insert(self.gpa, result.position - 1, s);
                            try self.history(s, "waitlist {s} {d}", .{ c.name, result.position });
                            try self.out.print("ENROLL {s} {s} waitlist {d}\n", .{ id, c.name, result.position });
                        }
                    },
                    .DROP => {
                        const c = try self.course(a[2]);
                        if (std.mem.findScalar(*Student, c.enrolled.items, s) != null) {
                            remove(Student, &c.enrolled, s);
                            remove(Course, &s.courses, c);
                            try self.history(s, "drop {s}", .{c.name});
                            try self.enrollmentLine("DROP", s, c);
                        } else if (std.mem.findScalar(*Student, c.waiting.items, s) != null) {
                            remove(Student, &c.waiting, s);
                            try self.history(s, "drop {s} waitlist", .{c.name});
                            try self.out.print("DROP {s} {s} waitlist removed\n", .{ id, c.name });
                        } else return self.fail("not registered {s} {s}", .{ id, c.name });
                        try self.promote();
                    },
                    .SWAP => {
                        const from = try self.course(a[2]);
                        const to = try self.course(a[3]);
                        if (std.mem.findScalar(*Student, from.enrolled.items, s) == null) return self.fail("not enrolled {s} {s}", .{ id, from.name });
                        if (from == to) return self.fail("same course {s}", .{from.name});
                        const result = try self.eligible(s, to, from);
                        if (result.action == .reason) return self.reject(result, s, to);
                        if (to.enrolled.items.len == to.capacity) return self.fail("course full {s}", .{to.name});
                        remove(Student, &from.enrolled, s);
                        remove(Course, &s.courses, from);
                        try self.enroll(s, to);
                        try self.history(s, "swap {s} {s}", .{ from.name, to.name });
                        try self.out.print("SWAP {s} {s} -> {s} credits {d}/{d}\n", .{ id, from.name, to.name, s.credits(null), s.limit });
                        try self.promote();
                    },
                    .OPTIONS => {
                        try self.out.print("OPTIONS {s} courses {d}\n", .{ id, self.courses.count() });
                        for (try self.ordered(Course, self.courses.values())) |c| try self.out.print("  {s} {s}\n", .{ c.name, try self.judgmentText(try self.judge(s, c)) });
                    },
                    .LIMIT => {
                        const limit = integer(a[2]);
                        if (limit < s.credits(null)) return self.fail("limit below enrolled {s} {d}", .{ id, s.credits(null) });
                        const old = s.limit;
                        s.limit = limit;
                        try self.out.print("LIMIT {s} {d} -> {d}\n", .{ id, old, limit });
                        try self.promote();
                    },
                    .SCHEDULE => try self.schedule(s),
                    .FREE => try self.freeTime(s, a[2]),
                    .AUDIT => {
                        try self.out.print("AUDIT {s} year {d} limit {d}\n", .{ id, s.year, s.limit });
                        for (s.grades) |r| try self.out.print("  record {s} {c} {d}\n", .{ r.code, r.grade, r.credits });
                        try self.out.print("  earned {d} gpa {s}\n", .{ s.earned(), try self.gpaText(s) });
                        for (try self.ordered(Course, s.courses.items)) |c| try self.out.print("  enrolled {s} {d}\n", .{ c.name, c.credits });
                        try self.out.print("  credits {d} remaining {d}\n", .{ s.credits(null), s.limit - s.credits(null) });
                        for (try self.ordered(Course, self.courses.values())) |c| {
                            if (std.mem.findScalar(*Student, c.waiting.items, s)) |i| try self.out.print("  waitlist {s} {d}\n", .{ c.name, i + 1 });
                        }
                    },
                    .HISTORY => {
                        try self.out.print("HISTORY {s} events {d}\n", .{ id, s.history.items.len });
                        for (s.history.items) |h| try self.out.print("  {d} {s}\n", .{ h.command, h.event });
                    },
                    else => unreachable,
                }
            },
            .CLOSE, .OPEN, .CAPACITY, .PREREQ, .CANCEL, .ROSTER, .INFO => {
                const c = try self.course(id);
                switch (op) {
                    .CLOSE, .OPEN => {
                        const open = op == .OPEN;
                        if (c.open == open) return self.fail("already {s} {s}", .{ if (open) "open" else "closed", id });
                        c.open = open;
                        try self.out.print("{s} {s} enrolled {d}/{d} waitlist {d}\n", .{ a[0], id, c.enrolled.items.len, c.capacity, c.waiting.items.len });
                        if (open) try self.promote();
                    },
                    .CAPACITY => {
                        const capacity: usize = @intCast(integer(a[2]));
                        if (capacity < c.enrolled.items.len) return self.fail("capacity below enrollment {s} {d}", .{ id, c.enrolled.items.len });
                        const old = c.capacity;
                        c.capacity = capacity;
                        try self.out.print("CAPACITY {s} {d} -> {d}\n", .{ id, old, capacity });
                        try self.promote();
                    },
                    .PREREQ => {
                        const prereq = try self.prerequisite(id, a[2]);
                        c.prereq = prereq;
                        try self.out.print("PREREQ {s} {s}\n", .{ id, prereq.text });
                        var i: usize = 0;
                        while (i < c.waiting.items.len) {
                            const s = c.waiting.items[i];
                            if (prereq.met(s)) {
                                i += 1;
                                continue;
                            }
                            _ = c.waiting.orderedRemove(i);
                            try self.history(s, "unlist {s}", .{id});
                            try self.out.print("  UNLIST {s} {s}\n", .{ s.name, id });
                        }
                    },
                    .CANCEL => {
                        try self.out.print("CANCEL {s} enrolled {d} waitlist {d}\n", .{ id, c.enrolled.items.len, c.waiting.items.len });
                        for (c.enrolled.items) |s| {
                            remove(Course, &s.courses, c);
                            try self.history(s, "cancel {s}", .{id});
                        }
                        for (c.waiting.items) |s| try self.history(s, "cancel {s} waitlist", .{id});
                        _ = self.courses.swapRemove(id);
                        try self.promote();
                    },
                    .ROSTER => {
                        try self.out.print("ROSTER {s} {s} enrolled {d}/{d} waitlist {d}\n", .{ id, if (c.open) "open" else "closed", c.enrolled.items.len, c.capacity, c.waiting.items.len });
                        for (try self.ordered(Student, c.enrolled.items)) |s| try self.out.print("  enrolled {s} year {d}\n", .{ s.name, s.year });
                        for (c.waiting.items, 0..) |s, i| try self.out.print("  waitlist {d} {s} year {d}\n", .{ i + 1, s.name, s.year });
                    },
                    .INFO => {
                        try self.out.print("INFO {s} {s} credits {d} capacity {d} prereq {s}\n", .{ id, if (c.open) "open" else "closed", c.credits, c.capacity, c.prereq.text });
                        const meetings = try self.gpa.dupe(Slot, c.slots);
                        std.mem.sort(Slot, meetings, {}, Slot.less);
                        for (meetings) |slot| try self.out.print("  meet {s} {s}-{s}\n", .{ days[slot.day], try self.clock(slot.start), try self.clock(slot.end) });
                        if (meetings.len == 0) try self.out.writeAll("  meet TBA\n");
                        try self.out.writeAll("  required by");
                        var found = false;
                        for (try self.ordered(Course, self.courses.values())) |other| {
                            if (!other.prereq.contains(id)) continue;
                            found = true;
                            try self.out.print(" {s}", .{other.name});
                        }
                        if (!found) try self.out.writeAll(" none");
                        try self.out.writeAll("\n");
                    },
                    else => unreachable,
                }
            },
            .STUDENTS => {
                try self.out.print("STUDENTS {d}\n", .{self.students.count()});
                for (try self.ordered(Student, self.students.values())) |s| try self.out.print("  {s} year {d} credits {d}/{d} courses {d} waitlists {d}\n", .{ s.name, s.year, s.credits(null), s.limit, s.courses.items.len, self.waitCount(s) });
            },
            .REPORT => try self.report(),
        }
    }
};
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    var registration = Registration{ .gpa = gpa, .out = &output.interface };
    const n: usize = @intCast(integer((try input.interface.takeDelimiter('\n')).?));
    for (0..n) |i| {
        registration.command = i + 1;
        const line = try gpa.dupe(u8, (try input.interface.takeDelimiter('\n')).?);
        var tokens: std.ArrayList([]const u8) = .empty;
        var it = std.mem.splitScalar(u8, line, ' ');
        while (it.next()) |token| try tokens.append(gpa, token);
        registration.execute(tokens.items) catch |err| {
            if (err != error.BadCommand) return err;
            try output.interface.print("ERROR {s}\n", .{registration.error_message});
        };
    }
    try output.interface.flush();
}
