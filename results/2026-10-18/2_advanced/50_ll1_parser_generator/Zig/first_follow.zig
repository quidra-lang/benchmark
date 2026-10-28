const c = @import("grammar_parser.zig");
pub const Sets = struct { grammar: *const c.Grammar, nullable: []bool, first: []c.Set, follow: []c.Set,
     nullable_passes: usize = 0, first_passes: usize = 0, follow_passes: usize = 0 };
pub const First = struct { terminals: c.Set = .empty, nullable: bool = true };
pub fn firstSequence(sequence: c.Sequence, sets: Sets) First {
    var out: First = .{};
    for (sequence) |symbol| {
        if (!c.nonterminal(symbol)) {
            _ = c.addUnique(&out.terminals, symbol);
            out.nullable = false;
            return out;
        }
        const index = sets.grammar.index(symbol).?;
        for (sets.first[index].items) |value| _ = c.addUnique(&out.terminals, value);
        if (!sets.nullable[index]) {
            out.nullable = false;
            return out;
        }
    }
    return out;
}
fn unite(target: *c.Set, source: c.Sequence) bool {
    var changed = false;
    for (source) |value| changed = c.addUnique(target, value) or changed;
    return changed;
}
pub fn calculate(grammar: *const c.Grammar) Sets {
    const n = grammar.rules.items.len;
    var out: Sets = .{ .grammar = grammar, .nullable = c.alloc(bool, n), .first = c.alloc(c.Set, n),
         .follow = c.alloc(c.Set, n) };
    @memset(out.nullable, false);
    @memset(out.first, .empty);
    @memset(out.follow, .empty);
    var changed = true;
    while (changed) {
        changed = false;
        out.nullable_passes += 1;
        for (grammar.rules.items, 0..) |rule, a| for (rule.alternatives.items) |rhs| {
            var nullable = true;
            for (rhs) |symbol| if (!c.nonterminal(symbol) or !out.nullable[grammar.index(symbol).?]) {
                nullable = false;
                break;
            };
            if (nullable and !out.nullable[a]) {
                out.nullable[a] = true;
                changed = true;
            }
        };
    }
    changed = true;
    while (changed) {
        changed = false;
        out.first_passes += 1;
        for (grammar.rules.items, 0..) |rule, a| for (rule.alternatives.items) |rhs| {
            const first = firstSequence(rhs, out);
            changed = unite(&out.first[a], first.terminals.items) or changed;
        };
    }
    _ = c.addUnique(&out.follow[grammar.index(grammar.start).?], "$");
    changed = true;
    while (changed) {
        changed = false;
        out.follow_passes += 1;
        for (grammar.rules.items, 0..) |rule, a| for (rule.alternatives.items) |rhs| for (rhs, 0..) |symbol, i| {
            if (!c.nonterminal(symbol)) continue;
            const b = grammar.index(symbol).?;
            const first = firstSequence(rhs[i + 1 ..], out);
            changed = unite(&out.follow[b], first.terminals.items) or changed;
            if (first.nullable) changed = unite(&out.follow[b], out.follow[a].items) or changed;
        };
    }
    return out;
}
