const std = @import("std");
const terms = @import("terms.zig");
const Term = terms.Term;
pub const Trail = struct {
    a: std.mem.Allocator, bindings: std.ArrayList(*Term) = .empty,
    pub fn mark(t: *Trail) usize { return t.bindings.items.len; }
    pub fn undo(t: *Trail, m: usize) void { while (t.bindings.items.len > m) { const variable = t.bindings.pop().?; variable.binding = null; } }
    pub fn unify(t: *Trail, left: *Term, right: *Term) anyerror!bool {
        const x = left.deref(); const y = right.deref(); if (x == y) return true;
        if (x.kind == .variable) { try t.bindings.append(t.a, x); x.binding = y; return true; }
        if (y.kind == .variable) { try t.bindings.append(t.a, y); y.binding = x; return true; }
        if (x.kind != y.kind) return false; if (x.kind == .integer) return x.integer == y.integer;
        if (!terms.eq(x.name, y.name) or x.arguments.len != y.arguments.len) return false;
        for (x.arguments, y.arguments) |a, b| if (!try t.unify(a, b)) return false; return true;
    }
};
pub fn identical(left: *Term, right: *Term) bool { const x = left.deref(); const y = right.deref(); if (x == y) return true; if (x.kind != y.kind or x.kind == .variable) return false; if (x.kind == .integer) return x.integer == y.integer; if (!terms.eq(x.name, y.name) or x.arguments.len != y.arguments.len) return false; for (x.arguments, y.arguments) |a, b| if (!identical(a, b)) return false; return true; }
