const std = @import("std");
const tac = @import("tac_parser.zig");
const cfg = @import("cfg.zig");
const df = @import("dataflow.zig");
pub const Allocation = struct { names: []const tac.Text, neighbors: []cfg.Set, costs: []u512, order: []const usize, potential: []const Potential, registers: []?usize, pressure: usize };
pub const Potential = struct { node: usize, degree: usize };
fn edge(neighbors: []cfg.Set, x: usize, y: usize) void { if (x != y) { neighbors[x].set(y); neighbors[y].set(x); } }
pub fn allocate(a: tac.Allocator, function: tac.Function, flow: *df.Flow, k: usize) !Allocation {
    const count = flow.variables.len; const neighbors = try a.alloc(cfg.Set, count); @memset(neighbors, .initEmpty()); const partners = try a.alloc(cfg.Set, count); @memset(partners, .initEmpty()); const costs = try a.alloc(u512, count); @memset(costs, 0); var pressure: usize = 0;
    for (function.params) |p| costs[flow.variable(p)] += 1;
    for (flow.graph.blocks, 0..) |block, bi| {
        if (!block.reachable) continue; var live = flow.live.output[bi]; var n = block.end; var weight: u512 = 1; for (0..block.depth) |_| weight *= 10;
        while (n > block.first) {
            n -= 1; const ins = function.code[n]; pressure = @max(pressure, @max(flow.live.before[n].count(), flow.live.after[n].count()));
            if (ins.dest.len > 0) { const x = flow.variable(ins.dest); costs[x] += weight; var it = live.iterator(.{}); while (it.next()) |v| { if (ins.kind != .copy or !tac.eq(flow.variables[v], ins.a)) edge(neighbors, x, v); } }
            for (ins.used()) |v| if (tac.variable(v)) { costs[flow.variable(v)] += weight; };
            flow.transfer(&live, ins, n + 1, 1);
        }
    }
    for (function.code) |ins| if (ins.kind == .copy and tac.variable(ins.a) and !tac.eq(ins.a, ins.dest)) {
        var x: ?usize = null; var y: ?usize = null; for (flow.variables, 0..) |name, i| { if (tac.eq(ins.dest, name)) x = i; if (tac.eq(ins.a, name)) y = i; } if (x != null and y != null) edge(partners, x.?, y.?);
    };
    var entry = flow.live.input[0]; for (function.params) |p| entry.set(flow.variable(p));
    for (function.params) |p| { var it = entry.iterator(.{}); while (it.next()) |v| edge(neighbors, flow.variable(p), v); }
    var remaining = cfg.Set.initEmpty(); for (0..count) |i| remaining.set(i); var order: std.ArrayList(usize) = .empty; var potential: std.ArrayList(Potential) = .empty;
    while (remaining.count() > 0) {
        var chosen: ?usize = null; var chosen_degree: usize = 0;
        var it = remaining.iterator(.{}); while (it.next()) |v| { var active_neighbors = neighbors[v]; active_neighbors.setIntersection(remaining); const degree = active_neighbors.count(); if (degree < k and (chosen == null or degree < chosen_degree)) { chosen = v; chosen_degree = degree; } }
        if (chosen == null) {
            it = remaining.iterator(.{}); while (it.next()) |v| { var active_neighbors = neighbors[v]; active_neighbors.setIntersection(remaining); const degree = active_neighbors.count(); if (chosen == null or costs[v] * @as(u512, chosen_degree) < costs[chosen.?] * @as(u512, degree)) { chosen = v; chosen_degree = degree; } }
            try potential.append(a, .{ .node = chosen.?, .degree = chosen_degree });
        }
        try order.append(a, chosen.?); remaining.unset(chosen.?);
    }
    const registers = try a.alloc(?usize, count); @memset(registers, null); var n = order.items.len;
    while (n > 0) { n -= 1; const v = order.items[n]; var free = std.StaticBitSet(16).initEmpty(); for (0..k) |r| free.set(r); var it = neighbors[v].iterator(.{}); while (it.next()) |neighbor| if (registers[neighbor]) |r| { free.unset(r); }; if (free.count() == 0) continue; var bias = std.StaticBitSet(16).initEmpty(); it = partners[v].iterator(.{}); while (it.next()) |partner| if (registers[partner]) |r| { if (free.isSet(r)) bias.set(r); }; registers[v] = if (bias.count() > 0) bias.findFirstSet().? else free.findFirstSet().?; }
    return .{ .names = flow.variables, .neighbors = neighbors, .costs = costs, .order = order.items, .potential = potential.items, .registers = registers, .pressure = pressure };
}
