const std = @import("std");
const c = @import("dataset.zig");
const gaussian = @import("gaussian.zig");
const em = @import("em.zig");
const kmeans = @import("kmeans.zig");
const report = @import("report.zig");
fn r(value: f64) []const u8 {
    return report.real(value, 4);
}
fn integers(values: anytype, offset: usize) []const u8 {
    var out: c.Text = .{};
    for (values, 0..) |value, i| out.add("{s}{d}", .{ if (i == 0) "" else " ", c.n(value) + c.n(offset) });
    return out.value();
}
fn reals(values: []const f64) []const u8 {
    var out: c.Text = .{};
    for (values, 0..) |value, i| out.add("{s}{s}", .{ if (i == 0) "" else " ", r(value) });
    return out.value();
}
fn optional(value: ?f64) []const u8 {
    return if (value) |number| r(number) else "-";
}
const Summary = struct { fit: em.Fit, k: usize, type_order: usize, parameters: usize, bic: f64, aic: f64,
     icl: f64, entropy: f64 = 0, assigned: []usize, sizes: []usize, entropies: []f64 };
fn parameterCount(k: usize, kind: c.Type) usize {
    return switch (kind) {
        .FULL => 6 * k - 1,
        .TIED => 3 * k + 2,
        .DIAG => 5 * k - 1,
        .SPHERICAL => 4 * k - 1,
    };
}
fn summarize(fit: em.Fit, type_order: usize, n: usize) Summary {
    const k = fit.model.components.len;
    const parameters = parameterCount(k, fit.model.kind);
    var out: Summary = .{ .fit = fit, .k = k, .type_order = type_order, .parameters = parameters,
         .bic = -2 * fit.e.loglik + c.f(parameters) * @log(c.f(n)), .aic = -2 * fit.e.loglik + 2 * c.f(parameters),
         .icl = 0, .assigned = c.alloc(usize, n), .sizes = c.alloc(usize, k), .entropies = c.alloc(f64,
         n) };
    @memset(out.sizes, 0);
    for (fit.e.records, 0..) |record, i| {
        var chosen: usize = 0;
        var entropy: f64 = 0;
        for (0..k) |j| {
            if (record.responsibility[j] > record.responsibility[chosen]) chosen = j;
            if (record.responsibility[j] > 0) entropy -= record.responsibility[j] * @log(record.responsibility[j]);
        }
        out.assigned[i] = chosen;
        out.sizes[chosen] += 1;
        out.entropies[i] = entropy;
        out.entropy += entropy;
    }
    out.icl = out.bic + 2 * out.entropy;
    return out;
}
fn criterion(model: Summary, which: usize) f64 {
    return if (which == 0) model.bic else if (which == 1) model.aic else model.icl;
}
const RankContext = struct { models: []const Summary, which: usize };
fn rankLess(context: RankContext, first: usize, second: usize) bool {
    const a = context.models[first];
    const b = context.models[second];
    const x = report.rounded(criterion(a, context.which), 4);
    const y = report.rounded(criterion(b, context.which), 4);
    if (x != y) return x < y;
    if (a.parameters != b.parameters) return a.parameters < b.parameters;
    if (a.k != b.k) return a.k < b.k;
    return a.type_order < b.type_order;
}
fn ranked(models: []const Summary, which: usize) []usize {
    const out = c.alloc(usize, models.len);
    for (out, 0..) |*value, i| value.* = i;
    std.mem.sort(usize, out, RankContext{ .models = models, .which = which }, rankLess);
    return out;
}
const Table = struct { data: [4][4]i64 = [_][4]i64{.{ 0, 0, 0, 0 }} ** 4, rows: usize, columns: usize };
fn contingency(a: []const usize, rows: usize, b: []const usize, columns: usize) Table {
    var out: Table = .{ .rows = rows, .columns = columns };
    for (a, b) |x, y| out.data[x][y] += 1;
    return out;
}
const Fraction = struct { numerator: i64, denominator: i64 };
fn choose(value: i64) i64 {
    return @divTrunc(value * (value - 1), 2);
}
fn ari(table: Table) Fraction {
    var cells: i64 = 0;
    var rows: i64 = 0;
    var columns: i64 = 0;
    var total: i64 = 0;
    for (table.data[0..table.rows]) |row| {
        var sum: i64 = 0;
        for (row[0..table.columns]) |value| {
            cells += choose(value);
            sum += value;
        }
        rows += choose(sum);
        total += sum;
    }
    for (0..table.columns) |j| {
        var sum: i64 = 0;
        for (0..table.rows) |i| sum += table.data[i][j];
        columns += choose(sum);
    }
    const z = choose(total);
    var numerator = 2 * (z * cells - rows * columns);
    var denominator = z * (rows + columns) - 2 * rows * columns;
    if (denominator == 0) return .{ .numerator = 1, .denominator = 1 };
    if (denominator < 0) {
        numerator = -numerator;
        denominator = -denominator;
    }
    var a = if (numerator < 0) -numerator else numerator;
    var b = denominator;
    while (b != 0) {
        const remainder = @mod(a, b);
        a = b;
        b = remainder;
    }
    return .{ .numerator = @divExact(numerator, a), .denominator = @divExact(denominator, a) };
}
fn fractionText(value: Fraction) []const u8 {
    return c.fmt("{d}/{d} {s}", .{ value.numerator, value.denominator, r(c.f(value.numerator) / c.f(value.denominator)) });
}
const Evaluation = struct { silhouette: ?f64 = null, ch: ?f64 = null, db: ?f64 = null, cluster: [4]?f64 = .{ null,
     null, null, null } };
