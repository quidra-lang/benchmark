const std = @import("std");
const c = @import("dataset.zig");
const m = @import("matrix.zig");
const eigen_module = @import("eigen.zig");
const pca = @import("pca.zig");
const plot = @import("plot.zig");
fn real(value: f64) []const u8 {
    return c.fmt("{d:.4}", .{if (@abs(value) < 0.00005) @as(f64, 0) else value});
}
fn real6(value: f64) []const u8 {
    return c.fmt("{d:.6}", .{if (@abs(value) < 0.0000005) @as(f64, 0) else value});
}
fn sum(values: []const f64) f64 {
    var out: f64 = 0;
    for (values) |value| out += value;
    return out;
}
fn descending(values: []const f64, a: usize, b: usize) bool {
    return if (values[a] != values[b]) values[a] > values[b] else a < b;
}
fn decreasing(values: []const f64) []usize {
    const out = c.alloc(usize, values.len);
    for (out, 0..) |*value, i| value.* = i;
    std.mem.sort(usize, out, values, descending);
    return out;
}
const Summary = struct { observed: usize = 0, mean: f64 = 0, sd: f64 = 0, minimum: f64 = 0, maximum: f64 = 0, msa: f64 = 0 };
const Analysis = struct { rows: []const c.Sample, values: c.Matrix, cov: c.Matrix, cor: c.Matrix,
     matrix: c.Matrix, z: c.Matrix, mean: c.Vector, sd: c.Vector, scale: c.Vector, eigen: eigen_module.Eigen };
fn analyze(input: c.Input, observed_means: []const f64, missing: []const u8, scaling: []const u8) Analysis {
    var rows: std.ArrayList(c.Sample) = .empty;
    var values: std.ArrayList(c.Vector) = .empty;
    for (input.data) |record| {
        var complete = true;
        for (record.values) |value| if (value == null) {
            complete = false;
        };
        if (c.eq(missing, "listwise") and !complete) continue;
        const cells = c.alloc(?f64, record.values.len);
        const numbers = c.vector(cells.len);
        for (record.values, 0..) |value, j| {
            numbers[j] = value orelse observed_means[j];
            cells[j] = numbers[j];
        }
        c.append(c.Sample, &rows, .{ .id = record.id, .values = cells });
        c.append(c.Vector, &values, numbers);
    }
    const mean = pca.means(values.items);
    const cov = pca.covariance(values.items, mean);
    const sd = c.vector(mean.len);
    const scale = c.vector(mean.len);
    for (0..mean.len) |j| {
        sd[j] = @sqrt(cov[j][j]);
        scale[j] = if (c.eq(scaling, "covariance")) 1 else sd[j];
    }
    const cor = pca.correlation(cov, sd);
    const matrix = if (c.eq(scaling, "covariance")) cov else cor;
    const z = c.alloc(c.Vector, rows.items.len);
    for (rows.items, z) |record, *standardized| standardized.* = pca.standardize(record, mean, scale);
    return .{ .rows = rows.items, .values = values.items, .cov = cov, .cor = cor, .matrix = matrix,
         .z = z, .mean = mean, .sd = sd, .scale = scale, .eigen = eigen_module.jacobi(matrix) };
}
fn flag(t2: f64, spe: f64, p: c.Params) []const u8 {
    return if (t2 > p.t2) (if (spe > p.spe) "TQ" else "T") else if (spe > p.spe) "Q" else "-";
}
const Diagnostic = struct { z: c.Vector, score: c.Vector, residual: c.Vector, tcontribution: c.Vector,
     qcontribution: c.Vector, t2: f64, spe: f64, quality: f64, flag_: []const u8 };
