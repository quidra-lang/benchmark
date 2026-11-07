const std = @import("std");
const d = @import("network_io.zig");
const factors = @import("factors.zig");
pub const Graph = struct { neighbors: [15]u16 = [_]u16{0} ** 15, present: u16 = 0 };
pub fn interactionGraph(initial: []const factors.Factor) Graph {
    var out: Graph = .{};
    for (initial) |factor| for (factor.variables) |a| {
        out.present |= d.bit(a);
        for (factor.variables) |b| if (a != b) {
            out.neighbors[a] |= d.bit(b);
        };
    };
    return out;
}
pub const Step = struct { variable: usize, fill: usize, scope: []const usize, size: usize };
pub const Plan = struct { steps: []const Step, maximum: usize = 0, total: usize = 0 };
pub fn makePlan(initial: []const factors.Factor, eliminate: []const usize, given: bool, order: []const usize,
     sizes: []const usize) Plan {
    var graph = interactionGraph(initial);
    var remaining: u16 = 0;
    for (eliminate) |variable| remaining |= d.bit(variable);
    var rank = [_]usize{0} ** 15;
    for (order, 0..) |variable, i| rank[variable] = i;
    var steps: std.ArrayList(Step) = .empty;
    var out: Plan = .{ .steps = &.{} };
    while (remaining != 0) {
        var selected: ?usize = null;
        var chosen_fill: usize = 0;
        var chosen_degree: usize = 0;
        for (0..sizes.len) |variable| {
            if (remaining & d.bit(variable) == 0) continue;
            const neighbors = graph.neighbors[variable];
            var fill: usize = 0;
            const degree: usize = @popCount(neighbors);
            for (0..sizes.len) |a| if (neighbors & d.bit(a) != 0) {
                for (a + 1..sizes.len) |b| if (neighbors & d.bit(b) != 0 and graph.neighbors[a] & d.bit(b) == 0) {
                    fill += 1;
                };
            };
            var better = selected == null;
            if (selected) |previous| better = if (given) rank[variable] < rank[previous] else fill < chosen_fill or (fill == chosen_fill and (degree < chosen_degree or (degree == chosen_degree and variable < previous)));
            if (better) {
                selected = variable;
                chosen_fill = fill;
                chosen_degree = degree;
            }
        }
        const variable = selected.?;
        const neighbors = graph.neighbors[variable];
        var scope: std.ArrayList(usize) = .empty;
        for (0..sizes.len) |v| if ((neighbors | d.bit(variable)) & d.bit(v) != 0) d.append(usize, &scope, v);
        const size = factors.entryCount(scope.items, sizes);
        d.append(Step, &steps, .{ .variable = variable, .fill = chosen_fill, .scope = scope.items, .size = size });
        out.maximum = @max(out.maximum, size);
        out.total += size;
        for (0..sizes.len) |v| {
            if (neighbors & d.bit(v) != 0) graph.neighbors[v] |= neighbors & ~d.bit(v);
            graph.neighbors[v] &= ~d.bit(variable);
        }
        graph.neighbors[variable] = 0;
        graph.present &= ~d.bit(variable);
        remaining &= ~d.bit(variable);
    }
    out.steps = steps.items;
    return out;
}
pub const Product = struct { variable: usize, factor: factors.Factor };
pub const Execution = struct { final: factors.Factor, products: []const Product };
pub fn execute(initial: []const factors.Factor, plan: Plan, sizes: []const usize, maximize: bool) Execution {
    var current = initial;
    var products: std.ArrayList(Product) = .empty;
    for (plan.steps) |step| {
        var selected: std.ArrayList(factors.Factor) = .empty;
        var remaining: std.ArrayList(factors.Factor) = .empty;
        for (current) |factor| {
            if (factors.contains(factor.variables, step.variable)) d.append(factors.Factor,
                 &selected, factor) else d.append(factors.Factor, &remaining, factor);
        }
        const product = factors.multiply(selected.items, sizes);
        d.append(factors.Factor, &remaining, product.eliminate(step.variable, maximize));
        if (maximize) d.append(Product, &products, .{ .variable = step.variable, .factor = product });
        current = remaining.items;
    }
    return .{ .final = factors.multiply(current, sizes), .products = products.items };
}
pub fn traceback(execution: Execution, sizes: []const usize) d.Assignment {
    var out = [_]usize{0} ** 15;
    var i = execution.products.len;
    while (i > 0) {
        i -= 1;
        const product = execution.products[i];
        var best: f64 = -1;
        var selected: usize = 0;
        for (0..sizes[product.variable]) |state| {
            out[product.variable] = state;
            const value = product.factor.value(out);
            if (value > best) {
                best = value;
                selected = state;
            }
        }
        out[product.variable] = selected;
    }
    return out;
}
