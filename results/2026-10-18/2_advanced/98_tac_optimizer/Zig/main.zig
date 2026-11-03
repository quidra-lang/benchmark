const std = @import("std");
const tac = @import("tac_parser.zig");
const cfg = @import("cfg.zig");
const df = @import("dataflow.zig");
const opt = @import("optimizations.zig");
const registers = @import("regalloc.zig");
const Text = tac.Text;
const pass_names = [_]Text{"constprop", "copyprop", "cse", "dce", "licm", "unreachable"};
fn list(b: *tac.Buffer, names: []const Text) !void { if (names.len == 0) try b.add("-"); for (names, 0..) |n, i| { if (i > 0) try b.add(","); try b.add(n); } }
fn blocks(b: *tac.Buffer, set: cfg.Set) !void { var it = set.iterator(.{}); var first = true; while (it.next()) |n| { if (!first) try b.add(","); try b.print("B{d}", .{n + 1}); first = false; } if (first) try b.add("-"); }
fn sequence(b: *tac.Buffer, values: []const usize, block: bool) !void { if (values.len == 0) try b.add("-"); for (values, 0..) |v, i| { if (i > 0) try b.add(","); if (block) try b.print("B{d}", .{v + 1}) else try b.print("{d}", .{v}); } }
fn tree(b: *tac.Buffer, graph: cfg.Graph, node: usize, depth: usize) anyerror!void { for (0..depth * 2) |_| try b.add(" "); try b.print("B{d}\n", .{node + 1}); for (graph.blocks, 0..) |child, i| if (child.reachable and child.idom == node) { try tree(b, graph, i, depth + 1); }; }
fn setText(b: *tac.Buffer, flow: *const df.Flow, set: cfg.Set, mode: usize) !void {
    var names: std.ArrayList(Text) = .empty;
    if (mode == 0) {
        const indices = try b.a.alloc(usize, set.count()); var p: usize = 0; var it = set.iterator(.{}); while (it.next()) |i| { indices[p] = i; p += 1; }
        std.mem.sort(usize, indices, flow, struct { fn cmp(f: *const df.Flow, x: usize, y: usize) bool { const a = f.definitions[x]; const c = f.definitions[y]; return if (a.number == c.number) tac.less({}, a.variable, c.variable) else a.number < c.number; } }.cmp);
        for (indices) |i| { const d = flow.definitions[i]; try names.append(b.a, try std.fmt.allocPrint(b.a, "{s}:{d}", .{d.variable, d.number})); }
    } else { var it = set.iterator(.{}); while (it.next()) |i| try names.append(b.a, if (mode == 1) flow.variables[i] else (try flow.expressions[i].expression(b.a)).?); std.mem.sort(Text, names.items, {}, tac.less); }
    try list(b, names.items);
}
fn analysis(b: *tac.Buffer, f: tac.Function, kind: Text) !void {
    const flow = try df.analyze(b.a, f); const graph = flow.graph; try b.print("== {s} ({s}) ==\ncode:\n", .{f.name, kind});
    for (f.code, 0..) |ins, n| {
        for (ins.labels) |label| try b.print("{s}:\n", .{label}); try b.print("  #{d} {s}", .{n + 1, try ins.text(b.a)});
        if (graph.blocks[graph.owner[n]].reachable) { var seen: std.ArrayList(Text) = .empty; for (ins.used()) |v| {
            if (!tac.variable(v)) continue; var duplicate = false; for (seen.items) |old| if (tac.eq(v, old)) { duplicate = true; }; if (duplicate) continue;
            try b.add(if (seen.items.len == 0) " | " else " "); try seen.append(b.a, v); try b.print("{s}:", .{v}); var numbers: std.ArrayList(usize) = .empty; var it = flow.reaching.before[n].iterator(.{}); while (it.next()) |i| { const d = flow.definitions[i]; if (tac.eq(v, d.variable)) try numbers.append(b.a, d.number); } std.mem.sort(usize, numbers.items, {}, std.sort.asc(usize)); try sequence(b, numbers.items, false);
        } }
        try b.add("\n");
    }
    try b.print("blocks: {d}\n", .{graph.blocks.len}); var unreachable_blocks = cfg.Set.initEmpty();
    for (graph.blocks, 0..) |block, i| { try b.print("B{d} {d}-{d} labels=", .{i + 1, block.first + 1, block.end}); try list(b, block.labels); try b.add(" preds="); try sequence(b, block.preds.items, true); try b.add(" succs="); try sequence(b, block.succs.items, true); try b.add("\n"); if (!block.reachable) unreachable_blocks.set(i); }
    try b.add("unreachable: "); try blocks(b, unreachable_blocks); try b.add("\norder: "); try sequence(b, graph.reverse, true); try b.line("\ndominators:");
    for (graph.blocks, 0..) |block, i| if (block.reachable) { try b.print("B{d} idom=", .{i + 1}); if (block.idom) |parent| try b.print("B{d}", .{parent + 1}) else try b.add("-"); try b.add(" dom="); try blocks(b, block.dom); try b.add("\n"); };
    try b.line("dominator tree:"); try tree(b, graph, 0, 0); try b.print("loops: {d}\n", .{graph.loops.len});
    for (graph.loops) |loop| { try b.print("header=B{d} latches=", .{loop.header + 1}); try blocks(b, loop.latches); try b.print(" depth={d} blocks=", .{loop.depth}); try blocks(b, loop.blocks); try b.add(" exits="); try blocks(b, loop.exits); try b.add("\n"); }
    for ([_]Text{"reaching definitions", "liveness", "available expressions"}, [_]df.Analysis{flow.reaching, flow.live, flow.available}, 0..) |name, sets, mode| {
        try b.print("{s}: iterations={d}\n", .{name, sets.iterations}); for (graph.blocks, 0..) |block, i| if (block.reachable) { try b.print("B{d} in=", .{i + 1}); try setText(b, &flow, sets.input[i], mode); try b.add(" out="); try setText(b, &flow, sets.output[i], mode); try b.add("\n"); };
    }
}
const Calls = struct { edges: []cfg.Set, reachable: cfg.Set };
fn functionIndex(program: tac.Program, name: Text) usize { for (program.functions, 0..) |f, i| if (tac.eq(f.name, name)) return i; unreachable; }
fn callGraph(a: tac.Allocator, p: tac.Program) !Calls {
    const edges = try a.alloc(cfg.Set, p.functions.len); @memset(edges, .initEmpty()); for (p.functions, 0..) |f, i| for (f.code) |ins| { if (ins.kind == .call) edges[i].set(functionIndex(p, ins.target)); };
    var reach = cfg.Set.initEmpty(); reach.set(functionIndex(p, "main")); while (true) { const before = reach; var it = before.iterator(.{}); while (it.next()) |n| reach.setUnion(edges[n]); if (before.eql(reach)) break; } return .{ .edges = edges, .reachable = reach };
}
fn callGraphText(b: *tac.Buffer, p: tac.Program, heading: Text) !Calls {
    const graph = try callGraph(b.a, p); try b.print("== call graph ({s}) ==\n", .{heading}); var unreachable_functions: std.ArrayList(Text) = .empty;
    for (p.functions, 0..) |f, i| {
        try b.print("{s} -> ", .{f.name}); var names: std.ArrayList(Text) = .empty; var it = graph.edges[i].iterator(.{}); while (it.next()) |n| try names.append(b.a, p.functions[n].name); try list(b, names.items);
        var closure = graph.edges[i]; while (true) { const before = closure; it = before.iterator(.{}); while (it.next()) |n| closure.setUnion(graph.edges[n]); if (before.eql(closure)) break; } if (closure.isSet(i)) try b.add(" (recursive)"); try b.add("\n"); if (!graph.reachable.isSet(i)) try unreachable_functions.append(b.a, f.name);
    }
    try b.add("unreachable functions: "); try list(b, unreachable_functions.items); try b.add("\n"); return graph;
}
fn rename(a: tac.Allocator, alloc: registers.Allocation, name: Text) !Text { if (!tac.variable(name)) return name; for (alloc.names, alloc.registers) |n, r| if (tac.eq(n, name)) return if (r) |v| try std.fmt.allocPrint(a, "R{d}", .{v}) else name; return name; }
fn spilled(alloc: registers.Allocation, name: Text) bool { for (alloc.names, alloc.registers) |n, r| if (tac.eq(n, name)) return r == null; return false; }
fn allocated(b: *tac.Buffer, f: tac.Function, k: usize) !tac.Function {
    var flow = try df.analyze(b.a, f); const alloc = try registers.allocate(b.a, f, &flow, k); var edges: usize = 0; for (alloc.neighbors) |ns| edges += ns.count();
    try b.print("== {s} ==\nnodes={d} edges={d} registers={d}\n", .{f.name, alloc.names.len, edges / 2, k});
    for (alloc.names, 0..) |n, i| { try b.print("{s} degree={d} cost={d} neighbors=", .{n, alloc.neighbors[i].count(), alloc.costs[i]}); var names: std.ArrayList(Text) = .empty; var it = alloc.neighbors[i].iterator(.{}); while (it.next()) |j| try names.append(b.a, alloc.names[j]); try list(b, names.items); try b.add("\n"); }
    try b.add("simplify: "); for (alloc.order, 0..) |i, n| { if (n > 0) try b.add(","); try b.add(alloc.names[i]); } if (alloc.order.len == 0) try b.add("-"); try b.add("\npotential spills: ");
    for (alloc.potential, 0..) |p, i| { if (i > 0) try b.add(","); try b.print("{s}({d}/{d})", .{alloc.names[p.node], alloc.costs[p.node], p.degree}); } if (alloc.potential.len == 0) try b.add("-"); try b.add("\n");
    var used = cfg.Set.initEmpty(); var spills: usize = 0;
    for (alloc.names, alloc.registers) |name, r| { try b.print("{s} -> ", .{name}); if (r) |reg| { used.set(reg); try b.print("R{d}\n", .{reg}); } else { spills += 1; try b.line("spill"); } }
    const params = try b.a.alloc(Text, f.params.len); var spill_defs: usize = 0; var spill_uses: usize = 0; var moves: usize = 0; for (f.params, 0..) |p, i| { params[i] = try rename(b.a, alloc, p); if (spilled(alloc, p)) spill_defs += 1; }
    var code: std.ArrayList(tac.Instruction) = .empty; var pending: std.ArrayList(Text) = .empty;
    for (f.code) |old| { var ins = old; try pending.appendSlice(b.a, old.labels); if (ins.dest.len > 0) { ins.dest = try rename(b.a, alloc, ins.dest); if (spilled(alloc, old.dest)) spill_defs += 1; }
        for (old.used(), 0..) |v, index| if (tac.variable(v)) { const new = try rename(b.a, alloc, v); ins.operand(index).* = new; if (spilled(alloc, v)) spill_uses += 1; };
        if (ins.kind == .copy and tac.eq(ins.dest, ins.a)) { moves += 1; continue; } ins.labels = pending.items; pending = .empty; try code.append(b.a, ins);
    }
    try b.print("summary: pressure={d} used={d} spilled={d} moves={d} spill_uses={d} spill_defs={d}\n", .{alloc.pressure, used.count(), spills, moves, spill_uses, spill_defs});
    const result: tac.Function = .{ .name = f.name, .params = params, .code = code.items }; try tac.functionText(b, result); return result;
}
const Execution = struct {
    a: tac.Allocator, program: tac.Program, inputs: []const i64, position: usize = 0, arrays: [][]i64,
    steps: []usize, calls: []usize, kinds: [11]usize = @splat(0), output: std.ArrayList(i64) = .empty,
    fn value(table: *std.StringHashMapUnmanaged(i64), operand: Text) i64 { return if (tac.variable(operand)) table.get(operand).? else if (operand.len == 0) 0 else tac.number(operand); }
    fn array(e: *Execution, name: Text) []i64 { for (e.program.arrays, 0..) |ar, i| if (tac.eq(ar.name, name)) return e.arrays[i]; unreachable; }
    fn call(e: *Execution, fi: usize, args: []const i64) anyerror!i64 {
        const f = e.program.functions[fi]; e.calls[fi] += 1; var table: std.StringHashMapUnmanaged(i64) = .empty; var pushed: std.ArrayList(i64) = .empty; for (f.params, args) |p, v| try table.put(e.a, p, v); var pc: usize = 0;
        while (pc < f.code.len) {
            const ins = f.code[pc]; e.steps[fi] += 1; e.kinds[@intFromEnum(ins.kind)] += 1; pc += 1;
            switch (ins.kind) {
                .copy => try table.put(e.a, ins.dest, value(&table, ins.a)), .bin => try table.put(e.a, ins.dest, tac.calculate(ins.op, value(&table, ins.a), value(&table, ins.b))),
                .load => try table.put(e.a, ins.dest, e.array(ins.array)[@intCast(value(&table, ins.a))]), .store => e.array(ins.array)[@intCast(value(&table, ins.a))] = value(&table, ins.b),
                .goto, .@"if" => if (ins.kind == .goto or tac.calculate(ins.op, value(&table, ins.a), value(&table, ins.b)) != 0) { outer: for (f.code, 0..) |target, index| for (target.labels) |label| if (tac.eq(label, ins.target)) { pc = index; break :outer; }; },
                .param => try pushed.append(e.a, value(&table, ins.a)),
                .call => { const start = pushed.items.len - ins.count; const result = try e.call(functionIndex(e.program, ins.target), pushed.items[start..]); pushed.items.len = start; if (ins.dest.len > 0) try table.put(e.a, ins.dest, result); },
                .@"return" => return if (ins.a.len > 0) value(&table, ins.a) else 0,
                .read => { try table.put(e.a, ins.dest, e.inputs[e.position]); e.position += 1; }, .print => try e.output.append(e.a, value(&table, ins.a)),
            }
        }
        return 0;
    }
};
fn execute(a: tac.Allocator, p: tac.Program, input: []const i64) !Execution {
    const arrays = try a.alloc([]i64, p.arrays.len); for (p.arrays, 0..) |ar, i| { arrays[i] = try a.alloc(i64, ar.size); @memset(arrays[i], 0); }
    const steps = try a.alloc(usize, p.functions.len); const calls = try a.alloc(usize, p.functions.len); @memset(steps, 0); @memset(calls, 0);
    var e: Execution = .{ .a = a, .program = p, .inputs = input, .arrays = arrays, .steps = steps, .calls = calls }; _ = try e.call(functionIndex(p, "main"), &.{}); return e;
}
fn sum(xs: []const usize) usize { var s: usize = 0; for (xs) |v| s += v; return s; }
fn instructionCounts(p: tac.Program) [11]usize { var counts: [11]usize = @splat(0); for (p.functions) |f| for (f.code) |i| { counts[@intFromEnum(i.kind)] += 1; }; return counts; }
fn comparison(b: *tac.Buffer, programs: [3]tac.Program, source: Text) !void {
    var lines = std.mem.tokenizeScalar(u8, source, '\n'); const runs: usize = @intCast(tac.number(lines.next().?)); const profiles = try b.a.alloc([3]usize, programs[0].functions.len); @memset(profiles, @splat(0)); const calls = try b.a.alloc(usize, programs[0].functions.len); @memset(calls, 0); var kinds: [3][11]usize = @splat(@splat(0)); var totals: [3]usize = @splat(0); var same: usize = 0;
    for (0..runs) |run| {
        var words = std.mem.tokenizeScalar(u8, lines.next().?, ' '); const count: usize = @intCast(tac.number(words.next().?)); const inputs = try b.a.alloc(i64, count); for (inputs) |*value| value.* = tac.number(words.next().?);
        try b.print("run {d}: inputs={d}\n", .{run + 1, count}); var outputs: [3][]const i64 = undefined;
        for (programs, [_]Text{"original", "optimized", "allocated"}, 0..) |p, name, pi| {
            const execution = try execute(b.a, p, inputs); outputs[pi] = execution.output.items; totals[pi] += sum(execution.steps); for (execution.kinds, 0..) |n, ki| kinds[pi][ki] += n;
            for (programs[0].functions, 0..) |f, oi| { for (p.functions, 0..) |other, fi| if (tac.eq(f.name, other.name)) { profiles[oi][pi] += execution.steps[fi]; if (pi == 0) calls[oi] += execution.calls[fi]; }; }
            try b.print("  {s}: steps={d} calls={d} output=", .{name, sum(execution.steps), sum(execution.calls)}); if (execution.output.items.len == 0) try b.add("-"); for (execution.output.items, 0..) |v, i| { if (i > 0) try b.add(","); try b.print("{d}", .{v}); } try b.add("\n");
        }
        const equal = std.mem.eql(i64, outputs[0], outputs[1]) and std.mem.eql(i64, outputs[0], outputs[2]); if (equal) same += 1; try b.print("  result: {s}\n", .{if (equal) "same" else "different"});
    }
    try b.line("== profile =="); for (programs[0].functions, profiles, calls) |f, profile, count| try b.print("{s}: calls={d} original={d} optimized={d} allocated={d}\n", .{f.name, count, profile[0], profile[1], profile[2]});
    const before = instructionCounts(programs[0]); const after = instructionCounts(programs[1]); try b.print("== summary ==\nruns={d} same={d} different={d}\ninstructions: original={d} optimized={d}\nkinds: ", .{runs, same, runs - same, sum(&before), sum(&after)});
    for (before, after, 0..) |x, y, ki| { if (ki > 0) try b.add(" "); try b.print("{s}={d}->{d}", .{@tagName(@as(tac.Kind, @enumFromInt(ki))), x, y}); }
    try b.print("\nsteps: original={d} optimized={d} allocated={d}\n", .{totals[0], totals[1], totals[2]});
    for (kinds, [_]Text{"original", "optimized", "allocated"}) |counts, name| { try b.print("dynamic {s}: ", .{name}); for (counts, 0..) |n, ki| { if (ki > 0) try b.add(" "); try b.print("{s}={d}", .{@tagName(@as(tac.Kind, @enumFromInt(ki))), n}); } try b.add("\n"); }
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa); defer arena.deinit(); const a = arena.allocator(); const source = try std.Io.Dir.cwd().readFileAlloc(init.io, "input/program.tac", a, .unlimited); const original = try tac.parse(a, source); var optimized = try tac.parse(a, source);
    const params = try std.Io.Dir.cwd().readFileAlloc(init.io, "input/params.txt", a, .unlimited); var words = std.mem.tokenizeAny(u8, params, " \n"); _ = words.next(); const k: usize = @intCast(tac.number(words.next().?)); _ = words.next(); var enabled: [6]bool = @splat(false); var max_rounds: usize = 0;
    while (words.next()) |word| { if (tac.eq(word, "max_rounds")) { max_rounds = @intCast(tac.number(words.next().?)); break; } for (pass_names, 0..) |name, i| if (tac.eq(name, word)) { enabled[i] = true; }; }
    var analyses: tac.Buffer = .{ .a = a }; var passes: tac.Buffer = .{ .a = a }; var allocation: tac.Buffer = .{ .a = a }; var compare: tac.Buffer = .{ .a = a }; var program_text: tac.Buffer = .{ .a = a };
    _ = try callGraphText(&analyses, original, "original"); for (original.functions) |f| try analysis(&analyses, f, "original"); var total: [6]usize = @splat(0);
    for (optimized.functions) |*f| {
        const before = f.code.len; try passes.print("== {s} ==\n", .{f.name}); var rounds: usize = 0;
        while (rounds < max_rounds) {
            rounds += 1; try passes.print("round {d}: ", .{rounds}); var records: tac.Buffer = .{ .a = a }; var changes: usize = 0; var first = true;
            for (pass_names, enabled, 0..) |name, on, pi| if (on) {
                const result = try opt.run(a, f, name); total[pi] += result.count; changes += result.count; if (!first) try passes.add(" "); first = false; try passes.print("{s}={d}", .{name, result.count}); for (result.records.items) |r| try records.print("  {s} {s}\n", .{name, r});
            };
            try passes.add("\n"); try passes.add(records.data.items); if (changes == 0) break;
        }
        try passes.print("result: rounds={d} instructions={d}->{d}\n", .{rounds, before, f.code.len});
    }
    const graph = try callGraphText(&analyses, optimized, "optimized"); var removed: std.ArrayList(Text) = .empty; var kept: std.ArrayList(tac.Function) = .empty;
    for (optimized.functions, 0..) |f, i| { if (enabled[5] and !graph.reachable.isSet(i)) try removed.append(a, f.name) else try kept.append(a, f); } optimized.functions = kept.items;
    try passes.add("== program ==\nremoved functions: "); try list(&passes, removed.items); try passes.add("\n== total ==\n"); var first = true;
    for (pass_names, enabled, total) |name, on, count| if (on) { if (!first) try passes.add(" "); first = false; try passes.print("{s}={d}", .{name, count}); }; try passes.add("\n");
    var allocated_functions: std.ArrayList(tac.Function) = .empty;
    for (optimized.functions) |f| { try analysis(&analyses, f, "optimized"); try allocated_functions.append(a, try allocated(&allocation, f, k)); }
    const allocated_program: tac.Program = .{ .arrays = optimized.arrays, .functions = allocated_functions.items }; try tac.programText(&program_text, optimized);
    try comparison(&compare, .{original, optimized, allocated_program}, try std.Io.Dir.cwd().readFileAlloc(init.io, "input/input.txt", a, .unlimited));
    for ([_]Text{"optimized.tac", "analysis.txt", "passes.txt", "regalloc.txt", "comparison.txt"}, [_]Text{program_text.data.items, analyses.data.items, passes.data.items, allocation.data.items, compare.data.items}) |name, data| { const file = try std.Io.Dir.cwd().createFile(init.io, try std.fmt.allocPrint(a, "output/{s}", .{name}), .{}); defer file.close(init.io); try file.writeStreamingAll(init.io, data); }
}