fn diagnose(z: c.Vector, eigen: eigen_module.Eigen, count: usize, p: c.Params) Diagnostic {
    const score = pca.scores(z, eigen.vectors);
    const residual = pca.residuals(z, score, eigen.vectors, count);
    const t2 = pca.hotelling(score, eigen.values, count);
    const spe = m.dot(residual, residual);
    var represented: f64 = 0;
    for (score[0..count]) |value| represented += value * value;
    const tc = c.vector(z.len);
    const qc = c.vector(z.len);
    for (z, 0..) |value, j| {
        var weight: f64 = 0;
        for (0..count) |k| weight += (score[k] / eigen.values[k]) * eigen.vectors[k][j];
        tc[j] = value * weight;
        qc[j] = residual[j] * residual[j];
    }
    return .{ .z = z, .score = score, .residual = residual, .tcontribution = tc, .qcontribution = qc,
         .t2 = t2, .spe = spe, .quality = represented / m.dot(z, z), .flag_ = flag(t2, spe, p) };
}
fn criterion(g: c.Matrix) f64 {
    var out: f64 = 0;
    for (0..g[0].len) |k| {
        var q2: f64 = 0;
        var q4: f64 = 0;
        for (g) |row| {
            q2 += row[k] * row[k];
            q4 += (row[k] * row[k]) * (row[k] * row[k]);
        }
        out += q4 / c.f(g.len) - (q2 / c.f(g.len)) * (q2 / c.f(g.len));
    }
    return out;
}
const Pair = struct { a: usize, b: usize, magnitude: f64 };
fn pairLess(_: void, a: Pair, b: Pair) bool {
    return if (a.magnitude != b.magnitude) a.magnitude > b.magnitude else if (a.a != b.a) a.a < b.a else a.b < b.b;
}
fn inside(r: i64, column: i64, rc: i64, cc: i64, rho: i64) bool {
    return (column - cc) * (column - cc) + (2 * (r - rc)) * (2 * (r - rc)) <= rho * rho;
}
fn plots(input: c.Input, a: Analysis, loadings: c.Matrix, broken: []const f64, total: f64, average: f64,
     diagnostics: []const Diagnostic, supplementary: []const Diagnostic) c.Lines {
    const p = input.params;
    const eigen = a.eigen;
    var out: c.Lines = .{};
    const kc: usize = @intFromFloat(@floor(average / eigen.values[0] * c.f(p.scree) + 0.5));
    out.add("scree width {d} kaiser_column {d}", .{ p.scree, kc });
    for (eigen.values, 0..) |value, k| {
        const length: usize = @intFromFloat(@floor(value / eigen.values[0] * c.f(p.scree) + 0.5));
        const position: usize = @intFromFloat(@floor(broken[k] * total / eigen.values[0] * c.f(p.scree) + 0.5));
        out.add("{s} pc{d} {s}", .{ plot.screeLine(length, kc, position, p.scree), k + 1, real(value) });
    }
    var m1: f64 = 0;
    var m2: f64 = 0;
    var l1: f64 = 0;
    var l2: f64 = 0;
    for ([_][]const Diagnostic{ diagnostics, supplementary }) |items| for (items) |item| {
        m1 = @max(m1, @abs(item.score[0]));
        m2 = @max(m2, @abs(item.score[1]));
    };
    for (loadings) |row| {
        l1 = @max(l1, @abs(row[0]));
        l2 = @max(l2, @abs(row[1]));
    }
    const scale = 0.9 * @min(m1 / l1, m2 / l2);
    const biplot = plot.grid(p.bh, p.bw);
    const origin = plot.biplotCell(0, 0, m1, m2, p.bw, p.bh);
    @memset(biplot[origin.row], '-');
    for (biplot) |row| row[origin.column] = '|';
    biplot[origin.row][origin.column] = '+';
    const tips = c.alloc(plot.Cell, input.names.len);
    for (loadings, 0..) |row, j| {
        tips[j] = plot.biplotCell(scale * row[0], scale * row[1], m1, m2, p.bw, p.bh);
        plot.shaftCells(biplot, origin, tips[j]);
    }
    const counts = c.alloc([]usize, p.bh);
    for (counts) |*row| {
        row.* = c.alloc(usize, p.bw);
        @memset(row.*, 0);
    }
    for (diagnostics) |item| {
        const cell = plot.biplotCell(item.score[0], item.score[1], m1, m2, p.bw, p.bh);
        counts[cell.row][cell.column] += 1;
    }
    for (counts, 0..) |row, r| for (row, 0..) |count, column| {
        if (count > 0) biplot[r][column] = if (count == 1) '.' else if (count <= 3) 'o' else '@';
    };
    for (diagnostics) |item| if (!c.eq(item.flag_, "-")) {
        const cell = plot.biplotCell(item.score[0], item.score[1], m1, m2, p.bw, p.bh);
        biplot[cell.row][cell.column] = 'X';
    };
    for (supplementary) |item| {
        const cell = plot.biplotCell(item.score[0], item.score[1], m1, m2, p.bw, p.bh);
        biplot[cell.row][cell.column] = '*';
    }
    for (tips, 0..) |tip, j| biplot[tip.row][tip.column] = @as(u8, @intCast('A' + j));
    out.add("", .{});
    out.add("biplot pc1 pc2 width {d} height {d}", .{ p.bw, p.bh });
    out.add("x {s} {s} y {s} {s} arrow_scale {s}", .{ real(-m1), real(m1), real(-m2), real(m2), real(scale) });
    out.extend(plot.framed(biplot));
    for (input.names, loadings, 0..) |name, row, j| out.add("{c} {s} {s} {s}", .{ @as(u8, @intCast('A' + j)),
         name, real(row[0]), real(row[1]) });
    const rho = c.n(p.radius);
    const rc = @divFloor(rho, 2) + 1;
    const cc = rho + 1;
    const circle = plot.grid(p.radius + 3, 2 * p.radius + 3);
    @memset(circle[c.u(rc)], '-');
    for (circle) |row| row[c.u(cc)] = '|';
    circle[c.u(rc)][c.u(cc)] = '+';
    for (circle, 0..) |row, r| for (row, 0..) |*value, column| {
        if (inside(c.n(r), c.n(column), rc, cc, rho) and (!inside(c.n(r) - 1, c.n(column), rc, cc,
             rho) or !inside(c.n(r) + 1, c.n(column), rc, cc, rho) or !inside(c.n(r), c.n(column) - 1,
             rc, cc, rho) or !inside(c.n(r), c.n(column) + 1, rc, cc, rho))) value.* = '.';
    };
    for (loadings, 0..) |row, j| {
        const cell = plot.circleCell(row[0] / @sqrt(a.matrix[j][j]), row[1] / @sqrt(a.matrix[j][j]), p.radius);
        circle[cell.row][cell.column] = @intCast('A' + j);
    }
    out.add("", .{});
    out.add("circle radius {d}", .{p.radius});
    out.extend(plot.framed(circle));
    for (input.names, loadings, 0..) |name, row, j| {
        const q1 = row[0] / @sqrt(a.matrix[j][j]);
        const q2 = row[1] / @sqrt(a.matrix[j][j]);
        out.add("{c} {s} {s} {s} {s}", .{ @as(u8, @intCast('A' + j)), name, real(q1), real(q2), real(q1 * q1 + q2 * q2) });
    }
    const diagnostic_plot = plot.grid(p.dh, p.dw);
    const limit = plot.diagnosticCell(p.t2, p.spe, 2 * p.t2, 2 * p.spe, p.dw, p.dh);
    @memset(diagnostic_plot[limit.row], '-');
    for (diagnostic_plot) |row| row[limit.column] = '|';
    diagnostic_plot[limit.row][limit.column] = '+';
    const diagnostic_counts = c.alloc([]usize, p.dh);
    for (diagnostic_counts) |*row| {
        row.* = c.alloc(usize, p.dw);
        @memset(row.*, 0);
    }
    for (diagnostics) |item| {
        const cell = plot.diagnosticCell(item.t2, item.spe, 2 * p.t2, 2 * p.spe, p.dw, p.dh);
        diagnostic_counts[cell.row][cell.column] += 1;
    }
    for (diagnostic_counts, 0..) |row, r| for (row, 0..) |count, column| {
        if (count > 0) diagnostic_plot[r][column] = if (count == 1) '.' else if (count <= 3) 'o' else '@';
    };
    for (supplementary) |item| {
        const cell = plot.diagnosticCell(item.t2, item.spe, 2 * p.t2, 2 * p.spe, p.dw, p.dh);
        diagnostic_plot[cell.row][cell.column] = '*';
    }
    out.add("", .{});
    out.add("diagnostic width {d} height {d} t2_max {s} spe_max {s}", .{ p.dw, p.dh, real(2 * p.t2), real(2 * p.spe) });
    out.extend(plot.framed(diagnostic_plot));
    return out;
}
fn write(io: std.Io, name: []const u8, lines: c.Lines) !void {
    var text: c.Text = .{};
    for (lines.data.items) |line| text.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = c.fmt("output/{s}", .{name}), .data = text.value() });
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    c.allocator = arena.allocator();
    try std.Io.Dir.cwd().createDirPath(init.io, "output");
    const input = try c.readInput(init.io);
    const p = input.params;
    const variables = input.names.len;
    const summary = c.alloc(Summary, variables);
    @memset(summary, .{});
    const observed_means = c.vector(variables);
    var incomplete: std.ArrayList([]const u8) = .empty;
    for (input.data) |record| {
        var missing = false;
        for (record.values) |value| if (value == null) {
            missing = true;
        };
        if (missing) c.append([]const u8, &incomplete, record.id);
    }
    for (summary, 0..) |*item, j| {
        var observed: std.ArrayList(f64) = .empty;
        for (input.data) |record| if (record.values[j]) |value| c.append(f64, &observed, value);
        item.observed = observed.items.len;
        item.mean = sum(observed.items) / c.f(item.observed);
        observed_means[j] = item.mean;
        item.minimum = observed.items[0];
        item.maximum = item.minimum;
        var squares: f64 = 0;
        for (observed.items) |value| {
            squares += (value - item.mean) * (value - item.mean);
            item.minimum = @min(item.minimum, value);
            item.maximum = @max(item.maximum, value);
        }
        item.sd = @sqrt(squares / c.f(item.observed - 1));
    }
    const a = analyze(input, observed_means, p.missing, p.scaling);
    const eigen = a.eigen;
    const n = a.rows.len;
    const total = sum(eigen.values);
    const average = total / c.f(variables);
    const ratio = c.vector(variables);
    const cumulative = c.vector(variables);
    const broken = c.vector(variables);
    const parallel = c.vector(variables);
    const errors = c.vector(variables);
    var kaiser: usize = 0;
    var broken_count = variables;
    var parallel_count = variables;
    var cumulative_count = variables;
    for (0..variables) |k| {
        ratio[k] = eigen.values[k] / total;
        cumulative[k] = (if (k > 0) cumulative[k - 1] else 0) + ratio[k];
        for (k + 1..variables + 1) |i| broken[k] += 1 / c.f(i);
        broken[k] /= c.f(variables);
        errors[k] = eigen.values[k] * @sqrt(2 / c.f(n));
        kaiser += @intFromBool(eigen.values[k] > average);
    }
    var state = p.seed;
    for (0..p.repetitions) |_| {
        const random = c.matrix(n, variables);
        for (random) |row| for (row) |*value| {
            state = @mod(48271 * state, 2147483647);
            value.* = c.f(state) / 2147483647;
        };
        const cov = pca.covariance(random, pca.means(random));
        const sd = c.vector(variables);
        for (0..variables) |j| sd[j] = @sqrt(cov[j][j]);
        const result = eigen_module.jacobi(pca.correlation(cov, sd));
        const variance = sum(result.values);
        for (0..variables) |k| parallel[k] += result.values[k] / variance;
    }
    for (0..variables) |k| {
        parallel[k] /= c.f(p.repetitions);
        if (broken_count == variables and ratio[k] <= broken[k]) broken_count = k;
        if (parallel_count == variables and ratio[k] <= parallel[k]) parallel_count = k;
        if (cumulative_count == variables and cumulative[k] >= p.cumulative) cumulative_count = k + 1;
    }
    const retained = @max(@as(usize, 1), if (c.eq(p.components, "kaiser")) kaiser else if (c.eq(p.components,
         "broken_stick")) broken_count else if (c.eq(p.components, "parallel")) parallel_count else if (c.eq(p.components,
         "cumulative")) cumulative_count else c.u(c.number(p.components)));
    const inverse = m.inverseDeterminant(a.cor);
    var rr_total: f64 = 0;
    var pp_total: f64 = 0;
    for (0..variables) |j| {
        var rr: f64 = 0;
        var pp: f64 = 0;
        for (0..variables) |k| if (j != k) {
            const partial = -inverse.inverse[j][k] / @sqrt(inverse.inverse[j][j] * inverse.inverse[k][k]);
            rr += a.cor[j][k] * a.cor[j][k];
            pp += partial * partial;
        };
        summary[j].msa = rr / (rr + pp);
        rr_total += rr;
        pp_total += pp;
    }
    const kmo = rr_total / (rr_total + pp_total);
    const bartlett = -(c.f(n) - 1 - (2 * c.f(variables) + 5) / 6) * @log(inverse.determinant);
    const loadings = c.matrix(variables, variables);
    const communality = c.vector(variables);
    for (0..variables) |j| {
        for (0..variables) |k| loadings[j][k] = eigen.vectors[k][j] * @sqrt(eigen.values[k]);
        for (0..retained) |k| communality[j] += loadings[j][k] * loadings[j][k];
        communality[j] /= a.matrix[j][j];
    }
    const g = c.matrix(variables, retained);
    const eta = c.vector(variables);
    for (0..variables) |j| {
        for (0..retained) |k| eta[j] += loadings[j][k] * loadings[j][k];
        eta[j] = @sqrt(eta[j]);
        for (0..retained) |k| g[j][k] = loadings[j][k] / eta[j];
    }
    const criteria = c.vector(p.cycles + 1);
    criteria[0] = criterion(g);
    for (0..p.cycles) |cycle| {
        for (0..retained - 1) |left| for (left + 1..retained) |right| {
            var sa: f64 = 0;
            var sb: f64 = 0;
            var sc: f64 = 0;
            var sd: f64 = 0;
            for (g) |row| {
                const phi = row[left] * row[left] - row[right] * row[right];
                const psi = 2 * row[left] * row[right];
                sa += phi;
                sb += psi;
                sc += phi * phi - psi * psi;
                sd += 2 * phi * psi;
            }
            const numerator = sd - 2 * sa * sb / c.f(variables);
            const denominator = sc - (sa * sa - sb * sb) / c.f(variables);
            const omega = @sqrt(numerator * numerator + denominator * denominator);
            if (omega == 0) continue;
            const cos4 = denominator / omega;
            const sin4 = numerator / omega;
            const cos2 = @sqrt((1 + cos4) / 2);
            const sin2 = if (cos2 == 0) @as(f64, 1) else sin4 / (2 * cos2);
            const cos1 = @sqrt((1 + cos2) / 2);
            const sin1 = sin2 / (2 * cos1);
            for (g) |row| {
                const x = row[left];
                const y = row[right];
                row[left] = cos1 * x + sin1 * y;
                row[right] = -sin1 * x + cos1 * y;
            }
        };
        criteria[cycle + 1] = criterion(g);
    }
    const rotated = c.matrix(retained, variables);
    const rotated_ss = c.vector(retained);
    for (0..retained) |k| {
        for (0..variables) |j| rotated[k][j] = g[j][k] * eta[j];
        _ = m.orient(rotated[k]);
        rotated_ss[k] = m.dot(rotated[k], rotated[k]);
    }
    const rotated_order = decreasing(rotated_ss);
    const diagnostics = c.alloc(Diagnostic, n);
    const supplementary = c.alloc(Diagnostic, input.supplementary.len);
    for (a.z, diagnostics) |z, *item| item.* = diagnose(z, eigen, retained, p);
    for (input.supplementary, supplementary) |record, *item| item.* = diagnose(pca.standardize(record,
         a.mean, a.scale), eigen, retained, p);
    const power = eigen_module.powerIteration(a.matrix, eigen.vectors);
    var out: c.Lines = .{};
    out.add("pca rows {d} used {d} variables {d} missing {s} scaling {s}", .{ input.data.len, n, variables,
         p.missing, p.scaling });
    var line: c.Text = .{};
    line.add("incomplete {d}", .{incomplete.items.len});
    if (incomplete.items.len == 0) line.add(" -", .{});
    for (incomplete.items) |id| line.add(" {s}", .{id});
    out.add("{s}", .{line.value()});
    out.add("", .{});
    out.add("variable observed missing mean sd min max msa", .{});
    for (input.names, summary) |name, item| out.add("{s} {d} {d} {s} {s} {s} {s} {s}", .{ name, item.observed,
         input.data.len - item.observed, real(item.mean), real(item.sd), real(item.minimum), real(item.maximum),
         real(item.msa) });
    out.add("adequacy kmo {s} determinant {s} bartlett {s} df {d}", .{ real(kmo), real6(inverse.determinant),
         real(bartlett), variables * (variables - 1) / 2 });
    out.add("", .{});
    out.add("matrix {s}", .{p.scaling});
    for (input.names, a.matrix) |name, row| {
        line = .{};
        line.add("{s}", .{name});
        for (row) |value| line.add(" {s}", .{real(value)});
        out.add("{s}", .{line.value()});
    }
    var pairs: std.ArrayList(Pair) = .empty;
    for (0..variables - 1) |j| for (j + 1..variables) |k| {
        c.append(Pair, &pairs, .{ .a = j, .b = k, .magnitude = @abs(a.cor[j][k]) });
    };
    std.mem.sort(Pair, pairs.items, {}, pairLess);
    line = .{};
    line.add("strongest", .{});
    for (pairs.items[0..@min(p.top, pairs.items.len)]) |pair| line.add(" {s}:{s}:{s}", .{ input.names[pair.a],
         input.names[pair.b], real(a.cor[pair.a][pair.b]) });
    out.add("{s}", .{line.value()});
    out.add("", .{});
    out.add("jacobi sweeps {d}", .{eigen.sweeps});
    out.add("eigenvalues total {s} average {s}", .{ real(total), real(average) });
    out.add("k eigenvalue ratio cumulative broken_stick parallel se separated", .{});
    for (0..variables) |k| {
        const separated = (k == 0 or @abs(eigen.values[k] - eigen.values[k - 1]) > errors[k]) and (k + 1 == variables or @abs(eigen.values[k] - eigen.values[k + 1]) > errors[k]);
        out.add("{d} {s} {s} {s} {s} {s} {s} {s}", .{ k + 1, real(eigen.values[k]), real(ratio[k]),
             real(cumulative[k]), real(broken[k]), real(parallel[k]), real(errors[k]), if (separated) "yes" else "no" });
    }
    out.add("retention kaiser {d} broken_stick {d} parallel {d} cumulative {d} target {s}", .{ kaiser,
         broken_count, parallel_count, cumulative_count, real(p.cumulative) });
    out.add("components {d} rule {s}", .{ retained, p.components });
    out.add("", .{});
    out.add("eigenvectors", .{});
    line = .{};
    line.add("variable", .{});
    for (1..variables + 1) |k| line.add(" pc{d}", .{k});
    out.add("{s}", .{line.value()});
    for (input.names, 0..) |name, j| {
        line = .{};
        line.add("{s}", .{name});
        for (eigen.vectors) |values| line.add(" {s}", .{real(values[j])});
        out.add("{s}", .{line.value()});
    }
    out.add("", .{});
    out.add("power_iteration iterations 1000", .{});
    out.add("k jacobi power agree_at match", .{});
    var matches: usize = 0;
    for (power, 0..) |item, k| {
        const match = @abs(item.value - eigen.values[k]) <= 1e-8 * eigen.values[0] and m.difference(item.vector,
             eigen.vectors[k]) <= 0.000001;
        matches += @intFromBool(match);
        out.add("{d} {s} {s} {s} {s}", .{ k + 1, real(eigen.values[k]), real(item.value), if (item.agreement) |step| c.fmt("{d}",
             .{step}) else "-", if (match) "yes" else "no" });
    }
    out.add("cross_check {d}/{d}", .{ matches, variables });
    out.add("", .{});
    out.add("scores", .{});
    out.add("component sd min min_id max max_id contributors", .{});
    for (0..retained) |k| {
        const contributions = c.vector(n);
        var squares: f64 = 0;
        var minimum: usize = 0;
        var maximum: usize = 0;
        for (diagnostics, 0..) |item, i| {
            const value = item.score[k];
            squares += value * value;
            contributions[i] = value * value / (c.f(n - 1) * eigen.values[k]);
            if (value < diagnostics[minimum].score[k]) minimum = i;
            if (value > diagnostics[maximum].score[k]) maximum = i;
        }
        line = .{};
        line.add("pc{d} {s} {s} {s} {s} {s}", .{ k + 1, real(@sqrt(squares / c.f(n - 1))), real(diagnostics[minimum].score[k]),
             a.rows[minimum].id, real(diagnostics[maximum].score[k]), a.rows[maximum].id });
        const order = decreasing(contributions);
        for (order[0..@min(p.top, n)]) |i| line.add(" {s}:{s}", .{ a.rows[i].id, real(contributions[i]) });
        out.add("{s}", .{line.value()});
    }
    out.add("", .{});
    out.add("varimax components {d} cycles {d}", .{ retained, p.cycles });
    for (criteria, 0..) |value, cycle| out.add("cycle {d} criterion {s}", .{ cycle, real6(value) });
    for (rotated_order, 0..) |source, k| {
        var closest: usize = 0;
        var congruence: f64 = -1;
        for (0..retained) |h| {
            const loading = m.column(loadings, h);
            const value = @abs(m.dot(rotated[source], loading) / @sqrt(m.dot(rotated[source], rotated[source]) * m.dot(loading,
                 loading)));
            if (value > congruence) {
                congruence = value;
                closest = h;
            }
        }
        out.add("rc{d} ss {s} ratio {s} closest pc{d} congruence {s}", .{ k + 1, real(rotated_ss[source]),
             real(rotated_ss[source] / total), closest + 1, real(congruence) });
    }
    out.add("", .{});
    out.add("sensitivity", .{});
    out.add("missing scaling rows sweeps eigenvalues cumulative congruence", .{});
    for ([_][]const u8{ "listwise", "mean" }) |missing| for ([_][]const u8{ "covariance", "correlation" }) |scaling| {
        const alternative = analyze(input, observed_means, missing, scaling);
        line = .{};
        line.add("{s} {s} {d} {d}", .{ missing, scaling, alternative.rows.len, alternative.eigen.sweeps });
        const variance = sum(alternative.eigen.values);
        var cumulative_ratio: f64 = 0;
        for (0..retained) |k| {
            line.add(" {s}", .{real(alternative.eigen.values[k])});
            cumulative_ratio += alternative.eigen.values[k] / variance;
        }
        line.add(" {s}", .{real(cumulative_ratio)});
        for (0..retained) |k| line.add(" {s}", .{real(@abs(m.dot(alternative.eigen.vectors[k], eigen.vectors[k])))});
        out.add("{s}", .{line.value()});
    };
    try write(init.io, "eigen.txt", out);
    var loading_file: c.Lines = .{};
    line = .{};
    line.add("variable", .{});
    for (1..retained + 1) |k| line.add(",pc{d}", .{k});
    line.add(",communality", .{});
    for (1..retained + 1) |k| line.add(",rc{d}", .{k});
    loading_file.add("{s}", .{line.value()});
    for (input.names, 0..) |name, j| {
        line = .{};
        line.add("{s}", .{name});
        for (loadings[j][0..retained]) |value| line.add(",{s}", .{real(value)});
        line.add(",{s}", .{real(communality[j])});
        for (rotated_order) |k| line.add(",{s}", .{real(rotated[k][j])});
        loading_file.add("{s}", .{line.value()});
    }
    try write(init.io, "loadings.csv", loading_file);
    var score_file: c.Lines = .{};
    line = .{};
    line.add("id,set", .{});
    for (1..retained + 1) |k| line.add(",pc{d}", .{k});
    score_file.add("{s}", .{line.value()});
    for (0..2) |set| {
        const rows = if (set == 0) a.rows else input.supplementary;
        const items = if (set == 0) diagnostics else supplementary;
        for (rows, items) |record, item| {
            line = .{};
            line.add("{s},{s}", .{ record.id, if (set == 0) "data" else "supplementary" });
            for (item.score[0..retained]) |value| line.add(",{s}", .{real(value)});
            score_file.add("{s}", .{line.value()});
        }
    }
    try write(init.io, "scores.csv", score_file);
    var outliers: c.Lines = .{};
    outliers.add("diagnostics components {d} t2_limit {s} spe_limit {s}", .{ retained, real(p.t2), real(p.spe) });
    outliers.add("id t2 spe quality flag", .{});
    var tflags: usize = 0;
    var qflags: usize = 0;
    var both: usize = 0;
    var any: usize = 0;
    const tvalues = c.vector(n);
    const qvalues = c.vector(n);
    for (a.rows, diagnostics, 0..) |record, item, i| {
        outliers.add("{s} {s} {s} {s} {s}", .{ record.id, real(item.t2), real(item.spe), real(item.quality), item.flag_ });
        tflags += @intFromBool(item.t2 > p.t2);
        qflags += @intFromBool(item.spe > p.spe);
        both += @intFromBool(c.eq(item.flag_, "TQ"));
        any += @intFromBool(!c.eq(item.flag_, "-"));
        tvalues[i] = item.t2;
        qvalues[i] = item.spe;
    }
    outliers.add("flagged t2 {d} spe {d} both {d} any {d}", .{ tflags, qflags, both, any });
    for (0..2) |kind| {
        outliers.add("", .{});
        outliers.add("top {s}", .{if (kind == 0) "t2" else "spe"});
        outliers.add("rank id {s} variable contribution", .{if (kind == 0) "t2" else "spe"});
        const values = if (kind == 0) tvalues else qvalues;
        const order = decreasing(values);
        for (order[0..@min(p.top, n)], 1..) |i, rank| {
            const contributions = if (kind == 0) diagnostics[i].tcontribution else diagnostics[i].qcontribution;
            const j = decreasing(contributions)[0];
            outliers.add("{d} {s} {s} {s} {s}", .{ rank, a.rows[i].id, real(values[i]), input.names[j], real(contributions[j]) });
        }
    }
    outliers.add("", .{});
    outliers.add("reconstruction", .{});
    outliers.add("k mean_spe max_spe max_id", .{});
    for (1..variables) |count| {
        var total_spe: f64 = 0;
        var maximum: f64 = -1;
        var largest: usize = 0;
        for (diagnostics, 0..) |item, i| {
            const residual = pca.residuals(item.z, item.score, eigen.vectors, count);
            const spe = m.dot(residual, residual);
            total_spe += spe;
            if (spe > maximum) {
                maximum = spe;
                largest = i;
            }
        }
        outliers.add("{d} {s} {s} {s}", .{ count, real(total_spe / c.f(n)), real(maximum), a.rows[largest].id });
    }
    outliers.add("", .{});
    outliers.add("supplementary", .{});
    line = .{};
    line.add("id", .{});
    for (1..retained + 1) |k| line.add(" pc{d}", .{k});
    line.add(" t2 spe flag nearest distance", .{});
    outliers.add("{s}", .{line.value()});
    for (input.supplementary, supplementary) |record, item| {
        var nearest: usize = 0;
        var minimum: f64 = -1;
        for (diagnostics, 0..) |other, i| {
            var distance: f64 = 0;
            for (0..retained) |k| {
                const delta = item.score[k] - other.score[k];
                distance += delta * delta;
            }
            if (minimum < 0 or distance < minimum) {
                minimum = distance;
                nearest = i;
            }
        }
        line = .{};
        line.add("{s}", .{record.id});
        for (item.score[0..retained]) |value| line.add(" {s}", .{real(value)});
        line.add(" {s} {s} {s} {s} {s}", .{ real(item.t2), real(item.spe), item.flag_, a.rows[nearest].id,
             real(@sqrt(minimum)) });
        outliers.add("{s}", .{line.value()});
    }
    try write(init.io, "outliers.txt", outliers);
    try write(init.io, "plots.txt", plots(input, a, loadings, broken, total, average, diagnostics, supplementary));
}
