const std = @import("std");
const c = @import("cnf_io.zig");
pub const Statistics = struct {
    decisions: i64 = 0,
    propagations: i64 = 0,
    conflicts: i64 = 0,
    max_depth: i64 = 0,
    pub fn add(self: *Statistics, other: Statistics) void {
        self.decisions += other.decisions;
        self.propagations += other.propagations;
        self.conflicts += other.conflicts;
        self.max_depth = @max(self.max_depth, other.max_depth);
    }
};
pub const Round = struct { sat: bool = false, values: c.Model = &.{}, stats: Statistics = .{}, events: c.Lines = .{} };
const Kind = enum { decision, flip, propagation };
const Trail = struct { literal: i64, kind: Kind };
const Search = struct {
    values: []i64,
    trail: std.ArrayList(Trail) = .empty,
    position: usize = 0,
    watches: []std.ArrayList(usize),
    out: Round = .{},
    fn value(self: Search, literal: i64) i64 {
        const assigned = self.values[@intCast(@abs(literal))];
        return if (assigned < 0) -1 else if (literal > 0) assigned else 1 - assigned;
    }
    fn assign(self: *Search, literal: i64, kind: Kind) void {
        self.values[@intCast(@abs(literal))] = @intFromBool(literal > 0);
        c.append(Trail, &self.trail, .{ .literal = literal, .kind = kind });
        self.out.events.add("{s}{d}", .{ switch (kind) {
            .decision => "D",
            .flip => "F",
            .propagation => "P",
        }, literal });
    }
};
fn watchIndex(literal: i64) usize {
    return @as(usize, @intCast(@abs(literal))) * 2 + @intFromBool(literal < 0);
}
fn searchRound(formula: c.Formula) Round {
    const clauses = c.alloc([]i64, formula.clauses.items.len);
    for (clauses, formula.clauses.items) |*clause, original| clause.* = c.dupe(i64, original);
    var search: Search = .{ .values = c.alloc(i64, formula.variables + 1), .watches = c.alloc(std.ArrayList(usize),
         2 * (formula.variables + 1)) };
    @memset(search.values, -1);
    @memset(search.watches, .empty);
    for (clauses, 0..) |clause, id| if (clause.len >= 2) {
        c.append(usize, &search.watches[watchIndex(clause[0])], id);
        c.append(usize, &search.watches[watchIndex(clause[1])], id);
    };
    for (clauses) |clause| {
        if (clause.len == 0 or (clause.len == 1 and search.value(clause[0]) == 0)) {
            search.out.stats.conflicts += 1;
            search.out.events.add("C", .{});
            return search.out;
        }
        if (clause.len == 1 and search.value(clause[0]) < 0) {
            search.assign(clause[0], .propagation);
            search.out.stats.propagations += 1;
        }
    }
    while (true) {
        var conflict = false;
        while (search.position < search.trail.items.len and !conflict) {
            const f = -search.trail.items[search.position].literal;
            search.position += 1;
            const watch = &search.watches[watchIndex(f)];
            var i: usize = 0;
            while (i < watch.items.len) {
                const id = watch.items[i];
                const clause = clauses[id];
                if (clause[0] == f) std.mem.swap(i64, &clause[0], &clause[1]);
                if (search.value(clause[0]) == 1) {
                    i += 1;
                    continue;
                }
                var replacement: usize = 2;
                while (replacement < clause.len and search.value(clause[replacement]) == 0) replacement += 1;
                if (replacement < clause.len) {
                    std.mem.swap(i64, &clause[1], &clause[replacement]);
                    _ = watch.orderedRemove(i);
                    c.append(usize, &search.watches[watchIndex(clause[1])], id);
                    continue;
                }
                if (search.value(clause[0]) == 0) {
                    search.out.stats.conflicts += 1;
                    search.out.events.add("C", .{});
                    conflict = true;
                    break;
                }
                if (search.value(clause[0]) < 0) {
                    search.assign(clause[0], .propagation);
                    search.out.stats.propagations += 1;
                }
                i += 1;
            }
        }
        if (conflict) {
            while (search.trail.items.len > 0 and search.trail.items[search.trail.items.len - 1].kind != .decision) {
                const entry = search.trail.pop().?;
                search.values[@intCast(@abs(entry.literal))] = -1;
            }
            if (search.trail.items.len == 0) return search.out;
            const literal = search.trail.pop().?.literal;
            search.values[@intCast(@abs(literal))] = -1;
            search.position = search.trail.items.len;
            search.assign(-literal, .flip);
            continue;
        }
        const counts = c.alloc([2]i64, formula.variables + 1);
        @memset(counts, .{ 0, 0 });
        for (clauses) |clause| {
            var satisfied = false;
            for (clause) |literal| if (search.value(literal) == 1) {
                satisfied = true;
            };
            if (satisfied) continue;
            var seen = std.mem.zeroes([401]bool);
            for (clause) |literal| if (search.value(literal) < 0 and !seen[c.u(literal + 200)]) {
                counts[@intCast(@abs(literal))][@intFromBool(literal < 0)] += 1;
                seen[c.u(literal + 200)] = true;
            };
        }
        var selected: i64 = 0;
        var greatest: i64 = 0;
        for (1..formula.variables + 1) |x| for (0..2) |negative| if (counts[x][negative] > greatest) {
            greatest = counts[x][negative];
            selected = if (negative == 1) -c.n(x) else c.n(x);
        };
        if (selected == 0) {
            search.out.sat = true;
            for (search.values) |*assigned| if (assigned.* < 0) {
                assigned.* = 0;
            };
            search.out.values = search.values;
            return search.out;
        }
        search.assign(selected, .decision);
        search.out.stats.decisions += 1;
        var depth: i64 = 0;
        for (search.trail.items) |entry| if (entry.kind != .propagation) {
            depth += 1;
        };
        search.out.stats.max_depth = @max(search.out.stats.max_depth, depth);
    }
}
pub fn round(formula: c.Formula) Round {
    const saved = c.allocator;
    var arena = std.heap.ArenaAllocator.init(saved);
    c.allocator = arena.allocator();
    var result = searchRound(formula);
    c.allocator = saved;
    result.values = c.dupe(i64, result.values);
    var events: c.Lines = .{};
    for (result.events.data.items) |event| events.add("{s}", .{event});
    result.events = events;
    arena.deinit();
    return result;
}
