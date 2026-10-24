const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const Error = Allocator.Error || Writer.Error || error{Invalid};
const Kind = enum { SEG, LAZY, FEN, RFEN, SPARSE, SQRT, PERSIST, GRID };
const Operation = enum {
    SUM, MIN, MAX, GCD,
    fn combine(op: Operation, a: i64, b: i64) i64 {
        return switch (op) { .SUM => a + b, .MIN => @min(a, b), .MAX => @max(a, b), .GCD => gcd(a, b) };
    }
    fn label(op: Operation) []const u8 {
        return switch (op) { .SUM => "sum", .MIN => "min", .MAX => "max", .GCD => "gcd" };
    }
};

fn equal(a: []const u8, b: []const u8) bool { return std.mem.eql(u8, a, b); }
fn number(text: []const u8) i64 { return std.fmt.parseInt(i64, text, 10) catch unreachable; }
fn integer(n: usize) i64 { return @intCast(n); }
fn magnitude(n: i64) i64 { return if (n < 0) -n else n; }
fn gcd(a: i64, b: i64) i64 {
    var x = magnitude(a);
    var y = magnitude(b);
    while (y != 0) { const remainder = @mod(x, y); x = y; y = remainder; }
    return x;
}
fn isqrt(n: usize) usize {
    var result: usize = 1;
    while ((result + 1) * (result + 1) <= n) : (result += 1) {}
    return result;
}
fn log2(n: usize) usize {
    var result: usize = 0;
    var power: usize = 1;
    while (power * 2 <= n) { result += 1; power *= 2; }
    return result;
}
fn power2(n: usize) usize { return @as(usize, 1) << @intCast(n); }
fn lowbit(n: usize) usize { return n & (~n + 1); }
fn line(out: *Writer, comptime fmt: []const u8, args: anytype) Writer.Error!void { try out.print(fmt ++ "\n", args); }
fn writeNumbers(out: *Writer, values: anytype) Writer.Error!void {
    for (values) |value| try out.print(" {d}", .{value});
    try out.writeByte('\n');
}
fn less(_: void, a: i64, b: i64) bool { return a < b; }

fn Owned(comptime T: type) type {
    return struct {
        arena: std.heap.ArenaAllocator,
        value: T,
        const Self = @This();
        fn create(args: anytype) Allocator.Error!*Self {
            const self = try std.heap.page_allocator.create(Self);
            self.* = .{ .arena = .init(std.heap.page_allocator), .value = undefined };
            errdefer self.destroy();
            self.value = try @call(.auto, T.init, .{self.arena.allocator()} ++ args);
            return self;
        }
        fn destroy(self: *Self) void {
            self.arena.deinit();
            std.heap.page_allocator.destroy(self);
        }
    };
}
fn replace(comptime T: type, slot: *?*Owned(T), args: anytype) Allocator.Error!void {
    const replacement = try Owned(T).create(args);
    if (slot.*) |old| old.destroy();
    slot.* = replacement;
}

const Interval = struct {
    left: usize,
    right: usize,
    fn leaf(range: Interval) bool { return range.left == range.right; }
    fn middle(range: Interval) usize { return (range.left + range.right) / 2; }
    fn length(range: Interval) usize { return range.right - range.left + 1; }
    fn covered(range: Interval, left: usize, right: usize) bool { return left <= range.left and range.right <= right; }
};
const Layout = struct {
    ranges: []?Interval,
    count: usize,
    max_node: usize = 0,
    fn init(gpa: Allocator, n: usize) Allocator.Error!Layout {
        const ranges = try gpa.alloc(?Interval, 4 * n);
        @memset(ranges, null);
        var shape: Layout = .{ .ranges = ranges, .count = 2 * n - 1 };
        shape.build(1, 0, n - 1);
        return shape;
    }
    fn build(shape: *Layout, node: usize, left: usize, right: usize) void {
        shape.ranges[node] = .{ .left = left, .right = right };
        shape.max_node = @max(shape.max_node, node);
        if (left == right) return;
        const middle = (left + right) / 2;
        shape.build(2 * node, left, middle);
        shape.build(2 * node + 1, middle + 1, right);
    }
    fn at(shape: Layout, node: usize) Interval { return shape.ranges[node].?; }
};
const Answer = struct {
    value: i64,
    visited: usize,
    pub fn format(answer: Answer, out: *Writer) Writer.Error!void {
        try out.print("sum={d} visited={d}", .{ answer.value, answer.visited });
    }
};
const SegmentAnswer = struct {
    op: Operation,
    answer: Answer,
    pub fn format(result: SegmentAnswer, out: *Writer) Writer.Error!void {
        try out.print("{s}={d} visited={d}", .{ result.op.label(), result.answer.value, result.answer.visited });
    }
};
const SegmentTree = struct {
    op: Operation,
    shape: Layout,
    values: []i64,
    fn init(gpa: Allocator, contents: []const i64, op: Operation) Allocator.Error!SegmentTree {
        var tree: SegmentTree = .{ .op = op, .shape = try Layout.init(gpa, contents.len), .values = try gpa.alloc(i64, 4 * contents.len) };
        tree.build(1, contents);
        return tree;
    }
    fn build(tree: *SegmentTree, node: usize, contents: []const i64) void {
        const range = tree.shape.at(node);
        if (range.leaf()) {
            tree.values[node] = if (tree.op == .GCD) magnitude(contents[range.left]) else contents[range.left];
        } else {
            tree.build(2 * node, contents);
            tree.build(2 * node + 1, contents);
            tree.pull(node);
        }
    }
    fn pull(tree: *SegmentTree, node: usize) void { tree.values[node] = tree.op.combine(tree.values[2 * node], tree.values[2 * node + 1]); }
    fn query(tree: *const SegmentTree, left: usize, right: usize, node: usize) Answer {
        const range = tree.shape.at(node);
        if (range.covered(left, right)) return .{ .value = tree.values[node], .visited = 1 };
        if (right <= range.middle() or left > range.middle()) {
            var child = tree.query(left, right, if (right <= range.middle()) 2 * node else 2 * node + 1);
            child.visited += 1;
            return child;
        }
        const a = tree.query(left, right, 2 * node);
        const b = tree.query(left, right, 2 * node + 1);
        return .{ .value = tree.op.combine(a.value, b.value), .visited = a.visited + b.visited + 1 };
    }
    fn update(tree: *SegmentTree, index: usize, value: i64, node: usize) usize {
        const range = tree.shape.at(node);
        if (range.leaf()) { tree.values[node] = if (tree.op == .GCD) magnitude(value) else value; return 1; }
        const visited = tree.update(index, value, if (index <= range.middle()) 2 * node else 2 * node + 1);
        tree.pull(node);
        return visited + 1;
    }
    fn describe(tree: *const SegmentTree, answer: Answer) SegmentAnswer { return .{ .op = tree.op, .answer = answer }; }
    fn dump(tree: *const SegmentTree, out: *Writer) Writer.Error!void {
        try line(out, "SEG DUMP {s} nodes={d}", .{ @tagName(tree.op), tree.shape.count });
        for (tree.shape.ranges, 0..) |maybe, node| if (maybe) |range| {
            try line(out, "NODE {d} {d} {d} {d}", .{ node, range.left, range.right, tree.values[node] });
        };
    }
};

