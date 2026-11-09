const r = @import("rational.zig");
const t = @import("tableau.zig");
pub const Result = struct { iterations: usize = 0, unbounded: ?usize = null };
pub fn phase(table: *t.Tableau, costs: []const r.Q, candidate_count: usize, log: *r.Text, level: usize, offset: r.Q, sign: r.Q) Result {
    var result: Result = .{};
    while (true) {
        const reduced = table.reduced(costs); var enter: ?usize = null;
        for (0..candidate_count) |k| if (reduced[k].n < 0) { enter = k; break; };
        const q = enter orelse return result;
        var leave: ?usize = null; var ratio: r.Q = .{};
        for (table.a, 0..) |row, i| if (row[q].n > 0) {
            const theta = table.beta[i].div(row[q]);
            if (leave == null or theta.cmp(ratio) == .lt or (theta.cmp(ratio) == .eq and table.basis[i] < table.basis[leave.?])) { leave = i; ratio = theta; }
        };
        const p = leave orelse { result.unbounded = q; return result; };
        const old = table.basis[p]; table.pivot(p, q); result.iterations += 1;
        if (level >= 1) log.line("PIVOT {d} enter {s} reduced {s} leave {s} row {s} ratio {s} objective {s}", .{ result.iterations, table.columns[q], reduced[q].str(), table.columns[old], table.rows[p], ratio.str(), offset.plus(sign.mul(table.value(costs))).str() });
    }
}
