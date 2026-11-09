const std = @import("std");
const chars = @import("charset.zig");
const code = @import("compiler.zig");
const fmt = @import("formatter.zig");
const back = @import("backtrack_vm.zig");
const pike = @import("pike_vm.zig");
const Text = []const u8;
const Name = struct { name: Text, group: usize };
const Pattern = struct { name: Text, flags: Text, text: Text, groups: usize = 0, names: []const Name = &.{}, root: ?*code.Node = null, program: []const code.Instruction = &.{}, compatible: bool = true, message: ?Text = null, column: usize = 0 };
const Parser = struct {
    a: std.mem.Allocator, text: Text, p: usize = 0, groups: usize = 0, names: std.ArrayList(Name) = .empty, refs: std.ArrayList(*code.Node) = .empty, message: Text = "", column: usize = 0,
    fn peek(p: *Parser) u8 { return if (p.p < p.text.len) p.text[p.p] else 0; }
    fn fail(p: *Parser, message: Text, column: usize) error{InvalidPattern} { p.message = message; p.column = column; return error.InvalidPattern; }
    fn node(p: *Parser, n: code.Node) !*code.Node { const result = try p.a.create(code.Node); result.* = n; return result; }
    fn digits(p: *Parser) Text { const start = p.p; while (std.ascii.isDigit(p.peek())) p.p += 1; return p.text[start..p.p]; }
    fn name(p: *Parser) !Text {
        if (!std.ascii.isAlphabetic(p.peek()) and p.peek() != '_') return p.fail("invalid group name", p.p + 1);
        const start = p.p; while (std.ascii.isAlphanumeric(p.peek()) or p.peek() == '_') p.p += 1;
        if (p.peek() != '>') return p.fail("invalid group name", p.p + 1);
        const value = p.text[start..p.p]; p.p += 1; return value;
    }
    fn alternate(p: *Parser) anyerror!*code.Node {
        var list: std.ArrayList(*code.Node) = .empty; try list.append(p.a, try p.concat());
        while (p.peek() == '|') { p.p += 1; try list.append(p.a, try p.concat()); }
        return if (list.items.len == 1) list.items[0] else p.node(.{ .kind = .alternation, .children = list.items });
    }
    fn concat(p: *Parser) anyerror!*code.Node {
        var list: std.ArrayList(*code.Node) = .empty;
        while (p.peek() != 0 and p.peek() != '|' and p.peek() != ')') try list.append(p.a, try p.quantified());
        return if (list.items.len == 1) list.items[0] else p.node(.{ .kind = .concat, .children = list.items });
    }
    fn quantifier(c: u8) bool { return c == '*' or c == '+' or c == '?' or c == '{'; }
    fn quantified(p: *Parser) anyerror!*code.Node {
        if (quantifier(p.peek())) return p.fail("nothing to repeat", p.p + 1);
        const base = try p.element(); if (!quantifier(p.peek())) return base;
        if (base.kind == .assertion or base.kind == .look) return p.fail("nothing to repeat", p.p + 1);
        const column = p.p + 1; const c = p.peek(); p.p += 1; var lower: usize = 0; var upper: ?usize = null;
        switch (c) {
            '*' => {}, '+' => lower = 1, '?' => upper = 1,
            else => {
                const low_digits = p.digits(); if (low_digits.len == 0) return p.fail("invalid quantifier", column); lower = try std.fmt.parseInt(usize, low_digits, 10);
                if (p.peek() == '}') upper = lower else if (p.peek() == ',') { p.p += 1; if (p.peek() != '}') { const high = p.digits(); if (high.len == 0) return p.fail("invalid quantifier", column); upper = try std.fmt.parseInt(usize, high, 10); } } else return p.fail("invalid quantifier", column);
                if (p.peek() != '}') return p.fail("invalid quantifier", column); p.p += 1;
                if (lower > 100 or (upper != null and upper.? > 100)) return p.fail("quantifier too large", column);
                if (upper != null and lower > upper.?) return p.fail("quantifier range out of order", column);
            },
        }
        var n: code.Node = .{ .kind = .repeat, .child = base, .lower = lower, .upper = upper };
        if (p.peek() == '?') { p.p += 1; n.mode = .lazy; } else if (p.peek() == '+') { p.p += 1; n.mode = .possessive; }
        if (quantifier(p.peek())) return p.fail("nested quantifier", p.p + 1);
        return p.node(n);
    }
    fn group(p: *Parser) anyerror!*code.Node {
        const column = p.p + 1; p.p += 1; var special: u8 = 0; var named: ?Text = null;
        if (p.peek() == '?') {
            p.p += 1; special = p.peek(); if (std.mem.indexOfScalar(u8, ":=!<", special) == null or special == 0) return p.fail("invalid group", column); p.p += 1;
            if (special == '<') { const nc = p.p + 1; named = try p.name(); for (p.names.items) |n| if (std.mem.eql(u8, n.name, named.?)) return p.fail("duplicate group name", nc); }
        }
        var number: usize = 0;
        if (special == 0 or special == '<') { p.groups += 1; number = p.groups; if (named) |n| try p.names.append(p.a, .{ .name = n, .group = number }); }
        const content = try p.alternate(); if (p.peek() != ')') return p.fail("missing )", column); p.p += 1;
        if (special == ':') return content;
        if (special == '=' or special == '!') return p.node(.{ .kind = .look, .neg = special == '!', .child = content });
        return p.node(.{ .kind = .group, .value = number, .child = content });
    }
    const Item = struct { set: chars.Set, single: ?u8 };
    fn item(p: *Parser) !Item {
        var c = p.peek(); p.p += 1; var set = chars.Set.initEmpty();
        if (c == '\\') {
            const column = p.p; c = p.peek(); if (c == 0) return p.fail("trailing backslash", column); p.p += 1;
            if (std.mem.indexOfScalar(u8, "dDwWsS", c) != null) { set = chars.standard(c); if (std.ascii.isUpper(c)) set.toggleAll(); return .{ .set = set, .single = null }; }
            if (c == 'n') c = 10 else if (c == 't') c = 9 else if (std.ascii.isAlphanumeric(c)) return p.fail("invalid escape", column);
        }
        set.set(c); return .{ .set = set, .single = c };
    }
    fn characterClass(p: *Parser) !*code.Node {
        const column = p.p + 1; p.p += 1; const neg = p.peek() == '^'; if (neg) p.p += 1;
        if (p.peek() == ']') return p.fail("empty class", p.p + 1);
        var set = chars.Set.initEmpty();
        while (true) {
            if (p.peek() == 0) return p.fail("missing ]", column); if (p.peek() == ']') { p.p += 1; break; }
            const first = try p.item();
            if (p.peek() == '-' and p.p + 1 < p.text.len and p.text[p.p + 1] != ']') {
                const dash = p.p + 1; p.p += 1; if (first.single == null) return p.fail("invalid range", dash); const last = try p.item();
                if (last.single == null or first.single.? > last.single.?) return p.fail("invalid range", dash);
                for (first.single.?..@as(usize, last.single.?) + 1) |c| set.set(c);
            } else set.setUnion(first.set);
        }
        return p.node(.{ .kind = .class, .set = set, .neg = neg });
    }
    fn escape(p: *Parser) !*code.Node {
        const column = p.p + 1; p.p += 1; var c = p.peek(); if (c == 0) return p.fail("trailing backslash", column); p.p += 1;
        if (std.mem.indexOfScalar(u8, "dDwWsS", c) != null) return p.node(.{ .kind = .class, .set = chars.standard(c), .neg = std.ascii.isUpper(c) });
        if (c == 'b' or c == 'B') return p.node(.{ .kind = .assertion, .value = @intFromEnum(if (c == 'b') chars.Assertion.WORD else chars.Assertion.NOTWORD) });
        if ((c >= '1' and c <= '9') or c == 'k') {
            var n: code.Node = .{ .kind = .backref, .column = column };
            if (c == 'k') { if (p.peek() != '<') return p.fail("invalid escape", column); p.p += 1; n.name = try p.name(); }
            else { const start = p.p - 1; _ = p.digits(); n.value = try std.fmt.parseInt(usize, p.text[start..p.p], 10); }
            const result = try p.node(n); try p.refs.append(p.a, result); return result;
        }
        if (c == 'n') c = 10 else if (c == 't') c = 9 else if (std.ascii.isAlphanumeric(c)) return p.fail("invalid escape", column);
        return p.node(.{ .kind = .literal, .value = c });
    }
    fn element(p: *Parser) anyerror!*code.Node {
        const c = p.peek(); switch (c) { '(' => return p.group(), '[' => return p.characterClass(), '\\' => return p.escape(), else => {} }
        p.p += 1; return p.node(switch (c) { '.' => .{ .kind = .any }, '^' => .{ .kind = .assertion, .value = @intFromEnum(chars.Assertion.BOL) }, '$' => .{ .kind = .assertion, .value = @intFromEnum(chars.Assertion.EOL) }, else => .{ .kind = .literal, .value = c } });
    }
    fn parse(p: *Parser) !*code.Node {
        const root = try p.alternate(); if (p.peek() != 0) return p.fail("unmatched )", p.p + 1);
        for (p.refs.items) |ref| {
            if (ref.name) |ref_name| { var found = false; for (p.names.items) |n| if (std.mem.eql(u8, ref_name, n.name)) { ref.value = n.group; found = true; break; }; if (!found) return p.fail("unknown group name", ref.column); }
            else if (ref.value > p.groups) return p.fail("invalid group reference", ref.column);
        }
        return root;
    }
};
const Part = union(enum) { literal: u8, group: usize };
fn template(a: std.mem.Allocator, text: Text, pat: Pattern) !?[]const Part {
    var parts: std.ArrayList(Part) = .empty; var p: usize = 0;
    while (p < text.len) {
        if (text[p] != '$') { try parts.append(a, .{ .literal = text[p] }); p += 1; continue; }
        p += 1; if (p == text.len) return null;
        if (text[p] == '$') { try parts.append(a, .{ .literal = '$' }); p += 1; continue; }
        var group: ?usize = null;
        if (std.ascii.isDigit(text[p])) { group = text[p] - '0'; p += 1; }
        else if (text[p] == '{') {
            const end = std.mem.indexOfScalarPos(u8, text, p + 1, '}') orelse return null; const name = text[p + 1..end];
            var numeric = name.len > 0; for (name) |c| if (!std.ascii.isDigit(c)) { numeric = false; };
            group = if (numeric) std.fmt.parseInt(usize, name, 10) catch null else null;
            if (group == null) for (pat.names) |n| { if (std.mem.eql(u8, name, n.name)) group = n.group; };
            p = end + 1;
        } else return null;
        if (group == null or group.? > pat.groups) return null; try parts.append(a, .{ .group = group.? });
    }
    return parts.items;
}
fn scan(a: std.mem.Allocator, vm: anytype, once: bool) ![]const back.Captures {
    var matches: std.ArrayList(back.Captures) = .empty; var start: usize = 0;
    while (start <= vm.text.len) { const captures = (try vm.search(start)) orelse break; try matches.append(a, captures); if (once) break; start = @as(usize, @intCast(captures[1])) + @intFromBool(captures[0] == captures[1]); }
    return matches.items;
}
fn matchLines(b: *fmt.Buffer, pat: Pattern, text: Text, captures: back.Captures) !void {
    for (0..pat.groups + 1) |k| { const first = captures[k * 2]; const last = captures[k * 2 + 1]; if (k == 0) try b.add("match") else try b.print("group {d}", .{k}); if (first < 0 or last < 0) try b.line(" -") else try b.print(" {d}-{d} {s}\n", .{first, last, try fmt.quoted(b.a, text[@intCast(first)..@intCast(last)])}); }
}
fn listing(b: *fmt.Buffer, p: Pattern) !void {
    const prop = code.properties(p.root.?, p.flags); var names: fmt.Buffer = .{ .a = b.a };
    for (p.names, 0..) |n, i| { if (i > 0) try names.add(","); try names.print("{s}:{d}", .{n.name, n.group}); }
    try b.print("=== {s}\nflags={s} groups={d} names={s} length={d}..{s} first={s} pike={s} size={d}\n", .{p.name, p.flags, p.groups, if (p.names.len == 0) "-" else names.data.items, prop.min, if (prop.max) |m| try std.fmt.allocPrint(b.a, "{d}", .{m}) else "inf", if (prop.first.count() == 0) "-" else try fmt.set(b.a, prop.first, false), if (p.compatible) "yes" else "no", p.program.len});
    for (p.program, 0..) |ins, i| try b.print("{d} {s}\n", .{i, try fmt.instruction(b.a, ins)});
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa); defer arena.deinit(); const a = arena.allocator();
    const sources = try std.Io.Dir.cwd().readFileAlloc(init.io, "input/patterns.txt", a, .unlimited);
    var patterns: std.ArrayList(Pattern) = .empty; var lines = std.mem.tokenizeScalar(u8, sources, '\n');
    var errors: fmt.Buffer = .{ .a = a };
    while (lines.next()) |line| {
        const first = std.mem.indexOfScalar(u8, line, ' ').?; const second = std.mem.indexOfScalarPos(u8, line, first + 1, ' ').?;
        var p: Pattern = .{ .name = line[0..first], .flags = line[first + 1..second], .text = line[second + 1..] }; var parser: Parser = .{ .a = a, .text = p.text };
        p.root = parser.parse() catch |err| switch (err) { error.InvalidPattern => null, else => return err };
        if (p.root) |root| { p.groups = parser.groups; p.names = parser.names.items; var builder: code.Builder = .{ .a = a }; p.program = try builder.compile(root); for (p.program) |ins| if (ins.op == .LOOK or ins.op == .BACKREF) { p.compatible = false; }; }
        else { p.message = parser.message; p.column = parser.column; try errors.print("{s}: {s} at column {d}\n  {s}\n  ", .{p.name, parser.message, parser.column, p.text}); for (1..p.column) |_| try errors.add(" "); try errors.line("^"); }
        try patterns.append(a, p);
    }
    var subjects: std.StringHashMapUnmanaged(Text) = .empty;
    lines = std.mem.tokenizeScalar(u8, try std.Io.Dir.cwd().readFileAlloc(init.io, "input/subjects.txt", a, .unlimited), '\n');
    while (lines.next()) |line| { const space = std.mem.indexOfScalar(u8, line, ' ').?; try subjects.put(a, line[0..space], try fmt.decode(a, line[space + 1..])); }
    var results: fmt.Buffer = .{ .a = a }; var programs: fmt.Buffer = .{ .a = a }; var steps: fmt.Buffer = .{ .a = a }; try steps.line("command,engine,steps");
    lines = std.mem.tokenizeScalar(u8, try std.Io.Dir.cwd().readFileAlloc(init.io, "input/commands.txt", a, .unlimited), '\n'); var number: usize = 0;
    while (lines.next()) |line| {
        number += 1; try results.print("#{d} {s}\n", .{number, line}); var words = std.mem.splitScalar(u8, line, ' '); const command = words.next().?; const replacing = std.mem.eql(u8, command, "REPLACE"); const mode = if (replacing) words.next().? else ""; const name = words.next().?;
        var pat: Pattern = undefined; for (patterns.items) |p| if (std.mem.eql(u8, name, p.name)) { pat = p; break; };
        if (pat.message != null) { try results.line("invalid pattern"); continue; }
        if (std.mem.eql(u8, command, "LIST")) { try results.print("instructions {d}\n", .{pat.program.len}); try listing(&programs, pat); continue; }
        const text = subjects.get(words.next().?).?; var parts: []const Part = &.{};
        if (replacing) { parts = (try template(a, try fmt.decode(a, words.rest()), pat)) orelse { try results.line("invalid template"); continue; }; }
        const full = std.mem.eql(u8, command, "MATCH"); const once = full or std.mem.eql(u8, command, "SEARCH") or (replacing and std.mem.eql(u8, mode, "FIRST"));
        var bt: back.VM = .{ .a = a, .program = pat.program, .flags = pat.flags, .text = text, .full = full }; var aborted = false;
        var matches = scan(a, &bt, once) catch |err| switch (err) { error.TooManySteps => blk: { aborted = true; break :blk &.{}; }, else => return err }; try steps.print("{d},backtrack,{d}\n", .{number, bt.steps});
        var engine: Text = "backtrack";
        if (pat.compatible) {
            var pk: pike.VM = .{ .a = a, .program = pat.program, .flags = pat.flags, .text = text, .full = full }; const other = try scan(a, &pk, once); try steps.print("{d},pike,{d}\n", .{number, pk.steps});
            var equal = matches.len == other.len; if (equal) for (matches, other) |x, y| { if (!std.mem.eql(i16, x[0..], y[0..])) equal = false; };
            if (!aborted and !equal) { try results.line("MISMATCH"); continue; }
            matches = other; engine = if (aborted) "pike (backtrack: TOO_MANY_STEPS)" else "both";
        } else if (aborted) { try results.line("TOO_MANY_STEPS"); continue; }
        try results.print("engine {s}\n", .{engine});
        if (full or std.mem.eql(u8, command, "SEARCH")) { if (matches.len == 0) try results.line("no match") else try matchLines(&results, pat, text, matches[0]); }
        else if (std.mem.eql(u8, command, "FINDALL")) { try results.print("matches {d}\n", .{matches.len}); for (matches) |c| try matchLines(&results, pat, text, c); }
        else if (replacing) {
            var out: fmt.Buffer = .{ .a = a }; var previous: usize = 0;
            for (matches) |c| { try out.add(text[previous..@intCast(c[0])]); for (parts) |part| switch (part) { .literal => |ch| try out.data.append(a, ch), .group => |g| { const x = c[g * 2]; const y = c[g * 2 + 1]; if (x >= 0 and y >= 0) try out.add(text[@intCast(x)..@intCast(y)]); } }; previous = @intCast(c[1]); }
            try out.add(text[previous..]); try results.print("replacements {d}\nresult {s}\n", .{matches.len, try fmt.quoted(a, out.data.items)});
        } else {
            try results.print("pieces {d}\n", .{matches.len + 1}); var previous: usize = 0;
            for (matches) |c| { try results.print("piece {s}\n", .{try fmt.quoted(a, text[previous..@intCast(c[0])])}); for (1..pat.groups + 1) |k| { const x = c[2 * k]; const y = c[2 * k + 1]; try results.print("group {d} {s}\n", .{k, if (x < 0 or y < 0) "-" else try fmt.quoted(a, text[@intCast(x)..@intCast(y)])}); } previous = @intCast(c[1]); }
            try results.print("piece {s}\n", .{try fmt.quoted(a, text[previous..])});
        }
    }
    if (programs.data.items.len == 0) try programs.line("no programs"); if (errors.data.items.len == 0) try errors.line("no errors");
    for ([_]Text{"results.txt", "programs.txt", "steps.csv", "errors.txt"}, [_]Text{results.data.items, programs.data.items, steps.data.items, errors.data.items}) |name, data| {
        const file = try std.Io.Dir.cwd().createFile(init.io, try std.fmt.allocPrint(a, "output/{s}", .{name}), .{}); defer file.close(init.io); try file.writeStreamingAll(init.io, data);
    }
}