const Aggregate = struct {
    sum: i64,
    min: i64,
    max: i64,
    fn merge(a: Aggregate, b: Aggregate) Aggregate { return .{ .sum = a.sum + b.sum, .min = @min(a.min, b.min), .max = @max(a.max, b.max) }; }
    fn eql(a: Aggregate, b: Aggregate) bool { return a.sum == b.sum and a.min == b.min and a.max == b.max; }
    pub fn format(value: Aggregate, out: *Writer) Writer.Error!void { try out.print("sum={d} min={d} max={d}", .{ value.sum, value.min, value.max }); }
};
const LazyAnswer = struct {
    value: Aggregate,
    visited: usize,
    pushes: usize,
    pub fn format(answer: LazyAnswer, out: *Writer) Writer.Error!void {
        try out.print("{f} visited={d} pushes={d}", .{ answer.value, answer.visited, answer.pushes });
    }
};
const Work = struct {
    visited: usize = 0,
    covered: usize = 0,
    pushes: usize = 0,
    pub fn format(work: Work, out: *Writer) Writer.Error!void { try out.print("visited={d} covered={d} pushes={d}", .{ work.visited, work.covered, work.pushes }); }
};
const LazyTree = struct {
    shape: Layout,
    values: []Aggregate,
    assign: []?i64,
    add: []i64,
    fn init(gpa: Allocator, contents: []const i64) Allocator.Error!LazyTree {
        const size = 4 * contents.len;
        var tree: LazyTree = .{ .shape = try Layout.init(gpa, contents.len), .values = try gpa.alloc(Aggregate, size), .assign = try gpa.alloc(?i64, size), .add = try gpa.alloc(i64, size) };
        @memset(tree.assign, null);
        @memset(tree.add, 0);
        tree.build(1, contents);
        return tree;
    }
    fn build(tree: *LazyTree, node: usize, contents: []const i64) void {
        const range = tree.shape.at(node);
        if (range.leaf()) {
            const value = contents[range.left];
            tree.values[node] = .{ .sum = value, .min = value, .max = value };
        } else {
            tree.build(2 * node, contents);
            tree.build(2 * node + 1, contents);
            tree.pull(node);
        }
    }
    fn pull(tree: *LazyTree, node: usize) void { tree.values[node] = Aggregate.merge(tree.values[2 * node], tree.values[2 * node + 1]); }
    fn apply(tree: *LazyTree, node: usize, value: i64, assignment: bool) void {
        const range = tree.shape.at(node);
        const old = tree.values[node];
        tree.values[node] = if (assignment) .{ .sum = value * integer(range.length()), .min = value, .max = value }
            else .{ .sum = old.sum + value * integer(range.length()), .min = old.min + value, .max = old.max + value };
        if (range.leaf()) return;
        if (assignment) { tree.assign[node] = value; tree.add[node] = 0; } else tree.add[node] += value;
    }
    fn push(tree: *LazyTree, node: usize) usize {
        if (tree.assign[node] == null and tree.add[node] == 0) return 0;
        for (2 * node..2 * node + 2) |child| {
            if (tree.assign[node]) |value| tree.apply(child, value, true);
            if (tree.add[node] != 0) tree.apply(child, tree.add[node], false);
        }
        tree.assign[node] = null;
        tree.add[node] = 0;
        return 1;
    }
    fn update(tree: *LazyTree, left: usize, right: usize, value: i64, assignment: bool, node: usize, work: *Work) void {
        work.visited += 1;
        const range = tree.shape.at(node);
        if (range.covered(left, right)) { work.covered += 1; tree.apply(node, value, assignment); return; }
        work.pushes += tree.push(node);
        if (left <= range.middle()) tree.update(left, right, value, assignment, 2 * node, work);
        if (right > range.middle()) tree.update(left, right, value, assignment, 2 * node + 1, work);
        tree.pull(node);
    }
    fn query(tree: *LazyTree, left: usize, right: usize, node: usize) LazyAnswer {
        const range = tree.shape.at(node);
        if (range.covered(left, right)) return .{ .value = tree.values[node], .visited = 1, .pushes = 0 };
        const pushes = tree.push(node);
        if (right <= range.middle() or left > range.middle()) {
            var child = tree.query(left, right, if (right <= range.middle()) 2 * node else 2 * node + 1);
            child.visited += 1;
            child.pushes += pushes;
            return child;
        }
        const a = tree.query(left, right, 2 * node);
        const b = tree.query(left, right, 2 * node + 1);
        return .{ .value = Aggregate.merge(a.value, b.value), .visited = a.visited + b.visited + 1, .pushes = a.pushes + b.pushes + pushes };
    }
    fn dump(tree: *const LazyTree, out: *Writer) Writer.Error!void {
        try line(out, "LAZY DUMP nodes={d}", .{tree.shape.count});
        for (tree.shape.ranges, 0..) |maybe, node| if (maybe) |range| {
            try out.print("NODE {d} {d} {d} {f} assign=", .{ node, range.left, range.right, tree.values[node] });
            if (tree.assign[node]) |value| try out.print("{d}", .{value}) else try out.writeByte('-');
            try line(out, " add={d}", .{tree.add[node]});
        };
    }
};

