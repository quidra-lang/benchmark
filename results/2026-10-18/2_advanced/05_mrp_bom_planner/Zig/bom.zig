const std = @import("std");
const r = @import("report.zig");
const master = @import("items.zig");
pub const Edge = struct { parent: usize, child: usize, quantity: i64, scrap: i64 };
pub fn need(edge: Edge, quantity: i64) i64 { return @divFloor(quantity * edge.quantity * (100 + edge.scrap) + 99, 100); }
pub const Graph = struct {
    children: []std.ArrayList(Edge),
    parents: []std.ArrayList(Edge),
    pub fn manufactured(graph: Graph, item: usize) bool { return graph.children[item].items.len > 0; }
    fn visit(graph: Graph, item: usize, target: usize, visited: []bool, trail: *std.ArrayList(usize)) bool {
        r.append(usize, trail, item);
        if (item == target) return true;
        visited[item] = true;
        for (graph.children[item].items) |edge| { if (!visited[edge.child] and graph.visit(edge.child, target, visited, trail)) return true; }
        trail.items.len -= 1;
        return false;
    }
    pub fn path(graph: Graph, item: usize, target: usize) ?[]const usize {
        const visited = r.alloc(bool, graph.children.len);
        @memset(visited, false);
        var found: std.ArrayList(usize) = .empty;
        return if (graph.visit(item, target, visited, &found)) found.items else null;
    }
    fn code(graph: Graph, item: usize, values: []i64) i64 {
        if (values[item] >= 0) return values[item];
        var largest: i64 = 0;
        for (graph.parents[item].items) |edge| largest = @max(largest, graph.code(edge.parent, values) + 1);
        values[item] = largest;
        return largest;
    }
    pub fn codes(graph: Graph) []const i64 { const values = r.alloc(i64, graph.children.len); @memset(values, -1); for (0..values.len) |item| _ = graph.code(item, values); return values; }
    fn cumulativeValue(graph: Graph, items: []const master.Item, item: usize, values: []i64) i64 {
        if (values[item] >= 0) return values[item];
        var largest: i64 = 0;
        for (graph.children[item].items) |edge| largest = @max(largest, graph.cumulativeValue(items, edge.child, values));
        values[item] = items[item].lead + largest;
        return values[item];
    }
    pub fn cumulative(graph: Graph, items: []const master.Item) []const i64 { const values = r.alloc(i64, items.len); @memset(values, -1); for (0..items.len) |item| _ = graph.cumulativeValue(items, item, values); return values; }
};
fn childLess(_: void, a: Edge, b: Edge) bool { return a.child < b.child; }
fn parentLess(_: void, a: Edge, b: Edge) bool { return a.parent < b.parent; }
pub fn load(text: []const u8, items: []const master.Item, errors: *std.ArrayList([]const u8)) Graph {
    const children = r.alloc(std.ArrayList(Edge), items.len);
    const parents = r.alloc(std.ArrayList(Edge), items.len);
    @memset(children, .empty);
    @memset(parents, .empty);
    const graph: Graph = .{ .children = children, .parents = parents };
    for (r.rows(text)) |row| {
        const f = row.fields;
        const parent = master.find(items, f[0]) orelse { r.problem(errors, "bom.csv", row.number, r.fmt("unknown item {s}", .{f[0]})); continue; };
        const child = master.find(items, f[1]) orelse { r.problem(errors, "bom.csv", row.number, r.fmt("unknown item {s}", .{f[1]})); continue; };
        const quantity = r.integer(f[2]);
        const scrap = r.integer(f[3]);
        if (quantity < 1) { r.problem(errors, "bom.csv", row.number, r.fmt("bad quantity {d}", .{quantity})); continue; }
        if (scrap > 50) { r.problem(errors, "bom.csv", row.number, r.fmt("bad scrap {d}", .{scrap})); continue; }
        if (parent == child) { r.problem(errors, "bom.csv", row.number, r.fmt("cycle {s} -> {s}", .{ f[0], f[0] })); continue; }
        var duplicate = false;
        for (children[parent].items) |edge| { if (edge.child == child) duplicate = true; }
        if (duplicate) { r.problem(errors, "bom.csv", row.number, r.fmt("duplicate {s} -> {s}", .{ f[0], f[1] })); continue; }
        if (graph.path(child, parent)) |path| {
            var names: std.ArrayList([]const u8) = .empty;
            for (path) |item| r.append([]const u8, &names, items[item].id);
            r.problem(errors, "bom.csv", row.number, r.fmt("cycle {s} -> {s}", .{ f[0], r.join(names.items, " -> ") }));
            continue;
        }
        const edge: Edge = .{ .parent = parent, .child = child, .quantity = quantity, .scrap = scrap };
        r.append(Edge, &children[parent], edge);
        r.append(Edge, &parents[child], edge);
        std.mem.sort(Edge, children[parent].items, {}, childLess);
        std.mem.sort(Edge, parents[child].items, {}, parentLess);
    }
    return graph;
}
