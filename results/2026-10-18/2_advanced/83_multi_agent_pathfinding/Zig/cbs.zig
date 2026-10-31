const std = @import("std");
const g = @import("grid_map.zig");
const ll = @import("low_level.zig");
pub fn position(path: g.Path, time: usize) usize {
    return path[@min(time, path.len - 1)];
}
pub const Conflict = struct { edge: bool, time: usize, a: usize, b: usize, u: usize, v: usize, category: usize = 2 };
pub const Constraint = struct { agent: usize, edge: bool, u: usize, v: usize, time: usize };
pub fn conflicts(paths: g.Plan) []Conflict {
    var maximum: usize = 0;
    for (paths) |path| maximum = @max(maximum, path.len - 1);
    var out: std.ArrayList(Conflict) = .empty;
    for (1..maximum + 1) |time| for (0..paths.len) |a| for (a + 1..paths.len) |b| {
        const current_a = position(paths[a], time);
        const current_b = position(paths[b], time);
        if (current_a == current_b) g.append(Conflict, &out, .{ .edge = false, .time = time,
             .a = a, .b = b, .u = current_a, .v = current_a }) else if (current_a == position(paths[b],
             time - 1) and current_b == position(paths[a], time - 1)) g.append(Conflict, &out,
             .{ .edge = true, .time = time, .a = a, .b = b, .u = position(paths[a], time - 1),
             .v = current_a });
    };
    return out.items;
}
pub fn split(conflict: Conflict) [2]Constraint {
    return .{ .{ .agent = conflict.a, .edge = conflict.edge, .u = conflict.u, .v = conflict.v,
         .time = conflict.time }, .{ .agent = conflict.b, .edge = conflict.edge, .u = conflict.v,
         .v = conflict.u, .time = conflict.time } };
}
pub fn planCost(paths: g.Plan, makespan: bool) i64 {
    var result: i64 = 0;
    for (paths) |path| {
        const cost = g.n(path.len - 1);
        result = if (makespan) @max(result, cost) else result + cost;
    }
    return result;
}
pub const Node = struct { paths: g.Plan, constraints: []const ll.Prohibitions, number: usize,
     depth: usize, parent: ?usize, conflicts: []const Conflict, cost: i64 };
pub fn newNode(paths: g.Plan, constraints: []const ll.Prohibitions, number: usize, depth: usize,
     parent: ?usize, makespan: bool) *Node {
    return g.create(Node, .{ .paths = paths, .constraints = constraints, .number = number,
         .depth = depth, .parent = parent, .conflicts = conflicts(paths), .cost = planCost(paths,
         makespan) });
}
pub fn less(a: *const Node, b: *const Node) bool {
    if (a.cost != b.cost) return a.cost < b.cost;
    if (a.conflicts.len != b.conflicts.len) return a.conflicts.len < b.conflicts.len;
    return a.number < b.number;
}
pub const Heap = struct {
    items: std.ArrayList(*Node) = .empty,
    pub fn push(self: *Heap, node: *Node) void {
        g.append(*Node, &self.items, node);
        var index = self.items.items.len - 1;
        while (index > 0) {
            const parent = (index - 1) / 2;
            if (!less(self.items.items[index], self.items.items[parent])) break;
            std.mem.swap(*Node, &self.items.items[index], &self.items.items[parent]);
            index = parent;
        }
    }
    pub fn pop(self: *Heap) *Node {
        const node = self.items.items[0];
        const last = self.items.pop().?;
        if (self.items.items.len == 0) return node;
        self.items.items[0] = last;
        var index: usize = 0;
        while (2 * index + 1 < self.items.items.len) {
            var child = 2 * index + 1;
            if (child + 1 < self.items.items.len and less(self.items.items[child + 1], self.items.items[child])) child += 1;
            if (!less(self.items.items[child], self.items.items[index])) break;
            std.mem.swap(*Node, &self.items.items[child], &self.items.items[index]);
            index = child;
        }
        return node;
    }
};
