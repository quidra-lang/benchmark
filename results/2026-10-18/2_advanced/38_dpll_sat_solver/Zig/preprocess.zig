const std = @import("std");
const c = @import("cnf_io.zig");
pub const Working = struct { id: usize, literals: c.Clause };
pub const Reduced = struct {
    clauses: std.ArrayList(Working) = .empty,
    fixed: []i64,
    pure: bool,
    conflict: bool = false,
    empty_clause: usize = 0,
    tautologies: usize = 0,
    duplicate_literals: usize = 0,
    unit_fixed: usize = 0,
    unit_removed: usize = 0,
    subsumed: usize = 0,
    pure_fixed: usize = 0,
    pure_removed: usize = 0,
    removed: [4]std.ArrayList(i64) = @splat(.empty),
    pub fn removedCount(self: Reduced) usize {
        return self.tautologies + self.unit_removed + self.subsumed + self.pure_removed;
    }
};
pub fn preprocess(formula: c.Formula, pure: bool) Reduced {
    var out: Reduced = .{ .pure = pure, .fixed = c.alloc(i64, formula.variables + 1) };
    @memset(out.fixed, -1);
    for (formula.clauses.items, 1..) |clause, index| {
        var tautology = false;
        for (clause) |literal| if (c.contains(clause, -literal)) {
            tautology = true;
        };
        if (tautology) {
            out.tautologies += 1;
            c.append(i64, &out.removed[0], c.n(index));
            continue;
        }
        var normalized: std.ArrayList(i64) = .empty;
        for (clause) |literal| {
            if (c.contains(normalized.items, literal)) out.duplicate_literals += 1 else c.append(i64, &normalized, literal);
        }
        c.append(Working, &out.clauses, .{ .id = index, .literals = normalized.items });
    }
    while (true) {
        var unit: i64 = 0;
        for (out.clauses.items) |clause| if (clause.literals.len == 0) {
            out.conflict = true;
            out.empty_clause = clause.id;
            return out;
        };
        for (out.clauses.items) |clause| if (clause.literals.len == 1) {
            unit = clause.literals[0];
            break;
        };
        if (unit == 0) break;
        out.fixed[@intCast(@abs(unit))] = @intFromBool(unit > 0);
        out.unit_fixed += 1;
        var remaining: std.ArrayList(Working) = .empty;
        for (out.clauses.items) |clause| {
            if (c.contains(clause.literals, unit)) {
                out.unit_removed += 1;
                c.append(i64, &out.removed[1], c.n(clause.id));
            } else {
                var literals: std.ArrayList(i64) = .empty;
                for (clause.literals) |literal| if (literal != -unit) c.append(i64, &literals, literal);
                c.append(Working, &remaining, .{ .id = clause.id, .literals = literals.items });
            }
        }
        out.clauses = remaining;
    }
    const remove = c.alloc(bool, out.clauses.items.len);
    @memset(remove, false);
    for (out.clauses.items, 0..) |second, b| for (out.clauses.items, 0..) |first, a| {
        if (a == b or !(first.literals.len < second.literals.len or a < b)) continue;
        var contained = true;
        for (first.literals) |literal| if (!c.contains(second.literals, literal)) {
            contained = false;
        };
        if (contained) {
            remove[b] = true;
            break;
        }
    };
    var remaining: std.ArrayList(Working) = .empty;
    for (out.clauses.items, remove) |clause, removed| {
        if (removed) {
            out.subsumed += 1;
            c.append(i64, &out.removed[2], c.n(clause.id));
        } else c.append(Working, &remaining, clause);
    }
    out.clauses = remaining;
    if (pure) while (true) {
        var present = std.mem.zeroes([401]bool);
        var pure_literals = std.mem.zeroes([401]bool);
        for (out.clauses.items) |clause| for (clause.literals) |literal| {
            present[c.u(literal + 200)] = true;
        };
        var count: usize = 0;
        for (0..401) |i| if (present[i] and !present[400 - i]) {
            pure_literals[i] = true;
            const literal = c.n(i) - 200;
            out.fixed[@intCast(@abs(literal))] = @intFromBool(literal > 0);
            count += 1;
        };
        if (count == 0) break;
        out.pure_fixed += count;
        remaining = .empty;
        for (out.clauses.items) |clause| {
            var removed = false;
            for (clause.literals) |literal| if (pure_literals[c.u(literal + 200)]) {
                removed = true;
            };
            if (removed) {
                out.pure_removed += 1;
                c.append(i64, &out.removed[3], c.n(clause.id));
            } else c.append(Working, &remaining, clause);
        }
        out.clauses = remaining;
    };
    return out;
}
