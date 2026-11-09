const std = @import("std");
const r = @import("report.zig");
const master = @import("items.zig");
const bom = @import("bom.zig");
pub const Cost = struct { material: i64 = 0, labor: i64 = 0, total: i64 = 0 };
pub fn rollup(items: []const master.Item, graph: bom.Graph, order: []const usize) []const Cost {
    const costs = r.alloc(Cost, items.len);
    @memset(costs, .{});
    var i = order.len;
    while (i > 0) {
        i -= 1;
        const id = order[i];
        var material = items[id].material;
        var labor = items[id].labor;
        for (graph.children[id].items) |edge| { material += @divFloor(edge.quantity * (100 + edge.scrap) * costs[edge.child].material + 50, 100); labor += @divFloor(edge.quantity * (100 + edge.scrap) * costs[edge.child].labor + 50, 100); }
        costs[id] = .{ .material = material, .labor = labor, .total = material + labor };
    }
    return costs;
}
fn valueLess(values: []const i64, a: usize, b: usize) bool { return values[a] > values[b] or (values[a] == values[b] and a < b); }
pub fn abc(values: []const i64) []const u8 {
    const order = r.alloc(usize, values.len);
    var total: i64 = 0;
    for (values, 0..) |value, i| { order[i] = i; total += value; }
    std.mem.sort(usize, order, values, valueLess);
    const result = r.alloc(u8, values.len);
    var before: i64 = 0;
    for (order) |id| { result[id] = if (values[id] == 0) 'C' else if (100 * before < 80 * total) 'A' else if (100 * before < 95 * total) 'B' else 'C'; before += values[id]; }
    return result;
}
