const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const Text = []const u8;
const Error = Allocator.Error || Writer.Error || error{Invalid};
const Kind = enum { BUG, TASK, STORY };
const Priority = enum { LOW, MEDIUM, HIGH, CRITICAL };
const State = enum { OPEN, TRIAGED, IN_PROGRESS, REVIEW, RESOLVED, CLOSED, REOPENED, DONE, BACKLOG, READY };
const Phase = enum { PLANNED, ACTIVE, ENDED };
const Field = enum { id, kind, status, priority, assignee, reviewer, estimate, sprint, comments, blocked, done, title };
const Operation = enum { eq, ne, lt, le, gt, ge, contains };

fn equal(a: Text, b: Text) bool { return std.mem.eql(u8, a, b); }
fn number(text: Text) u32 { return std.fmt.parseInt(u32, text, 10) catch unreachable; }
fn line(out: *Writer, comptime format: Text, arguments: anytype) Writer.Error!void { try out.print(format ++ "\n", arguments); }
fn lower(gpa: Allocator, text: Text) Allocator.Error!Text {
    const result = try gpa.dupe(u8, text);
    for (result) |*character| character.* = std.ascii.toLower(character.*);
    return result;
}
fn workflow(kind: Kind) []const State {
    return switch (kind) {
        .BUG => &.{ .OPEN, .TRIAGED, .IN_PROGRESS, .REVIEW, .RESOLVED, .CLOSED, .REOPENED },
        .TASK => &.{ .OPEN, .IN_PROGRESS, .DONE },
        .STORY => &.{ .BACKLOG, .READY, .IN_PROGRESS, .REVIEW, .DONE },
    };
}
fn transition(kind: Kind, from: State, target: State) bool {
    const edges: []const [2]State = switch (kind) {
        .BUG => &.{ .{ .OPEN, .TRIAGED }, .{ .TRIAGED, .IN_PROGRESS }, .{ .IN_PROGRESS, .REVIEW }, .{ .REVIEW, .IN_PROGRESS }, .{ .REVIEW, .RESOLVED }, .{ .RESOLVED, .CLOSED }, .{ .RESOLVED, .REOPENED }, .{ .CLOSED, .REOPENED }, .{ .REOPENED, .IN_PROGRESS } },
        .TASK => &.{ .{ .OPEN, .IN_PROGRESS }, .{ .IN_PROGRESS, .OPEN }, .{ .IN_PROGRESS, .DONE } },
        .STORY => &.{ .{ .BACKLOG, .READY }, .{ .READY, .BACKLOG }, .{ .READY, .IN_PROGRESS }, .{ .IN_PROGRESS, .REVIEW }, .{ .REVIEW, .IN_PROGRESS }, .{ .REVIEW, .DONE } },
    };
    for (edges) |edge| if (edge[0] == from and edge[1] == target) return true;
    return false;
}

const Issue = struct {
    number: u32,
    kind: Kind,
    priority: Priority,
    title: Text,
    state: State,
    assignee: ?usize = null,
    reviewer: ?usize = null,
    estimate: ?u32 = null,
    sprint: ?usize = null,
    comments: u32 = 0,
    blocks: [100]bool = @splat(false),
    duplicate: ?usize = null,
    history: std.ArrayList(Text) = .empty,

    fn done(issue: Issue) bool { return issue.state == .RESOLVED or issue.state == .CLOSED or issue.state == .DONE; }
    fn points(issue: Issue) u32 { return issue.estimate orelse 0; }
};

const Sprint = struct {
    name: Text,
    phase: Phase = .PLANNED,
    start: u32 = 0,
    end: u32 = 0,
    velocity: u32 = 0,
    records: [366]?u32 = @splat(null),
};

const Summary = struct { count: usize = 0, total: u32 = 0, remaining: u32 = 0, done: usize = 0 };
const Condition = struct { field: Field, operation: Operation, value: Text, expected: ?u32 = null };
const Query = struct { tokens: [101]Text = undefined, conditions: [101]?Condition = @splat(null), count: usize = 0 };