const Fenwick = struct {
    values: []i64,
    fn init(gpa: Allocator, n: usize) Allocator.Error!Fenwick {
        const values = try gpa.alloc(i64, n + 1);
        @memset(values, 0);
        return .{ .values = values };
    }
    fn add(tree: *Fenwick, position: usize, value: i64) usize {
        var p = position;
        var visited: usize = 0;
        while (p < tree.values.len) : (p += lowbit(p)) { tree.values[p] += value; visited += 1; }
        return visited;
    }
    fn prefix(tree: *const Fenwick, position: usize) Answer {
        var p = position;
        var answer: Answer = .{ .value = 0, .visited = 0 };
        while (p > 0) : (p -= lowbit(p)) { answer.value += tree.values[p]; answer.visited += 1; }
        return answer;
    }
    fn dump(tree: *const Fenwick, out: *Writer, label: []const u8) Writer.Error!void {
        try out.writeAll(label);
        try writeNumbers(out, tree.values[1..]);
    }
};
const PointFenwick = struct {
    contents: []i64,
    bits: Fenwick,
    fn init(gpa: Allocator, contents: []const i64) Allocator.Error!PointFenwick {
        var tree: PointFenwick = .{ .contents = try gpa.dupe(i64, contents), .bits = try Fenwick.init(gpa, contents.len) };
        for (contents, 0..) |value, i| _ = tree.bits.add(i + 1, value);
        return tree;
    }
    fn add(tree: *PointFenwick, index: usize, value: i64) usize { tree.contents[index] += value; return tree.bits.add(index + 1, value); }
    fn query(tree: *const PointFenwick, left: usize, right: usize) Answer {
        const a = tree.bits.prefix(right + 1);
        const b = tree.bits.prefix(left);
        return .{ .value = a.value - b.value, .visited = a.visited + b.visited };
    }
    fn lower(tree: *const PointFenwick, target: i64) struct { index: ?usize, visited: usize } {
        var pos: usize = 0;
        var rest = target;
        var visited: usize = 0;
        var step = power2(log2(tree.contents.len));
        while (step >= 1) : (step /= 2) {
            if (pos + step > tree.contents.len) continue;
            visited += 1;
            const value = tree.bits.values[pos + step];
            if (value < rest) { rest -= value; pos += step; }
        }
        return .{ .index = if (pos == tree.contents.len) null else pos, .visited = visited };
    }
};
const RangeFenwick = struct {
    b1: Fenwick,
    b2: Fenwick,
    fn init(gpa: Allocator, contents: []const i64) Allocator.Error!RangeFenwick {
        var tree: RangeFenwick = .{ .b1 = try Fenwick.init(gpa, contents.len), .b2 = try Fenwick.init(gpa, contents.len) };
        for (contents, 0..) |value, i| {
            const difference = value - (if (i == 0) @as(i64, 0) else contents[i - 1]);
            _ = tree.b1.add(i + 1, difference);
            _ = tree.b2.add(i + 1, integer(i) * difference);
        }
        return tree;
    }
    fn add(tree: *RangeFenwick, left: usize, right: usize, value: i64) usize {
        var visited = tree.b1.add(left + 1, value);
        visited += tree.b1.add(right + 2, -value);
        visited += tree.b2.add(left + 1, value * integer(left));
        visited += tree.b2.add(right + 2, -value * integer(right + 1));
        return visited;
    }
    fn prefix(tree: *const RangeFenwick, position: usize) Answer {
        const a = tree.b1.prefix(position);
        const b = tree.b2.prefix(position);
        return .{ .value = integer(position) * a.value - b.value, .visited = a.visited + b.visited };
    }
    fn query(tree: *const RangeFenwick, left: usize, right: usize) Answer {
        const a = tree.prefix(right + 1);
        const b = tree.prefix(left);
        return .{ .value = a.value - b.value, .visited = a.visited + b.visited };
    }
};

const SparseAnswer = struct {
    min: i64,
    minpos: usize,
    max: i64,
    maxpos: usize,
    level: usize,
    pub fn format(answer: SparseAnswer, out: *Writer) Writer.Error!void {
        try out.print("min={d} minpos={d} max={d} maxpos={d} level={d}", .{ answer.min, answer.minpos, answer.max, answer.maxpos, answer.level });
    }
};
const SparseTable = struct {
    contents: []i64,
    minimum: [][]usize,
    maximum: [][]usize,
    entries: usize,
    fn init(gpa: Allocator, contents: []const i64) Allocator.Error!SparseTable {
        const levels = log2(contents.len) + 1;
        var tree: SparseTable = .{ .contents = try gpa.dupe(i64, contents), .minimum = try gpa.alloc([]usize, levels), .maximum = try gpa.alloc([]usize, levels), .entries = 0 };
        for (0..levels) |level| {
            const length = contents.len - power2(level) + 1;
            tree.minimum[level] = try gpa.alloc(usize, length);
            tree.maximum[level] = try gpa.alloc(usize, length);
            tree.entries += length;
            for (0..length) |i| {
                if (level == 0) { tree.minimum[level][i] = i; tree.maximum[level][i] = i; } else {
                    const half = power2(level - 1);
                    tree.minimum[level][i] = tree.select(tree.minimum[level - 1][i], tree.minimum[level - 1][i + half], true);
                    tree.maximum[level][i] = tree.select(tree.maximum[level - 1][i], tree.maximum[level - 1][i + half], false);
                }
            }
        }
        return tree;
    }
    fn select(tree: *const SparseTable, a: usize, b: usize, minimum: bool) usize {
        return if (if (minimum) tree.contents[a] <= tree.contents[b] else tree.contents[a] >= tree.contents[b]) a else b;
    }
    fn query(tree: *const SparseTable, left: usize, right: usize) SparseAnswer {
        const level = log2(right - left + 1);
        const end = right + 1 - power2(level);
        const a = tree.select(tree.minimum[level][left], tree.minimum[level][end], true);
        const z = tree.select(tree.maximum[level][left], tree.maximum[level][end], false);
        return .{ .min = tree.contents[a], .minpos = a, .max = tree.contents[z], .maxpos = z, .level = level };
    }
    fn dump(tree: *const SparseTable, out: *Writer) Writer.Error!void {
        try line(out, "SPARSE DUMP levels={d}", .{tree.minimum.len});
        for (tree.minimum, tree.maximum, 0..) |minima, maxima, level| {
            try out.print("MIN {d}", .{level});
            try writeNumbers(out, minima);
            try out.print("MAX {d}", .{level});
            try writeNumbers(out, maxima);
        }
    }
};
const Split = struct {
    first: usize,
    last: usize,
    whole: usize,
    cells: usize,
    fn init(left: usize, right: usize, block: usize) Split {
        const first = left / block;
        const last = right / block;
        const whole = if (first == last) 0 else last - first - 1;
        return .{ .first = first, .last = last, .whole = whole, .cells = right - left + 1 - whole * block };
    }
    pub fn format(split: Split, out: *Writer) Writer.Error!void { try out.print("whole={d} cells={d}", .{ split.whole, split.cells }); }
};
const SqrtAnswer = struct {
    sum: i64,
    split: Split,
    pub fn format(answer: SqrtAnswer, out: *Writer) Writer.Error!void { try out.print("sum={d} {f}", .{ answer.sum, answer.split }); }
};
const SqrtBlocks = struct {
    block: usize,
    raw: []i64,
    tags: []i64,
    sums: []i64,
    fn init(gpa: Allocator, contents: []const i64, block: usize) Allocator.Error!SqrtBlocks {
        const count = (contents.len + block - 1) / block;
        const tree: SqrtBlocks = .{ .block = block, .raw = try gpa.dupe(i64, contents), .tags = try gpa.alloc(i64, count), .sums = try gpa.alloc(i64, count) };
        @memset(tree.tags, 0);
        @memset(tree.sums, 0);
        for (contents, 0..) |value, i| tree.sums[i / block] += value;
        return tree;
    }
    fn add(tree: *SqrtBlocks, left: usize, right: usize, value: i64) Split {
        const split = Split.init(left, right, tree.block);
        for (left..right + 1) |i| {
            const block = i / tree.block;
            if (block == split.first or block == split.last) { tree.raw[i] += value; tree.sums[block] += value; }
        }
        if (split.whole > 0) for (split.first + 1..split.last) |block| {
            tree.tags[block] += value;
            tree.sums[block] += value * integer(tree.block);
        };
        return split;
    }
    fn query(tree: *const SqrtBlocks, left: usize, right: usize) SqrtAnswer {
        const split = Split.init(left, right, tree.block);
        var sum: i64 = 0;
        for (left..right + 1) |i| {
            const block = i / tree.block;
            if (block == split.first or block == split.last) sum += tree.raw[i] + tree.tags[block];
        }
        if (split.whole > 0) for (split.first + 1..split.last) |block| { sum += tree.sums[block]; };
        return .{ .sum = sum, .split = split };
    }
    fn dump(tree: *const SqrtBlocks, out: *Writer) Writer.Error!void {
        try line(out, "SQRT DUMP block={d} blocks={d}", .{ tree.block, tree.tags.len });
        for (0..tree.tags.len) |block| {
            const first = block * tree.block;
            const end = @min((block + 1) * tree.block, tree.raw.len);
            try out.print("BLOCK {d} {d} {d} add={d} sum={d}", .{ block, first, end - 1, tree.tags[block], tree.sums[block] });
            try writeNumbers(out, tree.raw[first..end]);
        }
    }
};