fn evaluate(points: []const c.Point, labels: []const usize, k: usize) Evaluation {
    const n = points.len;
    var counts = [_]usize{0} ** 4;
    var centers = [_]c.Vec{.{ 0, 0 }} ** 4;
    var global: c.Vec = .{ 0, 0 };
    for (points, labels) |point, label| {
        counts[label] += 1;
        for (0..2) |axis| {
            centers[label][axis] += point.xy[axis];
            global[axis] += point.xy[axis];
        }
    }
    var groups: usize = 0;
    for (0..k) |j| if (counts[j] > 0) {
        groups += 1;
        centers[j][0] /= c.f(counts[j]);
        centers[j][1] /= c.f(counts[j]);
    };
    global[0] /= c.f(n);
    global[1] /= c.f(n);
    var out: Evaluation = .{};
    if (groups < 2) return out;
    var cluster_sum = [_]f64{0} ** 4;
    var silhouette: f64 = 0;
    for (points, labels, 0..) |point, label, i| {
        var value: f64 = 0;
        if (counts[label] > 1) {
            var sums = [_]f64{0} ** 4;
            for (points, labels, 0..) |other, other_label, j| if (j != i) {
                sums[other_label] += kmeans.distance(point.xy, other.xy);
            };
            const a = sums[label] / c.f(counts[label] - 1);
            var b = std.math.inf(f64);
            for (0..k) |j| if (j != label and counts[j] > 0) {
                b = @min(b, sums[j] / c.f(counts[j]));
            };
            value = (b - a) / @max(a, b);
        }
        silhouette += value;
        cluster_sum[label] += value;
    }
    out.silhouette = silhouette / c.f(n);
    for (0..k) |j| if (counts[j] > 0) {
        out.cluster[j] = cluster_sum[j] / c.f(counts[j]);
    };
    var between: f64 = 0;
    var within: f64 = 0;
    for (0..k) |j| if (counts[j] > 0) {
        between += c.f(counts[j]) * kmeans.distance2(centers[j], global);
    };
    for (points, labels) |point, label| within += kmeans.distance2(point.xy, centers[label]);
    out.ch = (between / c.f(groups - 1)) / (within / c.f(n - groups));
    var scatter = [_]f64{0} ** 4;
    for (0..k) |j| if (counts[j] > 0) {
        for (points, labels) |point, label| if (label == j) {
            scatter[j] += kmeans.distance(point.xy, centers[j]);
        };
        scatter[j] /= c.f(counts[j]);
    };
    var db: f64 = 0;
    for (0..k) |a| if (counts[a] > 0) {
        var maximum: f64 = 0;
        for (0..k) |b| if (b != a and counts[b] > 0) {
            maximum = @max(maximum, (scatter[a] + scatter[b]) / kmeans.distance(centers[a], centers[b]));
        };
        db += maximum;
    };
    out.db = db / c.f(groups);
    return out;
}
fn nextPermutation(values: []usize) bool {
    if (values.len < 2) return false;
    var i = values.len - 1;
    while (i > 0 and values[i - 1] >= values[i]) i -= 1;
    if (i == 0) return false;
    const pivot = i - 1;
    var j = values.len - 1;
    while (values[j] <= values[pivot]) j -= 1;
    std.mem.swap(usize, &values[j], &values[pivot]);
    std.mem.reverse(usize, values[i..]);
    return true;
}
fn matching(table: Table) []const usize {
    const permutation = c.alloc(usize, table.rows);
    for (permutation, 0..) |*value, i| value.* = i;
    const best = c.alloc(usize, table.rows);
    var maximum: i64 = -1;
    while (true) {
        var agreement: i64 = 0;
        for (permutation, 0..) |label, j| agreement += table.data[label][j];
        if (agreement > maximum) {
            maximum = agreement;
            @memcpy(best, permutation);
        }
        if (!nextPermutation(permutation)) break;
    }
    return best;
}
const Groups = struct { data: [4][4]usize = [_][4]usize{.{ 0, 0, 0, 0 }} ** 4, sizes: [4]usize = .{ 0, 0, 0, 0 }, count: usize };
fn integerLess(_: void, a: usize, b: usize) bool {
    return a < b;
}
fn mergeGroups(original: Groups, a: usize, b: usize) Groups {
    var groups = original;
    for (groups.data[b][0..groups.sizes[b]]) |value| {
        groups.data[a][groups.sizes[a]] = value;
        groups.sizes[a] += 1;
    }
    std.mem.sort(usize, groups.data[a][0..groups.sizes[a]], {}, integerLess);
    for (b..groups.count - 1) |i| {
        groups.data[i] = groups.data[i + 1];
        groups.sizes[i] = groups.sizes[i + 1];
    }
    groups.count -= 1;
    return groups;
}
fn groupEntropy(selected: Summary, groups: Groups, sizes: ?*[4]usize) f64 {
    var total: f64 = 0;
    if (sizes) |values| @memset(values[0..], 0);
    for (selected.fit.e.records) |record| {
        var sums = [_]f64{0} ** 4;
        var entropy: f64 = 0;
        for (0..groups.count) |g| {
            for (groups.data[g][0..groups.sizes[g]]) |component| sums[g] += record.responsibility[component];
            if (sums[g] > 0) entropy -= sums[g] * @log(sums[g]);
        }
        total += entropy;
        if (sizes) |values| {
            var chosen: usize = 0;
            for (1..groups.count) |j| if (sums[j] > sums[chosen]) {
                chosen = j;
            };
            values[chosen] += 1;
        }
    }
    return total;
}
fn groupName(values: []const usize) []const u8 {
    var out: c.Text = .{};
    for (values, 0..) |value, i| out.add("{s}{d}", .{ if (i == 0) "" else "+", value + 1 });
    return out.value();
}
const PointContext = struct { selected: *const Summary, density: bool };
fn pointLess(context: PointContext, a: usize, b: usize) bool {
    const selected = context.selected;
    const first = if (context.density) selected.fit.e.records[a].log_density else selected.fit.e.records[a].responsibility[selected.assigned[a]];
    const second = if (context.density) selected.fit.e.records[b].log_density else selected.fit.e.records[b].responsibility[selected.assigned[b]];
    const x = report.rounded(first, 4);
    const y = report.rounded(second, 4);
    return x < y or (x == y and a < b);
}
fn grid(width: usize, height: usize) [][]u8 {
    const out = c.alloc([]u8, height);
    for (out) |*row| {
        row.* = c.alloc(u8, width);
        @memset(row.*, ' ');
    }
    return out;
}
fn center(x: i64, y: i64, p: c.Params, step_x: f64, step_y: f64) c.Vec {
    return .{ p.xmin + (c.f(x) + 0.5) * step_x, p.ymax - (c.f(y) + 0.5) * step_y };
}
fn cell(xy: c.Vec, p: c.Params, step_x: f64, step_y: f64) ?[2]usize {
    const x = @floor((xy[0] - p.xmin) / step_x);
    const y = @floor((p.ymax - xy[1]) / step_y);
    if (x < 0 or x >= c.f(p.width) or y < 0 or y >= c.f(p.height)) return null;
    return .{ @intFromFloat(x), @intFromFloat(y) };
}
fn digit(value: usize) u8 {
    return '1' + @as(u8, @intCast(value));
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    c.allocator = arena.allocator();
    try std.Io.Dir.cwd().createDirPath(init.io, "output");
    const input = try c.load(init.io);
    const points = input.points;
    const p = input.params;
    const n = points.len;
    var model_list: std.ArrayList(Summary) = .empty;
    var km_results: [5]kmeans.Result = undefined;
    for (p.ks) |k| {
        km_results[k] = kmeans.run(points, input.initial[k], p.kmeans_max);
        for (p.types, 0..) |kind, order| c.append(Summary, &model_list, summarize(em.run(points, input.initial[k],
             kind, p), order, n));
    }
    const models = model_list.items;
    const bic = ranked(models, 0);
    const aic = ranked(models, 1);
    const icl = ranked(models, 2);
    const aic_rank = c.alloc(usize, models.len);
    const icl_rank = c.alloc(usize, models.len);
    for (0..models.len) |i| {
        aic_rank[aic[i]] = i + 1;
        icl_rank[icl[i]] = i + 1;
    }
    const selected = &models[bic[0]];
    const k = selected.k;
    const kind = selected.fit.model.kind;
    const km = km_results[k];
    var best_k = [_]usize{0} ** 5;
    for (p.ks) |count| for (bic) |index| {
        if (models[index].k == count) {
            best_k[count] = index;
            break;
        }
    };
    var model_file: c.Lines = .{};
    var trace: c.Lines = .{};
    var assignments: c.Lines = .{};
    var selection: c.Lines = .{};
    var map_file: c.Lines = .{};
    trace.add("K,type,iteration,loglik", .{});
    for (models, 0..) |model, index| {
        if (index > 0) model_file.add("", .{});
        model_file.add("model K={d} type={s}", .{ model.k, @tagName(model.fit.model.kind) });
        model_file.add("parameters {d}", .{model.parameters});
        model_file.add("loglik {s}", .{r(model.fit.e.loglik)});
        model_file.add("bic {s}", .{r(model.bic)});
        model_file.add("aic {s}", .{r(model.aic)});
        model_file.add("icl {s}", .{r(model.icl)});
        model_file.add("mean_entropy {s}", .{r(model.entropy / c.f(n))});
        model_file.add("settled_at {d}", .{model.fit.settled});
        model_file.add("largest_increase iteration {d} value {s}", .{ model.fit.largest, r(model.fit.trace[model.fit.largest] - model.fit.trace[model.fit.largest - 1]) });
        model_file.add("violations {d}", .{model.fit.violations.len});
        model_file.add("sizes {s}", .{integers(model.sizes, 0)});
        for (model.fit.model.components, 1..) |component, number| {
            const e = gaussian.eigen(component.cov);
            model_file.add("component {d} weight {s} mean {s} {s} cov {s} {s} {s} axes {s} {s} angle {s}",
                 .{ number, r(component.weight), r(component.mean[0]), r(component.mean[1]), r(component.cov[0]),
                 r(component.cov[1]), r(component.cov[2]), r(e.major), r(e.minor), r(e.angle) });
        }
        for (model.fit.trace, 0..) |value, t| trace.add("{d},{s},{d},{s}", .{ model.k, @tagName(model.fit.model.kind),
             t, r(value) });
    }
    assignments.add("id,component,max_responsibility,log_density,kmeans_cluster", .{});
    for (points, 0..) |point, i| assignments.add("{s},{d},{s},{s},{d}", .{ point.id, selected.assigned[i] + 1,
         r(selected.fit.e.records[i].responsibility[selected.assigned[i]]), r(selected.fit.e.records[i].log_density),
         km.assignment[i] + 1 });
    selection.add("ranking by bic", .{});
    selection.add("rank K type parameters loglik bic delta_bic aic aic_rank icl icl_rank", .{});
    for (bic, 1..) |index, rank| {
        const model = models[index];
        const delta = c.f(report.rounded(model.bic, 4) - report.rounded(selected.bic, 4)) / 10000;
        selection.add("{d} {d} {s} {d} {s} {s} {s} {s} {d} {s} {d}", .{ rank, model.k, @tagName(model.fit.model.kind),
             model.parameters, r(model.fit.e.loglik), r(model.bic), r(delta), r(model.aic), aic_rank[index],
             r(model.icl), icl_rank[index] });
    }
    selection.add("selected K={d} type={s}", .{ k, @tagName(kind) });
    selection.add("best_aic K={d} type={s}", .{ models[aic[0]].k, @tagName(models[aic[0]].fit.model.kind) });
    selection.add("best_icl K={d} type={s}", .{ models[icl[0]].k, @tagName(models[icl[0]].fit.model.kind) });
    selection.add("", .{});
    selection.add("best K per type", .{});
    for (p.types) |current| {
        var best: [3]usize = undefined;
        const rankings = [_][]const usize{ bic, aic, icl };
        for (rankings, 0..) |ranking, which| for (ranking) |index| {
            if (models[index].fit.model.kind == current) {
                best[which] = models[index].k;
                break;
            }
        };
        selection.add("{s} bic {d} aic {d} icl {d}", .{ @tagName(current), best[0], best[1], best[2] });
    }
    for (p.ks, 0..) |count, ki| {
        const model = models[best_k[count]];
        const current = km_results[count];
        const a = evaluate(points, model.assigned, count);
        const b = evaluate(points, current.assignment, count);
        selection.add("", .{});
        selection.add("K={d} type={s} bic {s}", .{ count, @tagName(model.fit.model.kind), r(model.bic) });
        selection.add("  kmeans iterations {d} inertia {s}", .{ current.iterations, r(current.inertia) });
        selection.add("  ari {s}", .{fractionText(ari(contingency(model.assigned, count, current.assignment, count)))});
        selection.add("  silhouette gmm {s} kmeans {s}", .{ optional(a.silhouette), optional(b.silhouette) });
        selection.add("  calinski_harabasz gmm {s} kmeans {s}", .{ optional(a.ch), optional(b.ch) });
        selection.add("  davies_bouldin gmm {s} kmeans {s}", .{ optional(a.db), optional(b.db) });
        if (ki > 0) {
            const previous = p.ks[ki - 1];
            const table = contingency(models[best_k[previous]].assigned, previous, model.assigned, count);
            var parents: c.Text = .{};
            var shared = [_]i64{0} ** 4;
            for (0..count) |j| {
                var parent: usize = 0;
                for (1..previous) |i| if (table.data[i][j] > table.data[parent][j]) {
                    parent = i;
                };
                parents.add("{s}{s}", .{ if (j == 0) "" else " ", if (table.data[parent][j] > 0) c.fmt("{d}",
                     .{parent + 1}) else "-" });
                shared[j] = table.data[parent][j];
            }
            selection.add("  parents K={d} {s} shared {s}", .{ previous, parents.value(), integers(shared[0..count], 0) });
        }
    }
    selection.add("", .{});
    selection.add("violations", .{});
    var violation_count: usize = 0;
    for (models) |model| for (model.fit.violations) |t| {
        violation_count += 1;
        selection.add("K={d} type={s} iteration {d} previous {s} current {s}", .{ model.k, @tagName(model.fit.model.kind),
             t, r(model.fit.trace[t - 1]), r(model.fit.trace[t]) });
    };
    if (violation_count == 0) selection.add("none", .{});
    selection.add("", .{});
    selection.add("selected components", .{});
    const selected_evaluation = evaluate(points, selected.assigned, k);
    for (selected.fit.model.components, 0..) |component, j| {
        const e = gaussian.eigen(component.cov);
        var soft: f64 = 0;
        var inside1: usize = 0;
        var inside2: usize = 0;
        const observed = c.alloc(usize, p.gof.len + 1);
        @memset(observed, 0);
        for (points, selected.fit.e.records, 0..) |point, record, i| {
            soft += record.responsibility[j];
            if (selected.assigned[i] == j) {
                const q = gaussian.mahalanobis(point.xy, component.mean, component.cov);
                const radius = @sqrt(q);
                inside1 += @intFromBool(q <= 1);
                inside2 += @intFromBool(q <= 4);
                var bin: usize = 0;
                while (bin < p.gof.len and radius >= p.gof[bin]) bin += 1;
                observed[bin] += 1;
            }
        }
        const expected = c.alloc(f64, observed.len);
        var chi: f64 = 0;
        for (observed, expected, 0..) |value, *ex, bin| {
            const low = if (bin > 0) p.gof[bin - 1] else 0;
            const upper = if (bin < p.gof.len) @exp(-p.gof[bin] * p.gof[bin] / 2) else 0;
            ex.* = c.f(selected.sizes[j]) * (@exp(-low * low / 2) - upper);
            chi += (c.f(value) - ex.*) * (c.f(value) - ex.*) / ex.*;
        }
        selection.add("component {d} weight {s} size {d} soft_size {s} mean {s} {s}", .{ j + 1, r(component.weight),
             selected.sizes[j], r(soft), r(component.mean[0]), r(component.mean[1]) });
        selection.add("  cov {s} {s} {s} corr {s}", .{ r(component.cov[0]), r(component.cov[1]), r(component.cov[2]),
             r(e.correlation) });
        selection.add("  eigen {s} {s} direction {s} {s} angle {s}", .{ r(e.leading), r(e.trailing),
             r(e.direction[0]), r(e.direction[1]), r(e.angle) });
        selection.add("  axes_1sigma {s} {s} axes_2sigma {s} {s}", .{ r(e.major), r(e.minor), r(2 * e.major), r(2 * e.minor) });
        selection.add("  inside_1sigma {d} inside_2sigma {d} area_1sigma {s}", .{ inside1, inside2, r(e.area) });
        selection.add("  silhouette {s}", .{optional(selected_evaluation.cluster[j])});
        selection.add("  gof observed {s} expected {s} chi2 {s}", .{ integers(observed, 0), reals(expected), r(chi) });
    }
    selection.add("", .{});
    selection.add("overlap", .{});
    if (k == 1) selection.add("none", .{});
    for (0..k) |a| for (a + 1..k) |b| {
        const d = gaussian.bhattacharyya(selected.fit.model.components[a], selected.fit.model.components[b]);
        var shared: f64 = 0;
        for (selected.fit.e.records) |record| shared += record.responsibility[a] * record.responsibility[b];
        selection.add("{d}-{d} bhattacharyya {s} coefficient {s} shared {s}", .{ a + 1, b + 1, r(d), r(@exp(-d)), r(shared) });
    };
    var groups: Groups = .{ .count = k };
    for (0..k) |j| {
        groups.data[j][0] = j;
        groups.sizes[j] = 1;
    }
    selection.add("", .{});
    selection.add("merging", .{});
    selection.add("start entropy {s}", .{r(groupEntropy(selected.*, groups, null))});
    for (1..k) |step| {
        var best_a: usize = 0;
        var best_b: usize = 1;
        var best: i64 = std.math.maxInt(i64);
        for (0..groups.count) |a| for (a + 1..groups.count) |b| {
            const value = report.rounded(groupEntropy(selected.*, mergeGroups(groups, a, b), null), 4);
            if (value < best) {
                best = value;
                best_a = a;
                best_b = b;
            }
        };
        const a = groupName(groups.data[best_a][0..groups.sizes[best_a]]);
        const b = groupName(groups.data[best_b][0..groups.sizes[best_b]]);
        groups = mergeGroups(groups, best_a, best_b);
        var sizes: [4]usize = undefined;
        const entropy = groupEntropy(selected.*, groups, &sizes);
        selection.add("step {d} merge {s} {s} entropy {s} sizes {s}", .{ step, a, b, r(entropy), integers(sizes[0..groups.count],
             0) });
    }
    const table = contingency(selected.assigned, k, km.assignment, k);
    const permutation = matching(table);
    var agreement: i64 = 0;
    for (permutation, 0..) |label, j| agreement += table.data[label][j];
    selection.add("", .{});
    selection.add("kmeans K={d}", .{k});
    selection.add("iterations {d}", .{km.iterations});
    selection.add("inertia {s}", .{r(km.inertia)});
    selection.add("sizes {s}", .{integers(km.sizes, 0)});
    for (km.centers, 1..) |mean, j| selection.add("center {d} {s} {s}", .{ j, r(mean[0]), r(mean[1]) });
    selection.add("contingency", .{});
    for (table.data[0..k]) |row| selection.add("{s}", .{integers(row[0..k], 0)});
    selection.add("ari {s}", .{fractionText(ari(table))});
    selection.add("matching {s}", .{integers(permutation, 1)});
    selection.add("agreement {d}/{d} {s}", .{ agreement, n, r(c.f(agreement) / c.f(n)) });
    var disagreements: usize = 0;
    for (points, 0..) |point, i| if (permutation[km.assignment[i]] != selected.assigned[i]) {
        disagreements += 1;
        selection.add("disagree {s} gmm {d} kmeans {d} max {s}", .{ point.id, selected.assigned[i] + 1,
             km.assignment[i] + 1, r(selected.fit.e.records[i].responsibility[selected.assigned[i]]) });
    };
    selection.add("disagreements {d}", .{disagreements});
    const initial: c.Model = .{ .components = c.alloc(c.Component, k) };
    for (initial.components, 0..) |*component, j| {
        component.* = .{ .weight = c.f(km.sizes[j]) / c.f(n), .mean = km.centers[j], .cov = .{ 0, 0, 0 } };
        var scatter: c.Cov = .{ 0, 0, 0 };
        for (points, km.assignment) |point, label| if (label == j) {
            const dx = point.xy[0] - component.mean[0];
            const dy = point.xy[1] - component.mean[1];
            scatter[0] += dx * dx;
            scatter[1] += dx * dy;
            scatter[2] += dy * dy;
        };
        component.cov = .{ scatter[0] / c.f(km.sizes[j]) + p.epsilon, scatter[1] / c.f(km.sizes[j]),
             scatter[2] / c.f(km.sizes[j]) + p.epsilon };
    }
    const refit = summarize(em.run(points, initial, kind, p), selected.type_order, n);
    selection.add("", .{});
    selection.add("refit_from_kmeans K={d} type={s}", .{ k, @tagName(kind) });
    selection.add("loglik {s} bic {s} settled_at {d}", .{ r(refit.fit.e.loglik), r(refit.bic), refit.fit.settled });
    selection.add("sizes {s}", .{integers(refit.sizes, 0)});
    selection.add("ari_vs_selected {s}", .{fractionText(ari(contingency(selected.assigned, k, refit.assigned, k)))});
    selection.add("", .{});
    selection.add("cross_validation K={d} type={s} folds {d}", .{ k, @tagName(kind), p.folds });
    var total_test: f64 = 0;
    for (0..p.folds) |fold| {
        var train: std.ArrayList(c.Point) = .empty;
        var test_rows: std.ArrayList(c.Point) = .empty;
        for (points, 0..) |point, i| {
            if (i % p.folds == fold) c.append(c.Point, &test_rows, point) else c.append(c.Point, &train, point);
        }
        const fit = em.run(train.items, input.initial[k], kind, p);
        const score = em.expectation(test_rows.items, fit.model).loglik / c.f(test_rows.items.len);
        total_test += score;
        selection.add("fold {d} train {d} test {d} train_loglik {s} test_loglik {s}", .{ fold + 1,
             train.items.len, test_rows.items.len, r(fit.e.loglik / c.f(train.items.len)), r(score) });
    }
    selection.add("mean_test_loglik {s}", .{r(total_test / c.f(p.folds))});
    var uncertain: std.ArrayList(usize) = .empty;
    var outliers: std.ArrayList(usize) = .empty;
    for (selected.fit.e.records, 0..) |record, i| {
        if (record.responsibility[selected.assigned[i]] < p.uncertain) c.append(usize, &uncertain, i);
        if (record.log_density < p.low_density) c.append(usize, &outliers, i);
    }
    std.mem.sort(usize, uncertain.items, PointContext{ .selected = selected, .density = false }, pointLess);
    std.mem.sort(usize, outliers.items, PointContext{ .selected = selected, .density = true }, pointLess);
    selection.add("", .{});
    selection.add("uncertain threshold {s}", .{r(p.uncertain)});
    for (uncertain.items) |i| selection.add("{s} component {d} max {s} responsibilities {s}", .{ points[i].id,
         selected.assigned[i] + 1, r(selected.fit.e.records[i].responsibility[selected.assigned[i]]),
         reals(selected.fit.e.records[i].responsibility[0..k]) });
    selection.add("count {d}", .{uncertain.items.len});
    selection.add("", .{});
    selection.add("outliers threshold {s}", .{r(p.low_density)});
    for (outliers.items) |i| {
        const j = selected.assigned[i];
        const component = selected.fit.model.components[j];
        selection.add("{s} component {d} log_density {s} q {s}", .{ points[i].id, j + 1, r(selected.fit.e.records[i].log_density),
             r(gaussian.mahalanobis(points[i].xy, component.mean, component.cov)) });
    }
    selection.add("count {d}", .{outliers.items.len});
    const step_x = (p.xmax - p.xmin) / c.f(p.width);
    const step_y = (p.ymax - p.ymin) / c.f(p.height);
    const cells = p.width * p.height;
    const densities = c.alloc(f64, cells);
    const records = c.alloc(em.Record, cells);
    var fmax: f64 = 0;
    var mass: f64 = 0;
    for (0..p.height) |y| for (0..p.width) |x| {
        const point = c.Point{ .id = "", .xy = center(c.n(x), c.n(y), p, step_x, step_y) };
        const record = em.expectation(&.{point}, selected.fit.model).records[0];
        var density: f64 = 0;
        for (0..k) |j| density += @exp(record.scores[j]);
        const index = y * p.width + x;
        densities[index] = density;
        records[index] = record;
        fmax = @max(fmax, density);
        mass += density;
    };
    mass *= step_x;
    mass *= step_y;
    const density = grid(p.width, p.height);
    const region = grid(p.width, p.height);
    const uncertainty = grid(p.width, p.height);
    const point_map = grid(p.width, p.height);
    var levels = [_]usize{0} ** 10;
    const characters = " .:-=+*#%@";
    const offsets = [_][2]i64{ .{ -1, 0 }, .{ 1, 0 }, .{ 0, -1 }, .{ 0, 1 } };
    for (0..p.height) |y| for (0..p.width) |x| {
        const index = y * p.width + x;
        const level = @min(@as(usize, 9), @as(usize, @intFromFloat(@floor(10 * densities[index] / fmax))));
        levels[level] += 1;
        density[y][x] = characters[level];
        const record = records[index];
        var chosen: usize = 0;
        var entropy: f64 = 0;
        for (0..k) |j| {
            if (record.scores[j] > record.scores[chosen]) chosen = j;
            if (record.responsibility[j] > 0) entropy -= record.responsibility[j] * @log(record.responsibility[j]);
        }
        region[y][x] = digit(chosen);
        if (k >= 2) {
            const value: i64 = @intFromFloat(@floor(10 * entropy / @log(c.f(k))));
            uncertainty[y][x] = characters[c.u(@max(0, @min(9, value)))];
        }
        for (selected.fit.model.components) |component| {
            if (gaussian.mahalanobis(center(c.n(x), c.n(y), p, step_x, step_y), component.mean, component.cov) > 4) continue;
            var contour = false;
            for (offsets) |offset| {
                const xx = c.n(x) + offset[0];
                const yy = c.n(y) + offset[1];
                if (xx >= 0 and xx < c.n(p.width) and yy >= 0 and yy < c.n(p.height) and gaussian.mahalanobis(center(xx,
                     yy, p, step_x, step_y), component.mean, component.cov) > 4) contour = true;
            }
            if (contour) point_map[y][x] = '.';
        }
    };
    for (selected.fit.model.components, 0..) |component, j| if (cell(component.mean, p, step_x, step_y)) |position| {
        density[position[1]][position[0]] = digit(j);
    };
    const occupied = c.alloc(i64, cells);
    @memset(occupied, -1);
    var outside: usize = 0;
    for (points, 0..) |point, i| {
        const position = cell(point.xy, p, step_x, step_y) orelse {
            outside += 1;
            continue;
        };
        const index = position[1] * p.width + position[0];
        if (occupied[index] == -1) occupied[index] = c.n(selected.assigned[i]) else if (occupied[index] != c.n(selected.assigned[i])) occupied[index] = -2;
        point_map[position[1]][position[0]] = if (occupied[index] == -2) '*' else digit(c.u(occupied[index]));
    }
    map_file.add("density K={d} type={s}", .{ k, @tagName(kind) });
    map_file.add("x {s} {s} y {s} {s} grid {d}x{d}", .{ r(p.xmin), r(p.xmax), r(p.ymin), r(p.ymax), p.width, p.height });
    map_file.add("max_density {s} mass_in_map {s}", .{ report.real(fmax, 6), r(mass) });
    report.frame(&map_file, density);
    for (levels, 0..) |count, level| map_file.add("level {d} \"{c}\" from {s} cells {d}", .{ level,
         characters[level], report.real(c.f(level) * fmax / 10, 6), count });
    map_file.add("", .{});
    map_file.add("regions", .{});
    report.frame(&map_file, region);
    map_file.add("", .{});
    map_file.add("uncertainty", .{});
    report.frame(&map_file, uncertainty);
    map_file.add("", .{});
    map_file.add("points", .{});
    report.frame(&map_file, point_map);
    map_file.add("outside {d}", .{outside});
    try report.save(init.io, "models.txt", model_file);
    try report.save(init.io, "loglik_trace.csv", trace);
    try report.save(init.io, "assignments.csv", assignments);
    try report.save(init.io, "selection.txt", selection);
    try report.save(init.io, "density_map.txt", map_file);
}