const Tracker = struct {
    gpa: Allocator,
    day: u32 = 1,
    users: std.ArrayList(Text) = .empty,
    issues: std.ArrayList(Issue) = .empty,
    sprints: std.ArrayList(Sprint) = .empty,

    fn issueIndex(tracker: *const Tracker, id: u32) ?usize {
        for (tracker.issues.items, 0..) |issue, index| if (issue.number == id) return index;
        return null;
    }
    fn userIndex(tracker: *const Tracker, name: Text) ?usize {
        for (tracker.users.items, 0..) |user, index| if (equal(user, name)) return index;
        return null;
    }
    fn sprintIndex(tracker: *const Tracker, name: Text) ?usize {
        for (tracker.sprints.items, 0..) |sprint, index| if (equal(sprint.name, name)) return index;
        return null;
    }
    fn lessIssue(tracker: *const Tracker, a: usize, b: usize) bool { return tracker.issues.items[a].number < tracker.issues.items[b].number; }
    fn ordered(tracker: *const Tracker) [100]usize {
        var result: [100]usize = @splat(0);
        for (0..tracker.issues.items.len) |index| result[index] = index;
        std.sort.heap(usize, result[0..tracker.issues.items.len], tracker, lessIssue);
        return result;
    }
    fn assigneeName(tracker: *const Tracker, user: ?usize) Text { return if (user) |index| tracker.users.items[index] else "-"; }
    fn sprintName(tracker: *const Tracker, sprint: ?usize) Text { return if (sprint) |index| tracker.sprints.items[index].name else "-"; }
    fn unfinishedBlocker(tracker: *const Tracker, target: usize) ?usize {
        var best: ?usize = null;
        for (tracker.issues.items, 0..) |issue, index| {
            if (!issue.blocks[target] or issue.done()) continue;
            if (best == null or issue.number < tracker.issues.items[best.?].number) best = index;
        }
        return best;
    }
    fn blocked(tracker: *const Tracker, index: usize) bool { return !tracker.issues.items[index].done() and tracker.unfinishedBlocker(index) != null; }
    fn wip(tracker: *const Tracker, user: ?usize) usize {
        var count: usize = 0;
        for (tracker.issues.items) |issue| {
            if (issue.assignee == user and issue.state == .IN_PROGRESS) count += 1;
        }
        return count;
    }
    fn active(tracker: *const Tracker) ?usize {
        for (tracker.sprints.items, 0..) |sprint, index| if (sprint.phase == .ACTIVE) return index;
        return null;
    }
    fn summary(tracker: *const Tracker, sprint: usize) Summary {
        var result: Summary = .{};
        for (tracker.issues.items) |issue| {
            if (issue.sprint != sprint) continue;
            result.count += 1;
            result.total += issue.points();
            if (issue.done()) result.done += 1 else result.remaining += issue.points();
        }
        return result;
    }
    fn reaches(tracker: *const Tracker, start: usize, goal: usize) bool {
        var queue: [100]usize = undefined;
        var seen: [100]bool = @splat(false);
        var head: usize = 0;
        var tail: usize = 1;
        queue[0] = start;
        seen[start] = true;
        while (head < tail) : (head += 1) {
            const current = queue[head];
            if (current == goal) return true;
            for (0..tracker.issues.items.len) |index| {
                if (!tracker.issues.items[current].blocks[index] or seen[index]) continue;
                seen[index] = true;
                queue[tail] = index;
                tail += 1;
            }
        }
        return false;
    }
};

fn compareNumber(actual: ?u32, operation: Operation, expected: ?u32) bool {
    if (operation == .eq) return actual == expected;
    if (operation == .ne) return actual != expected;
    const left = actual orelse return false;
    const right = expected.?;
    return switch (operation) { .lt => left < right, .le => left <= right, .gt => left > right, .ge => left >= right, else => unreachable };
}

fn conditionMatches(tracker: *const Tracker, index: usize, condition: Condition) bool {
    const issue = tracker.issues.items[index];
    const actual_number: ?u32 = switch (condition.field) {
        .id => issue.number,
        .priority => @intFromEnum(issue.priority),
        .estimate => issue.estimate,
        .comments => issue.comments,
        else => null,
    };
    switch (condition.field) {
        .id, .priority, .estimate, .comments => return compareNumber(actual_number, condition.operation, condition.expected),
        else => {},
    }
    if (condition.field == .title) {
        if (condition.value.len > issue.title.len) return false;
        for (0..issue.title.len - condition.value.len + 1) |offset| {
            var match = true;
            for (condition.value, 0..) |character, position| {
                if (std.ascii.toLower(issue.title[offset + position]) != character) { match = false; break; }
            }
            if (match) return true;
        }
        return false;
    }
    const actual: Text = switch (condition.field) {
        .kind => @tagName(issue.kind),
        .status => @tagName(issue.state),
        .assignee => tracker.assigneeName(issue.assignee),
        .reviewer => tracker.assigneeName(issue.reviewer),
        .sprint => tracker.sprintName(issue.sprint),
        .blocked => if (tracker.blocked(index)) "yes" else "no",
        .done => if (issue.done()) "yes" else "no",
        else => unreachable,
    };
    return if (condition.operation == .eq) equal(actual, condition.value) else !equal(actual, condition.value);
}