const PersistentNode = struct { value: i64, left: ?*const PersistentNode = null, right: ?*const PersistentNode = null };
const Created = struct { node: *const PersistentNode, count: usize };
const PersistentTree = struct {
    gpa: Allocator,
    n: usize,
    values: []i64,
    versions: std.ArrayList(*const PersistentNode) = .empty,
    value_roots: []*const PersistentNode,
    position_nodes: usize,
    value_nodes: usize,
    fn init(gpa: Allocator, contents: []const i64) Allocator.Error!PersistentTree {
        const values = try gpa.dupe(i64, contents);
        std.sort.heap(i64, values, {}, less);
        var distinct: usize = 0;
        for (values) |value| {
            if (distinct == 0 or value != values[distinct - 1]) { values[distinct] = value; distinct += 1; }
        }
        var tree: PersistentTree = .{ .gpa = gpa, .n = contents.len, .values = values[0..distinct], .value_roots = try gpa.alloc(*const PersistentNode, contents.len + 1), .position_nodes = 2 * contents.len - 1, .value_nodes = 2 * distinct - 1 };
        try tree.versions.append(gpa, try tree.build(contents, 0, contents.len - 1));
        const zero = try gpa.alloc(i64, distinct);
        @memset(zero, 0);
        tree.value_roots[0] = try tree.build(zero, 0, distinct - 1);
        for (contents, 0..) |value, i| {
            var left: usize = 0;
            var right = distinct;
            while (left < right) {
                const middle = (left + right) / 2;
                if (tree.values[middle] < value) left = middle + 1 else right = middle;
            }
            const created = try tree.change(tree.value_roots[i], 0, distinct - 1, left, 1, true);
            tree.value_roots[i + 1] = created.node;
            tree.value_nodes += created.count;
        }
        return tree;
    }
    fn node(tree: *const PersistentTree, value: i64, left: ?*const PersistentNode, right: ?*const PersistentNode) Allocator.Error!*const PersistentNode {
        const result = try tree.gpa.create(PersistentNode);
        result.* = .{ .value = value, .left = left, .right = right };
        return result;
    }
    fn build(tree: *const PersistentTree, contents: []const i64, left: usize, right: usize) Allocator.Error!*const PersistentNode {
        if (left == right) return tree.node(contents[left], null, null);
        const middle = (left + right) / 2;
        const a = try tree.build(contents, left, middle);
        const b = try tree.build(contents, middle + 1, right);
        return tree.node(a.value + b.value, a, b);
    }
    fn change(tree: *const PersistentTree, old: *const PersistentNode, left: usize, right: usize, index: usize, value: i64, increment: bool) Allocator.Error!Created {
        if (left == right) return .{ .node = try tree.node(if (increment) old.value + value else value, null, null), .count = 1 };
        const middle = (left + right) / 2;
        var a = old.left.?;
        var b = old.right.?;
        const changed = if (index <= middle) try tree.change(a, left, middle, index, value, increment) else try tree.change(b, middle + 1, right, index, value, increment);
        if (index <= middle) a = changed.node else b = changed.node;
        return .{ .node = try tree.node(a.value + b.value, a, b), .count = changed.count + 1 };
    }
    fn set(tree: *PersistentTree, version: usize, index: usize, value: i64) Allocator.Error!usize {
        const changed = try tree.change(tree.versions.items[version], 0, tree.n - 1, index, value, false);
        try tree.versions.append(tree.gpa, changed.node);
        tree.position_nodes += changed.count;
        return changed.count;
    }
    fn sum(current: *const PersistentNode, nl: usize, nr: usize, left: usize, right: usize) Answer {
        if (left <= nl and nr <= right) return .{ .value = current.value, .visited = 1 };
        const middle = (nl + nr) / 2;
        if (right <= middle or left > middle) {
            var child = if (right <= middle) sum(current.left.?, nl, middle, left, right) else sum(current.right.?, middle + 1, nr, left, right);
            child.visited += 1;
            return child;
        }
        const a = sum(current.left.?, nl, middle, left, right);
        const b = sum(current.right.?, middle + 1, nr, left, right);
        return .{ .value = a.value + b.value, .visited = a.visited + b.visited + 1 };
    }
    fn query(tree: *const PersistentTree, version: usize, left: usize, right: usize) Answer { return sum(tree.versions.items[version], 0, tree.n - 1, left, right); }
    fn kth(tree: *const PersistentTree, left: usize, right: usize, rank: usize) Answer {
        var u = tree.value_roots[right + 1];
        var w = tree.value_roots[left];
        var p: usize = 0;
        var q = tree.values.len - 1;
        var k = rank;
        var visited: usize = 1;
        while (p < q) {
            const middle = (p + q) / 2;
            const difference: usize = @intCast(u.left.?.value - w.left.?.value);
            if (k <= difference) { u = u.left.?; w = w.left.?; q = middle; }
            else { k -= difference; u = u.right.?; w = w.right.?; p = middle + 1; }
            visited += 1;
        }
        return .{ .value = tree.values[p], .visited = visited };
    }
};

