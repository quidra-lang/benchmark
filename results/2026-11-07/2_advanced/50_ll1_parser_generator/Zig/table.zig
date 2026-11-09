const std = @import("std");
const c = @import("grammar_parser.zig");
const first_follow = @import("first_follow.zig");
pub const Production = struct { lhs: usize, rhs: c.Sequence };
pub const Table = struct {
    grammar: *const c.Grammar,
    productions: []const Production,
    predict: []c.Set,
    first: []c.Set,
    terminals: c.Sequence,
    cells: []std.ArrayList(usize),
    chosen: []?usize,
    conflicts: usize = 0,
    pub fn terminalIndex(self: Table, name: []const u8) ?usize {
        for (self.terminals, 0..) |value, i| if (c.eq(value, name)) return i;
        return null;
    }
};
pub fn build(grammar: *const c.Grammar, sets: first_follow.Sets) Table {
    var productions: std.ArrayList(Production) = .empty;
    var terminals: c.Set = .empty;
    for (grammar.rules.items, 0..) |rule, a| for (rule.alternatives.items) |rhs| {
        c.append(Production, &productions, .{ .lhs = a, .rhs = rhs });
        for (rhs) |symbol| if (!c.nonterminal(symbol)) {
            _ = c.addUnique(&terminals, symbol);
        };
    };
    _ = c.addUnique(&terminals, "$");
    const names = c.sorted(terminals.items);
    const count = grammar.rules.items.len * names.len;
    var out: Table = .{ .grammar = grammar, .productions = productions.items, .predict = c.alloc(c.Set,
         productions.items.len), .first = c.alloc(c.Set, productions.items.len), .terminals = names,
         .cells = c.alloc(std.ArrayList(usize), count), .chosen = c.alloc(?usize, count) };
    @memset(out.predict, .empty);
    @memset(out.first, .empty);
    @memset(out.cells, .empty);
    @memset(out.chosen, null);
    for (productions.items, 0..) |production, p| {
        const first = first_follow.firstSequence(production.rhs, sets);
        out.first[p] = first.terminals;
        for (first.terminals.items) |value| _ = c.addUnique(&out.predict[p], value);
        if (first.nullable) for (sets.follow[production.lhs].items) |value| {
            _ = c.addUnique(&out.predict[p], value);
        };
        for (out.predict[p].items) |value| {
            const t = out.terminalIndex(value).?;
            c.append(usize, &out.cells[production.lhs * names.len + t], p);
        }
    }
    for (out.cells, 0..) |cell, index| {
        if (cell.items.len == 0) continue;
        if (cell.items.len > 1) out.conflicts += 1;
        var chosen = cell.items[0];
        const terminal = names[index % names.len];
        for (cell.items) |p| if (c.has(out.first[p].items, terminal)) {
            chosen = p;
            break;
        };
        out.chosen[index] = chosen;
    }
    return out;
}
pub fn reason(table: Table, production: usize, terminal: []const u8) []const u8 {
    return if (c.has(table.first[production].items, terminal)) "FIRST" else "FOLLOW";
}
pub fn conflictKind(table: Table, cell: []const usize, terminal: []const u8) []const u8 {
    var first: usize = 0;
    for (cell) |production| first += @intFromBool(c.has(table.first[production].items, terminal));
    return if (first == cell.len) "FIRST/FIRST" else if (first == 0) "FOLLOW/FOLLOW" else "FIRST/FOLLOW";
}
