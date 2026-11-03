const std = @import("std");
const b = @import("baskets.zig");
const Pair = struct { mask: u128, weight: i64 };
const Node = struct { item: usize, parent: usize, count: i64 = 0, children: std.ArrayList(usize) = .empty };
const Tree = struct { owner: *std.heap.ArenaAllocator, header: []const usize, nodes: []const Node };
const HeaderContext = struct { counts: *const [72]i64 };
fn headerLess(context: HeaderContext, a: usize, c: usize) bool { return if (context.counts[a] == context.counts[c]) a < c else context.counts[a] > context.counts[c]; }
fn build(base: []const Pair, minimum: i64) Tree {
    const owner = &b.alloc(std.heap.ArenaAllocator, 1)[0]; owner.* = std.heap.ArenaAllocator.init(b.backing); const allocator = owner.allocator();
    var counts: [72]i64 = @splat(0);
    for (base) |pair| { var it = b.iterator(pair.mask); while (it.next()) |code| counts[code] += pair.weight; }
    var header: std.ArrayList(usize) = .empty;
    for (counts, 0..) |count, code| { if (count >= minimum) header.append(allocator, code) catch @panic("allocation failed"); }
    std.mem.sort(usize, header.items, HeaderContext{ .counts = &counts }, headerLess);
    var nodes: std.ArrayList(Node) = .empty; nodes.append(allocator, .{ .item = 0, .parent = 0 }) catch @panic("allocation failed");
    for (base) |pair| {
        var current: usize = 0;
        for (header.items) |code| {
            if (!b.contains(pair.mask, b.bit(code))) continue;
            var child: ?usize = null;
            for (nodes.items[current].children.items) |index| { if (nodes.items[index].item == code) { child = index; break; } }
            if (child == null) { child = nodes.items.len; nodes.append(allocator, .{ .item = code, .parent = current }) catch @panic("allocation failed"); nodes.items[current].children.append(allocator, child.?) catch @panic("allocation failed"); }
            current = child.?; nodes.items[current].count += pair.weight;
        }
    }
    return .{ .owner = owner, .header = header.items, .nodes = nodes.items };
}
fn conditional(tree: Tree, item: usize) []const Pair {
    var result: std.ArrayList(Pair) = .empty;
    for (tree.nodes[1..]) |node| {
        if (node.item != item) continue;
        var mask: u128 = 0; var parent = node.parent;
        while (parent != 0) { mask |= b.bit(tree.nodes[parent].item); parent = tree.nodes[parent].parent; }
        result.append(tree.owner.allocator(), .{ .mask = mask, .weight = node.count }) catch @panic("allocation failed");
    }
    return result.items;
}
pub const Result = struct { header: usize, nodes: usize, conditional_trees: usize = 0, conditional_nodes: usize = 0, itemsets: []const b.Frequent = &.{}, counts: b.Counts = .empty };
pub fn growth(baskets: []const u128, minimum: i64, max_size: usize) Result {
    const base = b.alloc(Pair, baskets.len); for (baskets, base) |mask, *pair| pair.* = .{ .mask = mask, .weight = 1 };
    const whole = build(base, minimum); var result: Result = .{ .header = whole.header.len, .nodes = whole.nodes.len - 1 };
    const Entry = struct { tree: Tree, suffix: u128 };
    var stack: std.ArrayList(Entry) = .empty; b.append(Entry, &stack, .{ .tree = whole, .suffix = 0 }); var found: std.ArrayList(b.Frequent) = .empty;
    while (stack.pop()) |entry| {
        const tree = entry.tree; defer tree.owner.deinit();
        var position = tree.header.len;
        while (position > 0) {
            position -= 1; const item = tree.header[position]; const mask = entry.suffix | b.bit(item); var count: i64 = 0;
            for (tree.nodes[1..]) |node| { if (node.item == item) count += node.count; }
            b.append(b.Frequent, &found, .{ .mask = mask, .count = count }); b.put(&result.counts, mask, count);
            if (b.size(mask) < max_size) {
                const child = build(conditional(tree, item), minimum);
                if (child.nodes.len > 1) { b.append(Entry, &stack, .{ .tree = child, .suffix = mask }); result.conditional_trees += 1; result.conditional_nodes += child.nodes.len - 1; } else child.owner.deinit();
            }
        }
    }
    std.mem.sort(b.Frequent, found.items, {}, b.sizeLess); result.itemsets = found.items; return result;
}
