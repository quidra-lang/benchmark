const std = @import("std");
const c = @import("grammar_parser.zig");
fn fresh(grammar: c.Grammar, base: []const u8) []const u8 {
    var out = base;
    while (true) {
        out = c.fmt("{s}'>", .{out[0 .. out.len - 1]});
        if (grammar.index(out) == null) return out;
    }
}
fn leadingReachable(grammar: c.Grammar, source: []const u8, target: []const u8) bool {
    const seen = c.alloc(bool, grammar.rules.items.len);
    @memset(seen, false);
    var queue: std.ArrayList(usize) = .empty;
    const start = grammar.index(source).?;
    seen[start] = true;
    c.append(usize, &queue, start);
    var head: usize = 0;
    while (head < queue.items.len) : (head += 1) {
        const rule = grammar.rules.items[queue.items[head]];
        for (rule.alternatives.items) |rhs| {
            if (rhs.len == 0 or !c.nonterminal(rhs[0])) continue;
            if (c.eq(rhs[0], target)) return true;
            const next = grammar.index(rhs[0]).?;
            if (!seen[next]) {
                seen[next] = true;
                c.append(usize, &queue, next);
            }
        }
    }
    return false;
}
pub fn eliminateRecursion(grammar: *c.Grammar) c.Lines {
    var logs: c.Lines = .{};
    const original = c.alloc([]const u8, grammar.rules.items.len);
    for (grammar.rules.items, original) |rule, *name| name.* = rule.name;
    for (original, 0..) |current, i| {
        for (original[0..i]) |earlier| {
            const ci = grammar.index(current).?;
            const old = grammar.rules.items[ci].alternatives.items;
            var present = false;
            for (old) |rhs| if (rhs.len > 0 and c.eq(rhs[0], earlier)) {
                present = true;
            };
            if (!present or !leadingReachable(grammar.*, earlier, current)) continue;
            var replacement: c.Alternatives = .empty;
            const prefixes = grammar.rules.items[grammar.index(earlier).?].alternatives.items;
            for (old) |rhs| {
                if (rhs.len > 0 and c.eq(rhs[0], earlier)) {
                    for (prefixes) |prefix| c.alternativeUnique(&replacement, c.concat(prefix, rhs[1..]));
                } else c.alternativeUnique(&replacement, rhs);
            }
            grammar.rules.items[ci].alternatives = replacement;
            logs.add("substitute {s} into {s}", .{ earlier, current });
        }
        const ci = grammar.index(current).?;
        var remaining: c.Alternatives = .empty;
        for (grammar.rules.items[ci].alternatives.items) |rhs| {
            if (rhs.len == 1 and c.eq(rhs[0], current)) logs.add("remove cycle {s} -> {s}", .{ current,
                 current }) else c.append(c.Sequence, &remaining, rhs);
        }
        grammar.rules.items[ci].alternatives = remaining;
        var recursive = false;
        for (remaining.items) |rhs| if (rhs.len > 0 and c.eq(rhs[0], current)) {
            recursive = true;
        };
        if (!recursive) continue;
        const created = fresh(grammar.*, current);
        var base: c.Alternatives = .empty;
        var tail: c.Alternatives = .empty;
        for (remaining.items) |rhs| {
            if (rhs.len > 0 and c.eq(rhs[0], current)) c.append(c.Sequence, &tail, c.concat(rhs[1..],
                 &.{created})) else c.append(c.Sequence, &base, c.concat(rhs, &.{created}));
        }
        c.append(c.Sequence, &tail, &.{});
        grammar.rules.items[ci].alternatives = base;
        grammar.insert(.{ .name = created, .alternatives = tail }, ci + 1);
        logs.add("eliminate left recursion in {s} with {s}", .{ current, created });
    }
    return logs;
}
pub fn leftFactor(grammar: *c.Grammar) c.Lines {
    var logs: c.Lines = .{};
    var position: usize = 0;
    while (position < grammar.rules.items.len) : (position += 1) {
        const current = grammar.rules.items[position].name;
        const old = grammar.rules.items[position].alternatives.items;
        var replacement: c.Alternatives = .empty;
        var processed: c.Set = .empty;
        var created: std.ArrayList(c.Rule) = .empty;
        for (old) |rhs| {
            if (rhs.len == 0) {
                c.append(c.Sequence, &replacement, rhs);
                continue;
            }
            if (!c.addUnique(&processed, rhs[0])) continue;
            var group: c.Alternatives = .empty;
            for (old) |other| if (other.len > 0 and c.eq(other[0], rhs[0])) c.append(c.Sequence, &group, other);
            if (group.items.len == 1) {
                c.append(c.Sequence, &replacement, rhs);
                continue;
            }
            var prefix = group.items[0];
            for (group.items) |other| {
                var count: usize = 0;
                while (count < prefix.len and count < other.len and c.eq(prefix[count], other[count])) count += 1;
                prefix = prefix[0..count];
            }
            const name = fresh(grammar.*, current);
            var remainders: c.Alternatives = .empty;
            for (group.items) |other| c.append(c.Sequence, &remainders, other[prefix.len..]);
            const rule: c.Rule = .{ .name = name, .alternatives = remainders };
            c.append(c.Rule, &grammar.rules, rule);
            c.append(c.Rule, &created, rule);
            c.append(c.Sequence, &replacement, c.concat(prefix, &.{name}));
            logs.add("left factor {s} on {s} with {s}", .{ current, c.notation(prefix), name });
        }
        grammar.rules.items = grammar.rules.items[0 .. grammar.rules.items.len - created.items.len];
        grammar.rules.items[position].alternatives = replacement;
        for (created.items, 0..) |rule, i| grammar.insert(rule, position + 1 + i);
    }
    return logs;
}
