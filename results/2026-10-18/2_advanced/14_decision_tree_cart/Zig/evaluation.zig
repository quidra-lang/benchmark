const D = @import("dataset.zig");
const I = @import("impurity.zig");
const B = @import("tree_builder.zig");
pub const Nodes = struct {
    values: [1000]*const B.Node = undefined, len: usize = 0,
    fn add(self: *Nodes, node: *const B.Node) void { self.values[self.len] = node; self.len += 1; }
    pub fn slice(self: *const Nodes) []const *const B.Node { return self.values[0..self.len]; }
};
pub const Method = enum { primary, surrogate, fallback };
pub const Step = struct { node: *const B.Node, left: bool, method: Method };
pub const Route = struct { leaf: *const B.Node = undefined, path: [11]*const B.Node = undefined, steps: [10]Step = undefined, len: usize = 0 };
pub const Tree = struct {
    root: *const B.Node, cuts: [2048]bool = [_]bool{false} ** 2048,
    pub fn isLeaf(self: *const Tree, node: *const B.Node) bool { return node.split == null or self.cuts[node.number]; }
    pub fn preorder(self: *const Tree, start: ?*const B.Node) Nodes {
        var result: Nodes = .{};
        var pending: Nodes = .{};
        pending.add(start orelse self.root);
        while (pending.len > 0) {
            pending.len -= 1;
            const node = pending.values[pending.len];
            result.add(node);
            if (!self.isLeaf(node)) { pending.add(node.right.?); pending.add(node.left.?); }
        }
        return result;
    }
    pub fn leaves(self: *const Tree, start: ?*const B.Node) Nodes {
        const nodes = self.preorder(start);
        var result: Nodes = .{};
        for (nodes.slice()) |node| { if (self.isLeaf(node)) result.add(node); }
        return result;
    }
    pub fn depth(self: *const Tree) usize {
        const nodes = self.leaves(null);
        var result: usize = 0;
        for (nodes.slice()) |node| result = @max(result, node.depth);
        return result;
    }
    pub fn trainingErrors(self: *const Tree) i64 {
        const nodes = self.leaves(null);
        var result: i64 = 0;
        for (nodes.slice()) |node| result += node.stats.errors;
        return result;
    }
    pub fn route(self: *const Tree, data: *const D.Dataset, row: *const D.Row) Route {
        var result: Route = .{};
        var node = self.root;
        while (true) {
            result.path[result.len] = node;
            if (self.isLeaf(node)) { result.leaf = node; return result; }
            var left = node.default_left;
            var method: Method = .fallback;
            const primary = node.split.?;
            if (row.values[primary.attribute] >= 0) {
                left = B.goesLeft(data, primary, row);
                method = .primary;
            } else {
                for (node.surrogates[0..node.surrogate_count]) |surrogate| {
                    if (row.values[surrogate.split.attribute] < 0) continue;
                    left = B.goesLeft(data, surrogate.split, row) == surrogate.forward;
                    method = .surrogate;
                    break;
                }
            }
            result.steps[result.len] = .{ .node = node, .left = left, .method = method };
            result.len += 1;
            node = if (left) node.left.? else node.right.?;
        }
    }
    pub fn predict(self: *const Tree, data: *const D.Dataset, row: *const D.Row) usize { return self.route(data, row).leaf.stats.prediction; }
    pub fn correct(self: *const Tree, data: *const D.Dataset, rows: D.Rows) i64 {
        var result: i64 = 0;
        for (rows.slice()) |row| { if (self.predict(data, row) == row.label) result += 1; }
        return result;
    }
};
pub fn realText(value: f64, places: usize) []const u8 {
    const text = if (places == 6) D.fmt("{d:.6}", .{value}) else D.fmt("{d:.4}", .{value});
    if (D.eq(text, "-0.0000") or D.eq(text, "-0.000000")) return text[1..];
    return text;
}
pub fn ratio(numerator: i64, denominator: i64) []const u8 { return if (denominator == 0) "0/0 -" else D.fmt("{d}/{d} {s}", .{ numerator, denominator, realText(D.real(numerator) / D.real(denominator), 4) }); }
pub fn fraction(value: I.Fraction, places: usize) []const u8 {
    if (value.denominator == 0) return "- -";
    var a = if (value.numerator < 0) -value.numerator else value.numerator;
    var b = value.denominator;
    while (b != 0) { const remainder = @mod(a, b); a = b; b = remainder; }
    return D.fmt("{d}/{d} {s}", .{ @divExact(value.numerator, a), @divExact(value.denominator, a), realText(D.real(value.numerator) / D.real(value.denominator), places) });
}
pub fn countsText(counts: []const i64) []const u8 {
    var result: D.Text = .{};
    for (counts, 0..) |count, i| result.add("{s}{d}", .{ if (i > 0) " " else "", count });
    return result.value();
}
pub fn classification(data: *const D.Dataset, title: []const u8, rows: D.Rows, predictions: []const usize) D.Lines {
    var matrix = [_][6]i64{[_]i64{0} ** 6} ** 6;
    var correct: i64 = 0;
    for (rows.slice(), 0..) |row, i| {
        matrix[row.label][predictions[i]] += 1;
        if (row.label == predictions[i]) correct += 1;
    }
    var result: D.Lines = .{};
    result.add("confusion {s} correct {d}/{d} accuracy {s}", .{ title, correct, rows.len, fraction(.{ .numerator = correct, .denominator = D.n(rows.len) }, 4) });
    var header: D.Text = .{};
    header.write("actual\\predicted");
    for (data.classes) |class| header.add(" {s}", .{class});
    result.write(header.value());
    for (data.classes, 0..) |class, k| result.add("{s} {s}", .{ class, countsText(matrix[k][0..data.classes.len]) });
    var macro: f64 = 0;
    var available: usize = 0;
    for (data.classes, 0..) |class, k| {
        var predicted: i64 = 0;
        var support: i64 = 0;
        for (0..data.classes.len) |j| { predicted += matrix[j][k]; support += matrix[k][j]; }
        const hits = matrix[k][k];
        result.add("class {s} precision {s} recall {s} f1 {s} support {d}", .{ class, fraction(.{ .numerator = hits, .denominator = predicted }, 4), fraction(.{ .numerator = hits, .denominator = support }, 4), fraction(.{ .numerator = 2 * hits, .denominator = predicted + support }, 4), support });
        if (predicted + support > 0) { macro += D.real(2 * hits) / D.real(predicted + support); available += 1; }
    }
    result.add("macro_f1 {s}", .{if (available > 0) realText(macro / D.real(available), 4) else "-"});
    return result;
}
