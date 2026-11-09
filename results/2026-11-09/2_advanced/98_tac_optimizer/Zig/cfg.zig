const std = @import("std");
const tac = @import("tac_parser.zig");
pub const Set = std.StaticBitSet(1024);
pub const Block = struct { first: usize, end: usize, labels: []const tac.Text, preds: std.ArrayList(usize) = .empty, succs: std.ArrayList(usize) = .empty, reachable: bool = false, dom: Set = Set.initEmpty(), idom: ?usize = null, depth: usize = 0 };
pub const Loop = struct { header: usize, latches: Set = Set.initEmpty(), blocks: Set = Set.initEmpty(), exits: Set = Set.initEmpty(), outside: Set = Set.initEmpty(), depth: usize = 0 };
pub const Graph = struct { blocks: []Block, owner: []usize, post: []const usize, reverse: []const usize, loops: []Loop };
fn visit(a: tac.Allocator, blocks: []Block, b: usize, post: *std.ArrayList(usize)) anyerror!void { blocks[b].reachable = true; for (blocks[b].succs.items) |s| if (!blocks[s].reachable) { try visit(a, blocks, s, post); }; try post.append(a, b); }
fn target(f: tac.Function, owner: []const usize, label: tac.Text) usize { for (f.code, 0..) |i, n| for (i.labels) |l| if (tac.eq(label, l)) return owner[n]; unreachable; }
pub fn build(a: tac.Allocator, f: tac.Function) !Graph {
    var blocks: std.ArrayList(Block) = .empty; const owner = try a.alloc(usize, f.code.len);
    for (f.code, 0..) |i, n| {
        const leader = n == 0 or i.labels.len > 0 or f.code[n - 1].kind == .goto or f.code[n - 1].kind == .@"if" or f.code[n - 1].kind == .@"return";
        if (leader) try blocks.append(a, .{ .first = n, .end = n, .labels = i.labels }); owner[n] = blocks.items.len - 1; blocks.items[owner[n]].end = n + 1;
    }
    for (blocks.items, 0..) |*b, n| {
        const last = f.code[b.end - 1];
        if (last.kind == .goto) try b.succs.append(a, target(f, owner, last.target))
        else if (last.kind == .@"if") { try b.succs.append(a, n + 1); const to = target(f, owner, last.target); if (to != n + 1) try b.succs.append(a, to); }
        else if (last.kind != .@"return") try b.succs.append(a, n + 1);
    }
    for (blocks.items, 0..) |b, n| for (b.succs.items) |s| { try blocks.items[s].preds.append(a, n); };
    var post: std.ArrayList(usize) = .empty; try visit(a, blocks.items, 0, &post); const reverse = try a.dupe(usize, post.items); std.mem.reverse(usize, reverse);
    var all = Set.initEmpty(); for (reverse) |b| all.set(b); for (reverse) |b| blocks.items[b].dom = all; blocks.items[0].dom = .initEmpty(); blocks.items[0].dom.set(0);
    while (true) { var changed = false; for (reverse[1..]) |n| { var dom = all; for (blocks.items[n].preds.items) |p| if (blocks.items[p].reachable) { dom.setIntersection(blocks.items[p].dom); }; dom.set(n); if (!dom.eql(blocks.items[n].dom)) { blocks.items[n].dom = dom; changed = true; } } if (!changed) break; }
    for (reverse[1..]) |n| { var best: usize = 0; var it = blocks.items[n].dom.iterator(.{}); while (it.next()) |p| if (p != n and blocks.items[p].dom.count() > best) { best = blocks.items[p].dom.count(); blocks.items[n].idom = p; }; }
    var loops: std.ArrayList(Loop) = .empty;
    for (blocks.items, 0..) |h, hi| {
        if (!h.reachable) continue; var loop: Loop = .{ .header = hi }; loop.blocks.set(hi);
        for (blocks.items, 0..) |t, ti| if (t.reachable and t.dom.isSet(hi)) { for (t.succs.items) |s| if (s == hi) { loop.latches.set(ti); loop.blocks.set(ti); }; };
        if (loop.latches.count() == 0) continue;
        while (true) { const before = loop.blocks; var it = before.iterator(.{}); while (it.next()) |n| if (n != hi) { for (blocks.items[n].preds.items) |p| if (blocks.items[p].reachable) { loop.blocks.set(p); }; }; if (before.eql(loop.blocks)) break; }
        var it = loop.blocks.iterator(.{}); while (it.next()) |n| { blocks.items[n].depth += 1; if (f.code[blocks.items[n].end - 1].kind == .@"return") loop.exits.set(n); for (blocks.items[n].succs.items) |s| if (!loop.blocks.isSet(s)) { loop.exits.set(n); loop.outside.set(s); }; }
        try loops.append(a, loop);
    }
    for (loops.items) |*loop| for (loops.items) |other| { if (other.blocks.isSet(loop.header)) loop.depth += 1; };
    return .{ .blocks = blocks.items, .owner = owner, .post = post.items, .reverse = reverse, .loops = loops.items };
}
