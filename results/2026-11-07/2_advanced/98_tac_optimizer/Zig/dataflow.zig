const std = @import("std");
const tac = @import("tac_parser.zig");
const cfg = @import("cfg.zig");
pub const Set = cfg.Set;
pub const Definition = struct { variable: tac.Text, number: usize };
pub const Copy = struct { dest: tac.Text, source: tac.Text };
pub const Analysis = struct { input: []Set, output: []Set, before: []Set, after: []Set, iterations: usize = 0 };
pub const Flow = struct { a: tac.Allocator, function: tac.Function, graph: cfg.Graph, variables: []const tac.Text, definitions: []const Definition, expressions: []const tac.Instruction, copies: []const Copy, reaching: Analysis, live: Analysis, available: Analysis, copying: Analysis,
    pub fn variable(flow: *const Flow, name: tac.Text) usize { for (flow.variables, 0..) |v, i| if (tac.eq(v, name)) return i; unreachable; }
    pub fn expression(flow: *const Flow, ins: tac.Instruction) ?usize { for (flow.expressions, 0..) |e, i| if (sameExpression(e, ins)) return i; return null; }
    pub fn transfer(flow: *const Flow, set: *Set, ins: tac.Instruction, number: usize, mode: usize) void {
        const used = ins.used();
        if (mode == 0) { if (ins.dest.len > 0) { for (flow.definitions, 0..) |d, i| { if (tac.eq(d.variable, ins.dest)) set.unset(i); } for (flow.definitions, 0..) |d, i| { if (d.number == number and tac.eq(d.variable, ins.dest)) set.set(i); } } }
        else if (mode == 1) { if (ins.dest.len > 0) set.unset(flow.variable(ins.dest)); for (used) |v| if (tac.variable(v)) { set.set(flow.variable(v)); }; }
        else if (mode == 2) {
            if (flow.expression(ins)) |i| set.set(i);
            for (flow.expressions, 0..) |e, i| {
                if ((ins.kind == .store and e.kind == .load and tac.eq(e.array, ins.array)) or (ins.kind == .call and e.kind == .load)) set.unset(i);
                if (ins.dest.len > 0) for (e.used()) |v| { if (tac.eq(v, ins.dest)) set.unset(i); };
            }
        } else {
            if (ins.dest.len > 0) for (flow.copies, 0..) |copy, i| { if (tac.eq(copy.dest, ins.dest) or tac.eq(copy.source, ins.dest)) set.unset(i); };
            if (ins.kind == .copy and tac.variable(ins.a) and !tac.eq(ins.dest, ins.a)) for (flow.copies, 0..) |copy, i| { if (tac.eq(copy.dest, ins.dest) and tac.eq(copy.source, ins.a)) set.set(i); };
        }
    }
};
pub fn sameExpression(a: tac.Instruction, b: tac.Instruction) bool { return a.kind == b.kind and (a.kind == .bin or a.kind == .load) and tac.eq(a.op, b.op) and tac.eq(a.array, b.array) and tac.eq(a.a, b.a) and tac.eq(a.b, b.b); }
fn unique(a: tac.Allocator, list: *std.ArrayList(tac.Text), name: tac.Text) !void { if (!tac.variable(name)) return; for (list.items) |n| if (tac.eq(n, name)) return; try list.append(a, name); }
fn allocate(a: tac.Allocator, blocks: usize, instructions: usize) !Analysis { const input = try a.alloc(Set, blocks); const output = try a.alloc(Set, blocks); const before = try a.alloc(Set, instructions); const after = try a.alloc(Set, instructions); @memset(input, .initEmpty()); @memset(output, .initEmpty()); @memset(before, .initEmpty()); @memset(after, .initEmpty()); return .{ .input = input, .output = output, .before = before, .after = after }; }
fn solve(f: *Flow, mode: usize) void {
    const analysis = switch (mode) { 0 => &f.reaching, 1 => &f.live, 2 => &f.available, else => &f.copying };
    var universe = Set.initEmpty(); if (mode >= 2) { const n = if (mode == 2) f.expressions.len else f.copies.len; for (0..n) |i| universe.set(i); for (analysis.output) |*s| s.* = universe; }
    while (true) {
        analysis.iterations += 1; var changed = false; const order = if (mode == 1) f.graph.post else f.graph.reverse;
        for (order) |bi| {
            const b = f.graph.blocks[bi]; var set = if (mode >= 2 and bi != 0) universe else Set.initEmpty();
            if (mode == 1) { for (b.succs.items) |s| set.setUnion(analysis.input[s]); analysis.output[bi] = set; var n = b.end; while (n > b.first) { n -= 1; f.transfer(&set, f.function.code[n], n + 1, mode); } if (!set.eql(analysis.input[bi])) changed = true; analysis.input[bi] = set; }
            else {
                if (bi != 0 or mode == 0) for (b.preds.items) |p| { if (!f.graph.blocks[p].reachable) continue; if (mode == 0) set.setUnion(analysis.output[p]) else set.setIntersection(analysis.output[p]); };
                if (bi == 0 and mode == 0) for (f.definitions, 0..) |d, i| { if (d.number == 0) set.set(i); };
                analysis.input[bi] = set; for (b.first..b.end) |n| f.transfer(&set, f.function.code[n], n + 1, mode); if (!set.eql(analysis.output[bi])) changed = true; analysis.output[bi] = set;
            }
        }
        if (!changed) break;
    }
    for (f.graph.reverse) |bi| { const b = f.graph.blocks[bi]; var set = if (mode == 1) analysis.output[bi] else analysis.input[bi]; if (mode == 1) { var n = b.end; while (n > b.first) { n -= 1; analysis.after[n] = set; f.transfer(&set, f.function.code[n], n + 1, mode); analysis.before[n] = set; } } else for (b.first..b.end) |n| { analysis.before[n] = set; f.transfer(&set, f.function.code[n], n + 1, mode); analysis.after[n] = set; }; }
}
pub fn analyze(a: tac.Allocator, function: tac.Function) !Flow {
    const graph = try cfg.build(a, function); var vars: std.ArrayList(tac.Text) = .empty; var definitions: std.ArrayList(Definition) = .empty; var expressions: std.ArrayList(tac.Instruction) = .empty; var copies: std.ArrayList(Copy) = .empty;
    for (function.params) |p| { try unique(a, &vars, p); try definitions.append(a, .{ .variable = p, .number = 0 }); }
    for (function.code, 0..) |ins, n| {
        if (!graph.blocks[graph.owner[n]].reachable) continue; try unique(a, &vars, ins.dest); for (ins.used()) |v| try unique(a, &vars, v);
        if (ins.dest.len > 0) try definitions.append(a, .{ .variable = ins.dest, .number = n + 1 });
        if (ins.kind == .bin or ins.kind == .load) { var found = false; for (expressions.items) |e| if (sameExpression(e, ins)) { found = true; break; }; if (!found) try expressions.append(a, ins); }
        if (ins.kind == .copy and tac.variable(ins.a) and !tac.eq(ins.dest, ins.a)) { var found = false; for (copies.items) |c| if (tac.eq(c.dest, ins.dest) and tac.eq(c.source, ins.a)) { found = true; break; }; if (!found) try copies.append(a, .{ .dest = ins.dest, .source = ins.a }); }
    }
    std.mem.sort(tac.Text, vars.items, {}, tac.less);
    var flow: Flow = .{ .a = a, .function = function, .graph = graph, .variables = vars.items, .definitions = definitions.items, .expressions = expressions.items, .copies = copies.items, .reaching = try allocate(a, graph.blocks.len, function.code.len), .live = try allocate(a, graph.blocks.len, function.code.len), .available = try allocate(a, graph.blocks.len, function.code.len), .copying = try allocate(a, graph.blocks.len, function.code.len) };
    for (0..4) |mode| solve(&flow, mode); return flow;
}
