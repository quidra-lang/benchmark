const std = @import("std");
const r = @import("rational.zig");
const p = @import("lp_parser.zig");
const t = @import("tableau.zig");
const simplex = @import("simplex.zig");
const bb = @import("branch_bound.zig");
const Model = struct {
    name: []const u8, maximize: bool, names: []const []const u8, c: []r.Q, a: [][]r.Q, rhs: []r.Q, rows: []const []const u8, ops: []const []const u8,
    lower: []r.Bound, upper: []r.Bound, integer: []bool, log: usize, limit: usize,
    pub fn integerCount(self: Model) usize { var n: usize = 0; for (self.integer) |b| n += @intFromBool(b); return n; }
};
fn index(names: []const []const u8, name: []const u8) ?usize { for (names, 0..) |n, j| if (r.eq(n, name)) return j; return null; }
fn fail(source: *p.Model, line: usize, comptime message: []const u8, args: anytype) ?Model { source.error_line = line; source.message = r.fmt(message, args); return null; }
fn modelData(source: *p.Model) ?Model {
    var names: std.ArrayList([]const u8) = .empty;
    for (source.objective) |term| if (index(names.items, term.name) == null) r.add([]const u8, &names, term.name);
    for (source.rows.items) |row| for (row.terms) |term| { if (index(names.items, term.name) == null) r.add([]const u8, &names, term.name); };
    const n = names.items.len; const m = source.rows.items.len;
    const model = Model{ .name = source.name, .maximize = source.maximize, .names = names.items, .c = r.zero(n), .a = r.alloc([]r.Q, m), .rhs = r.zero(m), .rows = r.alloc([]const u8, m), .ops = r.alloc([]const u8, m), .lower = r.alloc(r.Bound, n), .upper = r.alloc(r.Bound, n), .integer = r.alloc(bool, n), .log = source.log, .limit = source.limit };
    @memset(model.lower, .{}); @memset(model.upper, .{ .infinity = 1 }); @memset(model.integer, false);
    for (source.objective) |term| { const j = index(model.names, term.name).?; model.c[j] = model.c[j].plus(term.coefficient); }
    for (source.rows.items, 0..) |row, i| { model.a[i] = r.zero(n); model.rows[i] = row.name; model.ops[i] = row.op; model.rhs[i] = row.rhs; for (row.terms) |term| { const j = index(model.names, term.name).?; model.a[i][j] = model.a[i][j].plus(term.coefficient); } }
    for (source.rows.items, 0..) |row, i| for (source.rows.items[0..i]) |old| { if (r.eq(old.name, row.name)) return fail(source, row.line, "duplicate constraint {s}", .{row.name}); };
    for (source.bounds.items) |record| {
        const w = record.words; const name = if (w.len == 5) w[2] else w[0]; const j = index(model.names, name) orelse return fail(source, record.line, "unknown variable {s}", .{name});
        if (w.len == 2) { model.lower[j] = .{ .infinity = -1 }; model.upper[j] = .{ .infinity = 1 }; }
        else if (w.len == 5) { model.lower[j] = r.bound(w[0]).?; model.upper[j] = r.bound(w[4]).?; }
        else { const b = r.bound(w[2]).?; if (r.eq(w[1], ">=") or r.eq(w[1], "=")) model.lower[j] = b; if (r.eq(w[1], "<=") or r.eq(w[1], "=")) model.upper[j] = b; }
        if (model.lower[j].cmp(model.upper[j]) == .gt) return fail(source, record.line, "inconsistent bounds {s}", .{name});
    }
    for (source.integers.items) |record| for (record.words) |name| {
        const j = index(model.names, name) orelse return fail(source, record.line, "unknown variable {s}", .{name}); model.integer[j] = true;
        if (model.lower[j].infinity == 0) model.lower[j].value = r.Q.int(model.lower[j].value.ceil());
        if (model.upper[j].infinity == 0) model.upper[j].value = r.Q.int(model.upper[j].value.floor());
        if (model.lower[j].cmp(model.upper[j]) == .gt) return fail(source, record.line, "inconsistent bounds {s}", .{name});
    };
    for (source.binaries.items) |record| for (record.words) |name| {
        const j = index(model.names, name) orelse return fail(source, record.line, "unknown variable {s}", .{name}); model.integer[j] = true; model.lower[j] = .{}; model.upper[j] = r.Bound.finite(r.Q.int(1));
    };
    return model;
}
const Mapping = struct { offset: r.Q, first: usize, second: ?usize = null, direction: r.Q, upper_row: ?usize = null };
const LP = struct {
    table: t.Tableau, map: []Mapping, sigma: []r.Q, initial: []usize, slack: []?usize, costs: []r.Q, phase_one: []r.Q, nonart: usize,
    offset: r.Q, sign: r.Q, x: []r.Q, objective: r.Q = .{}, w: r.Q = .{}, status: []const u8 = "OPTIMAL", unbounded: ?usize = null,
    phase1: usize = 0, phase2: usize = 0, drives: usize = 0, redundant: usize = 0,
    pub fn pivots(self: LP) usize { return self.phase1 + self.phase2 + self.drives; }
};
var total_solves: usize = 0; var total_phase1: usize = 0; var total_phase2: usize = 0; var total_drives: usize = 0;
fn solve(model: Model, lower: []const r.Bound, upper: []const r.Bound, node: usize, log: *r.Text) LP {
    const n = model.names.len; const m = model.rows.len;
    var columns: std.ArrayList([]const u8) = .empty; const map = r.alloc(Mapping, n); var constant: r.Q = .{};
    for (model.names, 0..) |name, j| {
        const k = columns.items.len;
        if (lower[j].infinity == 0) { map[j] = .{ .offset = lower[j].value, .first = k, .direction = r.Q.int(1) }; r.add([]const u8, &columns, name); }
        else if (upper[j].infinity == 0) { map[j] = .{ .offset = upper[j].value, .first = k, .direction = r.Q.int(-1) }; r.add([]const u8, &columns, r.fmt("{s}'", .{name})); }
        else { map[j] = .{ .offset = .{}, .first = k, .second = k + 1, .direction = r.Q.int(1) }; r.add([]const u8, &columns, r.fmt("{s}+", .{name})); r.add([]const u8, &columns, r.fmt("{s}-", .{name})); }
        constant = constant.plus(model.c[j].mul(map[j].offset));
    }
    var row_names: std.ArrayList([]const u8) = .empty; var ops: std.ArrayList([]const u8) = .empty; var beta: std.ArrayList(r.Q) = .empty;
    for (model.rows, 0..) |name, i| { r.add([]const u8, &row_names, name); r.add([]const u8, &ops, model.ops[i]); var b = model.rhs[i]; for (0..n) |j| b = b.minus(model.a[i][j].mul(map[j].offset)); r.add(r.Q, &beta, b); }
    for (0..n) |j| if (lower[j].infinity == 0 and upper[j].infinity == 0) { map[j].upper_row = row_names.items.len; r.add([]const u8, &row_names, r.fmt("{s}.ub", .{model.names[j]})); r.add([]const u8, &ops, "<="); r.add(r.Q, &beta, upper[j].value.minus(lower[j].value)); };
    const rows = row_names.items.len; const sigma = r.alloc(r.Q, rows); const slack = r.alloc(?usize, rows); const initial = r.alloc(usize, rows); @memset(slack, null);
    for (0..rows) |i| { sigma[i] = r.Q.int(if (beta.items[i].n < 0) -1 else 1); if (sigma[i].n < 0) { beta.items[i] = beta.items[i].neg(); ops.items[i] = if (r.eq(ops.items[i], "<=")) ">=" else if (r.eq(ops.items[i], ">=")) "<=" else "="; } }
    for (0..rows) |i| if (!r.eq(ops.items[i], "=")) { slack[i] = columns.items.len; if (r.eq(ops.items[i], "<=")) initial[i] = columns.items.len; r.add([]const u8, &columns, r.fmt("s:{s}", .{row_names.items[i]})); };
    const nonart = columns.items.len;
    for (0..rows) |i| if (!r.eq(ops.items[i], "<=")) { initial[i] = columns.items.len; r.add([]const u8, &columns, r.fmt("a:{s}", .{row_names.items[i]})); };
    const k = columns.items.len; const a = r.alloc([]r.Q, rows); for (a) |*row| row.* = r.zero(k);
    for (0..m) |i| for (0..n) |j| { a[i][map[j].first] = model.a[i][j].mul(map[j].direction).mul(sigma[i]); if (map[j].second) |s| a[i][s] = model.a[i][j].neg().mul(sigma[i]); };
    for (map) |mp| if (mp.upper_row) |i| { a[i][mp.first] = sigma[i]; };
    for (0..rows) |i| { if (slack[i]) |s| a[i][s] = r.Q.int(if (r.eq(ops.items[i], "<=")) 1 else -1); if (initial[i] >= nonart) a[i][initial[i]] = r.Q.int(1); }
    const sign = r.Q.int(if (model.maximize) -1 else 1); const costs = r.zero(k); const phase_one = r.zero(k);
    for (map, model.c) |mp, c| { costs[mp.first] = c.mul(mp.direction).mul(sign); if (mp.second) |s| costs[s] = c.neg().mul(sign); }
    for (nonart..k) |j| phase_one[j] = r.Q.int(1);
    var out = LP{ .table = .{ .a = a, .beta = beta.items, .basis = r.copy(usize, initial), .rows = row_names.items, .columns = columns.items }, .map = map, .sigma = sigma, .initial = initial, .slack = slack, .costs = costs, .phase_one = phase_one, .nonart = nonart, .offset = constant, .sign = sign, .x = r.zero(n) };
    log.line("SOLVE node {d} rows {d} columns {d} artificials {d}", .{node, rows, k, k - nonart});
    if (model.log >= 1) {
        for (map, 0..) |mp, j| { if (mp.second != null) log.line("MAP {s} split", .{model.names[j]}) else if (mp.direction.n < 0) log.line("MAP {s} reflect {s}", .{model.names[j], mp.offset.str()}) else { log.put("MAP {s} shift {s}", .{model.names[j], mp.offset.str()}); if (upper[j].infinity == 0) log.put(" upper {s}", .{upper[j].str()}); log.put("\n", .{}); } }
        for (sigma, row_names.items) |s, name| if (s.n < 0) log.line("FLIP {s}", .{name});
    }
    if (k > nonart) {
        if (model.log >= 1) log.line("PHASE 1", .{}); if (model.log >= 2) out.table.display(log, "phase 1 start", phase_one, .{}, r.Q.int(1));
        out.phase1 = simplex.phase(&out.table, phase_one, k, log, model.log, .{}, r.Q.int(1)).iterations; out.w = out.table.value(phase_one);
        if (model.log >= 1) log.line("PHASE 1 END objective {s} iterations {d}", .{out.w.str(), out.phase1});
        if (out.w.n > 0) out.status = "INFEASIBLE" else for (0..rows) |i| if (out.table.basis[i] >= nonart) {
            var enter: ?usize = null; for (0..nonart) |j| if (out.table.a[i][j].n != 0) { enter = j; break; };
            if (enter) |q| { if (model.log >= 1) log.line("DRIVE row {s} enter {s} leave {s}", .{row_names.items[i], columns.items[q], columns.items[out.table.basis[i]]}); out.table.pivot(i, q); out.drives += 1; }
            else { out.redundant += 1; if (model.log >= 1) log.line("REDUNDANT row {s}", .{row_names.items[i]}); }
        };
    }
    if (!r.eq(out.status, "INFEASIBLE")) {
        if (model.log >= 1) log.line("PHASE 2", .{}); if (model.log >= 2) out.table.display(log, "phase 2 start", costs, constant, sign);
        const result = simplex.phase(&out.table, costs, nonart, log, model.log, constant, sign); out.phase2 = result.iterations; out.unbounded = result.unbounded;
        if (result.unbounded) |q| { out.status = "UNBOUNDED"; if (model.log >= 1) log.line("UNBOUNDED enter {s}", .{columns.items[q]}); }
        out.objective = constant.plus(sign.mul(out.table.value(costs)));
        if (model.log >= 1) log.line("PHASE 2 END objective {s} iterations {d}", .{out.objective.str(), out.phase2});
    }
    if (model.log >= 2) out.table.display(log, "final", if (r.eq(out.status, "INFEASIBLE")) phase_one else costs, if (r.eq(out.status, "INFEASIBLE")) .{} else constant, if (r.eq(out.status, "INFEASIBLE")) r.Q.int(1) else sign);
    const values = out.table.solution(); for (map, 0..) |mp, j| { out.x[j] = mp.offset.plus(mp.direction.mul(values[mp.first])); if (mp.second) |s| out.x[j] = out.x[j].minus(values[s]); }
    log.line("RESULT {s} objective {s} phase1 {d} phase2 {d} drives {d} redundant {d}", .{out.status, if (r.eq(out.status, "OPTIMAL")) out.objective.str() else "-", out.phase1, out.phase2, out.drives, out.redundant});
    total_solves += 1; total_phase1 += out.phase1; total_phase2 += out.phase2; total_drives += out.drives; return out;
}
fn extremes(values: []const r.Q) []const u8 { var lo: ?r.Q = null; var hi: ?r.Q = null; for (values) |q| if (q.n != 0) { const v = if (q.n < 0) q.neg() else q; if (lo == null or v.cmp(lo.?) == .lt) lo = v; if (hi == null or v.cmp(hi.?) == .gt) hi = v; }; return if (lo) |v| r.fmt("{s} {s}", .{v.str(), hi.?.str()}) else "- -"; }
fn statistics(model: Model, text: *r.Text) void {
    var matrix: std.ArrayList(r.Q) = .empty; var bounds: std.ArrayList(r.Q) = .empty; var count: usize = 0;
    for (model.a) |row| for (row) |q| { r.add(r.Q, &matrix, q); count += @intFromBool(q.n != 0); };
    for (model.lower, model.upper) |lo, hi| { if (lo.infinity == 0) r.add(r.Q, &bounds, lo.value); if (hi.infinity == 0) r.add(r.Q, &bounds, hi.value); }
    text.line("STATS nonzeros {d} matrix {s} objective {s} rhs {s} bounds {s}", .{count, extremes(matrix.items), extremes(model.c), extremes(model.rhs), extremes(bounds.items)});
}
fn limitRange(lo: *r.Bound, hi: *r.Bound, numerator: r.Q, denominator: r.Q) void {
    if (denominator.n == 0) return; const b = r.Bound.finite(numerator.neg().div(denominator));
    if (denominator.n > 0 and b.cmp(lo.*) == .gt) lo.* = b;
    if (denominator.n < 0 and b.cmp(hi.*) == .lt) hi.* = b;
}
fn sensitivity(model: Model, lp: LP, text: *r.Text) void {
    const table = lp.table; const reduced = table.reduced(lp.costs); const prices = r.zero(model.rows.len); const rc = r.copy(r.Q, model.c);
    for (prices, 0..) |*q, i| q.* = lp.sign.neg().mul(lp.sigma[i]).mul(reduced[lp.initial[i]]);
    for (rc, 0..) |*q, j| for (prices, 0..) |y, i| { q.* = q.minus(y.mul(model.a[i][j])); };
    var primal: usize = 0; var dual: usize = 0;
    for (table.basis, table.beta) |b, v| if (b < lp.nonart and v.n == 0) { primal += 1; };
    for (0..lp.nonart) |k| if (!table.basic(k) and reduced[k].n == 0) { dual += 1; };
    var objective: r.Q = .{}; for (prices, model.rhs) |y, b| objective = objective.plus(y.mul(b)); for (rc, lp.x) |c, x| objective = objective.plus(c.mul(x));
    text.line("MODEL {s} {s} objective {s}", .{model.name, if (model.integerCount() > 0) "relaxation" else "lp", lp.objective.str()}); text.put("BASIS", .{}); for (table.basis) |b| text.put(" {s}", .{table.columns[b]}); text.put("\n", .{});
    text.line("DEGENERACY primal {d} dual {d}", .{primal, dual}); text.line("DUAL objective {s}", .{objective.str()});
    for (model.rows, 0..) |name, i| {
        var lo = r.Bound{ .infinity = -1 }; var hi = r.Bound{ .infinity = 1 }; var fixed = false;
        for (table.a, table.basis, table.beta) |row, b, beta| { const rho = lp.sigma[i].mul(row[lp.initial[i]]); if (rho.n != 0 and b >= lp.nonart) fixed = true; limitRange(&lo, &hi, beta, rho); }
        if (fixed) { lo = .{}; hi = .{}; }
        text.line("CONSTRAINT {s} price {s} rhs {s} range {s} {s}", .{name, prices[i].str(), model.rhs[i].str(), lo.shift(model.rhs[i]).str(), hi.shift(model.rhs[i]).str()});
    }
    for (model.names, lp.map, 0..) |name, mp, j| {
        const h = r.zero(table.columns.len); h[mp.first] = lp.sign.mul(mp.direction); if (mp.second) |s| h[s] = lp.sign.neg(); const eta = table.reduced(h);
        var lo = r.Bound{ .infinity = -1 }; var hi = r.Bound{ .infinity = 1 };
        for (0..lp.nonart) |k| if (!table.basic(k)) limitRange(&lo, &hi, reduced[k], eta[k]);
        var status: []const u8 = "basic";
        if (mp.second) |s| { if (!table.basic(mp.first) and !table.basic(s)) status = "zero"; }
        else if (!table.basic(mp.first)) status = if (mp.direction.n < 0) "upper" else "lower"
        else if (mp.upper_row) |i| { if (!table.basic(lp.slack[i].?)) status = "upper"; };
        text.line("VARIABLE {s} {s} value {s} reduced {s} cost {s} range {s} {s}", .{name, status, lp.x[j].str(), rc[j].str(), model.c[j].str(), lo.shift(model.c[j]).str(), hi.shift(model.c[j]).str()});
    }
}
pub fn main(init: std.process.Init) !void {
    var arena: std.heap.ArenaAllocator = .init(init.gpa); defer arena.deinit(); r.allocator = arena.allocator();
    const items = p.models(try r.read(init.io, "input/models.lp")); p.settings(try r.read(init.io, "input/params.txt"), items);
    var iterations: r.Text = .{}; var solutions: r.Text = .{}; var ranges: r.Text = .{}; var tree: r.Text = .{}; var csv: r.Text = .{};
    csv.line("model,status,objective,approx,relaxation,nodes,pivots", .{});
    var statuses = [_]usize{0} ** 5; var analyzed: usize = 0; var integers: usize = 0; var bnodes: usize = 0; var limited: usize = 0;
    for (items) |*source| {
        const data = if (source.error_line == 0) modelData(source) else null;
        const model = data orelse { statuses[4] += 1; iterations.line("MODEL {s} error", .{source.name}); solutions.line("MODEL {s}", .{source.name}); solutions.line("STATUS ERROR line {d} {s}", .{source.error_line, source.message}); ranges.line("MODEL {s} skipped ERROR", .{source.name}); csv.line("{s},ERROR,-,-,-,0,0", .{source.name}); continue; };
        iterations.line("MODEL {s} level {d}", .{model.name, model.log});
        var root: LP = undefined; var incumbent: ?LP = null; var status: []const u8 = undefined; var nodes: usize = 1; var pivots: usize = 0;
        if (model.integerCount() > 0) { const result = bb.run(LP, model, solve, &iterations, &tree); root = result.root.?; incumbent = result.incumbent; status = result.status; nodes = result.nodes; pivots = result.pivots; integers += 1; bnodes += nodes; limited += @intFromBool(r.eq(status, "NODE_LIMIT")); }
        else { root = solve(model, model.lower, model.upper, 1, &iterations); status = root.status; pivots = root.pivots(); if (r.eq(status, "OPTIMAL")) incumbent = root; }
        const statuses_names = [_][]const u8{ "OPTIMAL", "INFEASIBLE", "UNBOUNDED", "NODE_LIMIT" }; for (statuses_names, 0..) |s, i| if (r.eq(status, s)) { statuses[i] += 1; };
        solutions.line("MODEL {s} {s} variables {d} constraints {d} integers {d}", .{model.name, if (model.maximize) "maximize" else "minimize", model.names.len, model.rows.len, model.integerCount()}); statistics(model, &solutions); solutions.line("STATUS {s}", .{status});
        if (incumbent) |lp| solutions.line("OBJECTIVE {s} approx {s}", .{lp.objective.str(), lp.objective.approx()});
        if (model.integerCount() > 0 and r.eq(root.status, "OPTIMAL")) solutions.line("RELAXATION {s} approx {s}", .{root.objective.str(), root.objective.approx()});
        if (r.eq(root.status, "INFEASIBLE")) { solutions.line("INFEASIBILITY {s}", .{root.w.str()}); const reduced = root.table.reduced(root.phase_one); for (root.table.rows, 0..) |name, i| solutions.line("FARKAS {s} {s}", .{name, root.sigma[i].mul(root.phase_one[root.initial[i]].minus(reduced[root.initial[i]])).str()}); }
        if (incumbent != null or r.eq(status, "UNBOUNDED")) { const x = if (incumbent) |lp| lp.x else root.x; for (model.names, x) |name, value| solutions.line("VALUE {s} {s}", .{name, value.str()}); }
        if (r.eq(status, "UNBOUNDED")) { const ray = r.zero(root.table.columns.len); const q = root.unbounded.?; ray[q] = r.Q.int(1); for (root.table.basis, root.table.a) |b, row| ray[b] = row[q].neg(); var rate: r.Q = .{}; for (model.names, root.map, 0..) |name, mp, j| { var d = ray[mp.first].mul(mp.direction); if (mp.second) |s| d = d.minus(ray[s]); solutions.line("RAY {s} {s}", .{name, d.str()}); rate = rate.plus(d.mul(model.c[j])); } solutions.line("RATE {s}", .{rate.str()}); }
        if (incumbent) |lp| for (model.rows, 0..) |name, i| { var value: r.Q = .{}; for (model.a[i], lp.x) |a, x| value = value.plus(a.mul(x)); const margin = if (r.eq(model.ops[i], "<=")) model.rhs[i].minus(value) else value.minus(model.rhs[i]); solutions.line("ROW {s} {s} {s}", .{name, value.str(), margin.str()}); };
        if (model.integerCount() > 0) solutions.line("NODES {d}", .{nodes}); solutions.line("PIVOTS {d}", .{pivots});
        if (r.eq(root.status, "OPTIMAL")) { analyzed += 1; sensitivity(model, root, &ranges); } else ranges.line("MODEL {s} skipped {s}", .{model.name, root.status});
        csv.line("{s},{s},{s},{s},{s},{d},{d}", .{model.name, status, if (incumbent) |lp| lp.objective.str() else "-", if (incumbent) |lp| lp.objective.approx() else "-", if (r.eq(root.status, "OPTIMAL")) root.objective.str() else "-", nodes, pivots});
    }
    iterations.line("TOTAL solves {d} phase1 {d} phase2 {d} drives {d} pivots {d}", .{total_solves, total_phase1, total_phase2, total_drives, total_phase1 + total_phase2 + total_drives});
    solutions.line("SUMMARY models {d} optimal {d} infeasible {d} unbounded {d} node_limit {d} error {d}", .{items.len, statuses[0], statuses[1], statuses[2], statuses[3], statuses[4]}); ranges.line("SUMMARY analyzed {d} skipped {d}", .{analyzed, items.len - analyzed}); tree.line("SUMMARY models {d} nodes {d} node_limit {d}", .{integers, bnodes, limited});
    try r.write(init.io, "iterations.txt", iterations); try r.write(init.io, "solutions.txt", solutions); try r.write(init.io, "sensitivity.txt", ranges); try r.write(init.io, "bnb_tree.txt", tree); try r.write(init.io, "summary.csv", csv);
}
