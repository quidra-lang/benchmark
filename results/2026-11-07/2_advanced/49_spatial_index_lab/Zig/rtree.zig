const std = @import("std");
const c = @import("dataset.zig");
pub fn area(b: c.Box) i64 {
    return (b.x2 - b.x1) * (b.y2 - b.y1);
}
pub fn mbr(a: c.Box, b: c.Box) c.Box {
    return .{ .x1 = @min(a.x1, b.x1), .y1 = @min(a.y1, b.y1), .x2 = @max(a.x2, b.x2), .y2 = @max(a.y2, b.y2) };
}
pub fn enlargement(a: c.Box, b: c.Box) i64 {
    return area(mbr(a, b)) - area(a);
}
pub fn intersects(a: c.Box, b: c.Box) bool {
    return a.x1 <= b.x2 and b.x1 <= a.x2 and a.y1 <= b.y2 and b.y1 <= a.y2;
}
pub fn contains(a: c.Box, b: c.Box) bool {
    return a.x1 <= b.x1 and b.x2 <= a.x2 and a.y1 <= b.y1 and b.y2 <= a.y2;
}
pub fn overlap(a: c.Box, b: c.Box) i64 {
    const w = @min(a.x2, b.x2) - @max(a.x1, b.x1);
    const h = @min(a.y2, b.y2) - @max(a.y1, b.y1);
    return if (w > 0 and h > 0) w * h else 0;
}
pub fn distance(x: i64, y: i64, b: c.Box) i64 {
    const dx = if (x < b.x1) b.x1 - x else if (x > b.x2) x - b.x2 else 0;
    const dy = if (y < b.y1) b.y1 - y else if (y > b.y2) y - b.y2 else 0;
    return dx * dx + dy * dy;
}
pub const Entry = struct { box: c.Box, id: i64 = 0, number: i64 = 0, child: ?*Node = null };
pub const Node = struct {
    level: usize = 0,
    parent: ?*Node = null,
    entries: std.ArrayList(Entry) = .empty,
    pub fn box(self: Node) c.Box {
        var out = self.entries.items[0].box;
        for (self.entries.items[1..]) |entry| out = mbr(out, entry.box);
        return out;
    }
};
pub const Tree = struct {
    root: *Node,
    maximum: usize,
    minimum: usize,
    pub fn init(maximum: usize, minimum: usize) Tree {
        return .{ .root = c.create(Node, .{}), .maximum = maximum, .minimum = minimum };
    }
    pub fn split(self: *Tree, node: *Node) *Node {
        const old = c.dupe(Entry, node.entries.items);
        var first: usize = 0;
        var second: usize = 1;
        var largest = area(mbr(old[0].box, old[1].box)) - area(old[0].box) - area(old[1].box);
        for (0..old.len - 1) |i| for (i + 1..old.len) |j| {
            const value = area(mbr(old[i].box, old[j].box)) - area(old[i].box) - area(old[j].box);
            if (value > largest) {
                largest = value;
                first = i;
                second = j;
            }
        };
        var a: std.ArrayList(Entry) = .empty;
        var b: std.ArrayList(Entry) = .empty;
        var rest: std.ArrayList(Entry) = .empty;
        c.append(Entry, &a, old[first]);
        c.append(Entry, &b, old[second]);
        for (old, 0..) |entry, i| if (i != first and i != second) c.append(Entry, &rest, entry);
        var ba = a.items[0].box;
        var bb = b.items[0].box;
        while (rest.items.len > 0) {
            if (a.items.len + rest.items.len == self.minimum) {
                for (rest.items) |entry| c.append(Entry, &a, entry);
                break;
            }
            if (b.items.len + rest.items.len == self.minimum) {
                for (rest.items) |entry| c.append(Entry, &b, entry);
                break;
            }
            var chosen: usize = 0;
            var difference: i64 = -1;
            for (rest.items, 0..) |entry, i| {
                const x = enlargement(ba, entry.box);
                const y = enlargement(bb, entry.box);
                const value = @as(i64, @intCast(@abs(x - y)));
                if (value > difference) {
                    difference = value;
                    chosen = i;
                }
            }
            const entry = rest.orderedRemove(chosen);
            const d1 = enlargement(ba, entry.box);
            const d2 = enlargement(bb, entry.box);
            const left = d1 < d2 or (d1 == d2 and (area(ba) < area(bb) or (area(ba) == area(bb) and a.items.len <= b.items.len)));
            if (left) {
                c.append(Entry, &a, entry);
                ba = mbr(ba, entry.box);
            } else {
                c.append(Entry, &b, entry);
                bb = mbr(bb, entry.box);
            }
        }
        node.entries = a;
        const sibling = c.create(Node, .{ .level = node.level, .parent = node.parent, .entries = b });
        for (node.entries.items) |entry| if (entry.child) |child| {
            child.parent = node;
        };
        for (sibling.entries.items) |entry| if (entry.child) |child| {
            child.parent = sibling;
        };
        return sibling;
    }
    pub fn insert(self: *Tree, entry: Entry, level: usize) void {
        var node = self.root;
        while (node.level > level) {
            var chosen: usize = 0;
            for (node.entries.items[1..], 1..) |candidate, i| {
                const a = candidate.box;
                const b = node.entries.items[chosen].box;
                const ea = enlargement(a, entry.box);
                const eb = enlargement(b, entry.box);
                if (ea < eb or (ea == eb and area(a) < area(b))) chosen = i;
            }
            node = node.entries.items[chosen].child.?;
        }
        c.append(Entry, &node.entries, entry);
        if (entry.child) |child| child.parent = node;
        while (true) {
            const sibling = if (node.entries.items.len > self.maximum) self.split(node) else null;
            const parent = node.parent orelse {
                if (sibling) |other| {
                    self.root = c.create(Node, .{ .level = node.level + 1 });
                    c.append(Entry, &self.root.entries, .{ .box = node.box(), .child = node });
                    c.append(Entry, &self.root.entries, .{ .box = other.box(), .child = other });
                    node.parent = self.root;
                    other.parent = self.root;
                }
                return;
            };
            for (parent.entries.items) |*parent_entry| if (parent_entry.child.? == node) {
                parent_entry.box = node.box();
                break;
            };
            if (sibling) |other| {
                c.append(Entry, &parent.entries, .{ .box = other.box(), .child = other });
                other.parent = parent;
            }
            node = parent;
        }
    }
    pub fn delete(self: *Tree, point: c.Point) void {
        var node = findLeaf(self.root, point).?;
        for (node.entries.items, 0..) |entry, i| if (entry.id == point.id) {
            _ = node.entries.orderedRemove(i);
            break;
        };
        var removed: std.ArrayList(*Node) = .empty;
        while (node != self.root) {
            const parent = node.parent.?;
            var position: usize = 0;
            while (parent.entries.items[position].child.? != node) position += 1;
            if (node.entries.items.len < self.minimum) {
                _ = parent.entries.orderedRemove(position);
                c.append(*Node, &removed, node);
            } else parent.entries.items[position].box = node.box();
            node = parent;
        }
        for (removed.items) |old| {
            const entries = c.dupe(Entry, old.entries.items);
            for (entries) |entry| self.insert(entry, old.level);
        }
        while (self.root.level > 0 and self.root.entries.items.len == 1) {
            self.root = self.root.entries.items[0].child.?;
            self.root.parent = null;
        }
    }
    pub fn bulk(self: *Tree, source: []const Entry) void {
        var entries = c.dupe(Entry, source);
        var level: usize = 0;
        while (true) {
            const pages = (entries.len + self.maximum - 1) / self.maximum;
            var slabs: usize = 1;
            while (slabs * slabs < pages) slabs += 1;
            std.mem.sort(Entry, entries, false, entryLess);
            var nodes: std.ArrayList(*Node) = .empty;
            var start: usize = 0;
            while (start < entries.len) : (start += slabs * self.maximum) {
                const end = @min(entries.len, start + slabs * self.maximum);
                std.mem.sort(Entry, entries[start..end], true, entryLess);
                var begin = start;
                while (begin < end) : (begin += self.maximum) {
                    const node = c.create(Node, .{ .level = level });
                    for (entries[begin..@min(end, begin + self.maximum)]) |entry| {
                        c.append(Entry, &node.entries, entry);
                        if (entry.child) |child| child.parent = node;
                    }
                    c.append(*Node, &nodes, node);
                }
            }
            if (nodes.items.len == 1) {
                self.root = nodes.items[0];
                self.root.parent = null;
                return;
            }
            entries = c.alloc(Entry, nodes.items.len);
            for (nodes.items, entries, 0..) |node, *entry, i| entry.* = .{ .box = node.box(), .number = c.n(i), .child = node };
            level += 1;
        }
    }
};
fn entryLess(axis_y: bool, a: Entry, b: Entry) bool {
    const ax = if (axis_y) a.box.y1 + a.box.y2 else a.box.x1 + a.box.x2;
    const bx = if (axis_y) b.box.y1 + b.box.y2 else b.box.x1 + b.box.x2;
    const ay = if (axis_y) a.box.x1 + a.box.x2 else a.box.y1 + a.box.y2;
    const by = if (axis_y) b.box.x1 + b.box.x2 else b.box.y1 + b.box.y2;
    return ax < bx or (ax == bx and (ay < by or (ay == by and a.number < b.number)));
}
pub fn findLeaf(node: *Node, point: c.Point) ?*Node {
    if (node.level == 0) {
        for (node.entries.items) |entry| if (entry.id == point.id) return node;
        return null;
    }
    for (node.entries.items) |entry| if (contains(entry.box, point.box())) {
        if (findLeaf(entry.child.?, point)) |result| return result;
    };
    return null;
}