const Parser = struct {
    tracker: *const Tracker,
    query: *const Query,
    issue: usize,
    position: usize = 0,

    fn factor(parser: *Parser) bool {
        const position = parser.position;
        const token = parser.query.tokens[position];
        parser.position += 1;
        if (equal(token, "NOT")) return !parser.factor();
        if (equal(token, "(")) {
            const result = parser.expression();
            parser.position += 1;
            return result;
        }
        return conditionMatches(parser.tracker, parser.issue, parser.query.conditions[position].?);
    }
    fn term(parser: *Parser) bool {
        var result = parser.factor();
        while (parser.position < parser.query.count and equal(parser.query.tokens[parser.position], "AND")) {
            parser.position += 1;
            const right = parser.factor();
            result = result and right;
        }
        return result;
    }
    fn expression(parser: *Parser) bool {
        var result = parser.term();
        while (parser.position < parser.query.count and equal(parser.query.tokens[parser.position], "OR")) {
            parser.position += 1;
            const right = parser.term();
            result = result or right;
        }
        return result;
    }
};

const Session = struct {
    tracker: *Tracker,
    out: *Writer,
    problem: Text = "",

    fn fail(session: *Session, message: Text) error{Invalid} { session.problem = message; return error.Invalid; }
    fn failFormat(session: *Session, comptime format: Text, arguments: anytype) Error {
        const text = std.fmt.allocPrint(session.tracker.gpa, format, arguments) catch return error.OutOfMemory;
        return session.fail(text);
    }
    fn requireIssue(session: *Session, text: Text) Error!usize { return session.tracker.issueIndex(number(text)) orelse return session.fail("unknown issue"); }
    fn requireSprint(session: *Session, text: Text) Error!usize { return session.tracker.sprintIndex(text) orelse return session.fail("unknown sprint"); }
    fn requireUser(session: *Session, text: Text) Error!?usize {
        if (equal(text, "-")) return null;
        return session.tracker.userIndex(text) orelse return session.fail("unknown user");
    }
    fn record(session: *Session, index: usize, comptime format: Text, arguments: anytype) Error!void {
        const tracker = session.tracker;
        const content = try std.fmt.allocPrint(tracker.gpa, format, arguments);
        const entry = try std.fmt.allocPrint(tracker.gpa, "day {d} {s}", .{ tracker.day, content });
        try tracker.issues.items[index].history.append(tracker.gpa, entry);
    }
    fn notify(session: *Session, index: usize, before: bool) Error!void {
        const after = session.tracker.blocked(index);
        if (before != after) try line(session.out, "{s} {d}", .{ if (after) "BLOCKED" else "UNBLOCKED", session.tracker.issues.items[index].number });
    }
    fn changeState(session: *Session, index: usize, target: State) Error!void {
        const tracker = session.tracker;
        const ids = tracker.ordered();
        var before: [100]bool = @splat(false);
        for (0..tracker.issues.items.len) |affected| before[affected] = tracker.blocked(affected);
        const issue = &tracker.issues.items[index];
        try line(session.out, "MOVE {d} {s} {s}", .{ issue.number, @tagName(issue.state), @tagName(target) });
        try session.record(index, "MOVE {s} {s}", .{ @tagName(issue.state), @tagName(target) });
        issue.state = target;
        for (ids[0..tracker.issues.items.len]) |affected| if (issue.blocks[affected]) try session.notify(affected, before[affected]);
    }
    fn printOptional(session: *Session, value: ?u32) Error!void {
        if (value) |present| try session.out.print("{d}", .{present}) else try session.out.writeAll("-");
    }
    fn printSummary(session: *Session, sprint: usize) Error!void {
        const summary = session.tracker.summary(sprint);
        try session.out.print("issues {d} points {d}", .{ summary.count, summary.total });
    }
    fn printLinks(session: *Session, index: usize, kind: enum { blocks, blockers, duplicates }) Error!void {
        const tracker = session.tracker;
        const ids = tracker.ordered();
        var first = true;
        for (ids[0..tracker.issues.items.len]) |other_index| {
            const included = switch (kind) {
                .blocks => tracker.issues.items[index].blocks[other_index],
                .blockers => tracker.issues.items[other_index].blocks[index],
                .duplicates => tracker.issues.items[other_index].duplicate == index,
            };
            if (!included) continue;
            if (!first) try session.out.writeByte(',');
            try session.out.print("{d}", .{tracker.issues.items[other_index].number});
            first = false;
        }
        if (first) try session.out.writeAll("-");
    }
    fn checkCondition(session: *Session, token: Text) Error!Condition {
        var end: usize = 0;
        while (end < token.len and std.ascii.isLower(token[end])) : (end += 1) {}
        const field_name = token[0..end];
        const rest = token[end..];
        const operators = [_]Text{ ">=", "<=", "!=", "=", "<", ">", "~" };
        const operations = [_]Operation{ .ge, .le, .ne, .eq, .lt, .gt, .contains };
        var operator_index: ?usize = null;
        for (operators, 0..) |candidate, index| {
            if (std.mem.startsWith(u8, rest, candidate)) { operator_index = index; break; }
        }
        const selected = operator_index orelse return session.failFormat("syntax near {s}", .{token});
        const value = rest[operators[selected].len..];
        if (field_name.len == 0 or value.len == 0) return session.failFormat("syntax near {s}", .{token});
        const field: Field = if (equal(field_name, "type")) .kind else std.meta.stringToEnum(Field, field_name) orelse return session.failFormat("unknown field {s}", .{field_name});
        if (equal(field_name, "kind")) return session.failFormat("unknown field {s}", .{field_name});
        const operation = operations[selected];
        const equality = operation == .eq or operation == .ne;
        const ordered = field == .id or field == .priority or field == .estimate or field == .comments;
        if ((field == .title and operation != .contains) or (ordered and operation == .contains) or (!ordered and field != .title and !equality)) return session.failFormat("bad operator {s}", .{token});
        var result: Condition = .{ .field = field, .operation = operation, .value = value };
        if (equality and equal(value, "-") and (field == .assignee or field == .reviewer or field == .estimate or field == .sprint)) return result;
        if (field == .id or field == .estimate or field == .comments) {
            var valid = value.len >= 1 and value.len <= 6;
            for (value) |character| valid = valid and std.ascii.isDigit(character);
            if (valid) { result.expected = number(value); return result; }
        }
        if (field == .priority) {
            if (std.meta.stringToEnum(Priority, value)) |priority| { result.expected = @intFromEnum(priority); return result; }
        }
        if ((field == .kind and std.meta.stringToEnum(Kind, value) != null) or
            (field == .status and std.meta.stringToEnum(State, value) != null) or
            ((field == .assignee or field == .reviewer) and session.tracker.userIndex(value) != null) or
            (field == .sprint and session.tracker.sprintIndex(value) != null) or
            ((field == .blocked or field == .done) and (equal(value, "yes") or equal(value, "no")))) return result;
        if (field == .title) { result.value = try lower(session.tracker.gpa, value); return result; }
        return session.failFormat("bad value {s}", .{token});
    }
    fn checkQuery(session: *Session, text: Text) Error!Query {
        var query: Query = .{};
        var position: usize = 0;
        while (position < text.len) {
            if (text[position] == ' ') { position += 1; continue; }
            const start = position;
            if (text[position] == '(' or text[position] == ')') position += 1 else {
                while (position < text.len and text[position] != ' ' and text[position] != '(' and text[position] != ')') : (position += 1) {}
            }
            query.tokens[query.count] = text[start..position];
            query.count += 1;
        }
        var operand = true;
        var depth: usize = 0;
        for (query.tokens[0..query.count], 0..) |token, index| {
            if (operand) {
                if (equal(token, "(")) depth += 1
                else if (equal(token, "AND") or equal(token, "OR") or equal(token, ")")) return session.failFormat("syntax near {s}", .{token})
                else if (!equal(token, "NOT")) { query.conditions[index] = try session.checkCondition(token); operand = false; }
            } else if (equal(token, "AND") or equal(token, "OR")) operand = true
            else if (equal(token, ")") and depth > 0) depth -= 1
            else return session.failFormat("syntax near {s}", .{token});
        }
        if (operand or depth != 0) return session.fail("syntax at end");
        return query;
    }
    fn queryIssues(session: *Session, text: Text) Error!void {
        const parsed = try session.checkQuery(text);
        const tracker = session.tracker;
        const ids = tracker.ordered();
        var matches: [100]usize = undefined;
        var count: usize = 0;
        var rank: u32 = 4;
        while (rank > 0) {
            rank -= 1;
            for (ids[0..tracker.issues.items.len]) |index| {
                if (@intFromEnum(tracker.issues.items[index].priority) != rank) continue;
                var parser: Parser = .{ .tracker = tracker, .query = &parsed, .issue = index };
                if (parser.expression()) { matches[count] = index; count += 1; }
            }
        }
        try line(session.out, "QUERY {d}", .{count});
        for (matches[0..count]) |index| {
            const issue = tracker.issues.items[index];
            try session.out.print("{d} {s} {s} {s} {s} ", .{ issue.number, @tagName(issue.kind), @tagName(issue.priority), @tagName(issue.state), tracker.assigneeName(issue.assignee) });
            try session.printOptional(issue.estimate);
            try line(session.out, " {s}", .{issue.title});
        }
    }
    fn display(session: *Session, command: Text, words: []const Text) Error!void {
        const tracker = session.tracker;
        if (equal(command, "BOARD")) {
            try line(session.out, "BOARD", .{});
            inline for (.{ Kind.BUG, Kind.TASK, Kind.STORY }) |kind| {
                try session.out.print("{s}", .{@tagName(kind)});
                for (workflow(kind)) |state| {
                    var count: usize = 0;
                    for (tracker.issues.items) |issue| {
                        if (issue.kind == kind and issue.state == state) count += 1;
                    }
                    try session.out.print(" {s} {d}", .{ @tagName(state), count });
                }
                try session.out.writeByte('\n');
            }
            var finished: usize = 0;
            for (tracker.issues.items) |issue| {
                if (issue.done()) finished += 1;
            }
            try line(session.out, "TOTAL {d} open {d} done {d}", .{ tracker.issues.items.len, tracker.issues.items.len - finished, finished });
        } else if (equal(command, "WORKLOAD")) {
            var users: [20]Text = undefined;
            @memcpy(users[0..tracker.users.items.len], tracker.users.items);
            std.sort.heap(Text, users[0..tracker.users.items.len], {}, struct { fn less(_: void, a: Text, b: Text) bool { return std.mem.order(u8, a, b) == .lt; } }.less);
            try line(session.out, "WORKLOAD {d}", .{tracker.users.items.len});
            for (users[0..tracker.users.items.len]) |user| {
                const index = tracker.userIndex(user).?;
                var assigned: u32 = 0;
                var progressing: u32 = 0;
                var review: u32 = 0;
                var reviewing: u32 = 0;
                var total: u32 = 0;
                for (tracker.issues.items) |issue| {
                    if (issue.assignee == index and !issue.done()) {
                        assigned += 1; total += issue.points();
                        if (issue.state == .IN_PROGRESS) progressing += 1;
                        if (issue.state == .REVIEW) review += 1;
                    }
                    if (issue.reviewer == index and issue.state == .REVIEW) reviewing += 1;
                }
                try line(session.out, "{s} assigned {d} in_progress {d} review {d} reviewing {d} points {d}", .{ user, assigned, progressing, review, reviewing, total });
            }
        } else if (equal(command, "SPRINTS")) {
            try line(session.out, "SPRINTS {d}", .{tracker.sprints.items.len});
            for (tracker.sprints.items, 0..) |sprint, index| {
                try session.out.print("{s} {s}", .{ sprint.name, @tagName(sprint.phase) });
                if (sprint.phase == .ENDED) try session.out.print(" start {d} end {d} velocity {d}", .{ sprint.start, sprint.end, sprint.velocity }) else {
                    if (sprint.phase == .ACTIVE) try session.out.print(" start {d}", .{sprint.start});
                    try session.out.writeByte(' ');
                    try session.printSummary(index);
                    if (sprint.phase == .ACTIVE) try session.out.print(" remaining {d}", .{tracker.summary(index).remaining});
                }
                try session.out.writeByte('\n');
            }
        } else if (equal(command, "BURNDOWN")) {
            const index = try session.requireSprint(words[1]);
            const sprint = tracker.sprints.items[index];
            if (sprint.phase == .PLANNED) return session.fail("sprint not started");
            const last = if (sprint.phase == .ACTIVE) tracker.day else sprint.end;
            try line(session.out, "BURNDOWN {s} {s} days {d}", .{ sprint.name, @tagName(sprint.phase), last - sprint.start + 1 });
            var day = sprint.start;
            var value: u32 = 0;
            while (day <= last) : (day += 1) {
                if (sprint.records[day]) |recorded| value = recorded;
                try line(session.out, "day {d} {d}", .{ day, value });
            }
        } else {
            const index = try session.requireIssue(words[1]);
            const issue = tracker.issues.items[index];
            if (equal(command, "HISTORY")) {
                try line(session.out, "HISTORY {d} {d}", .{ issue.number, issue.history.items.len });
                for (issue.history.items) |entry| try line(session.out, "{s}", .{entry});
                return;
            }
            try line(session.out, "ISSUE {d} {s} {s} {s} blocked {s}", .{ issue.number, @tagName(issue.kind), @tagName(issue.priority), @tagName(issue.state), if (tracker.blocked(index)) "yes" else "no" });
            try line(session.out, "TITLE {s}", .{issue.title});
            try line(session.out, "PEOPLE assignee {s} reviewer {s}", .{ tracker.assigneeName(issue.assignee), tracker.assigneeName(issue.reviewer) });
            try session.out.writeAll("PLAN estimate ");
            try session.printOptional(issue.estimate);
            try line(session.out, " sprint {s} comments {d}", .{ tracker.sprintName(issue.sprint), issue.comments });
            try session.out.writeAll("LINKS blocks "); try session.printLinks(index, .blocks);
            try session.out.writeAll(" blocked_by "); try session.printLinks(index, .blockers);
            try session.out.writeAll(" duplicate_of "); try session.printOptional(if (issue.duplicate) |target| tracker.issues.items[target].number else null);
            try session.out.writeAll(" duplicated_by "); try session.printLinks(index, .duplicates);
            try session.out.writeByte('\n');
        }
    }
    fn sprintCommand(session: *Session, words: []const Text) Error!void {
        const tracker = session.tracker;
        const action = words[1];
        const name = words[2];
        if (equal(action, "NEW")) {
            if (tracker.sprintIndex(name) != null) return session.fail("sprint exists");
            try tracker.sprints.append(tracker.gpa, .{ .name = name });
            try line(session.out, "SPRINT NEW {s}", .{name});
            return;
        }
        const index = try session.requireSprint(name);
        const sprint = &tracker.sprints.items[index];
        if (equal(action, "ADD") or equal(action, "REMOVE")) {
            const issue_index = try session.requireIssue(words[3]);
            const issue = &tracker.issues.items[issue_index];
            if (sprint.phase == .ENDED) return session.fail("sprint ended");
            if (equal(action, "ADD")) {
                if (issue.done()) return session.fail("issue done");
                if (issue.sprint) |previous| if (tracker.sprints.items[previous].phase != .ENDED) return session.failFormat("in sprint {s}", .{tracker.sprints.items[previous].name});
                if (issue.state == .BACKLOG) return session.fail("not ready");
                issue.sprint = index;
            } else {
                if (issue.sprint != index) return session.fail("not in sprint");
                if (issue.done()) return session.fail("issue done");
                issue.sprint = null;
            }
            try session.record(issue_index, "SPRINT {s} {s}", .{ action, name });
            try session.out.print("SPRINT {s} {s} {d} ", .{ action, name, issue.number });
            try session.printSummary(index);
            try session.out.writeByte('\n');
        } else if (equal(action, "START")) {
            if (sprint.phase != .PLANNED) return session.fail("sprint not planned");
            if (tracker.active()) |active| return session.failFormat("sprint active {s}", .{tracker.sprints.items[active].name});
            const summary = tracker.summary(index);
            if (summary.count == 0) return session.fail("sprint empty");
            sprint.phase = .ACTIVE; sprint.start = tracker.day; sprint.records[tracker.day] = summary.remaining;
            try line(session.out, "SPRINT START {s} day {d} issues {d} points {d} remaining {d}", .{ name, tracker.day, summary.count, summary.total, summary.remaining });
        } else {
            if (sprint.phase != .ACTIVE) return session.fail("sprint not active");
            const summary = tracker.summary(index);
            sprint.records[tracker.day] = summary.remaining;
            sprint.velocity = summary.total - summary.remaining;
            sprint.phase = .ENDED; sprint.end = tracker.day;
            try line(session.out, "SPRINT END {s} day {d} velocity {d} done {d} returned {d}", .{ name, tracker.day, sprint.velocity, summary.done, summary.count - summary.done });
            const ids = tracker.ordered();
            for (ids[0..tracker.issues.items.len]) |issue_index| {
                const issue = &tracker.issues.items[issue_index];
                if (issue.sprint != index or issue.done()) continue;
                issue.sprint = null;
                try session.record(issue_index, "SPRINT RETURN {s}", .{name});
                try line(session.out, "RETURNED {d}", .{issue.number});
            }
        }
    }
    fn link(session: *Session, command: Text, words: []const Text) Error!void {
        const tracker = session.tracker;
        const unlink = equal(command, "UNLINK");
        const blocks = equal(words[2], "BLOCKS");
        if ((unlink and !blocks) or (!blocks and !equal(words[2], "DUPLICATES"))) return session.fail("bad link");
        const a = try session.requireIssue(words[1]);
        const b = try session.requireIssue(words[3]);
        const source = &tracker.issues.items[a];
        const target = &tracker.issues.items[b];
        if (!unlink and a == b) return session.fail("self link");
        const before = tracker.blocked(b);
        if (unlink) {
            if (!source.blocks[b]) return session.fail("no link");
            source.blocks[b] = false;
        } else if (blocks) {
            if (source.blocks[b]) return session.fail("link exists");
            if (tracker.reaches(b, a)) return session.fail("cycle");
            if (target.done()) return session.fail("issue done");
            source.blocks[b] = true;
        } else {
            if (source.kind != target.kind) return session.fail("type mismatch");
            if (source.done()) return session.fail("issue done");
            if (target.duplicate != null) return session.fail("target is duplicate");
            source.duplicate = b;
        }
        try session.record(a, "{s} {s} {d}", .{ command, words[2], target.number });
        try session.record(b, "{s} {s} {d}", .{ command, if (blocks) "BLOCKED_BY" else "DUPLICATED_BY", source.number });
        try line(session.out, "{s} {d} {s} {d}", .{ command, source.number, words[2], target.number });
        if (blocks) try session.notify(b, before) else {
            try session.changeState(a, if (source.kind == .BUG) .CLOSED else .DONE);
            if (source.sprint) |sprint| {
                if (tracker.sprints.items[sprint].phase != .ENDED) {
                    try session.record(a, "SPRINT REMOVE {s}", .{tracker.sprints.items[sprint].name});
                    source.sprint = null;
                }
            }
        }
    }
    fn execute(session: *Session, source: Text) Error!void {
        const tracker = session.tracker;
        var words: std.ArrayList(Text) = .empty;
        var split = std.mem.splitScalar(u8, source, ' ');
        while (split.next()) |word| try words.append(tracker.gpa, word);
        const args = words.items;
        const command = args[0];
        if (equal(command, "QUERY")) return session.queryIssues(source[6..]);
        if (equal(command, "SHOW") or equal(command, "HISTORY") or equal(command, "BOARD") or equal(command, "WORKLOAD") or equal(command, "SPRINTS") or equal(command, "BURNDOWN")) return session.display(command, args);
        if (equal(command, "DAY")) {
            const day = number(args[1]);
            if (day < tracker.day) return session.fail("day backwards");
            tracker.day = day;
            try line(session.out, "DAY {d}", .{day});
            return;
        }
        if (equal(command, "USER")) {
            if (tracker.userIndex(args[1]) != null) return session.fail("user exists");
            try tracker.users.append(tracker.gpa, args[1]);
            try line(session.out, "USER {s}", .{args[1]});
            return;
        }
        if (equal(command, "SPRINT")) return session.sprintCommand(args);
        if (equal(command, "CREATE")) {
            const id = number(args[1]);
            if (tracker.issueIndex(id) != null) return session.fail("issue exists");
            const kind = std.meta.stringToEnum(Kind, args[2]) orelse return session.fail("bad type");
            const priority = std.meta.stringToEnum(Priority, args[3]) orelse return session.fail("bad priority");
            const title = try std.mem.join(tracker.gpa, " ", args[4..]);
            const index = tracker.issues.items.len;
            const state = workflow(kind)[0];
            try tracker.issues.append(tracker.gpa, .{ .number = id, .kind = kind, .priority = priority, .title = title, .state = state });
            try session.record(index, "CREATE {s} {s}", .{ args[2], args[3] });
            try line(session.out, "CREATE {d} {s} {s} {s}", .{ id, args[2], args[3], @tagName(state) });
            return;
        }
        if (equal(command, "LINK") or equal(command, "UNLINK")) return session.link(command, args);
        const index = try session.requireIssue(args[1]);
        const issue = &tracker.issues.items[index];
        if (equal(command, "COMMENT")) {
            _ = try session.requireUser(args[2]);
            issue.comments += 1;
            const text = try std.mem.join(tracker.gpa, " ", args[3..]);
            try session.record(index, "COMMENT {s} {s}", .{ args[2], text });
            try line(session.out, "COMMENT {d} {d}", .{ issue.number, issue.comments });
        } else if (equal(command, "PRIORITY")) {
            const priority = std.meta.stringToEnum(Priority, args[2]) orelse return session.fail("bad priority");
            if (issue.done()) return session.fail("issue done");
            if (issue.priority == priority) return session.fail("no change");
            const previous = issue.priority;
            issue.priority = priority;
            try session.record(index, "PRIORITY {s} {s}", .{ @tagName(previous), args[2] });
            try line(session.out, "PRIORITY {d} {s} {s}", .{ issue.number, @tagName(previous), args[2] });
        } else if (equal(command, "ASSIGN") or equal(command, "REVIEWER")) {
            const user = try session.requireUser(args[2]);
            if (issue.done()) return session.fail("issue done");
            const assign = equal(command, "ASSIGN");
            if (user == (if (assign) issue.assignee else issue.reviewer)) return session.fail("no change");
            if (assign) {
                if (user == null and (issue.state == .IN_PROGRESS or issue.state == .REVIEW)) return session.fail("assignee required");
                if (issue.state == .IN_PROGRESS and tracker.wip(user) >= 3) return session.failFormat("wip limit {s}", .{args[2]});
                if (issue.state == .REVIEW and user == issue.reviewer) return session.fail("reviewer is assignee");
                issue.assignee = user;
            } else {
                if (user == null and issue.state == .REVIEW) return session.fail("reviewer required");
                if (issue.state == .REVIEW and user == issue.assignee) return session.fail("reviewer is assignee");
                issue.reviewer = user;
            }
            try session.record(index, "{s} {s}", .{ command, args[2] });
            try line(session.out, "{s} {d} {s}", .{ command, issue.number, args[2] });
        } else if (equal(command, "ESTIMATE")) {
            const estimate = number(args[2]);
            if (estimate != 0 and estimate != 1 and estimate != 2 and estimate != 3 and estimate != 5 and estimate != 8 and estimate != 13 and estimate != 21) return session.fail("bad estimate");
            if (issue.done()) return session.fail("issue done");
            if (issue.estimate == estimate) return session.fail("no change");
            const previous = if (issue.estimate) |value| try std.fmt.allocPrint(tracker.gpa, "{d}", .{value}) else "-";
            issue.estimate = estimate;
            try session.record(index, "ESTIMATE {s} {d}", .{ previous, estimate });
            try line(session.out, "ESTIMATE {d} {s} {d}", .{ issue.number, previous, estimate });
        } else {
            if (issue.duplicate) |target| return session.failFormat("duplicate of {d}", .{tracker.issues.items[target].number});
            const target = std.meta.stringToEnum(State, args[2]) orelse return session.fail("bad state");
            if (std.mem.indexOfScalar(State, workflow(issue.kind), target) == null) return session.fail("bad state");
            if (!transition(issue.kind, issue.state, target)) return session.failFormat("cannot move {s} to {s}", .{ @tagName(issue.state), args[2] });
            if (target == .IN_PROGRESS) {
                const active = tracker.active();
                if (issue.kind == .STORY and (active == null or issue.sprint != active)) return session.fail("not in active sprint");
                if (issue.assignee == null) return session.fail("no assignee");
                if (tracker.wip(issue.assignee) >= 3) return session.failFormat("wip limit {s}", .{tracker.assigneeName(issue.assignee)});
            }
            if (target == .REVIEW) {
                if (issue.reviewer == null) return session.fail("no reviewer");
                if (issue.reviewer == issue.assignee) return session.fail("reviewer is assignee");
            }
            if (target == .DONE or target == .RESOLVED) {
                if (tracker.unfinishedBlocker(index)) |blocker| return session.failFormat("blocked by {d}", .{tracker.issues.items[blocker].number});
            }
            if (target == .READY and issue.estimate == null) return session.fail("no estimate");
            try session.changeState(index, target);
        }
    }
};

