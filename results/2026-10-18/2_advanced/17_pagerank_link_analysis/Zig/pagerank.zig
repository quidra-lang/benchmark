const D = @import("graph_io.zig");
pub const Result = struct { values: [500]f64 = [_]f64{0} ** 500, changes: [100]f64 = undefined, iterations: usize, converged_at: ?usize = null };
pub fn powerIteration(graph: D.Graph, teleport: []const bool, damping: f64, iterations: usize, tolerance: f64) Result {
    var result: Result = .{ .iterations = iterations };
    var size: usize = 0;
    var weights = [_]usize{0} ** 500;
    for (0..graph.count) |u| {
        if (teleport[u]) size += 1;
        for (graph.out[u]) |v| weights[u] += graph.weights[u * graph.count + v];
    }
    for (teleport, 0..) |member, v| result.values[v] = if (member) 1 / D.real(size) else 0;
    for (0..iterations) |t| {
        var dangling: f64 = 0;
        for (0..graph.count) |u| { if (weights[u] == 0) dangling += result.values[u]; }
        const base = ((1 - damping) + damping * dangling) / D.real(size);
        var updated: [500]f64 = undefined;
        for (0..graph.count) |v| {
            var inflow: f64 = 0;
            for (graph.in[v]) |u| inflow += (result.values[u] * D.real(graph.weights[u * graph.count + v])) / D.real(weights[u]);
            updated[v] = damping * inflow + (if (teleport[v]) base else 0);
        }
        var change: f64 = 0;
        for (0..graph.count) |v| change += @abs(updated[v] - result.values[v]);
        result.changes[t] = change;
        if (result.converged_at == null and change < tolerance) result.converged_at = t + 1;
        @memcpy(result.values[0..graph.count], updated[0..graph.count]);
    }
    return result;
}
