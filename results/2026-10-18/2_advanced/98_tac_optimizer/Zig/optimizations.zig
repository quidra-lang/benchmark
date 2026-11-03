const std = @import("std");
const tac = @import("tac_parser.zig");
const cfg = @import("cfg.zig");
const df = @import("dataflow.zig");
pub const Result = struct { count: usize = 0, records: std.ArrayList(tac.Text) = .empty };
fn record(a: tac.Allocator, r: *Result, comptime f: tac.Text, args: anytype) !void { try r.records.append(a, try std.fmt.allocPrint(a, f, args)); }
fn copy(ins: *tac.Instruction, source: tac.Text) void { ins.kind = .copy; ins.a = source; ins.b = ""; ins.op = ""; ins.array = ""; }
fn rebuilt(a: tac.Allocator, original: []const tac.Instruction, changed: []const ?tac.Instruction, after: ?[]std.ArrayList(tac.Instruction)) ![]tac.Instruction {
    var code: std.ArrayList(tac.Instruction) = .empty; var labels: std.ArrayList(tac.Text) = .empty;
    for (original, changed, 0..) |old, value, n| {
        try labels.appendSlice(a, old.labels);
        if (value) |v| { var ins = v; ins.labels = labels.items; labels = .empty; try code.append(a, ins); }
        if (after) |items| for (items[n].items) |ins| { try code.append(a, ins); };
    }
    return code.items;
}
fn fold(a: tac.Allocator, ins: *tac.Instruction) !bool {
    if (ins.kind != .bin) return false; const av = !tac.variable(ins.a); const bv = !tac.variable(ins.b);
    if (av and bv) { const x = tac.number(ins.a); const y = tac.number(ins.b); if ((tac.eq(ins.op, "/") or tac.eq(ins.op, "%")) and y == 0) return false; const v = tac.calculate(ins.op, x, y); if (v < -2147483648 or v > 2147483647) return false; copy(ins, try std.fmt.allocPrint(a, "{d}", .{v})); return true; }
    if (av == bv) return false;
    const n = tac.number(if (av) ins.a else ins.b); const v = if (av) ins.b else ins.a;
    if ((tac.eq(ins.op, "+") and n == 0) or (tac.eq(ins.op, "*") and n == 1) or (!av and ((tac.eq(ins.op, "-") and n == 0) or (tac.eq(ins.op, "/") and n == 1)))) { copy(ins, v); return true; }
    if (tac.eq(ins.op, "*") and n == 0) { copy(ins, "0"); return true; } return false;
}
fn numbers(a: tac.Allocator, set: cfg.Set) !tac.Text { var b: tac.Buffer = .{ .a = a }; var it = set.iterator(.{}); while (it.next()) |n| { if (b.data.items.len > 0) try b.add(","); try b.print("#{d}", .{n + 1}); } return if (b.data.items.len == 0) "-" else b.data.items; }
fn sources(flow: *const df.Flow, expr: tac.Instruction, candidate: usize) cfg.Set {
    var found = cfg.Set.initEmpty(); const bi = flow.graph.owner[candidate]; const block = flow.graph.blocks[bi]; var n = candidate;
    while (n > block.first) { n -= 1; if (df.sameExpression(flow.function.code[n], expr)) { found.set(n); return found; } }
    var pending = cfg.Set.initEmpty(); for (block.preds.items) |p| if (flow.graph.blocks[p].reachable) { pending.set(p); }; var seen = cfg.Set.initEmpty();
    while (pending.findFirstSet()) |p| {
        pending.unset(p); if (seen.isSet(p)) continue; seen.set(p); const b = flow.graph.blocks[p]; n = b.end; var hit = false;
        while (n > b.first) { n -= 1; if (df.sameExpression(flow.function.code[n], expr)) { found.set(n); hit = true; break; } }
        if (!hit) for (b.preds.items) |pre| { if (flow.graph.blocks[pre].reachable and !seen.isSet(pre)) pending.set(pre); };
    }
    return found;
}
pub fn run(a: tac.Allocator, function: *tac.Function, pass: tac.Text) !Result {
    var flow = try df.analyze(a, function.*); var result: Result = .{};
    if (tac.eq(pass, "licm")) return licm(a, function, &flow);
    if (tac.eq(pass, "unreachable")) return unreachableCode(a, function, &flow);
    const changed = try a.alloc(?tac.Instruction, function.code.len); for (function.code, 0..) |ins, n| changed[n] = ins;
    const after = try a.alloc(std.ArrayList(tac.Instruction), function.code.len); @memset(after, .empty);
    if (tac.eq(pass, "constprop") or tac.eq(pass, "copyprop")) {
        for (function.code, 0..) |old, n| {
            if (!flow.graph.blocks[flow.graph.owner[n]].reachable) continue; var ins = old;
            for (old.used(), 0..) |v, operand| {
                if (!tac.variable(v)) continue; var replacement: ?tac.Text = null;
                if (tac.eq(pass, "constprop")) {
                    var value: ?tac.Text = null; var valid = true; var count: usize = 0; var it = flow.reaching.before[n].iterator(.{});
                    while (it.next()) |di| { const d = flow.definitions[di]; if (!tac.eq(d.variable, v)) continue; count += 1; if (d.number == 0) { valid = false; break; } const source = function.code[d.number - 1]; if (source.kind != .copy or tac.variable(source.a)) { valid = false; break; } if (value) |previous| { if (tac.number(previous) != tac.number(source.a)) valid = false; } value = source.a; }
                    if (valid and count > 0) replacement = value;
                } else { var it = flow.copying.before[n].iterator(.{}); while (it.next()) |ci| { const c = flow.copies[ci]; if (tac.eq(c.dest, v)) { replacement = c.source; break; } } }
                if (replacement) |r| { ins.operand(operand).* = r; try record(a, &result, "#{d}: {s} -> {s}", .{n + 1, v, r}); }
            }
            changed[n] = ins;
            if (tac.eq(pass, "constprop")) {
                if (ins.kind == .@"if" and !tac.variable(ins.a) and !tac.variable(ins.b)) {
                    if (tac.calculate(ins.op, tac.number(ins.a), tac.number(ins.b)) != 0) { changed[n] = .{ .kind = .goto, .target = ins.target }; try record(a, &result, "#{d}: fold goto {s}", .{n + 1, ins.target}); }
                    else { changed[n] = null; try record(a, &result, "#{d}: delete {s}", .{n + 1, try ins.text(a)}); }
                } else if (try fold(a, &ins)) { changed[n] = ins; try record(a, &result, "#{d}: fold {s}", .{n + 1, try ins.text(a)}); }
            }
        }
    } else if (tac.eq(pass, "dce")) {
        const records = try a.alloc(?tac.Text, function.code.len); @memset(records, null);
        for (flow.graph.blocks) |b| { if (!b.reachable) continue; var live = flow.live.output[flow.graph.owner[b.first]]; var n = b.end;
            while (n > b.first) { n -= 1; var ins = function.code[n]; const dead = ins.dest.len > 0 and !live.isSet(flow.variable(ins.dest));
                if ((ins.kind == .copy and tac.eq(ins.dest, ins.a)) or ((ins.kind == .copy or ins.kind == .bin or ins.kind == .load) and dead)) { changed[n] = null; records[n] = try std.fmt.allocPrint(a, "#{d}: delete {s}", .{n + 1, try ins.text(a)}); continue; }
                if (ins.kind == .call and dead) { records[n] = try std.fmt.allocPrint(a, "#{d}: unused result {s}", .{n + 1, try ins.text(a)}); ins.dest = ""; changed[n] = ins; }
                flow.transfer(&live, ins, n + 1, 1);
            }
        }
        for (records) |r| if (r) |text| { try result.records.append(a, text); };
    } else if (tac.eq(pass, "cse")) {
        var processed = cfg.Set.initEmpty();
        for (function.code, 0..) |ins, first| {
            if (!flow.graph.blocks[flow.graph.owner[first]].reachable) continue; const ei = flow.expression(ins) orelse continue;
            if (processed.isSet(ei) or !flow.available.before[first].isSet(ei)) continue; processed.set(ei);
            var candidates = cfg.Set.initEmpty(); var source_set = cfg.Set.initEmpty();
            for (function.code, 0..) |other, n| if (flow.graph.blocks[flow.graph.owner[n]].reachable and df.sameExpression(ins, other) and flow.available.before[n].isSet(ei)) { candidates.set(n); source_set.setUnion(sources(&flow, ins, n)); };
            var excluded = candidates.iterator(.{}); while (excluded.next()) |n| source_set.unset(n); function.temporaries += 1; const temporary = try std.fmt.allocPrint(a, "_t{d}", .{function.temporaries});
            var it = source_set.iterator(.{}); while (it.next()) |n| { var source = changed[n].?; const dest = source.dest; source.dest = temporary; changed[n] = source; try after[n].append(a, .{ .kind = .copy, .dest = dest, .a = temporary }); }
            it = candidates.iterator(.{}); while (it.next()) |n| { var target = changed[n].?; copy(&target, temporary); changed[n] = target; }
            try record(a, &result, "{s}: {s} sources={s} replaced={s}", .{(try ins.expression(a)).?, temporary, try numbers(a, source_set), try numbers(a, candidates)}); result.count += candidates.count();
        }
    }
    if (!tac.eq(pass, "cse")) result.count = result.records.items.len;
    function.code = try rebuilt(a, function.code, changed, after); return result;
}
fn licm(a: tac.Allocator, function: *tac.Function, flow: *df.Flow) !Result {
    var result: Result = .{}; const order = try a.alloc(usize, flow.graph.loops.len); for (order, 0..) |*v, i| v.* = i;
    std.mem.sort(usize, order, flow, struct { fn cmp(f: *df.Flow, x: usize, y: usize) bool { const left = f.graph.loops[x]; const right = f.graph.loops[y]; return if (left.blocks.count() == right.blocks.count()) left.header < right.header else left.blocks.count() < right.blocks.count(); } }.cmp);
    for (order) |li| {
        const loop = flow.graph.loops[li]; var marked = cfg.Set.initEmpty(); var mark_order: std.ArrayList(usize) = .empty;
        while (true) { const before = marked;
            for (function.code, 0..) |ins, n| {
                if (!loop.blocks.isSet(flow.graph.owner[n]) or marked.isSet(n) or (ins.kind != .copy and ins.kind != .bin and ins.kind != .load)) continue; var valid = true;
                if (ins.kind == .load) for (function.code, 0..) |other, k| { if (loop.blocks.isSet(flow.graph.owner[k]) and (other.kind == .call or (other.kind == .store and tac.eq(ins.array, other.array)))) valid = false; };
                for (ins.used()) |v| if (tac.variable(v)) { var inner: usize = 0; var outer: usize = 0; var source_marked = false; var it = flow.reaching.before[n].iterator(.{}); while (it.next()) |di| { const d = flow.definitions[di]; if (!tac.eq(v, d.variable)) continue; if (d.number > 0 and loop.blocks.isSet(flow.graph.owner[d.number - 1])) { inner += 1; source_marked = marked.isSet(d.number - 1); } else outer += 1; } if (inner > 0 and !(inner == 1 and outer == 0 and source_marked)) valid = false; };
                if (valid) { marked.set(n); try mark_order.append(a, n); }
            }
            if (marked.eql(before)) break;
        }
        var moving = cfg.Set.initEmpty(); var move_order: std.ArrayList(usize) = .empty;
        for (mark_order.items) |n| {
            const ins = function.code[n]; var definitions: usize = 0; for (function.code, 0..) |other, k| { if (loop.blocks.isSet(flow.graph.owner[k]) and tac.eq(ins.dest, other.dest)) definitions += 1; }
            if (definitions != 1 or flow.live.input[loop.header].isSet(flow.variable(ins.dest))) continue;
            const block = flow.graph.owner[n]; var dominates = true; var it = loop.exits.iterator(.{}); while (it.next()) |e| if (!flow.graph.blocks[e].dom.isSet(block)) { dominates = false; };
            const dangerous = ins.kind == .load or (ins.kind == .bin and (tac.eq(ins.op, "/") or tac.eq(ins.op, "%")) and (tac.variable(ins.b) or tac.number(ins.b) == 0));
            if (!dominates) { if (dangerous) continue; var live_outside = false; it = loop.outside.iterator(.{}); while (it.next()) |s| if (flow.live.input[s].isSet(flow.variable(ins.dest))) { live_outside = true; }; if (live_outside) continue; }
            var valid = true; for (ins.used()) |v| if (tac.variable(v)) { var ds = flow.reaching.before[n].iterator(.{}); while (ds.next()) |di| { const d = flow.definitions[di]; if (tac.eq(d.variable, v) and d.number > 0 and loop.blocks.isSet(flow.graph.owner[d.number - 1]) and !moving.isSet(d.number - 1)) valid = false; } };
            if (valid) { moving.set(n); try move_order.append(a, n); }
        }
        if (move_order.items.len == 0) continue;
        const header = flow.graph.blocks[loop.header]; var outside: std.ArrayList(usize) = .empty; for (header.preds.items) |p| if (!loop.blocks.isSet(p)) { try outside.append(a, p); };
        const reused = loop.header != 0 and outside.items.len == 1 and flow.graph.blocks[outside.items[0]].succs.items.len == 1;
        var insert = header.first; var label: ?tac.Text = null;
        if (reused) { const pre = flow.graph.blocks[outside.items[0]]; insert = pre.end; const last = function.code[pre.end - 1]; if (last.kind == .goto or last.kind == .@"if") insert -= 1; }
        else { function.preheaders += 1; label = try std.fmt.allocPrint(a, "_p{d}", .{function.preheaders}); }
        const preheader_labels = reused and insert == flow.graph.blocks[outside.items[0]].first;
        var code: std.ArrayList(tac.Instruction) = .empty; var pending: std.ArrayList(tac.Text) = .empty;
        for (function.code, 0..) |old, n| {
            if (n == insert) for (move_order.items, 0..) |mi, index| { var ins = function.code[mi]; ins.labels = if (index == 0 and label != null) try a.dupe(tac.Text, &.{label.?}) else if (index == 0 and preheader_labels) old.labels else &.{}; try code.append(a, ins); };
            if (!(n == insert and preheader_labels)) try pending.appendSlice(a, old.labels); if (moving.isSet(n)) continue; var ins = old;
            if (label != null and !loop.blocks.isSet(flow.graph.owner[n]) and (ins.kind == .goto or ins.kind == .@"if")) for (header.labels) |h| { if (tac.eq(ins.target, h)) ins.target = label.?; };
            ins.labels = pending.items; pending = .empty; try code.append(a, ins);
        }
        function.code = code.items; var nums: tac.Buffer = .{ .a = a }; for (move_order.items, 0..) |n, i| { if (i > 0) try nums.add(","); try nums.print("#{d}", .{n + 1}); }
        if (reused) try record(a, &result, "B{d}: hoist {s} to B{d}", .{loop.header + 1, nums.data.items, outside.items[0] + 1}) else try record(a, &result, "B{d}: hoist {s} to new {s}", .{loop.header + 1, nums.data.items, label.?}); result.count = move_order.items.len; return result;
    }
    return result;
}
fn unreachableCode(a: tac.Allocator, function: *tac.Function, flow: *df.Flow) !Result {
    var result: Result = .{}; var code: std.ArrayList(tac.Instruction) = .empty;
    for (flow.graph.blocks, 0..) |b, i| { if (!b.reachable) try record(a, &result, "remove block B{d}", .{i + 1}) else try code.appendSlice(a, function.code[b.first..b.end]); }
    const changed = try a.alloc(?tac.Instruction, code.items.len); for (code.items, 0..) |ins, n| { changed[n] = ins; if ((ins.kind == .goto or ins.kind == .@"if") and n + 1 < code.items.len) for (code.items[n + 1].labels) |label| { if (tac.eq(ins.target, label)) { changed[n] = null; try record(a, &result, "remove jump #{d}", .{n + 1}); break; } }; }
    function.code = try rebuilt(a, code.items, changed, null);
    var targets: std.StringHashMapUnmanaged(void) = .empty; for (function.code) |ins| if (ins.kind == .goto or ins.kind == .@"if") { try targets.put(a, ins.target, {}); };
    for (function.code) |*ins| { var labels: std.ArrayList(tac.Text) = .empty; for (ins.labels) |label| { if (targets.contains(label)) try labels.append(a, label) else try record(a, &result, "remove label {s}", .{label}); } ins.labels = labels.items; }
    result.count = result.records.items.len; return result;
}
