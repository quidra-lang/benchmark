const D = @import("graph_io.zig");
pub const Result = struct { authority: [500]f64 = [_]f64{0} ** 500, hub: [500]f64 = [_]f64{0} ** 500 };
pub fn hits(graph: D.Graph, nodes: []const bool, iterations: usize) Result {
    var result: Result = .{};
    for (nodes, 0..) |member, v| { if (member) { result.authority[v] = 1; result.hub[v] = 1; } }
    for (0..iterations) |_| {
        var incoming = [_]f64{0} ** 500;
        var outgoing = [_]f64{0} ** 500;
        var a_square: f64 = 0;
        var h_square: f64 = 0;
        for (nodes, 0..) |member, v| { if (member) { for (graph.in[v]) |u| incoming[v] += result.hub[u]; } }
        for (nodes, 0..) |member, u| { if (member) { for (graph.out[u]) |v| outgoing[u] += incoming[v]; } }
        for (nodes, 0..) |member, v| { if (member) { a_square += incoming[v] * incoming[v]; h_square += outgoing[v] * outgoing[v]; } }
        const a_norm = @sqrt(a_square);
        const h_norm = @sqrt(h_square);
        for (nodes, 0..) |member, v| { if (member) { result.authority[v] = incoming[v] / a_norm; result.hub[v] = outgoing[v] / h_norm; } }
    }
    return result;
}
