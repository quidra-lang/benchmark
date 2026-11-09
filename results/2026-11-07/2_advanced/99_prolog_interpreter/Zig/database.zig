const std = @import("std");
const terms = @import("terms.zig");
const Term = terms.Term;
pub const Clause = struct {
    head: *Term, body: ?*Term, file: usize, line: usize,
    pub fn copy(c: Clause, a: std.mem.Allocator) !struct { head: *Term, body: ?*Term } {
        const pair = try terms.compound(a, "$clause", &.{c.head, c.body orelse try terms.atom(a, "$fact")}); const copied = try terms.copy(a, pair); return .{ .head = copied.arguments[0], .body = if (c.body != null) copied.arguments[1] else null };
    }
};
pub const Predicate = struct { name: terms.Text, arity: usize, clauses: std.ArrayList(Clause) = .empty, discontiguous: [2]bool = .{false, false} };
pub const Database = struct {
    a: std.mem.Allocator, predicates: std.ArrayList(*Predicate) = .empty,
    pub fn find(d: *Database, name: terms.Text, arity: usize) ?*Predicate { for (d.predicates.items) |p| if (terms.eq(p.name, name) and p.arity == arity) return p; return null; }
    pub fn add(d: *Database, clause: Clause) !*Predicate { const h = clause.head.deref(); var predicate = d.find(h.name, h.arguments.len); if (predicate == null) { const p = try d.a.create(Predicate); p.* = .{ .name = h.name, .arity = h.arguments.len }; try d.predicates.append(d.a, p); predicate = p; } try predicate.?.clauses.append(d.a, clause); return predicate.?; }
    pub fn candidates(d: *Database, goal: *Term) ![]const Clause { const g = goal.deref(); const p = d.find(g.name, g.arguments.len).?; var result: std.ArrayList(Clause) = .empty; for (p.clauses.items) |c| if (g.arguments.len == 0 or compatible(g.arguments[0], c.head.arguments[0])) { try result.append(d.a, c); }; return result.items; }
};
fn compatible(left: *Term, right: *Term) bool { const x = left.deref(); const y = right.deref(); if (x.kind == .variable or y.kind == .variable) return true; if (x.kind != y.kind) return false; if (x.kind == .integer) return x.integer == y.integer; return terms.eq(x.name, y.name) and x.arguments.len == y.arguments.len; }
