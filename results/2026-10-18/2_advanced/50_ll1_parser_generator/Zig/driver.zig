const std = @import("std");
const c = @import("grammar_parser.zig");
const first_follow = @import("first_follow.zig");
const table_module = @import("table.zig");
pub const InputToken = struct { name: []const u8, position: usize };
pub const Tree = struct { symbol: []const u8, mark: []const u8 = "", children: []*Tree = &.{} };
pub const Action = enum { accept, match, predict, skip, pop, missing };
pub const Step = struct { stack: c.Sequence, input: c.Sequence, top: []const u8, current: []const u8,
     position: usize, production: ?usize = null, action: Action = .accept };
pub const Parse = struct { steps: []const Step, left_parse: []const usize, tree: *Tree, matches: usize = 0,
     max_stack: usize = 0, skip: usize = 0, pop: usize = 0, missing: usize = 0 };
const Entry = struct { symbol: []const u8, node: ?*Tree };
pub fn drive(grammar: *const c.Grammar, sets: first_follow.Sets, table: table_module.Table, input: []const InputToken) Parse {
    const tokens = c.alloc(InputToken, input.len + 1);
    @memcpy(tokens[0..input.len], input);
    tokens[input.len] = .{ .name = "$", .position = 0 };
    const root = c.create(Tree, .{ .symbol = grammar.start });
    var stack: std.ArrayList(Entry) = .empty;
    c.append(Entry, &stack, .{ .symbol = "$", .node = null });
    c.append(Entry, &stack, .{ .symbol = grammar.start, .node = root });
    var out: Parse = .{ .steps = &.{}, .left_parse = &.{}, .tree = root };
    var steps: std.ArrayList(Step) = .empty;
    var left_parse: std.ArrayList(usize) = .empty;
    var current: usize = 0;
    while (true) {
        const stack_symbols = c.alloc([]const u8, stack.items.len);
        for (stack.items, stack_symbols) |entry, *symbol| symbol.* = entry.symbol;
        const rest = c.alloc([]const u8, tokens.len - current);
        for (tokens[current..], rest) |token, *symbol| symbol.* = token.name;
        out.max_stack = @max(out.max_stack, stack.items.len);
        const top = stack.items[stack.items.len - 1];
        var step: Step = .{ .stack = stack_symbols, .input = rest, .top = top.symbol, .current = tokens[current].name,
             .position = tokens[current].position };
        if (c.eq(top.symbol, "$") and c.eq(step.current, "$")) {
            step.action = .accept;
            c.append(Step, &steps, step);
            break;
        }
        if (c.eq(top.symbol, "$")) {
            step.action = .skip;
            out.skip += 1;
            current += 1;
        } else if (!c.nonterminal(top.symbol)) {
            _ = stack.pop();
            if (c.eq(top.symbol, step.current)) {
                step.action = .match;
                out.matches += 1;
                current += 1;
            } else {
                step.action = .missing;
                out.missing += 1;
                top.node.?.mark = "missing";
            }
        } else {
            const lhs = grammar.index(top.symbol).?;
            const terminal = table.terminalIndex(step.current).?;
            if (table.chosen[lhs * table.terminals.len + terminal]) |chosen| {
                step.action = .predict;
                step.production = chosen;
                c.append(usize, &left_parse, chosen);
                _ = stack.pop();
                const rhs = table.productions[chosen].rhs;
                if (rhs.len == 0) {
                    top.node.?.children = c.alloc(*Tree, 1);
                    top.node.?.children[0] = c.create(Tree, .{ .symbol = "%empty" });
                } else {
                    top.node.?.children = c.alloc(*Tree, rhs.len);
                    for (rhs, top.node.?.children) |symbol, *child| child.* = c.create(Tree, .{ .symbol = symbol });
                    var remaining = rhs.len;
                    while (remaining > 0) {
                        remaining -= 1;
                        c.append(Entry, &stack, .{ .symbol = rhs[remaining], .node = top.node.?.children[remaining] });
                    }
                }
            } else if (c.eq(step.current, "$") or c.has(sets.follow[lhs].items, step.current)) {
                step.action = .pop;
                out.pop += 1;
                top.node.?.mark = "error";
                _ = stack.pop();
            } else {
                step.action = .skip;
                out.skip += 1;
                current += 1;
            }
        }
        c.append(Step, &steps, step);
    }
    out.steps = steps.items;
    out.left_parse = left_parse.items;
    return out;
}
