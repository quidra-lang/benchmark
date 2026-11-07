const std = @import("std");
const terms = @import("terms.zig");
const reader = @import("reader.zig");
const unify = @import("unify.zig");
const database = @import("database.zig");
const predicates = @import("predicates.zig");
const Text = terms.Text;
const Term = terms.Term;
const file_names = [_]Text{"prelude.pl", "program.pl"};
const Buffer = struct { a: std.mem.Allocator, data: std.ArrayList(u8) = .empty,
    fn add(b: *Buffer, s: Text) !void { try b.data.appendSlice(b.a, s); }
    fn print(b: *Buffer, comptime f: Text, args: anytype) !void { try b.add(try std.fmt.allocPrint(b.a, f, args)); }
    fn line(b: *Buffer, s: Text) !void { try b.add(s); try b.add("\n"); }
};
const Writer = struct {
    a: std.mem.Allocator, names: std.AutoHashMapUnmanaged(*Term, Text) = .empty, next: usize = 1, quoted: bool = true,
    fn atom(w: *Writer, name: Text) !Text {
        var plain = terms.eq(name, "[]") or terms.eq(name, "!") or terms.eq(name, ";");
        if (name.len > 0 and std.ascii.isLower(name[0])) { plain = true; for (name) |c| if (!std.ascii.isAlphanumeric(c) and c != '_') { plain = false; }; }
        if (!plain and name.len > 0 and !terms.eq(name, ".")) { plain = true; for (name) |c| if (!reader.symbol(c)) { plain = false; }; }
        if (!w.quoted or plain) return name; var b: Buffer = .{ .a = w.a }; try b.add("'");
        for (name) |c| switch (c) { '\\' => try b.add("\\\\"), '\'' => try b.add("\\'"), 10 => try b.add("\\n"), 9 => try b.add("\\t"), else => try b.data.append(w.a, c) }; try b.add("'"); return b.data.items;
    }
    fn write(w: *Writer, term: *Term, limit: usize, operand: bool) anyerror!Text {
        const t = term.deref();
        if (t.kind == .variable) { if (w.names.get(t)) |name| return name; const name = try std.fmt.allocPrint(w.a, "_G{d}", .{w.next}); w.next += 1; try w.names.put(w.a, t, name); return name; }
        if (t.kind == .integer) return std.fmt.allocPrint(w.a, "{d}", .{t.integer});
        if (t.kind == .atom) { const text = try w.atom(t.name); return if (operand and (reader.infix(t.name) != null or reader.prefix(t.name) != null)) std.fmt.allocPrint(w.a, "({s})", .{text}) else text; }
        var b: Buffer = .{ .a = w.a };
        if (t.is(".", 2)) { const parts = try terms.listParts(w.a, t); try b.add("["); for (parts.elements, 0..) |element, i| { if (i > 0) try b.add(","); try b.add(try w.write(element, 999, false)); } if (!parts.tail.is("[]", 0)) { try b.add("|"); try b.add(try w.write(parts.tail, 999, false)); } try b.add("]"); return b.data.items; }
        if (t.arguments.len == 2) if (reader.infix(t.name)) |op| {
            const left = try w.write(t.arguments[0], op.left, true); const right = try w.write(t.arguments[1], op.right, true);
            if (terms.eq(t.name, ",")) try b.print("{s},{s}", .{left, right})
            else if (std.ascii.isAlphabetic(t.name[0])) try b.print("{s} {s} {s}", .{left, t.name, right})
            else try b.print("{s}{s}{s}{s}{s}", .{left, if (left.len > 0 and reader.symbol(left[left.len - 1])) " " else "", t.name, if (right.len > 0 and reader.symbol(right[0])) " " else "", right});
            return if (op.priority > limit) std.fmt.allocPrint(w.a, "({s})", .{b.data.items}) else b.data.items;
        };
        if (t.arguments.len == 1) if (reader.prefix(t.name)) |priority| { const x = try w.write(t.arguments[0], priority, true); try b.print("{s}{s}{s}", .{t.name, if (x.len > 0 and (reader.symbol(x[0]) or std.ascii.isDigit(x[0]) or x[0] == '(')) " " else "", x}); return if (priority > limit) std.fmt.allocPrint(w.a, "({s})", .{b.data.items}) else b.data.items; };
        try b.add(try w.atom(t.name)); try b.add("("); for (t.arguments, 0..) |arg, i| { if (i > 0) try b.add(","); try b.add(try w.write(arg, 999, false)); } try b.add(")"); return b.data.items;
    }
};
fn written(a: std.mem.Allocator, t: *Term) !Text { var w: Writer = .{ .a = a }; return w.write(t, 1200, false); }
fn indicatorText(a: std.mem.Allocator, name: Text, arity: usize) !Text { return written(a, try terms.compound(a, "/", &.{try terms.atom(a, name), try terms.integer(a, @intCast(arity))})); }
const Consultant = struct {
    a: std.mem.Allocator, db: database.Database, report: Buffer, counts: [2][3]usize = @splat(@splat(0)), last: [2]?*database.Predicate = .{null, null},
    fn warning(c: *Consultant, file: usize, line: usize, message: Text) !void { c.counts[file][2] += 1; try c.report.print("{s}:{d}: warning: {s}\n", .{file_names[file], line, message}); }
    fn add(c: *Consultant, term: *Term, file: usize, line: usize, parsing: *reader.Reader) !void {
        var head = term; var body: ?*Term = null; if (term.is(":-", 2)) { head = term.arguments[0]; body = term.arguments[1]; }
        var fault: ?*Term = null;
        if (head.kind == .variable) fault = try terms.atom(c.a, "instantiation_error")
        else if (head.kind == .integer) fault = try terms.typeError(c.a, "callable", head)
        else if (predicates.control(head.name, head.arguments.len) or predicates.builtin(head.name, head.arguments.len)) fault = try terms.compound(c.a, "permission_error", &.{try terms.atom(c.a, "modify"), try terms.atom(c.a, "static_procedure"), try terms.indicator(c.a, head)})
        else if (body) |b| { body = try terms.convert(c.a, b); if (body == null) fault = try terms.typeError(c.a, "callable", b); }
        if (fault) |f| { c.counts[file][1] += 1; try c.report.print("{s}:{d}: error: {s}\n", .{file_names[file], line, try written(c.a, f)}); return; }
        const name = try indicatorText(c.a, head.name, head.arguments.len); const previous = c.db.find(head.name, head.arguments.len);
        if (previous) |p| {
            if (file == 1 and p.clauses.items.len > 0 and p.clauses.items[0].file == 0) { try c.warning(file, line, try std.fmt.allocPrint(c.a, "redefining prelude procedure {s}", .{name})); p.clauses.clearRetainingCapacity(); }
            var same_file = false; for (p.clauses.items) |clause| if (clause.file == file) { same_file = true; };
            if (same_file and c.last[file] != p and !p.discontiguous[file]) { try c.warning(file, line, try std.fmt.allocPrint(c.a, "clauses of {s} are not together", .{name})); p.discontiguous[file] = true; }
        }
        c.last[file] = try c.db.add(.{ .head = head, .body = body, .file = file, .line = line }); c.counts[file][0] += 1;
        for (0..2) |kind| { var names: std.ArrayList(Text) = .empty; for (parsing.names.items) |v| { if ((kind == 0 and v.name[0] != '_' and v.count == 1) or (kind == 1 and v.name.len > 1 and v.name[0] == '_' and v.count > 1)) try names.append(c.a, v.name); } if (names.items.len > 0) try c.warning(file, line, try std.fmt.allocPrint(c.a, "{s}{s}", .{if (kind == 0) "singleton variables: " else "variables starting with _ occur more than once: ", try std.mem.join(c.a, ", ", names.items)})); }
    }
    fn consult(c: *Consultant, file: usize, source: Text) !void {
        var parsing = try reader.Reader.init(c.a, source, 1); var lines: std.ArrayList(Text) = .empty; var it = std.mem.splitScalar(u8, source, '\n'); while (it.next()) |line| try lines.append(c.a, line);
        while (parsing.peek().kind != .eof) {
            const line = parsing.peek().line; const term = parsing.clause(false) catch |err| switch (err) {
                error.Syntax => blk: {
                    const token = parsing.issue; c.counts[file][1] += 1; try c.report.print("{s}:{d}:{d}: syntax error: {s}\n", .{file_names[file], token.line, token.column, parsing.message});
                    if (token.kind != .eof) { try c.report.print("    {s}\n", .{lines.items[token.line - 1]}); for (0..token.column + 3) |_| try c.report.add(" "); try c.report.line("^"); }
                    parsing.p = token.index; while (parsing.peek().kind != .end and parsing.peek().kind != .eof) parsing.p += 1; if (parsing.peek().kind == .end) parsing.p += 1; break :blk null;
                }, else => return err,
            };
            if (term) |t| try c.add(t, file, line, &parsing);
        }
    }
    fn finish(c: *Consultant) !void {
        var reported: std.StringHashMapUnmanaged(void) = .empty;
        for (c.db.predicates.items) |predicate| for (predicate.clauses.items) |clause| {
            var pending: std.ArrayList(*Term) = .empty; if (clause.body) |body| try pending.append(c.a, body);
            while (pending.pop()) |item| {
                const t = item.deref(); if (t.kind == .variable or t.kind == .integer) continue;
                if (t.is(",", 2) or t.is(";", 2) or t.is("->", 2)) { try pending.append(c.a, t.arguments[1]); try pending.append(c.a, t.arguments[0]); }
                else if (t.is("\\+", 1) or t.is("call", 1)) try pending.append(c.a, t.arguments[0])
                else if (t.is("findall", 3)) try pending.append(c.a, t.arguments[1])
                else if (t.is("catch", 3)) { try pending.append(c.a, t.arguments[2]); try pending.append(c.a, t.arguments[0]); }
                else if (!predicates.control(t.name, t.arguments.len) and !predicates.builtin(t.name, t.arguments.len) and c.db.find(t.name, t.arguments.len) == null) { const name = try indicatorText(c.a, t.name, t.arguments.len); if (!reported.contains(name)) { try reported.put(c.a, name, {}); try c.warning(clause.file, clause.line, try std.fmt.allocPrint(c.a, "undefined procedure {s} called from {s}", .{name, try indicatorText(c.a, predicate.name, predicate.arity)})); } }
            }
        };
        var clauses: usize = 0; for (c.db.predicates.items) |p| clauses += p.clauses.items.len;
        for (file_names, c.counts) |file, counts| try c.report.print("{s}: clauses={d} errors={d} warnings={d}\n", .{file, counts[0], counts[1], counts[2]}); try c.report.print("database: predicates={d} clauses={d}\n", .{c.db.predicates.items.len, clauses});
    }
};
fn listing(a: std.mem.Allocator, db: *database.Database) !Text {
    var b: Buffer = .{ .a = a };
    for (db.predicates.items, 0..) |p, pi| {
        if (pi > 0) try b.add("\n");
        for (p.clauses.items) |clause| {
            var occurrences: std.ArrayList(*Term) = .empty; try terms.variables(a, clause.head, &occurrences); if (clause.body) |body| try terms.variables(a, body, &occurrences); var w: Writer = .{ .a = a }; var count: usize = 0;
            for (occurrences.items) |v| {
                if (w.names.contains(v)) continue; var frequency: usize = 0; for (occurrences.items) |other| if (other == v) { frequency += 1; };
                var name: Text = "_"; if (frequency > 1) { name = if (count < 26) try std.fmt.allocPrint(a, "{c}", .{@as(u8, @intCast('A' + count % 26))}) else try std.fmt.allocPrint(a, "{c}{d}", .{@as(u8, @intCast('A' + count % 26)), count / 26}); count += 1; } try w.names.put(a, v, name);
            }
            const head = try w.write(clause.head, 1200, false);
            if (clause.body) |body| { try b.print("{s} :-\n", .{head}); var t = body; while (t.is(",", 2)) { try b.print("    {s},\n", .{try w.write(t.arguments[0], 999, false)}); t = t.arguments[1]; } try b.print("    {s}.\n", .{try w.write(t, 999, false)}); }
            else try b.print("{s}.\n", .{head});
        }
    }
    return b.data.items;
}
fn answer(a: std.mem.Allocator, vars: []const reader.Variable) !Text {
    var w: Writer = .{ .a = a }; for (vars) |v| { if (v.name[0] == '_') continue; const t = v.variable.deref(); if (t.kind == .variable and !w.names.contains(t)) try w.names.put(a, t, v.name); }
    var previous: std.AutoHashMapUnmanaged(*Term, Text) = .empty; var items: std.ArrayList(Text) = .empty;
    for (vars) |v| { if (v.name[0] == '_') continue; const t = v.variable.deref(); if (t.kind == .variable) { if (previous.get(t)) |name| try items.append(a, try std.fmt.allocPrint(a, "{s} = {s}", .{name, v.name})); try previous.put(a, t, v.name); } else try items.append(a, try std.fmt.allocPrint(a, "{s} = {s}", .{v.name, try w.write(t, 699, true)})); }
    return if (items.items.len == 0) "true" else std.mem.join(a, ", ", items.items);
}
const Profile = struct { name: Text, arity: usize, display: Text, calls: usize = 0, tries: usize = 0 };
const Goal = struct { term: ?*Term = null, marker: enum { none, ITE, NAF, EXIT, COLLECT } = .none, height: usize = 0, choice: ?*Choice = null, barrier: usize = 0, context: ?*Choice = null, next: ?*Goal = null };
const Choice = struct {
    kind: enum { ALT, CLAUSES, BETWEEN, LENGTH, CATCH, FINDALL }, mark: usize, resume_list: ?*Goal,
    goal: ?*Term = null, candidates: []const database.Clause = &.{}, next_candidate: usize = 1, barrier: usize = 0, context: ?*Choice = null,
    target: ?*Term = null, upper: i64 = 0, next_value: i64 = 0, tail: ?*Term = null, number: ?*Term = null, count: usize = 0,
    catcher: ?*Term = null, recovery: ?*Term = null, parent: ?*Choice = null, template: ?*Term = null, result: ?*Term = null, results: std.ArrayList(*Term) = .empty,
};
const Engine = struct {
    a: std.mem.Allocator, db: *database.Database, variables: []const reader.Variable, limit: ?usize, profiles: *std.ArrayList(Profile),
    trail: unify.Trail, goals: ?*Goal = null, choices: std.ArrayList(*Choice) = .empty, context: ?*Choice = null,
    current_name: Text = "", current_arity: usize = 0, ball: ?*Term = null, counts: [4]usize = @splat(0), answers: Buffer, output: Buffer,
    fn prepend(e: *Engine, continuation: ?*Goal, value: Goal) !*Goal { const g = try e.a.create(Goal); g.* = value; g.next = continuation; return g; }
    fn entry(e: *Engine, continuation: ?*Goal, term: *Term, barrier: usize, context: ?*Choice) !*Goal { return e.prepend(continuation, .{ .term = term, .barrier = barrier, .context = context }); }
    fn create(e: *Engine, choice: Choice) !*Choice { const p = try e.a.create(Choice); p.* = choice; p.mark = e.trail.mark(); try e.choices.append(e.a, p); e.counts[2] += 1; return p; }
    fn profile(e: *Engine, name: Text, arity: usize) !usize { for (e.profiles.items, 0..) |p, i| if (terms.eq(p.name, name) and p.arity == arity) return i; try e.profiles.append(e.a, .{ .name = name, .arity = arity, .display = try indicatorText(e.a, name, arity) }); return e.profiles.items.len - 1; }
    fn infer(e: *Engine, name: Text, arity: usize) !void { if (e.counts[1] == 20000) return error.Limit; e.counts[1] += 1; const index = try e.profile(name, arity); e.profiles.items[index].calls += 1; e.current_name = name; e.current_arity = arity; }
    pub fn fault(e: *Engine, term: *Term) error{Fault} { e.ball = term; return error.Fault; }
    pub fn writeOutput(e: *Engine, term: ?*Term, quoted: bool) !void { if (term) |t| { var w: Writer = .{ .a = e.a, .quoted = quoted }; try e.output.add(try w.write(t, 1200, false)); } else try e.output.add("\n"); }
    fn cut(e: *Engine, height: usize) void { e.choices.items.len = @min(height, e.choices.items.len); }
    fn tryClause(e: *Engine, clause: database.Clause, goal: *Term, barrier: usize, context: ?*Choice, continuation: ?*Goal) !bool {
        const index = try e.profile(goal.name, goal.arguments.len); e.profiles.items[index].tries += 1; const copied = try clause.copy(e.a); if (!try e.trail.unify(copied.head, goal)) return false;
        e.goals = if (copied.body) |body| try e.entry(continuation, body, barrier, context) else continuation; return true;
    }
    fn userCall(e: *Engine, goal: *Term, context: ?*Choice) !bool {
        if (e.db.find(goal.name, goal.arguments.len) == null) return e.fault(try terms.compound(e.a, "existence_error", &.{try terms.atom(e.a, "procedure"), try terms.indicator(e.a, goal)}));
        const candidates = try e.db.candidates(goal); if (candidates.len == 0) return false; const height = e.choices.items.len;
        if (candidates.len > 1) _ = try e.create(.{ .kind = .CLAUSES, .mark = 0, .resume_list = e.goals, .goal = goal, .candidates = candidates, .barrier = height, .context = context });
        return e.tryClause(candidates[0], goal, height, context, e.goals);
    }
    fn control(e: *Engine, g: *Term, barrier: usize, context: ?*Choice) !bool {
        const args = g.arguments; const continuation = e.goals; const height = e.choices.items.len;
        if (g.is(",", 2)) e.goals = try e.entry(try e.entry(continuation, args[1], barrier, context), args[0], barrier, context)
        else if (g.is("!", 0)) e.cut(barrier)
        else if (g.is(";", 2)) {
            _ = try e.create(.{ .kind = .ALT, .mark = 0, .resume_list = try e.entry(continuation, args[1], barrier, context) }); const left = args[0].deref();
            if (left.is("->", 2)) { const then = try e.entry(continuation, left.arguments[1], barrier, context); const marker = try e.prepend(then, .{ .marker = .ITE, .height = height }); e.goals = try e.entry(marker, left.arguments[0], height + 1, context); }
            else e.goals = try e.entry(continuation, left, barrier, context);
        } else if (g.is("->", 2)) { const then = try e.entry(continuation, args[1], barrier, context); const marker = try e.prepend(then, .{ .marker = .ITE, .height = height }); e.goals = try e.entry(marker, args[0], height, context); }
        else if (g.is("\\+", 1)) { _ = try e.create(.{ .kind = .ALT, .mark = 0, .resume_list = continuation }); const marker = try e.prepend(continuation, .{ .marker = .NAF, .height = height }); e.goals = try e.entry(marker, try terms.compound(e.a, "call", &.{args[0]}), barrier, context); }
        else if (terms.eq(g.name, "call")) {
            e.current_name = "call"; e.current_arity = args.len; var target = args[0].deref();
            if (target.kind == .variable) return e.fault(try terms.atom(e.a, "instantiation_error")); if (target.kind == .integer) return e.fault(try terms.typeError(e.a, "callable", target));
            if (args.len > 1) target = try terms.compound(e.a, target.name, try std.mem.concat(e.a, *Term, &.{target.arguments, args[1..]}));
            const converted = (try terms.convert(e.a, target)) orelse return e.fault(try terms.typeError(e.a, "callable", target)); e.goals = try e.entry(continuation, converted, height, context);
        } else if (g.is("catch", 3)) {
            const frame = try e.create(.{ .kind = .CATCH, .mark = 0, .resume_list = continuation, .catcher = args[1], .recovery = args[2], .parent = context }); const marker = try e.prepend(continuation, .{ .marker = .EXIT, .choice = frame, .context = context }); e.goals = try e.entry(marker, try terms.compound(e.a, "call", &.{args[0]}), barrier, frame);
        }
        return true;
    }
    fn between(e: *Engine, args: []*Term) !bool {
        const lower = try predicates.integer(e, args[0]); const upper = try predicates.integer(e, args[1]); const value = args[2].deref();
        if (value.kind != .variable and value.kind != .integer) return e.fault(try terms.typeError(e.a, "integer", value)); if (value.kind == .integer) return lower <= value.integer and value.integer <= upper;
        if (lower > upper) return false; if (lower < upper) _ = try e.create(.{ .kind = .BETWEEN, .mark = 0, .resume_list = e.goals, .upper = upper, .target = value, .next_value = lower + 1 }); return e.trail.unify(value, try terms.integer(e.a, lower));
    }
    fn freshList(e: *Engine, n: usize) !*Term { const elements = try e.a.alloc(*Term, n); for (elements) |*t| t.* = try terms.variable(e.a); return terms.list(e.a, elements, null); }
    fn length(e: *Engine, args: []*Term) !bool {
        const number = args[1].deref(); if (number.kind != .variable and number.kind != .integer) return e.fault(try terms.typeError(e.a, "integer", number)); if (number.kind == .integer and number.integer < 0) return e.fault(try terms.domainError(e.a, "not_less_than_zero", number));
        const parts = try terms.listParts(e.a, args[0]); const count = parts.elements.len;
        if (parts.tail.is("[]", 0)) return e.trail.unify(number, try terms.integer(e.a, @intCast(count))); if (parts.tail.kind != .variable) return e.fault(try terms.typeError(e.a, "list", args[0]));
        if (number.kind == .integer) { if (number.integer < @as(i64, @intCast(count))) return false; return e.trail.unify(parts.tail, try e.freshList(@intCast(number.integer - @as(i64, @intCast(count))))); }
        _ = try e.create(.{ .kind = .LENGTH, .mark = 0, .resume_list = e.goals, .tail = parts.tail, .number = number, .count = count, .next_value = @as(i64, @intCast(count)) + 1 }); return (try e.trail.unify(parts.tail, try terms.atom(e.a, "[]"))) and (try e.trail.unify(number, try terms.integer(e.a, @intCast(count))));
    }
    fn step(e: *Engine) !bool {
        const selected = e.goals.?; e.goals = selected.next; e.context = selected.context;
        switch (selected.marker) {
            .ITE => { e.cut(selected.height); return true; }, .NAF => { e.cut(selected.height); return false; },
            .EXIT => { if (e.choices.items.len > 0 and e.choices.items[e.choices.items.len - 1] == selected.choice.?) _ = e.choices.pop(); return true; },
            .COLLECT => { const choice = selected.choice.?; try choice.results.append(e.a, try terms.copy(e.a, choice.template.?)); return false; }, .none => {},
        }
        const goal = selected.term.?.deref(); if (predicates.control(goal.name, goal.arguments.len)) return e.control(goal, selected.barrier, selected.context);
        try e.infer(goal.name, goal.arguments.len); const args = goal.arguments;
        if (goal.is("findall", 3)) {
            const frame = try e.create(.{ .kind = .FINDALL, .mark = 0, .resume_list = e.goals, .template = args[0], .result = args[2] }); const marker = try e.prepend(null, .{ .marker = .COLLECT, .choice = frame }); e.goals = try e.entry(marker, try terms.compound(e.a, "call", &.{args[1]}), selected.barrier, selected.context); return true;
        }
        if (goal.is("throw", 1)) { const ball = args[0].deref(); if (ball.kind == .variable) return e.fault(try terms.atom(e.a, "instantiation_error")); e.ball = ball; return error.Thrown; }
        if (goal.is("between", 3)) return e.between(args); if (goal.is("length", 2)) return e.length(args); if (predicates.deterministic(goal.name, args.len)) return predicates.execute(e, goal); return e.userCall(goal, selected.context);
    }
    fn backtrack(e: *Engine) !bool {
        while (true) {
            e.counts[3] += 1;
            while (e.choices.items.len > 0) { const choice = e.choices.items[e.choices.items.len - 1]; e.trail.undo(choice.mark); if (choice.kind != .CATCH) break; _ = e.choices.pop(); }
            if (e.choices.items.len == 0) return false; const choice = e.choices.items[e.choices.items.len - 1];
            switch (choice.kind) {
                .ALT => { _ = e.choices.pop(); e.goals = choice.resume_list; return true; },
                .CLAUSES => { const clause = choice.candidates[choice.next_candidate]; choice.next_candidate += 1; if (choice.next_candidate == choice.candidates.len) _ = e.choices.pop(); if (try e.tryClause(clause, choice.goal.?, choice.barrier, choice.context, choice.resume_list)) return true; },
                .BETWEEN => { try e.infer("between", 3); const v = choice.next_value; if (v == choice.upper) _ = e.choices.pop() else choice.next_value += 1; if (try e.trail.unify(choice.target.?, try terms.integer(e.a, v))) { e.goals = choice.resume_list; return true; } },
                .LENGTH => { try e.infer("length", 2); const n = choice.next_value; choice.next_value += 1; if ((try e.trail.unify(choice.tail.?, try e.freshList(@intCast(n - @as(i64, @intCast(choice.count)))))) and (try e.trail.unify(choice.number.?, try terms.integer(e.a, n)))) { e.goals = choice.resume_list; return true; } },
                .FINDALL => { _ = e.choices.pop(); if (try e.trail.unify(try terms.list(e.a, choice.results.items, null), choice.result.?)) { e.goals = choice.resume_list; return true; } },
                .CATCH => unreachable,
            }
        }
    }
    fn exception(e: *Engine, original: *Term) !bool {
        const ball = try terms.copy(e.a, original); var context = e.context;
        while (context) |frame| {
            var index: usize = 0; while (index < e.choices.items.len and e.choices.items[index] != frame) index += 1; e.cut(index); e.trail.undo(frame.mark); const mark = e.trail.mark();
            if (try e.trail.unify(try terms.copy(e.a, ball), frame.catcher.?)) { e.goals = try e.entry(frame.resume_list, try terms.compound(e.a, "call", &.{frame.recovery.?}), e.choices.items.len, frame.parent); return true; }
            e.trail.undo(mark); context = frame.parent;
        }
        try e.answers.print("uncaught exception: {s}\n", .{try written(e.a, ball)}); return false;
    }
    fn cycle(e: *Engine) !bool {
        if (e.goals == null) {
            e.counts[0] += 1; const text = try answer(e.a, e.variables); if ((e.limit != null and e.counts[0] == e.limit.?) or e.choices.items.len == 0) { try e.answers.print("{s}.\n", .{text}); return false; }
            try e.answers.print("{s} ;\n", .{text}); if (!try e.backtrack()) { try e.answers.line("false."); return false; }
        } else if (!try e.step()) { if (!try e.backtrack()) { try e.answers.line("false."); return false; } }
        return true;
    }
    fn run(e: *Engine) !void {
        execution: while (true) {
            const active = e.cycle() catch |err| switch (err) {
                error.Limit => { try e.answers.line("inference limit exceeded"); break :execution; },
                error.Fault, error.Thrown => {
                    const ball = if (err == error.Fault) try terms.compound(e.a, "error", &.{e.ball.?, try terms.compound(e.a, "/", &.{try terms.atom(e.a, e.current_name), try terms.integer(e.a, @intCast(e.current_arity))})}) else e.ball.?;
                    if (try e.exception(ball)) continue :execution else break :execution;
                }, else => return err,
            };
            if (!active) break;
        }
    }
};
fn statistics(b: *Buffer, prefix: Text, c: [4]usize) !void { try b.print("{s} solutions={d} inferences={d} choicepoints={d} backtracks={d}\n", .{prefix, c[0], c[1], c[2], c[3]}); }
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa); defer arena.deinit(); const a = arena.allocator();
    var consultant: Consultant = .{ .a = a, .db = .{ .a = a }, .report = .{ .a = a } };
    for (file_names, 0..) |name, index| try consultant.consult(index, try std.Io.Dir.cwd().readFileAlloc(init.io, try std.fmt.allocPrint(a, "input/{s}", .{name}), a, .unlimited)); try consultant.finish();
    var answers: Buffer = .{ .a = a }; var writes: Buffer = .{ .a = a }; var stats: Buffer = .{ .a = a }; var profiles: std.ArrayList(Profile) = .empty; var totals: [4]usize = @splat(0);
    const source = try std.Io.Dir.cwd().readFileAlloc(init.io, "input/queries.txt", a, .unlimited); var lines = std.mem.tokenizeScalar(u8, source, '\n'); var number: usize = 0;
    while (lines.next()) |line| {
        number += 1; try answers.line(line); try writes.print("== query {d} ==\n", .{number}); const marker = std.mem.indexOf(u8, line, "?- ").?; const start = marker + 3; const limit: ?usize = if (marker == 0) null else try std.fmt.parseInt(usize, std.mem.trim(u8, line[0..marker], " "), 10);
        var parsing = try reader.Reader.init(a, line[start..], start + 1); const query = parsing.clause(true) catch |err| switch (err) { error.Syntax => { try answers.print("syntax error at column {d}: {s}\n", .{parsing.issue.column, parsing.message}); try stats.print("query {d}: syntax error\n", .{number}); continue; }, else => return err };
        var engine: Engine = .{ .a = a, .db = &consultant.db, .variables = parsing.names.items, .limit = limit, .profiles = &profiles, .trail = .{ .a = a }, .answers = .{ .a = a }, .output = .{ .a = a } };
        engine.goals = try engine.entry(null, try terms.compound(a, "call", &.{query}), 0, null); try engine.run(); for (engine.counts, 0..) |c, i| totals[i] += c;
        try answers.add(engine.answers.data.items); try writes.add(engine.output.data.items); if (engine.output.data.items.len > 0 and engine.output.data.items[engine.output.data.items.len - 1] != 10) try writes.add("\n"); try statistics(&stats, try std.fmt.allocPrint(a, "query {d}:", .{number}), engine.counts);
    }
    try statistics(&stats, "total:", totals); try stats.line("== profile =="); std.mem.sort(Profile, profiles.items, {}, struct { fn cmp(_: void, x: Profile, y: Profile) bool { return if (x.calls == y.calls) std.mem.order(u8, x.display, y.display) == .lt else x.calls > y.calls; } }.cmp);
    for (profiles.items) |profile| { try stats.print("{s} calls={d}", .{profile.display, profile.calls}); if (consultant.db.find(profile.name, profile.arity) != null) try stats.print(" tries={d}", .{profile.tries}); try stats.add("\n"); }
    for ([_]Text{"consult.txt", "listing.txt", "answers.txt", "write_output.txt", "stats.txt"}, [_]Text{consultant.report.data.items, try listing(a, &consultant.db), answers.data.items, writes.data.items, stats.data.items}) |name, data| { const file = try std.Io.Dir.cwd().createFile(init.io, try std.fmt.allocPrint(a, "output/{s}", .{name}), .{}); defer file.close(init.io); try file.writeStreamingAll(init.io, data); }
}