const GridFenwick = struct {
    height: usize,
    width: usize,
    values: []i64,
    fn init(gpa: Allocator, height: usize, width: usize, contents: []const i64) Allocator.Error!GridFenwick {
        var tree: GridFenwick = .{ .height = height, .width = width, .values = try gpa.alloc(i64, (height + 1) * (width + 1)) };
        @memset(tree.values, 0);
        for (0..height) |i| for (0..width) |j| { _ = tree.add(i, j, contents[i * width + j]); };
        return tree;
    }
    fn add(tree: *GridFenwick, row: usize, column: usize, value: i64) usize {
        var visited: usize = 0;
        var y = row + 1;
        while (y <= tree.height) : (y += lowbit(y)) {
            var z = column + 1;
            while (z <= tree.width) : (z += lowbit(z)) { tree.values[y * (tree.width + 1) + z] += value; visited += 1; }
        }
        return visited;
    }
    fn prefix(tree: *const GridFenwick, row: usize, column: usize) Answer {
        var answer: Answer = .{ .value = 0, .visited = 0 };
        var y = row;
        while (y > 0) : (y -= lowbit(y)) {
            var z = column;
            while (z > 0) : (z -= lowbit(z)) { answer.value += tree.values[y * (tree.width + 1) + z]; answer.visited += 1; }
        }
        return answer;
    }
    fn query(tree: *const GridFenwick, top: usize, left: usize, bottom: usize, right: usize) Answer {
        const a = tree.prefix(bottom + 1, right + 1);
        const b = tree.prefix(top, right + 1);
        const c = tree.prefix(bottom + 1, left);
        const d = tree.prefix(top, left);
        return .{ .value = a.value - b.value - c.value + d.value, .visited = a.visited + b.visited + c.visited + d.visited };
    }
    fn dump(tree: *const GridFenwick, out: *Writer) Writer.Error!void {
        try line(out, "GRID DUMP rows={d} cols={d}", .{ tree.height, tree.width });
        for (1..tree.height + 1) |row| {
            try out.print("ROW {d}", .{row});
            const first = row * (tree.width + 1) + 1;
            try writeNumbers(out, tree.values[first .. first + tree.width]);
        }
    }
};

