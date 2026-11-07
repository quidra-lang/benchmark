const std = @import("std");
pub const Text = []const u8;
pub const Term = struct {
    kind: enum { integer, atom, variable, compound }, name: Text = "", integer: i64 = 0, arguments: []*Term = &.{}, binding: ?*Term = null,
    pub fn deref(t: *Term) *Term { var x = t; while (x.kind == .variable and x.binding != null) x = x.binding.?; return x; }
    pub fn is(t: *Term, name: Text, arity: usize) bool { const x = t.deref(); return (x.kind == .atom or x.kind == .compound) and eq(x.name, name) and x.arguments.len == arity; }
};
pub fn eq(a: Text, b: Text) bool { return std.mem.eql(u8, a, b); }
fn create(a: std.mem.Allocator, term: Term) !*Term { const t = try a.create(Term); t.* = term; return t; }
pub fn variable(a: std.mem.Allocator) !*Term { return create(a, .{ .kind = .variable }); }
pub fn integer(a: std.mem.Allocator, n: i64) !*Term { return create(a, .{ .kind = .integer, .integer = n }); }
pub fn atom(a: std.mem.Allocator, name: Text) !*Term { return create(a, .{ .kind = .atom, .name = name }); }
pub fn compound(a: std.mem.Allocator, name: Text, args: []const *Term) !*Term { return if (args.len == 0) atom(a, name) else create(a, .{ .kind = .compound, .name = name, .arguments = try a.dupe(*Term, args) }); }
pub fn indicator(a: std.mem.Allocator, t: *Term) !*Term { const x = t.deref(); return compound(a, "/", &.{try atom(a, x.name), try integer(a, @intCast(x.arguments.len))}); }
pub fn typeError(a: std.mem.Allocator, expected: Text, actual: *Term) !*Term { return compound(a, "type_error", &.{try atom(a, expected), actual}); }
pub fn domainError(a: std.mem.Allocator, expected: Text, actual: *Term) !*Term { return compound(a, "domain_error", &.{try atom(a, expected), actual}); }
pub fn list(a: std.mem.Allocator, elements: []const *Term, tail: ?*Term) !*Term { var t = tail orelse try atom(a, "[]"); var n = elements.len; while (n > 0) { n -= 1; t = try compound(a, ".", &.{elements[n], t}); } return t; }
pub const Parts = struct { elements: []*Term, tail: *Term };
pub fn listParts(a: std.mem.Allocator, term: *Term) !Parts { var elements: std.ArrayList(*Term) = .empty; var t = term.deref(); while (t.is(".", 2)) { try elements.append(a, t.arguments[0]); t = t.arguments[1].deref(); } return .{ .elements = elements.items, .tail = t }; }
fn copyWith(a: std.mem.Allocator, term: *Term, copies: *std.AutoHashMapUnmanaged(*Term, *Term)) anyerror!*Term {
    const t = term.deref(); if (t.kind == .variable) { if (copies.get(t)) |v| return v; const v = try variable(a); try copies.put(a, t, v); return v; }
    if (t.kind != .compound) return t; const args = try a.alloc(*Term, t.arguments.len); for (t.arguments, 0..) |arg, i| args[i] = try copyWith(a, arg, copies); return compound(a, t.name, args);
}
pub fn copy(a: std.mem.Allocator, term: *Term) !*Term { var copies: std.AutoHashMapUnmanaged(*Term, *Term) = .empty; return copyWith(a, term, &copies); }
pub fn variables(a: std.mem.Allocator, term: *Term, result: *std.ArrayList(*Term)) anyerror!void { const t = term.deref(); if (t.kind == .variable) try result.append(a, t) else if (t.kind == .compound) for (t.arguments) |arg| { try variables(a, arg, result); }; }
pub fn convert(a: std.mem.Allocator, term: *Term) anyerror!?*Term {
    const t = term.deref(); if (t.kind == .integer) return null; if (t.kind == .variable) return try compound(a, "call", &.{t});
    if (t.is(",", 2) or t.is(";", 2) or t.is("->", 2)) { const left = (try convert(a, t.arguments[0])) orelse return null; const right = (try convert(a, t.arguments[1])) orelse return null; return try compound(a, t.name, &.{left, right}); } return t;
}
