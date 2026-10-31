const std = @import("std");
const d = @import("alignment.zig");
const distances = @import("distances.zig");
pub const Tree = struct {
    size: usize,
    next: usize,
    negative: usize = 0,
    present: [32]bool = [_]bool{false} ** 32,
    adjacent: [32][32]bool = [_][32]bool{[_]bool{false} ** 32} ** 32,
    length: [32][32]f64 = [_][32]f64{[_]f64{0} ** 32} ** 32,
    pub fn init(size: usize) Tree {
        return .{ .size = size, .next = size };
    }
    pub fn internal(self: *Tree) usize {
        const node = self.next;
        self.present[node] = true;
        self.next += 1;
        return node;
    }
    pub fn connect(self: *Tree, a: usize, b: usize, length: f64) void {
        self.present[a] = true;
        self.present[b] = true;
        self.adjacent[a][b] = true;
        self.adjacent[b][a] = true;
        self.length[a][b] = length;
        self.length[b][a] = length;
    }
    pub fn disconnect(self: *Tree, a: usize, b: usize) f64 {
        self.adjacent[a][b] = false;
        self.adjacent[b][a] = false;
        return self.length[a][b];
    }
    pub fn taxa(self: *const Tree) []const usize {
        var out: std.ArrayList(usize) = .empty;
        for (0..self.size) |i| if (self.present[i]) d.append(usize, &out, i);
        return out.items;
    }
};
pub const Rooted = struct {
    root: usize = 0,
    outgroup: usize,
    parent: [32]?usize = [_]?usize{null} ** 32,
    children: [32][32]usize = undefined,
    child_count: [32]usize = [_]usize{0} ** 32,
    masks: [32]u32 = [_]u32{0} ** 32,
    ingroup: u32 = 0,
    order: [32]usize = undefined,
    count: usize = 0,
    pub fn init(tree: *const Tree, outgroup: usize) Rooted {
        var out: Rooted = .{ .outgroup = outgroup };
        while (!tree.adjacent[outgroup][out.root]) out.root += 1;
        out.visit(tree, out.root, null);
        out.ingroup = out.masks[out.root] ^ d.bit(outgroup);
        return out;
    }
    fn visit(self: *Rooted, tree: *const Tree, node: usize, parent: ?usize) void {
        self.parent[node] = parent;
        self.order[self.count] = node;
        self.count += 1;
        if (node < tree.size) self.masks[node] = d.bit(node);
        for (0..tree.next) |child| if (tree.adjacent[node][child] and (parent == null or child != parent.?)) {
            self.children[node][self.child_count[node]] = child;
            self.child_count[node] += 1;
            self.visit(tree, child, node);
            self.masks[node] |= self.masks[child];
        };
    }
    pub fn splits(self: *const Rooted, tree: *const Tree) []const u32 {
        var out: std.ArrayList(u32) = .empty;
        for (tree.size..tree.next) |node| if (tree.present[node] and node != self.root) d.append(u32,
             &out, self.masks[node]);
        return out.items;
    }
};
pub fn star(size: usize, taxa: []const usize) Tree {
    var out = Tree.init(size);
    const root = out.internal();
    for (taxa) |taxon| out.connect(root, taxon, 0);
    return out;
}
pub fn neighborJoining(matrix: *const distances.Matrix, size: usize, taxa: []const usize) Tree {
    var tree = Tree.init(size);
    var active: [32]usize = undefined;
    @memcpy(active[0..taxa.len], taxa);
    var count = taxa.len;
    var values = [_][32]f64{[_]f64{0} ** 32} ** 32;
    for (taxa) |a| for (taxa) |b| {
        values[a][b] = matrix[a][b];
    };
    while (count >= 4) {
        var totals = [_]f64{0} ** 32;
        for (active[0..count]) |a| for (active[0..count]) |b| {
            if (a != b) totals[a] += values[a][b];
        };
        var best = std.math.inf(f64);
        var first: usize = 0;
        var second: usize = 0;
        for (0..count) |i| for (i + 1..count) |j| {
            const a = active[i];
            const b = active[j];
            const value = d.f(count - 2) * values[a][b] - totals[a] - totals[b];
            if (value < best) {
                best = value;
                first = a;
                second = b;
            }
        };
        const node = tree.internal();
        const distance = values[first][second];
        const left = distance / 2 + (totals[first] - totals[second]) / d.f(2 * (count - 2));
        tree.connect(first, node, left);
        tree.connect(second, node, distance - left);
        var remaining: [32]usize = undefined;
        var length: usize = 0;
        for (active[0..count]) |other| if (other != first and other != second) {
            remaining[length] = other;
            length += 1;
            const value = (values[first][other] + values[second][other] - distance) / 2;
            values[node][other] = value;
            values[other][node] = value;
        };
        remaining[length] = node;
        length += 1;
        @memcpy(active[0..length], remaining[0..length]);
        count = length;
    }
    const a = active[0];
    const b = active[1];
    const c = active[2];
    const node = tree.internal();
    const ab = values[a][b];
    const ac = values[a][c];
    const bc = values[b][c];
    tree.connect(a, node, (ab + ac - bc) / 2);
    tree.connect(b, node, (ab + bc - ac) / 2);
    tree.connect(c, node, (ac + bc - ab) / 2);
    for (0..tree.next) |i| for (i + 1..tree.next) |j| {
        if (tree.adjacent[i][j] and tree.length[i][j] < 0) {
            tree.connect(i, j, 0);
            tree.negative += 1;
        }
    };
    return tree;
}
fn pathVisit(tree: *const Tree, node: usize, parent: ?usize, unit: bool, out: *[32]f64) void {
    for (0..tree.next) |child| if (tree.adjacent[node][child] and (parent == null or child != parent.?)) {
        out[child] = out[node] + (if (unit) 1 else tree.length[node][child]);
        pathVisit(tree, child, node, unit, out);
    };
}
pub fn paths(tree: *const Tree, start: usize, unit: bool) [32]f64 {
    var out = [_]f64{0} ** 32;
    pathVisit(tree, start, null, unit, &out);
    return out;
}
pub fn patristic(tree: *const Tree) distances.Matrix {
    var out: distances.Matrix = [_][16]f64{[_]f64{0} ** 16} ** 16;
    for (tree.taxa()) |a| {
        const values = paths(tree, a, false);
        for (tree.taxa()) |b| out[a][b] = values[b];
    }
    return out;
}