const array_fields = .{ "segment", "lazy", "fenwick", "range_fenwick", "sparse", "sqrt", "persistent" };
const State = struct {
    n: usize = 0,
    values: [2000]i64 = undefined,
    original: [2000]i64 = undefined,
    segment: ?*Owned(SegmentTree) = null,
    lazy: ?*Owned(LazyTree) = null,
    fenwick: ?*Owned(PointFenwick) = null,
    range_fenwick: ?*Owned(RangeFenwick) = null,
    sparse: ?*Owned(SparseTable) = null,
    sqrt: ?*Owned(SqrtBlocks) = null,
    persistent: ?*Owned(PersistentTree) = null,
    grid: ?*Owned(GridFenwick) = null,
    fn array(state: *State) []i64 { return state.values[0..state.n]; }
    fn count(state: *const State) usize {
        var result: usize = 0;
        inline for (array_fields) |field| { if (@field(state, field) != null) result += 1; }
        return result;
    }
    fn discard(state: *State) void {
        inline for (array_fields) |field| {
            if (@field(state, field)) |box| box.destroy();
            @field(state, field) = null;
        }
    }
    fn deinit(state: *State) void { state.discard(); if (state.grid) |box| box.destroy(); }
    fn load(state: *State, values: []const i64) void {
        state.discard();
        state.n = values.len;
        @memcpy(state.array(), values);
        @memcpy(state.original[0..state.n], values);
    }
    fn reset(state: *State) Allocator.Error!void {
        @memcpy(state.array(), state.original[0..state.n]);
        if (state.segment) |box| try replace(SegmentTree, &state.segment, .{ state.array(), box.value.op });
        if (state.lazy != null) try replace(LazyTree, &state.lazy, .{state.array()});
        if (state.fenwick != null) try replace(PointFenwick, &state.fenwick, .{state.array()});
        if (state.range_fenwick != null) try replace(RangeFenwick, &state.range_fenwick, .{state.array()});
        if (state.sparse != null) try replace(SparseTable, &state.sparse, .{state.array()});
        if (state.sqrt) |box| try replace(SqrtBlocks, &state.sqrt, .{ state.array(), box.value.block });
        if (state.persistent != null) try replace(PersistentTree, &state.persistent, .{state.array()});
    }
    fn change(state: *State, range: Interval, value: i64, assignment: bool) void {
        for (state.values[range.left .. range.right + 1]) |*item| item.* = if (assignment) value else item.* + value;
    }
};
const VersionAnswer = struct {
    version: usize,
    answer: Answer,
    pub fn format(result: VersionAnswer, out: *Writer) Writer.Error!void { try out.print("version={d} {f}", .{ result.version, result.answer }); }
};
const MoQuery = struct {
    left: usize,
    right: usize,
    number: usize,
    fn before(block: usize, a: MoQuery, b: MoQuery) bool {
        const x = a.left / block;
        const y = b.left / block;
        if (x != y) return x < y;
        if (a.right != b.right) return if (x % 2 == 0) a.right < b.right else a.right > b.right;
        return a.number < b.number;
    }
};
const MoWindow = struct {
    ranks: []usize,
    frequency: []usize,
    distinct: usize = 0,
    moves: usize = 0,
    fn add(window: *MoWindow, index: usize) void {
        const rank = window.ranks[index];
        if (window.frequency[rank] == 0) window.distinct += 1;
        window.frequency[rank] += 1;
        window.moves += 1;
    }
    fn remove(window: *MoWindow, index: usize) void {
        const rank = window.ranks[index];
        window.frequency[rank] -= 1;
        if (window.frequency[rank] == 0) window.distinct -= 1;
        window.moves += 1;
    }
};
fn arg(words: []const []const u8, index: usize) i64 { return number(words[index]); }
fn tokenize(gpa: Allocator, text: []const u8) Allocator.Error![]const []const u8 {
    var result: std.ArrayList([]const u8) = .empty;
    var iterator = std.mem.tokenizeScalar(u8, text, ' ');
    while (iterator.next()) |word| try result.append(gpa, word);
    return result.items;
}
fn parseValues(gpa: Allocator, words: []const []const u8) Allocator.Error![]i64 {
    const values = try gpa.alloc(i64, words.len);
    for (words, values) |word, *value| value.* = number(word);
    return values;
}
const Session = struct {
    state: *State,
    gpa: Allocator,
    out: *Writer,
    problem: []const u8 = "",
    fn fail(session: *Session, comptime fmt: []const u8, args: anytype) Error {
        session.problem = std.fmt.allocPrint(session.gpa, fmt, args) catch return error.OutOfMemory;
        return error.Invalid;
    }
    fn need(session: *Session, comptime T: type, structure: ?*Owned(T), kind: Kind) Error!*T {
        const box = structure orelse return session.fail("NOT BUILT {s}", .{@tagName(kind)});
        return &box.value;
    }
    fn checkIndex(session: *Session, index: i64) Error!usize {
        if (index < 0 or index >= integer(session.state.n)) return session.fail("BAD INDEX {d}", .{index});
        return @intCast(index);
    }
    fn checkRange(session: *Session, left: i64, right: i64) Error!Interval {
        const l = try session.checkIndex(left);
        const r = try session.checkIndex(right);
        if (l > r) return session.fail("BAD RANGE {d} {d}", .{ left, right });
        return .{ .left = l, .right = r };
    }
    fn checkVersion(session: *Session, tree: *const PersistentTree, version: i64) Error!usize {
        if (version < 0 or version >= integer(tree.versions.items.len)) return session.fail("BAD VERSION {d}", .{version});
        return @intCast(version);
    }
    fn checkCell(session: *Session, tree: *const GridFenwick, row: i64, column: i64) Error!void {
        if (row < 0 or row >= integer(tree.height) or column < 0 or column >= integer(tree.width)) return session.fail("BAD CELL {d} {d}", .{ row, column });
    }
    fn report(session: *Session, kind: Kind, matched: bool, result: anytype, ok: *usize, diff: *usize) Writer.Error!void {
        if (matched) ok.* += 1 else diff.* += 1;
        try line(session.out, "{s} {s} {f}", .{ @tagName(kind), if (matched) @as([]const u8, "OK") else "DIFF", result });
    }
    fn check(session: *Session, range: Interval) Writer.Error!void {
        const state = session.state;
        var direct: Aggregate = .{ .sum = 0, .min = state.values[range.left], .max = state.values[range.left] };
        var divisor: i64 = 0;
        for (state.values[range.left .. range.right + 1]) |value| {
            direct.sum += value;
            direct.min = @min(direct.min, value);
            direct.max = @max(direct.max, value);
            divisor = gcd(divisor, value);
        }
        try line(session.out, "CHECK {d} {d} {f} gcd={d}", .{ range.left, range.right, direct, divisor });
        var ok: usize = 0;
        var diff: usize = 0;
        if (state.segment) |box| {
            const answer = box.value.query(range.left, range.right, 1);
            const expected = switch (box.value.op) { .SUM => direct.sum, .MIN => direct.min, .MAX => direct.max, .GCD => divisor };
            try session.report(.SEG, answer.value == expected, box.value.describe(answer), &ok, &diff);
        }
        if (state.lazy) |box| {
            const answer = box.value.query(range.left, range.right, 1);
            try session.report(.LAZY, answer.value.eql(direct), answer, &ok, &diff);
        }
        if (state.fenwick) |box| {
            const answer = box.value.query(range.left, range.right);
            try session.report(.FEN, answer.value == direct.sum, answer, &ok, &diff);
        }
        if (state.range_fenwick) |box| {
            const answer = box.value.query(range.left, range.right);
            try session.report(.RFEN, answer.value == direct.sum, answer, &ok, &diff);
        }
        if (state.sparse) |box| {
            const answer = box.value.query(range.left, range.right);
            try session.report(.SPARSE, answer.min == direct.min and answer.max == direct.max, answer, &ok, &diff);
        }
        if (state.sqrt) |box| {
            const answer = box.value.query(range.left, range.right);
            try session.report(.SQRT, answer.sum == direct.sum, answer, &ok, &diff);
        }
        if (state.persistent) |box| {
            const version = box.value.versions.items.len - 1;
            const answer = box.value.query(version, range.left, range.right);
            try session.report(.PERSIST, answer.value == direct.sum, VersionAnswer{ .version = version, .answer = answer }, &ok, &diff);
        }
        try line(session.out, "RESULT ok={d} diff={d}", .{ ok, diff });
    }
    fn mo(session: *Session, words: []const []const u8) Error!void {
        const state = session.state;
        const queries = try session.gpa.alloc(MoQuery, (words.len - 1) / 2);
        for (queries, 0..) |*query, i| {
            const range = try session.checkRange(arg(words, 2 * i + 1), arg(words, 2 * i + 2));
            query.* = .{ .left = range.left, .right = range.right, .number = i + 1 };
        }
        const block = isqrt(state.n);
        const order = try session.gpa.dupe(MoQuery, queries);
        std.sort.heap(MoQuery, order, block, MoQuery.before);
        const sorted = try session.gpa.dupe(i64, state.array());
        std.sort.heap(i64, sorted, {}, less);
        const ranks = try session.gpa.alloc(usize, state.n);
        for (state.array(), ranks) |value, *rank| {
            var left: usize = 0;
            var right = sorted.len;
            while (left < right) {
                const middle = (left + right) / 2;
                if (sorted[middle] < value) left = middle + 1 else right = middle;
            }
            rank.* = left;
        }
        var window: MoWindow = .{ .ranks = ranks, .frequency = try session.gpa.alloc(usize, state.n) };
        @memset(window.frequency, 0);
        const answers = try session.gpa.alloc(usize, queries.len);
        var left: usize = 0;
        var right: i64 = -1;
        for (order) |query| {
            while (left > query.left) { left -= 1; window.add(left); }
            while (right < integer(query.right)) { right += 1; window.add(@intCast(right)); }
            while (left < query.left) { window.remove(left); left += 1; }
            while (right > integer(query.right)) { window.remove(@intCast(right)); right -= 1; }
            answers[query.number - 1] = window.distinct;
        }
        try line(session.out, "MO queries={d} block={d} moves={d}", .{ queries.len, block, window.moves });
        try session.out.writeAll("ORDER");
        for (order) |query| try session.out.print(" {d}", .{query.number});
        try session.out.writeByte('\n');
        for (queries) |query| try line(session.out, "ANSWER {d} {d} {d} distinct={d}", .{ query.number, query.left, query.right, answers[query.number - 1] });
    }
    fn execute(session: *Session, text: []const u8) Error!void {
        const words = try tokenize(session.gpa, text);
        const command = words[0];
        const state = session.state;
        const out = session.out;
        if (equal(command, "ARRAY")) {
            const range = try session.checkRange(arg(words, 1), arg(words, 2));
            try out.print("ARRAY {d} {d}", .{ range.left, range.right });
            return writeNumbers(out, state.values[range.left .. range.right + 1]);
        }
        if (equal(command, "LOAD")) {
            const removed = state.count();
            state.load(try parseValues(session.gpa, words[1..]));
            return line(out, "LOAD n={d} removed={d}", .{ state.n, removed });
        }
        if (equal(command, "RESET")) {
            const rebuilt = state.count();
            try state.reset();
            return line(out, "RESET rebuilt={d}", .{rebuilt});
        }
        if (equal(command, "CHECK")) return session.check(try session.checkRange(arg(words, 1), arg(words, 2)));
        if (equal(command, "MO")) return session.mo(words);
        const kind = std.meta.stringToEnum(Kind, command).?;
        const action = words[1];
        switch (kind) {
            .SEG => {
                if (equal(action, "BUILD")) {
                    const op = std.meta.stringToEnum(Operation, words[2]) orelse return session.fail("BAD OP {s}", .{words[2]});
                    try replace(SegmentTree, &state.segment, .{ state.array(), op });
                    const tree = &state.segment.?.value;
                    return line(out, "SEG BUILD {s} nodes={d} maxnode={d} root={d}", .{ @tagName(op), tree.shape.count, tree.shape.max_node, tree.values[1] });
                }
                const tree = try session.need(SegmentTree, state.segment, kind);
                if (equal(action, "DUMP")) return tree.dump(out);
                if (equal(action, "UPDATE")) {
                    const index = try session.checkIndex(arg(words, 2));
                    const value = arg(words, 3);
                    const visited = tree.update(index, value, 1);
                    state.values[index] = value;
                    return line(out, "SEG UPDATE {d} {d} root={d} visited={d}", .{ index, value, tree.values[1], visited });
                }
                const range = try session.checkRange(arg(words, 2), arg(words, 3));
                return line(out, "SEG QUERY {d} {d} {f}", .{ range.left, range.right, tree.describe(tree.query(range.left, range.right, 1)) });
            },
            .LAZY => {
                if (equal(action, "BUILD")) {
                    try replace(LazyTree, &state.lazy, .{state.array()});
                    const tree = &state.lazy.?.value;
                    return line(out, "LAZY BUILD nodes={d} {f}", .{ tree.shape.count, tree.values[1] });
                }
                const tree = try session.need(LazyTree, state.lazy, kind);
                if (equal(action, "DUMP")) return tree.dump(out);
                const range = try session.checkRange(arg(words, 2), arg(words, 3));
                if (equal(action, "QUERY")) return line(out, "LAZY QUERY {d} {d} {f}", .{ range.left, range.right, tree.query(range.left, range.right, 1) });
                const value = arg(words, 4);
                const assignment = equal(action, "ASSIGN");
                var work: Work = .{};
                tree.update(range.left, range.right, value, assignment, 1, &work);
                state.change(range, value, assignment);
                return line(out, "LAZY {s} {d} {d} {d} {f}", .{ action, range.left, range.right, value, work });
            },
            .FEN => {
                if (equal(action, "BUILD")) {
                    try replace(PointFenwick, &state.fenwick, .{state.array()});
                    const tree = &state.fenwick.?.value;
                    return line(out, "FEN BUILD n={d} total={d}", .{ state.n, tree.bits.prefix(state.n).value });
                }
                const tree = try session.need(PointFenwick, state.fenwick, kind);
                if (equal(action, "DUMP")) {
                    try line(out, "FEN DUMP n={d}", .{state.n});
                    return tree.bits.dump(out, "T");
                }
                if (equal(action, "LOWER")) {
                    for (tree.contents, 0..) |value, i| if (value < 0) { return session.fail("NEGATIVE {d}", .{i}); };
                    const target = arg(words, 2);
                    const answer = tree.lower(target);
                    try out.print("FEN LOWER {d} index=", .{target});
                    if (answer.index) |index| try out.print("{d}", .{index}) else try out.writeAll("none");
                    return line(out, " visited={d}", .{answer.visited});
                }
                if (equal(action, "RANGE")) {
                    const range = try session.checkRange(arg(words, 2), arg(words, 3));
                    return line(out, "FEN RANGE {d} {d} {f}", .{ range.left, range.right, tree.query(range.left, range.right) });
                }
                const index = try session.checkIndex(arg(words, 2));
                if (equal(action, "PREFIX")) return line(out, "FEN PREFIX {d} {f}", .{ index, tree.bits.prefix(index + 1) });
                const value = arg(words, 3);
                const visited = tree.add(index, value);
                state.values[index] += value;
                return line(out, "FEN ADD {d} {d} visited={d}", .{ index, value, visited });
            },
            .RFEN => {
                if (equal(action, "BUILD")) {
                    try replace(RangeFenwick, &state.range_fenwick, .{state.array()});
                    const tree = &state.range_fenwick.?.value;
                    return line(out, "RFEN BUILD n={d} total={d}", .{ state.n, tree.query(0, state.n - 1).value });
                }
                const tree = try session.need(RangeFenwick, state.range_fenwick, kind);
                if (equal(action, "DUMP")) {
                    try line(out, "RFEN DUMP n={d}", .{state.n});
                    try tree.b1.dump(out, "B1");
                    return tree.b2.dump(out, "B2");
                }
                const range = try session.checkRange(arg(words, 2), arg(words, 3));
                if (equal(action, "SUM")) return line(out, "RFEN SUM {d} {d} {f}", .{ range.left, range.right, tree.query(range.left, range.right) });
                const value = arg(words, 4);
                const visited = tree.add(range.left, range.right, value);
                state.change(range, value, false);
                return line(out, "RFEN ADD {d} {d} {d} visited={d}", .{ range.left, range.right, value, visited });
            },
            .SPARSE => {
                if (equal(action, "BUILD")) {
                    try replace(SparseTable, &state.sparse, .{state.array()});
                    const tree = &state.sparse.?.value;
                    return line(out, "SPARSE BUILD levels={d} entries={d}", .{ tree.minimum.len, tree.entries });
                }
                const tree = try session.need(SparseTable, state.sparse, kind);
                if (equal(action, "DUMP")) return tree.dump(out);
                const range = try session.checkRange(arg(words, 2), arg(words, 3));
                return line(out, "SPARSE QUERY {d} {d} {f}", .{ range.left, range.right, tree.query(range.left, range.right) });
            },
            .SQRT => {
                if (equal(action, "BUILD")) {
                    const block: usize = if (words.len == 3) @intCast(arg(words, 2)) else isqrt(state.n);
                    if (block > state.n) return session.fail("BAD BLOCK {d}", .{block});
                    try replace(SqrtBlocks, &state.sqrt, .{ state.array(), block });
                    return line(out, "SQRT BUILD block={d} blocks={d}", .{ block, state.sqrt.?.value.tags.len });
                }
                const tree = try session.need(SqrtBlocks, state.sqrt, kind);
                if (equal(action, "DUMP")) return tree.dump(out);
                const range = try session.checkRange(arg(words, 2), arg(words, 3));
                if (equal(action, "SUM")) return line(out, "SQRT SUM {d} {d} {f}", .{ range.left, range.right, tree.query(range.left, range.right) });
                const value = arg(words, 4);
                const split = tree.add(range.left, range.right, value);
                state.change(range, value, false);
                return line(out, "SQRT ADD {d} {d} {d} {f}", .{ range.left, range.right, value, split });
            },
            .PERSIST => {
                if (equal(action, "BUILD")) {
                    try replace(PersistentTree, &state.persistent, .{state.array()});
                    const tree = &state.persistent.?.value;
                    return line(out, "PERSIST BUILD nodes={d} distinct={d} valuenodes={d}", .{ tree.position_nodes, tree.values.len, tree.value_nodes });
                }
                const tree = try session.need(PersistentTree, state.persistent, kind);
                if (equal(action, "NODES")) return line(out, "PERSIST NODES versions={d} position={d} value={d}", .{ tree.versions.items.len, tree.position_nodes, tree.value_nodes });
                if (equal(action, "KTH")) {
                    const range = try session.checkRange(arg(words, 2), arg(words, 3));
                    const k = arg(words, 4);
                    if (k < 1 or k > integer(range.length())) return session.fail("BAD K {d}", .{k});
                    const answer = tree.kth(range.left, range.right, @intCast(k));
                    return line(out, "PERSIST KTH {d} {d} {d} value={d} visited={d}", .{ range.left, range.right, k, answer.value, answer.visited });
                }
                const version = try session.checkVersion(tree, arg(words, 2));
                if (equal(action, "SET")) {
                    const index = try session.checkIndex(arg(words, 3));
                    const value = arg(words, 4);
                    const created = try tree.set(version, index, value);
                    return line(out, "PERSIST SET {d} {d} {d} version={d} created={d}", .{ version, index, value, tree.versions.items.len - 1, created });
                }
                const range = try session.checkRange(arg(words, 3), arg(words, 4));
                return line(out, "PERSIST QUERY {d} {d} {d} {f}", .{ version, range.left, range.right, tree.query(version, range.left, range.right) });
            },
            .GRID => {
                if (equal(action, "BUILD")) {
                    const height: usize = @intCast(arg(words, 2));
                    const width: usize = @intCast(arg(words, 3));
                    const count = words.len - 4;
                    if (count != height * width) return session.fail("BAD COUNT {d} {d}", .{ count, height * width });
                    const values = try parseValues(session.gpa, words[4..]);
                    var total: i64 = 0;
                    for (values) |value| total += value;
                    try replace(GridFenwick, &state.grid, .{ height, width, values });
                    return line(out, "GRID BUILD rows={d} cols={d} total={d}", .{ height, width, total });
                }
                const tree = try session.need(GridFenwick, state.grid, kind);
                if (equal(action, "DUMP")) return tree.dump(out);
                const row = arg(words, 2);
                const column = arg(words, 3);
                try session.checkCell(tree, row, column);
                if (equal(action, "ADD")) {
                    const value = arg(words, 4);
                    const visited = tree.add(@intCast(row), @intCast(column), value);
                    return line(out, "GRID ADD {d} {d} {d} visited={d}", .{ row, column, value, visited });
                }
                const bottom = arg(words, 4);
                const right = arg(words, 5);
                try session.checkCell(tree, bottom, right);
                if (row > bottom or column > right) return session.fail("BAD RECT {d} {d} {d} {d}", .{ row, column, bottom, right });
                return line(out, "GRID SUM {d} {d} {d} {d} {f}", .{ row, column, bottom, right, tree.query(@intCast(row), @intCast(column), @intCast(bottom), @intCast(right)) });
            },
        }
    }
};

