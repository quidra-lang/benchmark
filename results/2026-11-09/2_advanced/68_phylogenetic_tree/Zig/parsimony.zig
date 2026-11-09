const std = @import("std");
const d = @import("alignment.zig");
const building = @import("tree_building.zig");
const Tree = building.Tree;
const Rooted = building.Rooted;
pub const Merge = struct { set: u8, changes: i64 };
pub fn merge(a: u8, b: u8) Merge {
    return if (a & b != 0) .{ .set = a & b, .changes = 0 } else .{ .set = a | b, .changes = 1 };
}
pub const Provisional = struct { sets: [32]u8 = [_]u8{0} ** 32, changes: i64 = 0 };
pub fn provisional(tree: *const Tree, root: *const Rooted, pattern: [16]u8) Provisional {
    var out: Provisional = .{};
    var i = root.count;
    while (i > 0) {
        i -= 1;
        const node = root.order[i];
        if (node < tree.size) out.sets[node] = pattern[node] else {
            var children: [2]usize = undefined;
            var count: usize = 0;
            for (root.children[node][0..root.child_count[node]]) |child| if (child != root.outgroup) {
                children[count] = child;
                count += 1;
            };
            const result = merge(out.sets[children[0]], out.sets[children[1]]);
            out.sets[node] = result.set;
            out.changes += result.changes;
            if (node == root.root) out.changes += merge(out.sets[node], out.sets[root.outgroup]).changes;
        }
    }
    return out;
}
pub fn patternScores(tree: *const Tree, patterns: d.Patterns, outgroup: usize) []const i64 {
    const root = Rooted.init(tree, outgroup);
    const out = d.alloc(i64, patterns.encoded.len);
    for (patterns.encoded, out) |pattern, *value| value.* = provisional(tree, &root, pattern).changes;
    return out;
}
pub fn score(tree: *const Tree, patterns: d.Patterns, outgroup: usize) i64 {
    const root = Rooted.init(tree, outgroup);
    var out: i64 = 0;
    for (patterns.encoded, patterns.weights) |pattern, weight| out += provisional(tree, &root,
         pattern).changes * weight;
    return out;
}
fn firstBase(value: u8) u8 {
    return value & (~value + 1);
}
pub const Reconstruction = struct { ancestors: [32]?[]u8 = [_]?[]u8{null} ** 32, changes: [32][32]i64 = [_][32]i64{[_]i64{0} ** 32} ** 32,
     sites: []i64 };
pub fn reconstruct(tree: *const Tree, patterns: d.Patterns, outgroup: usize) Reconstruction {
    var out: Reconstruction = .{ .sites = d.alloc(i64, patterns.columns.len) };
    const root = Rooted.init(tree, outgroup);
    for (tree.size..tree.next) |node| out.ancestors[node] = d.alloc(u8, patterns.columns.len);
    for (patterns.columns, 0..) |index, column| {
        const p = provisional(tree, &root, patterns.encoded[index]);
        out.sites[column] = p.changes;
        const first = firstBase(merge(p.sets[root.root], p.sets[outgroup]).set);
        var states = [_]u8{0} ** 32;
        for ([_]usize{ root.root, outgroup }) |node| states[node] = if (p.sets[node] & first != 0) first else firstBase(p.sets[node]);
        for (root.order[1..root.count]) |node| if (node != outgroup) {
            const parent = states[root.parent[node].?];
            states[node] = if (p.sets[node] & parent != 0) parent else firstBase(p.sets[node]);
        };
        for (tree.size..tree.next) |node| out.ancestors[node].?[column] = "ACGT"[@ctz(states[node])];
        for (0..tree.next) |a| for (a + 1..tree.next) |b| {
            if (tree.adjacent[a][b]) out.changes[a][b] += @intFromBool(states[a] != states[b]);
        };
    }
    return out;
}
pub const Branch = struct { mask: u32, first: usize, second: usize };
fn branchLess(_: void, a: Branch, b: Branch) bool {
    return a.mask < b.mask;
}
pub fn branches(tree: *const Tree, outgroup: usize) []const Branch {
    const root = Rooted.init(tree, outgroup);
    const out = d.alloc(Branch, root.count - 1);
    for (root.order[1..root.count], out) |child, *branch| branch.* = .{ .mask = if (child == outgroup) root.ingroup else root.masks[child],
         .first = root.parent[child].?, .second = child };
    std.mem.sort(Branch, out, {}, branchLess);
    return out;
}
pub fn insert(tree: *const Tree, first: usize, second: usize, taxon: usize) Tree {
    var out = tree.*;
    _ = out.disconnect(first, second);
    const node = out.internal();
    out.connect(first, node, 0);
    out.connect(second, node, 0);
    out.connect(taxon, node, 0);
    return out;
}
pub const Swap = struct { mask: u32, number: usize, tree: Tree };
pub fn nniCandidates(tree: *const Tree, outgroup: usize, out: *std.ArrayList(Swap)) void {
    out.clearRetainingCapacity();
    const root = Rooted.init(tree, outgroup);
    for (branches(tree, outgroup)) |branch| {
        const u = branch.first;
        const v = branch.second;
        if (u < tree.size or v < tree.size) continue;
        var sibling: usize = undefined;
        for (root.children[u][0..root.child_count[u]]) |child| if (child != v and child != outgroup) {
            sibling = child;
        };
        var children = [_]usize{ root.children[v][0], root.children[v][1] };
        if (root.masks[children[0]] > root.masks[children[1]]) std.mem.swap(usize, &children[0], &children[1]);
        for (children, 1..) |child, number| {
            var candidate = tree.*;
            const sibling_length = candidate.disconnect(u, sibling);
            const child_length = candidate.disconnect(v, child);
            candidate.connect(u, child, child_length);
            candidate.connect(v, sibling, sibling_length);
            d.append(Swap, out, .{ .mask = branch.mask, .number = number, .tree = candidate });
        }
    }
}
