const std = @import("std");
const c = @import("dataset.zig");
pub const Node = struct {
    x: i64 = 0,
    y: i64 = 0,
    size: i64,
    points: std.ArrayList(c.Point) = .empty,
    children: [4]?*Node = .{ null, null, null, null },
    pub fn leaf(self: Node) bool {
        return self.children[0] == null;
    }
};
pub fn destination(node: Node, point: c.Point) usize {
    const half = @divExact(node.size, 2);
    return (if (point.y >= node.y + half) @as(usize, 2) else 0) + (if (point.x >= node.x + half) @as(usize, 1) else 0);
}
pub fn insert(node: *Node, point: c.Point, bucket: usize) void {
    if (!node.leaf()) {
        insert(node.children[destination(node.*, point)].?, point, bucket);
        return;
    }
    c.pointInsert(&node.points, point);
    if (node.points.items.len <= bucket) return;
    const half = @divExact(node.size, 2);
    for (0..4) |i| node.children[i] = c.create(Node, .{ .x = node.x + c.n(i % 2) * half, .y = node.y + c.n(i / 2) * half,
         .size = half });
    const old = node.points.items;
    node.points = .empty;
    for (old) |value| insert(node, value, bucket);
}
pub fn delete(node: *Node, point: c.Point, bucket: usize) void {
    if (node.leaf()) {
        c.pointRemove(&node.points, point.id);
        return;
    }
    delete(node.children[destination(node.*, point)].?, point, bucket);
    var count: usize = 0;
    for (node.children) |child_| {
        const child = child_.?;
        if (!child.leaf()) return;
        count += child.points.items.len;
    }
    if (count > bucket) return;
    for (&node.children) |*child_| {
        const child = child_.*.?;
        for (child.points.items) |value| c.pointInsert(&node.points, value);
        child_.* = null;
    }
}