fn readLine(gpa: Allocator, input: *std.Io.Reader) ![]const u8 {
    var buffer: Writer.Allocating = .init(gpa);
    defer buffer.deinit();
    _ = try input.streamDelimiterEnding(&buffer.writer, '\n');
    if (input.seek < input.end) input.toss(1) else if (buffer.written().len == 0) return error.EndOfStream;
    const text = try buffer.toOwnedSlice();
    return if (text.len > 0 and text[text.len - 1] == '\r') text[0 .. text.len - 1] else text;
}
pub fn main(init: std.process.Init) !void {
    var header = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer header.deinit();
    var state: State = .{};
    defer state.deinit();
    var input_buffer: [1024]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    _ = try readLine(header.allocator(), &input.interface);
    const initial = try tokenize(header.allocator(), try readLine(header.allocator(), &input.interface));
    state.load(try parseValues(header.allocator(), initial));
    const count: usize = @intCast(number(try readLine(header.allocator(), &input.interface)));
    for (0..count) |_| {
        var scratch = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer scratch.deinit();
        const gpa = scratch.allocator();
        const text = try readLine(gpa, &input.interface);
        var response: Writer.Allocating = .init(gpa);
        defer response.deinit();
        var session: Session = .{ .state = &state, .gpa = gpa, .out = &response.writer };
        session.execute(text) catch |err| {
            if (err != error.Invalid) return err;
            try line(&output.interface, "ERROR {s}", .{session.problem});
            try output.interface.flush();
            continue;
        };
        try output.interface.writeAll(response.written());
        try output.interface.flush();
    }
}
