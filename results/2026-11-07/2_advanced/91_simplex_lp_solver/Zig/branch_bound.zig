const std = @import("std");
const r = @import("rational.zig");
pub const Node = struct { lower: []r.Bound, upper: []r.Bound, depth: usize = 0, parent: usize = 0, branch: []const u8 = "root", parent_value: r.Q = .{} };
pub fn Outcome(comptime S: type) type { return struct { root: ?S = null, incumbent: ?S = null, status: []const u8 = "INFEASIBLE", nodes: usize = 0, pivots: usize = 0, incumbents: usize = 0, pruned: usize = 0, infeasible: usize = 0, bound: ?r.Q = null, open: usize = 0 }; }
pub fn better(maximize: bool, a: r.Q, b: r.Q) bool { return a.cmp(b) == (if (maximize) std.math.Order.gt else .lt); }
pub fn run(comptime S: type, model: anytype, solve: anytype, log: *r.Text, tree: *r.Text) Outcome(S) {
    var out: Outcome(S) = .{}; var stack: std.ArrayList(Node) = .empty;
    r.add(Node, &stack, .{ .lower = r.copy(r.Bound, model.lower), .upper = r.copy(r.Bound, model.upper) });
    tree.line("MODEL {s} {s} integers {d} node_limit {d}", .{model.name, if (model.maximize) "maximize" else "minimize", model.integerCount(), model.limit});
    while (stack.items.len > 0) {
        if (out.nodes == model.limit) { out.status = "NODE_LIMIT"; break; }
        const node = stack.pop().?; out.nodes += 1;
        const lp: S = solve(model, node.lower, node.upper, out.nodes, log);
        if (out.root == null) out.root = lp;
        out.pivots += lp.pivots(); var action: []const u8 = undefined;
        if (r.eq(lp.status, "INFEASIBLE")) { out.infeasible += 1; action = "infeasible"; }
        else if (r.eq(lp.status, "UNBOUNDED")) { action = "unbounded"; out.status = "UNBOUNDED"; }
        else if (out.incumbent != null and !better(model.maximize, lp.objective, out.incumbent.?.objective)) { out.pruned += 1; action = "pruned"; }
        else {
            var fractional: ?usize = null;
            for (lp.x, model.integer, 0..) |x, integer, j| if (integer and x.d != 1) { fractional = j; break; };
            if (fractional) |j| {
                const v = lp.x[j]; action = r.fmt("branch {s} {s}", .{model.names[j], v.str()});
                const high = Node{ .lower = r.copy(r.Bound, node.lower), .upper = r.copy(r.Bound, node.upper), .depth = node.depth + 1, .parent = out.nodes, .branch = r.fmt("{s}>={d}", .{model.names[j], v.ceil()}), .parent_value = lp.objective };
                high.lower[j] = r.Bound.finite(r.Q.int(v.ceil())); r.add(Node, &stack, high);
                const low = Node{ .lower = r.copy(r.Bound, node.lower), .upper = r.copy(r.Bound, node.upper), .depth = node.depth + 1, .parent = out.nodes, .branch = r.fmt("{s}<={d}", .{model.names[j], v.floor()}), .parent_value = lp.objective };
                low.upper[j] = r.Bound.finite(r.Q.int(v.floor())); r.add(Node, &stack, low);
            } else { action = "incumbent"; out.incumbent = lp; out.incumbents += 1; }
        }
        tree.line("NODE {d} depth {d} parent {s} branch {s} lp {s} pivots {d} action {s}", .{out.nodes, node.depth, if (node.parent == 0) "-" else r.fmt("{d}", .{node.parent}), node.branch, if (r.eq(lp.status, "OPTIMAL")) lp.objective.str() else if (r.eq(lp.status, "INFEASIBLE")) "infeasible" else "unbounded", lp.pivots(), action});
        if (r.eq(out.status, "UNBOUNDED")) break;
    }
    if (!r.eq(out.status, "NODE_LIMIT") and !r.eq(out.status, "UNBOUNDED")) out.status = if (out.incumbent != null) "OPTIMAL" else "INFEASIBLE";
    if (out.incumbent) |s| out.bound = s.objective;
    if (r.eq(out.status, "NODE_LIMIT")) {
        var i = stack.items.len; while (i > 0) { i -= 1; const n = stack.items[i]; tree.line("OPEN parent {d} branch {s} bound {s}", .{n.parent, n.branch, n.parent_value.str()}); if (out.bound == null or better(model.maximize, n.parent_value, out.bound.?)) out.bound = n.parent_value; }
    }
    out.open = stack.items.len;
    tree.line("RESULT {s} objective {s} nodes {d} incumbents {d} pruned {d} infeasible {d} open {d} bound {s}", .{out.status, if (out.incumbent) |s| s.objective.str() else "-", out.nodes, out.incumbents, out.pruned, out.infeasible, out.open, if (out.bound) |q| q.str() else "-"});
    return out;
}