fn readLine(reader: *std.Io.Reader, gpa: Allocator) !?Text {
    var buffer: Writer.Allocating = .init(gpa);
    defer buffer.deinit();
    _ = try reader.streamDelimiterEnding(&buffer.writer, '\n');
    if (reader.bufferedLen() > 0) reader.toss(1) else if (buffer.written().len == 0) return null;
    return try buffer.toOwnedSlice();
}

pub fn main(init: std.process.Init) !void {
    var storage: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer storage.deinit();
    const gpa = storage.allocator();
    var tracker: Tracker = .{ .gpa = gpa };
    var input_buffer: [4096]u8 = undefined;
    var output_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const first = std.mem.trim(u8, (try readLine(&input.interface, gpa)).?, "\r");
    const count = number(first);
    for (0..count) |_| {
        const source = std.mem.trim(u8, (try readLine(&input.interface, gpa)).?, "\r");
        var session: Session = .{ .tracker = &tracker, .out = &output.interface };
        session.execute(source) catch |err| switch (err) {
            error.Invalid => try line(&output.interface, "ERROR {s}", .{session.problem}),
            else => return err,
        };
        if (tracker.active()) |active| tracker.sprints.items[active].records[tracker.day] = tracker.summary(active).remaining;
        try output.interface.flush();
    }
}
