const std = @import("std");
const c = @import("grammar_parser.zig");
const transform = @import("transform.zig");
const first_follow = @import("first_follow.zig");
const table_module = @import("table.zig");
const driver = @import("driver.zig");
const Indices = std.ArrayList(usize);
fn join(values: c.Sequence, separator: []const u8) []const u8 {
    var out: c.Text = .{};
    for (values, 0..) |value, i| out.add("{s}{s}", .{ if (i == 0) "" else separator, value });
    return out.value();
}
fn numbers(values: []const usize, offset: usize, separator: []const u8) []const u8 {
    var out: c.Text = .{};
    for (values, 0..) |value, i| out.add("{s}{d}", .{ if (i == 0) "" else separator, value + offset });
    return out.value();
}
fn heading(out: *c.Text, name: []const u8, values: c.Sequence) void {
    out.add("{s}", .{name});
    for (values) |value| out.add(" {s}", .{value});
    out.add("\n", .{});
}
fn numberHeading(out: *c.Text, name: []const u8, values: []const usize, offset: usize) void {
    out.add("{s}", .{name});
    for (values) |value| out.add(" {d}", .{value + offset});
    out.add("\n", .{});
}
fn spaces(count: usize) []const u8 {
    const out = c.alloc(u8, count);
    @memset(out, ' ');
    return out;
}
fn padded(value: []const u8, width: usize, left: bool) []const u8 {
    return if (left) c.fmt("{s}{s}", .{ value, spaces(width - value.len) }) else c.fmt("{s}{s}", .{ spaces(width - value.len),
         value });
}
fn removeNames(grammar: *c.Grammar, removed: c.Sequence) void {
    var kept: std.ArrayList(c.Rule) = .empty;
    for (grammar.rules.items) |rule| if (!c.has(removed, rule.name)) c.append(c.Rule, &kept, rule);
    grammar.rules = kept;
}
fn reachable(grammar: c.Grammar) c.Set {
    var seen: c.Set = .empty;
    _ = c.addUnique(&seen, grammar.start);
    var head: usize = 0;
    while (head < seen.items.len) : (head += 1) {
        const rule = grammar.rules.items[grammar.index(seen.items[head]).?];
        for (rule.alternatives.items) |rhs| for (rhs) |symbol| {
            if (c.nonterminal(symbol)) _ = c.addUnique(&seen, symbol);
        };
    }
    return seen;
}
fn innerLess(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a[1 .. a.len - 1], b[1 .. b.len - 1]);
}
fn removeAlternatives(grammar: *c.Grammar, removed: c.Sequence, kind: []const u8, diagnostics: *c.Lines) void {
    for (grammar.rules.items) |*rule| {
        var kept: c.Alternatives = .empty;
        for (rule.alternatives.items) |rhs| {
            var first: ?[]const u8 = null;
            for (rhs) |symbol| if (c.has(removed, symbol)) {
                first = symbol;
                break;
            };
            if (first) |symbol| diagnostics.add("removed {s} ({s} {s})", .{ c.productionText(rule.name,
                 rhs), kind, symbol }) else c.append(c.Sequence, &kept, rhs);
        }
        rule.alternatives = kept;
    }
}
fn clean(grammar: *c.Grammar, diagnostics: *c.Lines) void {
    var undefined_names: c.Set = .empty;
    for (grammar.rules.items) |rule| for (rule.alternatives.items) |rhs| for (rhs) |symbol| {
        if (c.nonterminal(symbol) and grammar.index(symbol) == null) _ = c.addUnique(&undefined_names, symbol);
    };
    std.mem.sort([]const u8, undefined_names.items, {}, innerLess);
    for (undefined_names.items) |name| diagnostics.add("undefined nonterminal {s}", .{name});
    removeAlternatives(grammar, undefined_names.items, "undefined", diagnostics);
    var productive: c.Set = .empty;
    var changed = true;
    while (changed) {
        changed = false;
        for (grammar.rules.items) |rule| for (rule.alternatives.items) |rhs| {
            var possible = true;
            for (rhs) |symbol| if (c.nonterminal(symbol) and !c.has(productive.items, symbol)) {
                possible = false;
                break;
            };
            if (possible) changed = c.addUnique(&productive, rule.name) or changed;
        };
    }
    var unproductive: c.Set = .empty;
    for (grammar.rules.items) |rule| if (!c.has(productive.items, rule.name)) {
        _ = c.addUnique(&unproductive, rule.name);
        diagnostics.add("unproductive nonterminal {s}", .{rule.name});
    };
    removeNames(grammar, unproductive.items);
    removeAlternatives(grammar, unproductive.items, "unproductive", diagnostics);
    const seen = reachable(grammar.*);
    var unreachable_names: c.Set = .empty;
    for (grammar.rules.items) |rule| if (!c.has(seen.items, rule.name)) {
        _ = c.addUnique(&unreachable_names, rule.name);
        diagnostics.add("unreachable nonterminal {s}", .{rule.name});
    };
    removeNames(grammar, unreachable_names.items);
}
fn reportRecursion(grammar: c.Grammar, diagnostics: *c.Lines) void {
    const count = grammar.rules.items.len;
    for (0..count) |start| {
        const seen = c.alloc(bool, count);
        @memset(seen, false);
        const parent = c.alloc(usize, count);
        var queue: Indices = .empty;
        c.append(usize, &queue, start);
        seen[start] = true;
        var head: usize = 0;
        var last: ?usize = null;
        while (head < queue.items.len and last == null) : (head += 1) {
            const current = queue.items[head];
            for (grammar.rules.items[current].alternatives.items) |rhs| {
                if (rhs.len == 0 or !c.nonterminal(rhs[0])) continue;
                const next = grammar.index(rhs[0]).?;
                if (next == start) {
                    last = current;
                    break;
                }
                if (!seen[next]) {
                    seen[next] = true;
                    parent[next] = current;
                    c.append(usize, &queue, next);
                }
            }
        }
        if (last) |finish| {
            var path: c.Set = .empty;
            var current = finish;
            while (current != start) {
                c.append([]const u8, &path, grammar.rules.items[current].name);
                current = parent[current];
            }
            std.mem.reverse([]const u8, path.items);
            var full: c.Set = .empty;
            c.append([]const u8, &full, grammar.rules.items[start].name);
            for (path.items) |name| c.append([]const u8, &full, name);
            c.append([]const u8, &full, grammar.rules.items[start].name);
            diagnostics.add("left recursion: {s}", .{join(full.items, " -> ")});
        }
    }
}
fn summaryLine(grammar: c.Grammar) []const u8 {
    var terminals: c.Set = .empty;
    var productions: usize = 0;
    var empty: usize = 0;
    var unit: usize = 0;
    for (grammar.rules.items) |rule| for (rule.alternatives.items) |rhs| {
        productions += 1;
        empty += @intFromBool(rhs.len == 0);
        unit += @intFromBool(rhs.len == 1 and c.nonterminal(rhs[0]));
        for (rhs) |symbol| if (!c.nonterminal(symbol)) {
            _ = c.addUnique(&terminals, symbol);
        };
    };
    return c.fmt("start={s} nonterminals={d} terminals={d} productions={d} empty={d} unit={d}", .{ grammar.start,
         grammar.rules.items.len, terminals.items.len, productions, empty, unit });
}
fn listing(out: *c.Text, grammar: c.Grammar, numbered: bool) void {
    var total: usize = 0;
    for (grammar.rules.items) |rule| total += rule.alternatives.items.len;
    const width = c.fmt("{d}", .{total}).len;
    var number: usize = 0;
    for (grammar.rules.items) |rule| for (rule.alternatives.items, 0..) |rhs, i| {
        number += 1;
        if (numbered) out.add("{s}  ", .{padded(c.fmt("{d}", .{number}), width, false)});
        out.add("{s}{s}{s}\n", .{ if (i == 0) rule.name else spaces(rule.name.len), if (i == 0) " -> " else " | ",
             c.notation(rhs) });
    };
}
fn logs(out: *c.Text, values: c.Lines) void {
    if (values.data.items.len == 0) out.add("none\n", .{}) else for (values.data.items) |line| out.add("{s}\n", .{line});
}
const Cost = struct { length: usize, height: usize };
const infinity: Cost = .{ .length = 1000000000, .height = 1000000000 };
fn sameCost(a: Cost, b: Cost) bool {
    return a.length == b.length and a.height == b.height;
}
fn lessCost(a: Cost, b: Cost) bool {
    return a.length < b.length or (a.length == b.length and a.height < b.height);
}
const Sentences = struct { length: []Cost, context: []Cost, shortest: []?c.Sequence, left: []?c.Sequence, right: []?c.Sequence };
fn alternativeCost(grammar: c.Grammar, rhs: c.Sequence, length: []const Cost) Cost {
    var out: Cost = .{ .length = 0, .height = 0 };
    for (rhs) |symbol| {
        if (c.nonterminal(symbol)) {
            const value = length[grammar.index(symbol).?];
            if (sameCost(value, infinity)) return infinity;
            out.length += value.length;
            out.height = @max(out.height, value.height);
        } else out.length += 1;
    }
    out.height += 1;
    return out;
}
fn sentenceOf(grammar: c.Grammar, rhs: c.Sequence, shortest: []const ?c.Sequence) c.Sequence {
    var out: c.Set = .empty;
    for (rhs) |symbol| {
        if (c.nonterminal(symbol)) {
            for (shortest[grammar.index(symbol).?].?) |value| c.append([]const u8, &out, value);
        } else c.append([]const u8, &out, symbol);
    }
    return out.items;
}
fn shortestFor(grammar: c.Grammar, index: usize, out: *Sentences) c.Sequence {
    if (out.shortest[index]) |known| return known;
    for (grammar.rules.items[index].alternatives.items) |rhs| if (sameCost(alternativeCost(grammar,
         rhs, out.length), out.length[index])) {
        var value: c.Set = .empty;
        for (rhs) |symbol| {
            if (c.nonterminal(symbol)) {
                for (shortestFor(grammar, grammar.index(symbol).?, out)) |word| c.append([]const u8, &value, word);
            } else c.append([]const u8, &value, symbol);
        }
        out.shortest[index] = value.items;
        return value.items;
    };
    unreachable;
}
fn occurrenceCost(grammar: c.Grammar, production: table_module.Production, position: usize, out: Sentences) Cost {
    const context = out.context[production.lhs];
    if (sameCost(context, infinity)) return infinity;
    var length = context.length;
    for (production.rhs, 0..) |symbol, i| if (i != position) {
        length += if (c.nonterminal(symbol)) out.length[grammar.index(symbol).?].length else 1;
    };
    return .{ .length = length, .height = context.height + 1 };
}
fn contextFor(grammar: c.Grammar, table: table_module.Table, index: usize, out: *Sentences) void {
    if (out.left[index] != null) return;
    for (table.productions) |production| for (production.rhs, 0..) |symbol, i| if (c.eq(symbol, grammar.rules.items[index].name) and sameCost(occurrenceCost(grammar,
         production, i, out.*), out.context[index])) {
        contextFor(grammar, table, production.lhs, out);
        out.left[index] = c.concat(out.left[production.lhs].?, sentenceOf(grammar, production.rhs[0..i], out.shortest));
        out.right[index] = c.concat(sentenceOf(grammar, production.rhs[i + 1 ..], out.shortest), out.right[production.lhs].?);
        return;
    };
    unreachable;
}
fn sentences(grammar: c.Grammar, table: table_module.Table) Sentences {
    const count = grammar.rules.items.len;
    var out: Sentences = .{ .length = c.alloc(Cost, count), .context = c.alloc(Cost, count), .shortest = c.alloc(?c.Sequence,
         count), .left = c.alloc(?c.Sequence, count), .right = c.alloc(?c.Sequence, count) };
    @memset(out.length, infinity);
    @memset(out.context, infinity);
    @memset(out.shortest, null);
    @memset(out.left, null);
    @memset(out.right, null);
    var changed = true;
    while (changed) {
        changed = false;
        for (grammar.rules.items, 0..) |rule, a| for (rule.alternatives.items) |rhs| {
            const value = alternativeCost(grammar, rhs, out.length);
            if (lessCost(value, out.length[a])) {
                out.length[a] = value;
                changed = true;
            }
        };
    }
    for (0..count) |a| _ = shortestFor(grammar, a, &out);
    const start = grammar.index(grammar.start).?;
    out.context[start] = .{ .length = 0, .height = 0 };
    changed = true;
    while (changed) {
        changed = false;
        for (table.productions) |production| for (production.rhs, 0..) |symbol, i| if (c.nonterminal(symbol)) {
            const a = grammar.index(symbol).?;
            const value = occurrenceCost(grammar, production, i, out);
            if (lessCost(value, out.context[a])) {
                out.context[a] = value;
                changed = true;
            }
        };
    }
    out.left[start] = &.{};
    out.right[start] = &.{};
    for (0..count) |a| contextFor(grammar, table, a, &out);
    return out;
}
fn conflictPath(grammar: c.Grammar, sets: first_follow.Sets, table: table_module.Table, number: usize,
     terminal: []const u8) []const usize {
    if (c.eq(table_module.reason(table, number, terminal), "FIRST")) {
        const seen = c.alloc(bool, table.productions.len);
        @memset(seen, false);
        const parent = c.alloc(usize, table.productions.len);
        var queue: Indices = .empty;
        c.append(usize, &queue, number);
        seen[number] = true;
        var head: usize = 0;
        while (head < queue.items.len) : (head += 1) {
            const current = queue.items[head];
            for (table.productions[current].rhs) |symbol| {
                if (c.eq(symbol, terminal)) {
                    var out: Indices = .empty;
                    var at = current;
                    while (at != number) {
                        c.append(usize, &out, at);
                        at = parent[at];
                    }
                    std.mem.reverse(usize, out.items);
                    return out.items;
                }
                if (c.nonterminal(symbol)) {
                    const a = grammar.index(symbol).?;
                    for (table.productions, 0..) |production, p| if (production.lhs == a and !seen[p]) {
                        seen[p] = true;
                        parent[p] = current;
                        c.append(usize, &queue, p);
                    };
                }
                if (!c.nonterminal(symbol) or !sets.nullable[grammar.index(symbol).?]) break;
            }
        }
        return &.{};
    }
    const paths = c.alloc(?[]const usize, grammar.rules.items.len);
    @memset(paths, null);
    const start = table.productions[number].lhs;
    paths[start] = &.{};
    var queue: Indices = .empty;
    c.append(usize, &queue, start);
    var head: usize = 0;
    while (head < queue.items.len) : (head += 1) {
        const current = queue.items[head];
        if (c.eq(grammar.rules.items[current].name, grammar.start) and c.eq(terminal, "$")) return paths[current].?;
        for (table.productions, 0..) |production, p| for (production.rhs, 0..) |symbol, i| if (c.eq(symbol,
             grammar.rules.items[current].name)) {
            const first = first_follow.firstSequence(production.rhs[i + 1 ..], sets);
            const old = paths[current].?;
            const path = c.alloc(usize, old.len + 1);
            @memcpy(path[0..old.len], old);
            path[old.len] = p;
            if (c.has(first.terminals.items, terminal)) return path;
            if (first.nullable and paths[production.lhs] == null) {
                paths[production.lhs] = path;
                c.append(usize, &queue, production.lhs);
            }
        };
    }
    return &.{};
}
const EarleyItem = struct { production: usize, dot: usize, origin: usize };
const Chart = struct {
    items: std.ArrayList(EarleyItem) = .empty,
    seen: std.AutoHashMapUnmanaged(EarleyItem, void) = .empty,
    fn add(self: *Chart, item: EarleyItem) void {
        const result = self.seen.getOrPut(c.allocator, item) catch @panic("allocation failed");
        if (!result.found_existing) c.append(EarleyItem, &self.items, item);
    }
};
fn language(grammar: c.Grammar, tokens: c.Sequence) bool {
    var productions: std.ArrayList(table_module.Production) = .empty;
    for (grammar.rules.items, 0..) |rule, a| for (rule.alternatives.items) |rhs| c.append(table_module.Production,
         &productions, .{ .lhs = a, .rhs = rhs });
    const augmented = productions.items.len;
    c.append(table_module.Production, &productions, .{ .lhs = grammar.rules.items.len, .rhs = &.{grammar.start} });
    const chart = c.alloc(Chart, tokens.len + 1);
    @memset(chart, .{});
    chart[0].add(.{ .production = augmented, .dot = 0, .origin = 0 });
    for (0..chart.len) |position| {
        var changed = true;
        while (changed) {
            const previous = chart[position].items.items.len;
            var index: usize = 0;
            while (index < chart[position].items.items.len) : (index += 1) {
                const item = chart[position].items.items[index];
                const production = productions.items[item.production];
                if (item.dot == production.rhs.len) {
                    const count = chart[item.origin].items.items.len;
                    for (0..count) |i| {
                        const waiting = chart[item.origin].items.items[i];
                        const source = productions.items[waiting.production];
                        if (waiting.dot < source.rhs.len and c.nonterminal(source.rhs[waiting.dot]) and grammar.index(source.rhs[waiting.dot]).? == production.lhs) chart[position].add(.{ .production = waiting.production,
                             .dot = waiting.dot + 1, .origin = waiting.origin });
                    }
                } else {
                    const symbol = production.rhs[item.dot];
                    if (c.nonterminal(symbol)) {
                        const a = grammar.index(symbol).?;
                        for (productions.items, 0..) |next, p| if (next.lhs == a) chart[position].add(.{ .production = p,
                             .dot = 0, .origin = position });
                    } else if (position < tokens.len and c.eq(symbol, tokens[position])) chart[position + 1].add(.{ .production = item.production,
                         .dot = item.dot + 1, .origin = item.origin });
                }
            }
            changed = chart[position].items.items.len != previous;
        }
    }
    return chart[tokens.len].seen.contains(.{ .production = augmented, .dot = 1, .origin = 0 });
}
fn compact(node: *const driver.Tree) *driver.Tree {
    var children: std.ArrayList(*driver.Tree) = .empty;
    for (node.children) |child| {
        if (c.eq(child.symbol, "%empty")) continue;
        const value = compact(child);
        if (value.mark.len == 0 and c.nonterminal(value.symbol) and value.children.len == 0) continue;
        if (value.mark.len == 0 and c.nonterminal(value.symbol) and std.mem.indexOfScalar(u8, value.symbol, '\'') != null) {
            for (value.children) |grandchild| c.append(*driver.Tree, &children, grandchild);
        } else c.append(*driver.Tree, &children, value);
    }
    if (children.items.len == 1 and node.mark.len == 0) return children.items[0];
    return c.create(driver.Tree, .{ .symbol = node.symbol, .mark = node.mark, .children = children.items });
}
fn label(node: *const driver.Tree) []const u8 {
    return if (node.mark.len == 0) node.symbol else c.fmt("{s} ({s})", .{ node.symbol, node.mark });
}
fn treeChildren(out: *c.Text, node: *const driver.Tree, prefix: []const u8) void {
    for (node.children, 0..) |child, i| {
        const last = i + 1 == node.children.len;
        out.add("{s}{s}{s}\n", .{ prefix, if (last) "`-- " else "|-- ", label(child) });
        treeChildren(out, child, c.fmt("{s}{s}", .{ prefix, if (last) "    " else "|   " }));
    }
}
fn printTree(out: *c.Text, node: *const driver.Tree) void {
    out.add("{s}\n", .{label(node)});
    treeChildren(out, node, "");
}
fn actionText(step: driver.Step, table: table_module.Table) []const u8 {
    return switch (step.action) {
        .accept => "accept",
        .match => c.fmt("match {s}", .{step.current}),
        .predict => blk: {
            const p = step.production.?;
            const production = table.productions[p];
            break :blk c.fmt("predict {d}: {s}", .{ p + 1, c.productionText(table.grammar.rules.items[production.lhs].name,
                 production.rhs) });
        },
        .skip => c.fmt("error: skip {s}", .{step.current}),
        .pop => c.fmt("error: pop {s}", .{step.top}),
        .missing => c.fmt("error: missing {s}", .{step.top}),
    };
}
fn errorText(step: driver.Step, number: usize, table: table_module.Table) []const u8 {
    const unexpected = if (c.eq(step.current, "$")) "end of input" else c.fmt("\"{s}\" at token {d}",
         .{ step.current, step.position });
    var expected: c.Set = .empty;
    if (c.nonterminal(step.top)) {
        const a = table.grammar.index(step.top).?;
        for (table.terminals, 0..) |terminal, t| if (table.cells[a * table.terminals.len + t].items.len > 0) c.append([]const u8,
             &expected, if (c.eq(terminal, "$")) terminal else c.fmt("\"{s}\"", .{terminal}));
    } else c.append([]const u8, &expected, if (c.eq(step.top, "$")) step.top else c.fmt("\"{s}\"", .{step.top}));
    const recovery = switch (step.action) {
        .skip => c.fmt("skipped \"{s}\"", .{step.current}),
        .pop => c.fmt("popped {s}", .{step.top}),
        else => c.fmt("inserted \"{s}\"", .{step.top}),
    };
    return c.fmt("step {d}: unexpected {s}; expected {s}; {s}", .{ number, unexpected, join(expected.items, " "), recovery });
}
fn trace(out: *c.Text, parse: driver.Parse, table: table_module.Table) void {
    var rows: std.ArrayList([4][]const u8) = .empty;
    c.append([4][]const u8, &rows, .{ "step", "stack", "input", "action" });
    for (parse.steps, 0..) |step, i| c.append([4][]const u8, &rows, .{ c.fmt("{d}", .{i + 1}), c.notation(step.stack),
         c.notation(step.input), actionText(step, table) });
    var widths = [_]usize{ 0, 0, 0 };
    for (rows.items) |row| for (0..3) |column| {
        widths[column] = @max(widths[column], row[column].len);
    };
    for (rows.items) |row| out.add("{s}  {s}  {s}  {s}\n", .{ padded(row[0], widths[0], true), padded(row[1],
         widths[1], true), padded(row[2], widths[2], true), row[3] });
}
fn reportInput(out: *c.Text, input: usize, original: c.Sequence, parse: driver.Parse, errors: c.Lines,
     belongs: bool, grammar: c.Grammar, table: table_module.Table) void {
    out.add("== input {d} ==\n", .{input + 1});
    heading(out, "tokens:", original);
    trace(out, parse, table);
    numberHeading(out, "left parse:", parse.left_parse, 1);
    out.add("stats: steps={d} predicts={d} matches={d} max_stack={d}\n", .{ parse.steps.len, parse.left_parse.len,
         parse.matches, parse.max_stack });
    if (errors.data.items.len > 0) {
        out.add("errors:\n", .{});
        for (errors.data.items) |line| out.add("  {s}\n", .{line});
    }
    if (errors.data.items.len == 0) out.add("result: accepted\n", .{}) else out.add("result: rejected (errors: {d})\n",
         .{errors.data.items.len});
    out.add("language: {s}\n", .{if (belongs) "yes" else "no"});
    if (errors.data.items.len == 0) {
        out.add("derivation:\n  {s}\n", .{grammar.start});
        var form: c.Sequence = &.{grammar.start};
        for (parse.left_parse) |number| {
            var position: usize = 0;
            while (!c.nonterminal(form[position])) position += 1;
            form = c.concat(c.concat(form[0..position], table.productions[number].rhs), form[position + 1 ..]);
            out.add("  => {s}\n", .{c.notation(form)});
        }
    }
    out.add("tree:\n", .{});
    printTree(out, parse.tree);
    out.add("compact tree:\n", .{});
    printTree(out, compact(parse.tree));
    out.add("\n", .{});
}
fn occurrenceLess(_: void, a: c.Occurrence, b: c.Occurrence) bool {
    return std.mem.lessThan(u8, a.name, b.name);
}
fn write(io: std.Io, name: []const u8, value: []const u8) !void {
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = c.fmt("output/{s}", .{name}), .data = value });
}
pub fn main(init: std.process.Init) !void {
    var permanent_arena = std.heap.ArenaAllocator.init(init.gpa);
    defer permanent_arena.deinit();
    c.allocator = permanent_arena.allocator();
    const permanent = c.allocator;
    try std.Io.Dir.cwd().createDirPath(init.io, "output");
    const parsed = c.readGrammar(try c.readLines(init.io, "input/grammar.bnf"));
    var grammar = parsed.grammar;
    var diagnostics = parsed.diagnostics;
    if (parsed.declarations) {
        std.mem.sort(c.Occurrence, parsed.word_first.items, {}, occurrenceLess);
        for (parsed.word_first.items) |entry| if (!c.has(parsed.declared.items, entry.name)) diagnostics.add("undeclared terminal {s} at line {d}",
             .{ entry.name, entry.line });
    }
    clean(&grammar, &diagnostics);
    const cleaned = grammar.clone();
    reportRecursion(cleaned, &diagnostics);
    const before = table_module.build(&cleaned, first_follow.calculate(&cleaned)).conflicts;
    const elimination = transform.eliminateRecursion(&grammar);
    const eliminated = grammar.clone();
    const factoring = transform.leftFactor(&grammar);
    const factored = grammar.clone();
    const seen = reachable(grammar);
    var removed: c.Set = .empty;
    var removal: c.Lines = .{};
    for (grammar.rules.items) |rule| if (!c.has(seen.items, rule.name)) {
        _ = c.addUnique(&removed, rule.name);
        removal.add("remove unreachable {s}", .{rule.name});
        diagnostics.add("unreachable after transformation {s}", .{rule.name});
    };
    removeNames(&grammar, removed.items);
    const sets = first_follow.calculate(&grammar);
    const table = table_module.build(&grammar, sets);
    const sentence = sentences(grammar, table);
    var known: c.Set = .empty;
    for (table.terminals) |terminal| if (!c.eq(terminal, "$")) c.append([]const u8, &known, terminal);
    if (parsed.declarations) for (c.sorted(parsed.declared.items)) |terminal| {
        if (!c.has(known.items, terminal)) diagnostics.add("unused token {s}", .{terminal});
    };
    var grammar_file: c.Text = .{};
    var sets_file: c.Text = .{};
    var table_file: c.Text = .{};
    var parses_file: c.Text = .{};
    var diagnostics_file: c.Text = .{};
    grammar_file.add("== cleaned grammar ==\n{s}\n", .{summaryLine(cleaned)});
    listing(&grammar_file, cleaned, false);
    grammar_file.add("\n== left recursion elimination ==\n", .{});
    logs(&grammar_file, elimination);
    grammar_file.add("{s}\n", .{summaryLine(eliminated)});
    listing(&grammar_file, eliminated, false);
    grammar_file.add("\n== left factoring ==\n", .{});
    logs(&grammar_file, factoring);
    grammar_file.add("{s}\n", .{summaryLine(factored)});
    listing(&grammar_file, factored, false);
    grammar_file.add("\n== final grammar ==\n", .{});
    logs(&grammar_file, removal);
    grammar_file.add("{s}\n", .{summaryLine(grammar)});
    listing(&grammar_file, grammar, true);
    grammar_file.add("\n== cross reference ==\n", .{});
    var symbols: c.Set = .empty;
    for (grammar.rules.items) |rule| c.append([]const u8, &symbols, rule.name);
    for (known.items) |terminal| c.append([]const u8, &symbols, terminal);
    for (symbols.items) |symbol| {
        var used: Indices = .empty;
        for (table.productions, 0..) |production, p| if (c.has(production.rhs, symbol)) c.append(usize, &used, p);
        const name = if (c.nonterminal(symbol)) symbol else c.fmt("\"{s}\"", .{symbol});
        if (used.items.len == 0) grammar_file.add("{s} not used\n", .{name}) else numberHeading(&grammar_file,
             c.fmt("{s} used in", .{name}), used.items, 1);
    }
    sets_file.add("passes: nullable={d} first={d} follow={d}\n\n", .{ sets.nullable_passes, sets.first_passes,
         sets.follow_passes });
    for (grammar.rules.items, 0..) |rule, a| {
        sets_file.add("{s}\n  nullable: {s}\n", .{ rule.name, if (sets.nullable[a]) "yes" else "no" });
        heading(&sets_file, "  first:", c.sorted(sets.first[a].items));
        heading(&sets_file, "  follow:", c.sorted(sets.follow[a].items));
        heading(&sets_file, "  shortest:", sentence.shortest[a].?);
    }
    table_file.add("== predict sets ==\n", .{});
    for (table.productions, 0..) |production, p| {
        table_file.add("{d}: {s}\n", .{ p + 1, c.productionText(grammar.rules.items[production.lhs].name, production.rhs) });
        heading(&table_file, "  predict:", c.sorted(table.predict[p].items));
    }
    table_file.add("\n== parse table ==\n", .{});
    var rows: std.ArrayList(c.Sequence) = .empty;
    c.append(c.Sequence, &rows, c.concat(&.{""}, table.terminals));
    for (grammar.rules.items, 0..) |rule, a| {
        const row = c.alloc([]const u8, table.terminals.len + 1);
        row[0] = rule.name;
        for (table.terminals, 0..) |_, t| {
            const cell = table.cells[a * table.terminals.len + t].items;
            row[t + 1] = if (cell.len == 0) "." else numbers(cell, 1, "/");
        }
        c.append(c.Sequence, &rows, row);
    }
    const widths = c.alloc(usize, table.terminals.len + 1);
    @memset(widths, 0);
    for (rows.items) |row| for (row, 0..) |value, i| {
        widths[i] = @max(widths[i], value.len);
    };
    for (rows.items) |row| {
        table_file.add("{s}", .{padded(row[0], widths[0], true)});
        for (row[1..], 1..) |value, i| table_file.add("  {s}", .{padded(value, widths[i], false)});
        table_file.add("\n", .{});
    }
    table_file.add("\n== conflicts ==\n", .{});
    if (table.conflicts == 0) table_file.add("none\n", .{});
    for (grammar.rules.items, 0..) |rule, a| for (table.terminals, 0..) |terminal, t| {
        const index = a * table.terminals.len + t;
        const cell = table.cells[index].items;
        if (cell.len < 2) continue;
        table_file.add("conflict {s} on {s}: {s}, chosen {d}\n", .{ rule.name, terminal, table_module.conflictKind(table,
             cell, terminal), table.chosen[index].? + 1 });
        for (cell) |number| {
            const production = table.productions[number];
            const path = conflictPath(grammar, sets, table, number, terminal);
            table_file.add("  {d}: {s} ({s}", .{ number + 1, c.productionText(grammar.rules.items[production.lhs].name,
                 production.rhs), table_module.reason(table, number, terminal) });
            if (path.len > 0) table_file.add(" via {s}", .{numbers(path, 1, " ")});
            table_file.add(")\n", .{});
        }
    };
    table_file.add("LL(1): {s}\nconflicts before transformation: {d}\n", .{ if (table.conflicts > 0) "no" else "yes", before });
    const inputs = try c.readLines(init.io, "input/inputs.txt");
    const used = c.alloc(bool, table.productions.len);
    @memset(used, false);
    var mismatches: Indices = .empty;
    var accepted_count: usize = 0;
    var in_language: usize = 0;
    var unknown_total: usize = 0;
    var skip_total: usize = 0;
    var pop_total: usize = 0;
    var missing_total: usize = 0;
    for (inputs, 0..) |line, input| {
        var scratch = std.heap.ArenaAllocator.init(init.gpa);
        c.allocator = scratch.allocator();
        const original = c.words(line);
        var tokens: std.ArrayList(driver.InputToken) = .empty;
        var errors: c.Lines = .{};
        for (original, 0..) |token, i| {
            if (!c.has(known.items, token)) {
                errors.add("unknown \"{s}\" at token {d}; removed", .{ token, i + 1 });
                unknown_total += 1;
            } else c.append(driver.InputToken, &tokens, .{ .name = token, .position = i + 1 });
        }
        const parse = driver.drive(&grammar, sets, table, tokens.items);
        for (parse.steps, 0..) |step, i| if (step.action == .skip or step.action == .pop or step.action == .missing) errors.add("{s}",
             .{errorText(step, i + 1, table)});
        const accepted = errors.data.items.len == 0;
        const belongs = language(cleaned, original);
        accepted_count += @intFromBool(accepted);
        in_language += @intFromBool(belongs);
        skip_total += parse.skip;
        pop_total += parse.pop;
        missing_total += parse.missing;
        for (parse.left_parse) |number| used[number] = true;
        var rendered: c.Text = .{};
        reportInput(&rendered, input, original, parse, errors, belongs, grammar, table);
        c.allocator = permanent;
        if (accepted != belongs) c.append(usize, &mismatches, input + 1);
        parses_file.add("{s}", .{rendered.value()});
        scratch.deinit();
    }
    parses_file.add("== summary ==\ninputs={d} accepted={d} rejected={d} in_language={d}\n", .{ inputs.len,
         accepted_count, inputs.len - accepted_count, in_language });
    numberHeading(&parses_file, "mismatches:", mismatches.items, 0);
    var used_count: usize = 0;
    for (used) |value| used_count += @intFromBool(value);
    parses_file.add("recovery: unknown={d} skip={d} pop={d} missing={d}\ncoverage: {d} of {d} productions used\n",
         .{ unknown_total, skip_total, pop_total, missing_total, used_count, table.productions.len });
    var unused: Indices = .empty;
    for (used, 0..) |value, number| if (!value) c.append(usize, &unused, number);
    numberHeading(&parses_file, "unused:", unused.items, 1);
    for (unused.items) |number| {
        var scratch = std.heap.ArenaAllocator.init(init.gpa);
        c.allocator = scratch.allocator();
        const production = table.productions[number];
        const example = c.concat(c.concat(sentence.left[production.lhs].?, sentenceOf(grammar, production.rhs,
             sentence.shortest)), sentence.right[production.lhs].?);
        const tokens = c.alloc(driver.InputToken, example.len);
        for (example, tokens, 1..) |token, *entry, i| entry.* = .{ .name = token, .position = i };
        const parse = driver.drive(&grammar, sets, table, tokens);
        const errors = parse.skip + parse.pop + parse.missing;
        var rendered: c.Text = .{};
        rendered.add("  {d}: {s}\n", .{ number + 1, c.productionText(grammar.rules.items[production.lhs].name, production.rhs) });
        heading(&rendered, "    example:", example);
        if (errors > 0) rendered.add("    result: rejected (errors: {d})\n", .{errors}) else rendered.add("    result: accepted\n",
             .{});
        var found = false;
        for (parse.left_parse) |p| if (p == number) {
            found = true;
        };
        rendered.add("    used: {s}\n", .{if (found) "yes" else "no"});
        c.allocator = permanent;
        parses_file.add("{s}", .{rendered.value()});
        scratch.deinit();
    }
    for (diagnostics.data.items) |line| diagnostics_file.add("{s}\n", .{line});
    if (table.conflicts > 0) diagnostics_file.add("result: not LL(1) (conflicts: {d})\n", .{table.conflicts}) else diagnostics_file.add("result: LL(1)\n",
         .{});
    try write(init.io, "grammar.txt", grammar_file.value());
    try write(init.io, "sets.txt", sets_file.value());
    try write(init.io, "table.txt", table_file.value());
    try write(init.io, "parses.txt", parses_file.value());
    try write(init.io, "diagnostics.txt", diagnostics_file.value());
}
