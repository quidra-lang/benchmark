const c = @import("cnf_io.zig");
fn pair(formula: *c.Formula, a: i64, b: i64) void {
    c.append(c.Clause, &formula.clauses, c.dupe(i64, &.{ a, b }));
}
pub fn queens(n: usize) c.Formula {
    var out: c.Formula = .{ .variables = n * n };
    for (0..n) |r| {
        const clause = c.alloc(i64, n);
        for (clause, 1..) |*literal, column| literal.* = c.n(r * n + column);
        c.append(c.Clause, &out.clauses, clause);
    }
    for (1..out.variables + 1) |a| for (a + 1..out.variables + 1) |b| {
        const ar = (a - 1) / n;
        const ac = (a - 1) % n;
        const br = (b - 1) / n;
        const bc = (b - 1) % n;
        if (ar == br or ac == bc or @abs(c.n(ar) - c.n(br)) == @abs(c.n(ac) - c.n(bc))) pair(&out, -c.n(a), -c.n(b));
    };
    return out;
}
pub fn pigeon(pigeons: usize, holes: usize) c.Formula {
    var out: c.Formula = .{ .variables = pigeons * holes };
    for (0..pigeons) |p| {
        const clause = c.alloc(i64, holes);
        for (clause, 1..) |*literal, h| literal.* = c.n(p * holes + h);
        c.append(c.Clause, &out.clauses, clause);
    }
    for (0..pigeons) |p| for (1..holes + 1) |a| for (a + 1..holes + 1) |b| pair(&out, -c.n(p * holes + a), -c.n(p * holes + b));
    for (1..holes + 1) |h| for (0..pigeons) |a| for (a + 1..pigeons) |b| pair(&out, -c.n(a * holes + h), -c.n(b * holes + h));
    return out;
}
pub fn color(graph: c.Graph, colors: usize) c.Formula {
    var out: c.Formula = .{ .variables = graph.vertices * colors };
    for (0..graph.vertices) |x| {
        const clause = c.alloc(i64, colors);
        for (clause, 1..) |*literal, k| literal.* = c.n(x * colors + k);
        c.append(c.Clause, &out.clauses, clause);
    }
    for (0..graph.vertices) |x| for (1..colors + 1) |a| for (a + 1..colors + 1) |b| pair(&out, -c.n(x * colors + a),
         -c.n(x * colors + b));
    for (graph.edges.items) |edge| for (1..colors + 1) |k| pair(&out, -c.n((edge.a - 1) * colors + k),
         -c.n((edge.b - 1) * colors + k));
    return out;
}
pub fn decode(model: c.Model, rows: usize, columns: usize) []i64 {
    const positions = c.alloc(i64, rows);
    @memset(positions, 0);
    for (positions, 0..) |*position, r| for (1..columns + 1) |column| {
        if (model[r * columns + column] == 1) position.* = c.n(column);
    };
    return positions;
}
