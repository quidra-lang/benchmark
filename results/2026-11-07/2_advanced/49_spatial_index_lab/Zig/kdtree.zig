const std = @import("std");
const c = @import("dataset.zig");
pub fn keyLess(a: c.Point, b: c.Point, axis: usize) bool {
    const first_a = if (axis == 0) a.x else a.y;
    const first_b = if (axis == 0) b.x else b.y;
    const second_a = if (axis == 0) a.y else a.x;
    const second_b = if (axis == 0) b.y else b.x;
    return first_a < first_b or (first_a == first_b and (second_a < second_b or (second_a == second_b and a.id < b.id)));
}
fn less(axis: usize, a: c.Point, b: c.Point) bool {
    return keyLess(a, b, axis);
}
pub const Node = struct { point: c.Point, depth: usize, left: ?*Node = null, right: ?*Node = null };
pub fn build(points: []const c.Point, depth: usize) ?*Node {
    if (points.len == 0) return null;
    const sorted = c.dupe(c.Point, points);
    std.mem.sort(c.Point, sorted, depth % 2, less);
    const middle = sorted.len / 2;
    return c.create(Node, .{ .point = sorted[middle], .depth = depth, .left = build(sorted[0..middle],
         depth + 1), .right = build(sorted[middle + 1 ..], depth + 1) });
}
pub fn insert(node_: ?*Node, point: c.Point, depth: usize) *Node {
    const node = node_ orelse return c.create(Node, .{ .point = point, .depth = depth });
    if (keyLess(point, node.point, node.depth % 2)) node.left = insert(node.left, point, node.depth + 1) else node.right = insert(node.right,
         point, node.depth + 1);
    return node;
}
pub fn minimum(node: *const Node, axis: usize) c.Point {
    if (node.depth % 2 == axis) return if (node.left) |left| minimum(left, axis) else node.point;
    var out = node.point;
    if (node.left) |left| {
        const candidate = minimum(left, axis);
        if (keyLess(candidate, out, axis)) out = candidate;
    }
    if (node.right) |right| {
        const candidate = minimum(right, axis);
        if (keyLess(candidate, out, axis)) out = candidate;
    }
    return out;
}
pub fn delete(node_: ?*Node, point: c.Point) ?*Node {
    const node = node_ orelse return null;
    const axis = node.depth % 2;
    if (node.point.id == point.id) {
        if (node.right) |right| {
            const replacement = minimum(right, axis);
            node.point = replacement;
            node.right = delete(node.right, replacement);
        } else if (node.left) |left| {
            const replacement = minimum(left, axis);
            node.point = replacement;
            node.right = delete(node.left, replacement);
            node.left = null;
        } else return null;
    } else if (keyLess(point, node.point, axis)) node.left = delete(node.left, point) else node.right = delete(node.right, point);
    return node;
}
