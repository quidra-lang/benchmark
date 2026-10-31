const D = @import("dataset.zig");
const I = @import("impurity.zig");
const B = @import("tree_builder.zig");
const E = @import("evaluation.zig");
pub const Decision = struct { node: *const B.Node, rows: i64, leaf_error: i64, subtree_error: i64, pruned: bool };
pub const Result = struct { tree: E.Tree, decisions: [500]Decision = undefined, count: usize = 0 };
pub const SequenceEntry = struct { tree: E.Tree, alpha: I.Fraction };
fn decide(node: *const B.Node, visits: []const i64, errors: []const i64, result: *Result) i64 {
    const leaf_error = errors[node.number];
    if (node.split == null) return leaf_error;
    const left = decide(node.left.?, visits, errors, result);
    const right = decide(node.right.?, visits, errors, result);
    const subtree = left + right;
    const pruned = leaf_error <= subtree;
    result.decisions[result.count] = .{ .node = node, .rows = visits[node.number], .leaf_error = leaf_error, .subtree_error = subtree, .pruned = pruned };
    result.count += 1;
    if (pruned) result.tree.cuts[node.number] = true;
    return if (pruned) leaf_error else subtree;
}
pub fn reducedError(data: *const D.Dataset, root: *const B.Node, rows: D.Rows) Result {
    var result: Result = .{ .tree = .{ .root = root } };
    const grown: E.Tree = .{ .root = root };
    var visits = [_]i64{0} ** 2048;
    var errors = [_]i64{0} ** 2048;
    for (rows.slice()) |row| {
        const route = grown.route(data, row);
        for (route.path[0 .. route.len + 1]) |node| { visits[node.number] += 1; if (row.label != node.stats.prediction) errors[node.number] += 1; }
    }
    _ = decide(root, &visits, &errors, &result);
    return result;
}
pub fn costComplexity(root: *const B.Node) []const SequenceEntry {
    var tree: E.Tree = .{ .root = root };
    var sequence: std.ArrayList(SequenceEntry) = .empty;
    D.append(SequenceEntry, &sequence, .{ .tree = tree, .alpha = .{ .numerator = 0, .denominator = 1 } });
    while (!tree.isLeaf(root)) {
        const nodes = tree.preorder(null);
        var strengths: [1000]I.Fraction = undefined;
        var minimum: ?I.Fraction = null;
        for (nodes.slice(), 0..) |node, i| {
            if (tree.isLeaf(node)) continue;
            const descendants = tree.leaves(node);
            var errors: i64 = 0;
            for (descendants.slice()) |leaf| errors += leaf.stats.errors;
            strengths[i] = .{ .numerator = node.stats.errors - errors, .denominator = D.n(descendants.len) - 1 };
            if (minimum == null or I.compare(strengths[i], minimum.?) < 0) minimum = strengths[i];
        }
        var weakest = [_]bool{false} ** 2048;
        for (nodes.slice(), 0..) |node, i| { if (!tree.isLeaf(node) and I.compare(strengths[i], minimum.?) == 0) weakest[node.number] = true; }
        for (weakest, 0..) |cut, i| { if (cut) tree.cuts[i] = true; }
        D.append(SequenceEntry, &sequence, .{ .tree = tree, .alpha = minimum.? });
    }
    return sequence.items;
}
const std = @import("std");
