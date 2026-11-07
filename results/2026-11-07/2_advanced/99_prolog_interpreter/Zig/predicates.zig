const std = @import("std");
const terms = @import("terms.zig");
const unify = @import("unify.zig");
const Term = terms.Term;
pub fn deterministic(name: terms.Text, arity: usize) bool {
    const entries = [_]struct { name: terms.Text, arity: usize }{
        .{ .name = "true", .arity = 0 }, .{ .name = "fail", .arity = 0 }, .{ .name = "false", .arity = 0 }, .{ .name = "=", .arity = 2 }, .{ .name = "\\=", .arity = 2 }, .{ .name = "==", .arity = 2 }, .{ .name = "\\==", .arity = 2 },
        .{ .name = "var", .arity = 1 }, .{ .name = "nonvar", .arity = 1 }, .{ .name = "atom", .arity = 1 }, .{ .name = "number", .arity = 1 }, .{ .name = "integer", .arity = 1 }, .{ .name = "atomic", .arity = 1 }, .{ .name = "compound", .arity = 1 }, .{ .name = "callable", .arity = 1 }, .{ .name = "is_list", .arity = 1 },
        .{ .name = "is", .arity = 2 }, .{ .name = "=:=", .arity = 2 }, .{ .name = "=\\=", .arity = 2 }, .{ .name = "<", .arity = 2 }, .{ .name = ">", .arity = 2 }, .{ .name = "=<", .arity = 2 }, .{ .name = ">=", .arity = 2 },
        .{ .name = "functor", .arity = 3 }, .{ .name = "arg", .arity = 3 }, .{ .name = "=..", .arity = 2 }, .{ .name = "copy_term", .arity = 2 }, .{ .name = "atom_length", .arity = 2 }, .{ .name = "atom_chars", .arity = 2 }, .{ .name = "write", .arity = 1 }, .{ .name = "writeq", .arity = 1 }, .{ .name = "nl", .arity = 0 },
    };
    for (entries) |entry| if (terms.eq(name, entry.name) and arity == entry.arity) return true; return false;
}
pub fn control(name: terms.Text, arity: usize) bool { if (terms.eq(name, "call") and arity >= 1 and arity <= 8) return true; if (arity == 2 and (terms.eq(name, ",") or terms.eq(name, ";") or terms.eq(name, "->"))) return true; return (terms.eq(name, "!") and arity == 0) or (terms.eq(name, "\\+") and arity == 1) or (terms.eq(name, "catch") and arity == 3); }
pub fn builtin(name: terms.Text, arity: usize) bool { return deterministic(name, arity) or (arity == 3 and (terms.eq(name, "findall") or terms.eq(name, "between"))) or (arity == 1 and terms.eq(name, "throw")) or (arity == 2 and terms.eq(name, "length")); }
pub fn integer(host: anytype, term: *Term) !i64 { const t = term.deref(); if (t.kind == .variable) return host.fault(try terms.atom(host.a, "instantiation_error")); if (t.kind != .integer) return host.fault(try terms.typeError(host.a, "integer", t)); return t.integer; }
fn atom(host: anytype, term: *Term) !terms.Text { const t = term.deref(); if (t.kind == .variable) return host.fault(try terms.atom(host.a, "instantiation_error")); if (t.kind != .atom) return host.fault(try terms.typeError(host.a, "atom", t)); return t.name; }
fn proper(host: anytype, term: *Term) !terms.Parts { const parts = try terms.listParts(host.a, term); if (parts.tail.kind == .variable) return host.fault(try terms.atom(host.a, "instantiation_error")); if (!parts.tail.is("[]", 0)) return host.fault(try terms.typeError(host.a, "list", term)); return parts; }
pub fn arithmetic(host: anytype, term: *Term) anyerror!i64 {
    const t = term.deref(); if (t.kind == .variable) return host.fault(try terms.atom(host.a, "instantiation_error")); if (t.kind == .integer) return t.integer;
    const unary = t.arguments.len == 1 and (terms.eq(t.name, "-") or terms.eq(t.name, "abs")); const binary = t.arguments.len == 2 and (terms.eq(t.name, "+") or terms.eq(t.name, "-") or terms.eq(t.name, "*") or terms.eq(t.name, "//") or terms.eq(t.name, "mod") or terms.eq(t.name, "rem") or terms.eq(t.name, "min") or terms.eq(t.name, "max"));
    if (!unary and !binary) return host.fault(try terms.typeError(host.a, "evaluable", try terms.indicator(host.a, t)));
    const x = try arithmetic(host, t.arguments[0]); var result: i64 = 0;
    if (unary) result = if (terms.eq(t.name, "-")) -x else @intCast(@abs(x)) else {
        const y = try arithmetic(host, t.arguments[1]); if ((terms.eq(t.name, "//") or terms.eq(t.name, "mod") or terms.eq(t.name, "rem")) and y == 0) return host.fault(try terms.compound(host.a, "evaluation_error", &.{try terms.atom(host.a, "zero_divisor")}));
        result = if (terms.eq(t.name, "+")) x + y else if (terms.eq(t.name, "-")) x - y else if (terms.eq(t.name, "*")) x * y else if (terms.eq(t.name, "//")) @divTrunc(x, y) else if (terms.eq(t.name, "mod")) x - y * @divFloor(x, y) else if (terms.eq(t.name, "rem")) @rem(x, y) else if (terms.eq(t.name, "min")) @min(x, y) else @max(x, y);
    }
    if (result < -2147483648 or result > 2147483647) return host.fault(try terms.compound(host.a, "evaluation_error", &.{try terms.atom(host.a, "int_overflow")})); return result;
}
pub fn execute(host: anytype, goal: *Term) anyerror!bool {
    const a = host.a; const g = goal.deref(); const args = g.arguments;
    if (g.is("true", 0)) return true; if (g.is("fail", 0) or g.is("false", 0)) return false;
    if (g.is("=", 2)) return host.trail.unify(args[0], args[1]);
    if (g.is("\\=", 2)) { const mark = host.trail.mark(); const yes = try host.trail.unify(args[0], args[1]); host.trail.undo(mark); return !yes; }
    if (g.is("==", 2) or g.is("\\==", 2)) return unify.identical(args[0], args[1]) == terms.eq(g.name, "==");
    if (g.is("is", 2)) { const n = try arithmetic(host, args[1]); return host.trail.unify(args[0], try terms.integer(a, n)); }
    if (args.len == 2 and (terms.eq(g.name, "=:=") or terms.eq(g.name, "=\\=") or terms.eq(g.name, "<") or terms.eq(g.name, ">") or terms.eq(g.name, "=<") or terms.eq(g.name, ">="))) { const x = try arithmetic(host, args[0]); const y = try arithmetic(host, args[1]); return if (terms.eq(g.name, "=:=")) x == y else if (terms.eq(g.name, "=\\=")) x != y else if (terms.eq(g.name, "<")) x < y else if (terms.eq(g.name, ">")) x > y else if (terms.eq(g.name, "=<")) x <= y else x >= y; }
    if (g.is("nl", 0)) { try host.writeOutput(null, true); return true; }
    if (g.is("write", 1) or g.is("writeq", 1)) { try host.writeOutput(args[0], terms.eq(g.name, "writeq")); return true; }
    if (args.len == 1) {
        const t = args[0].deref();
        if (terms.eq(g.name, "var")) return t.kind == .variable; if (terms.eq(g.name, "nonvar")) return t.kind != .variable;
        if (terms.eq(g.name, "atom")) return t.kind == .atom; if (terms.eq(g.name, "number") or terms.eq(g.name, "integer")) return t.kind == .integer;
        if (terms.eq(g.name, "atomic")) return t.kind == .atom or t.kind == .integer; if (terms.eq(g.name, "compound")) return t.kind == .compound;
        if (terms.eq(g.name, "callable")) return t.kind == .atom or t.kind == .compound; if (terms.eq(g.name, "is_list")) return (try terms.listParts(a, t)).tail.is("[]", 0);
    }
    if (g.is("copy_term", 2)) return host.trail.unify(try terms.copy(a, args[0]), args[1]);
    if (g.is("functor", 3)) {
        const t = args[0].deref(); const n = args[1].deref(); const arity = args[2].deref();
        if (t.kind != .variable) return (try host.trail.unify(args[1], if (t.kind == .compound) try terms.atom(a, t.name) else t)) and (try host.trail.unify(args[2], try terms.integer(a, @intCast(t.arguments.len))));
        if (n.kind == .variable or arity.kind == .variable) return host.fault(try terms.atom(a, "instantiation_error")); if (n.kind == .compound) return host.fault(try terms.typeError(a, "atomic", n));
        if (arity.kind != .integer) return host.fault(try terms.typeError(a, "integer", arity)); if (arity.integer < 0) return host.fault(try terms.domainError(a, "not_less_than_zero", arity)); if (arity.integer > 255) return host.fault(try terms.compound(a, "representation_error", &.{try terms.atom(a, "max_arity")}));
        if (arity.integer == 0) return host.trail.unify(t, n); if (n.kind == .integer) return host.fault(try terms.typeError(a, "atom", n)); const elements = try a.alloc(*Term, @intCast(arity.integer)); for (elements) |*element| element.* = try terms.variable(a); return host.trail.unify(t, try terms.compound(a, n.name, elements));
    }
    if (g.is("arg", 3)) {
        const n = args[0].deref(); const t = args[1].deref(); if (n.kind == .variable or t.kind == .variable) return host.fault(try terms.atom(a, "instantiation_error")); if (n.kind != .integer) return host.fault(try terms.typeError(a, "integer", n)); if (t.kind != .compound) return host.fault(try terms.typeError(a, "compound", t)); if (n.integer < 1 or n.integer > @as(i64, @intCast(t.arguments.len))) return false; return host.trail.unify(t.arguments[@intCast(n.integer - 1)], args[2]);
    }
    if (g.is("=..", 2)) {
        const t = args[0].deref(); if (t.kind != .variable) { var elements: std.ArrayList(*Term) = .empty; try elements.append(a, if (t.kind == .compound) try terms.atom(a, t.name) else t); if (t.kind == .compound) try elements.appendSlice(a, t.arguments); return host.trail.unify(try terms.list(a, elements.items, null), args[1]); }
        const parts = try proper(host, args[1]); if (parts.elements.len == 0) return host.fault(try terms.domainError(a, "non_empty_list", try terms.atom(a, "[]"))); const head = parts.elements[0].deref(); if (head.kind == .variable) return host.fault(try terms.atom(a, "instantiation_error"));
        if (parts.elements.len == 1) { if (head.kind == .compound) return host.fault(try terms.typeError(a, "atomic", head)); return host.trail.unify(t, head); }
        if (head.kind != .atom) return host.fault(try terms.typeError(a, "atom", head)); if (parts.elements.len > 256) return host.fault(try terms.compound(a, "representation_error", &.{try terms.atom(a, "max_arity")})); return host.trail.unify(t, try terms.compound(a, head.name, parts.elements[1..]));
    }
    if (g.is("atom_length", 2)) { const name = try atom(host, args[0]); const n = args[1].deref(); if (n.kind != .variable and n.kind != .integer) return host.fault(try terms.typeError(a, "integer", n)); return host.trail.unify(args[1], try terms.integer(a, @intCast(name.len))); }
    if (g.is("atom_chars", 2)) {
        const t = args[0].deref(); if (t.kind != .variable) { const name = try atom(host, t); const chars = try a.alloc(*Term, name.len); for (0..name.len) |i| chars[i] = try terms.atom(a, name[i..i + 1]); return host.trail.unify(args[1], try terms.list(a, chars, null)); }
        const parts = try proper(host, args[1]); var bytes: std.ArrayList(u8) = .empty; for (parts.elements) |element| { const ch = element.deref(); if (ch.kind == .variable) return host.fault(try terms.atom(a, "instantiation_error")); if (ch.kind != .atom or ch.name.len != 1) return host.fault(try terms.typeError(a, "character", ch)); try bytes.appendSlice(a, ch.name); } return host.trail.unify(t, try terms.atom(a, bytes.items));
    }
    unreachable;
}
