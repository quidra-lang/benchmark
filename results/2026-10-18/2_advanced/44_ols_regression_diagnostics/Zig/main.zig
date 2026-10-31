const std = @import("std");
const c = @import("dataframe.zig");
const formula = @import("formula.zig");
const qr = @import("qr_solver.zig");
const inference = @import("inference.zig");
const diagnostic = @import("diagnostics.zig");
const real = inference.real;
const pFormat = inference.pFormat;
const Row = struct { fields: []const []const u8, mark: []const u8 = "" };
fn join(values: []const []const u8, separator: []const u8) []const u8 {
    var out: c.Text = .{};
    for (values, 0..) |value, i| out.add("{s}{s}", .{ if (i == 0) "" else separator, value });
    return out.value();
}
fn repeat(character: u8, count: usize) []const u8 {
    const out = c.alloc(u8, count);
    @memset(out, character);
    return out;
}
fn integer(value: anytype) []const u8 {
    return c.fmt("{d}", .{value});
}
fn add(out: *c.Lines, values: []const []const u8) void {
    for (values) |value| out.add("{s}", .{value});
}
fn row(rows: *std.ArrayList(Row), fields: []const []const u8, mark: []const u8) void {
    c.append(Row, rows, .{ .fields = c.dupe([]const u8, fields), .mark = mark });
}
fn table(header: []const []const u8, rows: []const Row) c.Lines {
    const widths = c.alloc(usize, header.len);
    for (header, widths) |field, *width| width.* = field.len;
    for (rows) |entry| for (entry.fields, 0..) |field, j| {
        widths[j] = @max(widths[j], field.len);
    };
    var entries: std.ArrayList(Row) = .empty;
    c.append(Row, &entries, .{ .fields = header });
    for (rows) |entry| c.append(Row, &entries, entry);
    var out: c.Lines = .{};
    for (entries.items) |entry| {
        var line: c.Text = .{};
        for (entry.fields, 0..) |field, j| {
            if (j == 0) line.add("{s}{s}", .{ field, repeat(' ', widths[j] - field.len) }) else line.add("  {s}{s}",
                 .{ repeat(' ', widths[j] - field.len), field });
        }
        if (entry.mark.len > 0) line.add(" {s}", .{entry.mark});
        out.add("{s}", .{std.mem.trimEnd(u8, line.value(), " ")});
    }
    return out;
}
const Statistics = struct { n: usize, df: usize, sigma: f64, tss: f64 = 0, r2: f64 = 0, adjusted: f64 = 0,
     f: f64 = 0, f_p: f64 = 1, loglik: f64 = 0, aic: f64 = 0, bic: f64 = 0, press: f64 = 0, predicted: f64 = 0,
     critical: f64 = 0, quantiles: [5]f64 = std.mem.zeroes([5]f64) };
fn lessFloat(_: void, a: f64, b: f64) bool {
    return a < b;
}
fn lessIndex(_: void, a: usize, b: usize) bool {
    return a < b;
}
fn statistics(y: []const f64, weights: []const f64, model: qr.Fit, p: c.Params) Statistics {
    var out: Statistics = .{ .n = y.len, .df = y.len - model.rank, .sigma = @sqrt(model.rss / c.f(y.len - model.rank)) };
    var sw: f64 = 0;
    var sy: f64 = 0;
    var lw: f64 = 0;
    for (y, weights) |value, w| {
        sw += w;
        sy += w * value;
        lw += @log(w);
    }
    const mean = sy / sw;
    for (y, weights) |value, w| out.tss += w * (value - mean) * (value - mean);
    out.r2 = 1 - model.rss / out.tss;
    out.adjusted = 1 - (1 - out.r2) * c.f(out.n - 1) / c.f(out.df);
    if (model.rank > 1) {
        out.f = ((out.tss - model.rss) / c.f(model.rank - 1)) / (model.rss / c.f(out.df));
        out.f_p = inference.pF(out.f, c.f(model.rank - 1), c.f(out.df));
    }
    out.loglik = 0.5 * (lw - c.f(out.n) * (@log(2 * 3.141592653589793) + 1 - @log(c.f(out.n)) + @log(model.rss)));
    out.aic = -2 * out.loglik + 2 * c.f(model.rank + 1);
    out.bic = -2 * out.loglik + @log(c.f(out.n)) * c.f(model.rank + 1);
    for (model.weighted_residuals, model.leverage) |eps, h| {
        const value = eps / (1 - h);
        out.press += value * value;
    }
    out.predicted = 1 - out.press / out.tss;
    const residuals = c.dupe(f64, model.weighted_residuals);
    std.mem.sort(f64, residuals, {}, lessFloat);
    for (0..5) |q| {
        const g = c.f(out.n - 1) * (c.f(q) / 4);
        const k: usize = @intFromFloat(@floor(g));
        out.quantiles[q] = if (k + 1 < out.n) residuals[k] + (g - c.f(k)) * (residuals[k + 1] - residuals[k]) else residuals[k];
    }
    out.critical = inference.tQuantile(p.confidence, c.f(out.df));
    return out;
}
fn columns(x: c.Matrix, indices: []const usize) c.Matrix {
    const out = c.matrix(x.len, indices.len);
    for (x, out) |source, destination| for (indices, 0..) |j, k| {
        destination[k] = source[j];
    };
    return out;
}
const SubsetFit = struct { model: qr.Fit, stats: Statistics };
fn fitSubset(design: formula.Design, terms: []const usize, p: c.Params) SubsetFit {
    const model = qr.fit(columns(design.x, formula.selectedColumns(design, terms)), design.y, design.weights, p.rank_tol);
    return .{ .model = model, .stats = statistics(design.y, design.weights, model, p) };
}
fn subsetStatistics(design: formula.Design, terms: []const usize, p: c.Params) struct { stats: Statistics,
     rank: usize, rss: f64 } {
    const saved = c.allocator;
    var arena = std.heap.ArenaAllocator.init(saved);
    defer arena.deinit();
    c.allocator = arena.allocator();
    defer c.allocator = saved;
    const result = fitSubset(design, terms, p);
    return .{ .stats = result.stats, .rank = result.model.rank, .rss = result.model.rss };
}
const Marginal = struct { term: usize, degrees: usize, ss: f64, rss: f64, f: f64 = 0, p: f64 = 0 };
fn marginal(design: formula.Design, terms: []const usize, model: qr.Fit, stats: Statistics, p: c.Params) []const Marginal {
    var out: std.ArrayList(Marginal) = .empty;
    for (terms) |term| {
        var removable = true;
        for (terms) |other| if (formula.contained(design.formula.terms[term], design.formula.terms[other])) {
            removable = false;
        };
        if (!removable) continue;
        var remaining: std.ArrayList(usize) = .empty;
        for (terms) |other| if (other != term) c.append(usize, &remaining, other);
        const smaller = subsetStatistics(design, remaining.items, p);
        var drop: Marginal = .{ .term = term, .degrees = model.rank - smaller.rank, .rss = smaller.rss, .ss = 0 };
        drop.ss = drop.rss - model.rss;
        if (drop.degrees > 0) {
            drop.f = (drop.ss / c.f(drop.degrees)) / (model.rss / c.f(stats.df));
            drop.p = inference.pF(drop.f, c.f(drop.degrees), c.f(stats.df));
        }
        c.append(Marginal, &out, drop);
    }
    return out.items;
}
fn dataSummary(data: c.Dataframe) c.Lines {
    var out: c.Lines = .{};
    out.add("Data: {d} rows, {d} columns", .{ data.rows.len, data.names.len });
    add(&out, &.{ "", "Numeric columns:" });
    var numeric: std.ArrayList(usize) = .empty;
    var rows: std.ArrayList(Row) = .empty;
    for (data.names, 0..) |name, j| if (!data.categorical[j]) {
        c.append(usize, &numeric, j);
        var values: std.ArrayList(f64) = .empty;
        var sum: f64 = 0;
        for (data.rows) |record| if (record[j]) |value| {
            c.append(f64, &values, value.number);
            sum += value.number;
        };
        const mean = sum / c.f(values.items.len);
        var squares: f64 = 0;
        var minimum = values.items[0];
        var maximum = minimum;
        for (values.items) |value| {
            squares += (value - mean) * (value - mean);
            minimum = @min(minimum, value);
            maximum = @max(maximum, value);
        }
        row(&rows, &.{ name, integer(values.items.len), integer(data.rows.len - values.items.len),
             real(mean), real(@sqrt(squares / c.f(values.items.len - 1))), real(minimum), real(maximum) },
             "");
    };
    out.extend(table(&.{ "column", "n", "missing", "Mean", "SD", "Min", "Max" }, rows.items));
    add(&out, &.{ "", "Categorical columns:" });
    for (data.names, 0..) |name, j| if (data.categorical[j]) {
        var labels: std.ArrayList([]const u8) = .empty;
        var present: usize = 0;
        for (data.rows) |record| if (record[j]) |value| {
            present += 1;
            var found = false;
            for (labels.items) |label| if (c.eq(label, value.label)) {
                found = true;
            };
            if (!found) c.append([]const u8, &labels, value.label);
        };
        std.mem.sort([]const u8, labels.items, {}, textLess);
        var levels: std.ArrayList([]const u8) = .empty;
        for (labels.items) |label| {
            var count: usize = 0;
            for (data.rows) |record| if (record[j]) |value| {
                if (c.eq(label, value.label)) count += 1;
            };
            c.append([]const u8, &levels, c.fmt("{s} {d}", .{ label, count }));
        }
        out.add("{s}: {d} values, {d} missing, {d} levels: {s}", .{ name, present, data.rows.len - present,
             labels.items.len, join(levels.items, ", ") });
    };
    add(&out, &.{ "", "Correlations (pairwise complete observations):" });
    var header: std.ArrayList([]const u8) = .empty;
    c.append([]const u8, &header, "column");
    for (numeric.items) |j| c.append([]const u8, &header, data.names[j]);
    rows = .empty;
    for (numeric.items) |a| {
        var fields: std.ArrayList([]const u8) = .empty;
        c.append([]const u8, &fields, data.names[a]);
        for (numeric.items) |b| {
            var count: usize = 0;
            var sx: f64 = 0;
            var sy: f64 = 0;
            for (data.rows) |record| if (record[a] != null and record[b] != null) {
                count += 1;
                sx += record[a].?.number;
                sy += record[b].?.number;
            };
            const mx = sx / c.f(count);
            const my = sy / c.f(count);
            var xy: f64 = 0;
            var xx: f64 = 0;
            var yy: f64 = 0;
            for (data.rows) |record| if (record[a] != null and record[b] != null) {
                const x = record[a].?.number - mx;
                const y = record[b].?.number - my;
                xy += x * y;
                xx += x * x;
                yy += y * y;
            };
            c.append([]const u8, &fields, real(xy / @sqrt(xx * yy)));
        }
        row(&rows, fields.items, "");
    }
    out.extend(table(header.items, rows.items));
    out.add("", .{});
    return out;
}
fn textLess(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}
const Model = struct { design: formula.Design, fit_: qr.Fit, stats: Statistics, diag: diagnostic.Diagnostics,
     terms: []const usize, drops: []const Marginal, predicted: usize = 0, with_actual: usize = 0,
     covered: usize = 0, error_squares: f64 = 0 };
fn modelSummary(model: Model, input: c.Input, index: usize) c.Lines {
    const design = model.design;
    const fit_ = model.fit_;
    const stats = model.stats;
    const diag = model.diag;
    const n = design.y.len;
    const rank = fit_.rank;
    var terms: std.ArrayList([]const u8) = .empty;
    var aliases: std.ArrayList([]const u8) = .empty;
    for (design.formula.terms) |term| c.append([]const u8, &terms, term.name);
    for (design.columns, fit_.alias) |column, alias| if (alias) c.append([]const u8, &aliases, column.name);
    var out: c.Lines = .{};
    out.add("Model {d}: {s}", .{ index, design.formula.raw });
    out.add("Terms: {s}", .{join(terms.items, ", ")});
    out.add("Weights: {s}", .{if (design.formula.weight) |j| input.data.names[j] else "none"});
    out.add("Observations: {d} used, {d} dropped", .{ n, input.data.rows.len - n });
    out.add("Columns: {d}, rank {d}, aliased: {s}", .{ design.columns.len, rank, if (aliases.items.len == 0) "none" else join(aliases.items,
         ", ") });
    out.add("", .{});
    out.add("Residuals: Min {s}, 1Q {s}, Median {s}, 3Q {s}, Max {s}", .{ real(stats.quantiles[0]),
         real(stats.quantiles[1]), real(stats.quantiles[2]), real(stats.quantiles[3]), real(stats.quantiles[4]) });
    add(&out, &.{ "", "Coefficients:" });
    const errors = c.vector(design.columns.len);
    const robust = c.vector(design.columns.len);
    for (fit_.accepted, 0..) |j, k| {
        errors[j] = stats.sigma * @sqrt(fit_.variance[k]);
        var sum: f64 = 0;
        for (0..n) |i| {
            const h = fit_.leverage[i];
            const eps = fit_.weighted_residuals[i];
            const omega = eps * eps / ((1 - h) * (1 - h));
            sum += omega * fit_.g[i][k] * fit_.g[i][k];
        }
        robust[j] = @sqrt(sum);
    }
    var rows: std.ArrayList(Row) = .empty;
    for (design.columns, 0..) |column, j| {
        if (fit_.alias[j]) row(&rows, &.{ column.name, "NA", "NA", "NA", "NA" }, "") else {
            const t = fit_.coefficients[j] / errors[j];
            const p = inference.pT(t, c.f(stats.df));
            row(&rows, &.{ column.name, real(fit_.coefficients[j]), real(errors[j]), real(t), pFormat(p) },
                 inference.significance(p));
        }
    }
    out.extend(table(&.{ "term", "Estimate", "Std. Error", "t value", "Pr(>|t|)" }, rows.items));
    add(&out, &.{ "---", "Signif. codes: 0 '***' 0.001 '**' 0.01 '*' 0.05 '.' 0.1 ' ' 1", "" });
    out.add("Residual standard error: {s} on {d} degrees of freedom", .{ real(stats.sigma), stats.df });
    out.add("Multiple R-squared: {s}, Adjusted R-squared: {s}", .{ real(stats.r2), real(stats.adjusted) });
    out.add("F-statistic: {s} on {d} and {d} DF, p-value: {s}", .{ real(stats.f), rank - 1, stats.df, pFormat(stats.f_p) });
    out.add("Log-likelihood: {s}, AIC: {s}, BIC: {s}", .{ real(stats.loglik), real(stats.aic), real(stats.bic) });
    out.add("PRESS: {s}, Predicted R-squared: {s}", .{ real(stats.press), real(stats.predicted) });
    out.add("", .{});
    out.add("Confidence intervals (level {s}, t {s}):", .{ real(input.params.confidence), real(stats.critical) });
    rows = .empty;
    for (design.columns, 0..) |column, j| row(&rows, &.{ column.name, if (fit_.alias[j]) "NA" else real(fit_.coefficients[j] - stats.critical * errors[j]),
         if (fit_.alias[j]) "NA" else real(fit_.coefficients[j] + stats.critical * errors[j]) }, "");
    out.extend(table(&.{ "term", "Lower", "Upper" }, rows.items));
    add(&out, &.{ "", "Robust standard errors (HC3):" });
    rows = .empty;
    for (design.columns, 0..) |column, j| {
        if (fit_.alias[j]) row(&rows, &.{ column.name, "NA", "NA", "NA" }, "") else {
            const t = fit_.coefficients[j] / robust[j];
            const p = inference.pT(t, c.f(stats.df));
            row(&rows, &.{ column.name, real(robust[j]), real(t), pFormat(p) }, inference.significance(p));
        }
    }
    out.extend(table(&.{ "term", "Std. Error", "t value", "Pr(>|t|)" }, rows.items));
    add(&out, &.{ "", "Analysis of variance (sequential):" });
    rows = .empty;
    for (design.formula.terms, 0..) |term, t| {
        var degrees: usize = 0;
        var sum: f64 = 0;
        for (fit_.accepted, 0..) |j, k| if (design.columns[j].term == t) {
            degrees += 1;
            sum += fit_.effects[k] * fit_.effects[k];
        };
        if (degrees == 0) continue;
        const mean = sum / c.f(degrees);
        const value = mean / (fit_.rss / c.f(stats.df));
        const p = inference.pF(value, c.f(degrees), c.f(stats.df));
        row(&rows, &.{ term.name, integer(degrees), real(sum), real(mean), real(value), pFormat(p) }, inference.significance(p));
    }
    row(&rows, &.{ "Residuals", integer(stats.df), real(fit_.rss), real(fit_.rss / c.f(stats.df)) }, "");
    out.extend(table(&.{ "term", "Df", "Sum Sq", "Mean Sq", "F value", "Pr(>F)" }, rows.items));
    add(&out, &.{ "", "Marginal F tests (drop one term):" });
    rows = .empty;
    for (model.drops) |drop| row(&rows, &.{ design.formula.terms[drop.term].name, integer(drop.degrees),
         real(drop.ss), real(drop.rss), if (drop.degrees > 0) real(drop.f) else "NA", if (drop.degrees > 0) pFormat(drop.p) else "NA" },
         if (drop.degrees > 0) inference.significance(drop.p) else "");
    out.extend(table(&.{ "term", "Df", "Sum Sq", "RSS", "F value", "Pr(>F)" }, rows.items));
    add(&out, &.{ "", "Variance inflation factors:" });
    rows = .empty;
    for (fit_.accepted[1..]) |target| {
        var other: std.ArrayList(usize) = .empty;
        for (fit_.accepted) |j| if (j != target) c.append(usize, &other, j);
        const response = c.vector(n);
        var sy: f64 = 0;
        var sw: f64 = 0;
        for (0..n) |i| {
            response[i] = design.x[i][target];
            sy += design.weights[i] * response[i];
            sw += design.weights[i];
        }
        const auxiliary = qr.fit(columns(design.x, other.items), response, design.weights, input.params.rank_tol);
        const mean = sy / sw;
        var tss: f64 = 0;
        for (response, design.weights) |value, w| tss += w * (value - mean) * (value - mean);
        const r2 = 1 - auxiliary.rss / tss;
        const vif = 1 / (1 - r2);
        row(&rows, &.{ design.columns[target].name, real(vif) }, if (vif > input.params.vif) "high" else "");
    }
    out.extend(table(&.{ "column", "VIF" }, rows.items));
    add(&out, &.{ "", "Diagnostics:" });
    out.add("Durbin-Watson: {s} ({s})", .{ real(diag.durbin), if (diag.durbin < input.params.durbin) "positive autocorrelation" else if (diag.durbin > 4 - input.params.durbin) "negative autocorrelation" else "no autocorrelation" });
    out.add("Breusch-Pagan: {s} on {d} DF, p-value: {s} ({s})", .{ real(diag.bp), diag.bp_df, pFormat(diag.bp_p),
         if (diag.bp_p < input.params.breusch) "heteroscedastic" else "homoscedastic" });
    out.add("Jarque-Bera: {s} on 2 DF, p-value: {s}, skewness {s}, kurtosis {s} ({s})", .{ real(diag.jb),
         pFormat(diag.jb_p), real(diag.skewness), real(diag.kurtosis), if (diag.jb_p < input.params.normality) "non-normal" else "normal" });
    const augmented = c.matrix(n, rank + 2);
    for (0..n) |i| {
        for (fit_.accepted, 0..) |j, k| augmented[i][k] = design.x[i][j];
        augmented[i][rank] = fit_.fitted[i] * fit_.fitted[i];
        augmented[i][rank + 1] = fit_.fitted[i] * fit_.fitted[i] * fit_.fitted[i];
    }
    const reset = qr.fit(augmented, design.y, design.weights, input.params.rank_tol);
    const q = reset.rank - rank;
    const df = n - reset.rank;
    const reset_f = ((fit_.rss - reset.rss) / c.f(q)) / (reset.rss / c.f(df));
    out.add("RESET (powers 2 and 3): F {s} on {d} and {d} DF, p-value: {s}", .{ real(reset_f), q,
         df, pFormat(inference.pF(reset_f, c.f(q), c.f(df))) });
    var outlier: usize = 0;
    for (1..n) |i| if (@abs(diag.studentized[i]) > @abs(diag.studentized[outlier])) {
        outlier = i;
    };
    const unadjusted = inference.pT(diag.studentized[outlier], c.f(stats.df - 1));
    out.add("Outlier test: row {d}, studentized {s}, unadjusted p-value: {s}, Bonferroni p-value: {s}",
         .{ design.used[outlier] + 1, real(diag.studentized[outlier]), pFormat(unadjusted), pFormat(@min(1,
         c.f(n) * unadjusted)) });
    out.add("Flagged rows: leverage {d}, outlier {d}, cooks {d}, dffits {d}, any {d}", .{ diag.flag_counts[0],
         diag.flag_counts[1], diag.flag_counts[2], diag.flag_counts[3], diag.any });
    out.add("Largest Cook's distances:", .{});
    const order = c.alloc(usize, n);
    for (order, 0..) |*value, i| value.* = i;
    std.mem.sort(usize, order, @as([]const f64, diag.cooks), cookLess);
    for (order[0..@min(3, n)]) |i| out.add("row {d}: cooks_d {s}, leverage {s}, studentized {s}, flags {s}",
         .{ design.used[i] + 1, real(diag.cooks[i]), real(fit_.leverage[i]), real(diag.studentized[i]),
         diag.flags[i] });
    out.add("Largest absolute DFBETAS:", .{});
    rows = .empty;
    for (fit_.accepted, 0..) |j, k| {
        var largest: usize = 0;
        for (1..n) |i| if (@abs(diag.dfbetas[i][k]) > @abs(diag.dfbetas[largest][k])) {
            largest = i;
        };
        row(&rows, &.{ design.columns[j].name, integer(design.used[largest] + 1), real(diag.dfbetas[largest][k]) }, "");
    }
    out.extend(table(&.{ "column", "row", "DFBETAS" }, rows.items));
    return out;
}
fn cookLess(values: []const f64, a: usize, b: usize) bool {
    return if (values[a] != values[b]) values[a] > values[b] else a < b;
}
fn predictionLines(model: *Model, prediction: c.Dataframe, index: usize) c.Lines {
    var out: c.Lines = .{};
    const fit_ = model.fit_;
    const stats = model.stats;
    for (prediction.rows, 0..) |record, i| {
        if (!formula.predictable(model.design, record)) {
            out.add("{d},{d},NA,NA,NA,NA,NA,NA,NA,NA,NA", .{ index, i + 1 });
            continue;
        }
        model.predicted += 1;
        const values = formula.recordValues(model.design.columns, record);
        var value: f64 = 0;
        for (fit_.accepted) |j| value += values[j] * fit_.coefficients[j];
        var squares: f64 = 0;
        for (0..fit_.rank) |k| {
            var sum: f64 = 0;
            for (fit_.accepted, 0..) |j, m| sum += values[j] * fit_.inverse[m][k];
            squares += sum * sum;
        }
        const se = stats.sigma * @sqrt(squares);
        const confidence = stats.critical * se;
        const interval = stats.critical * @sqrt(stats.sigma * stats.sigma + se * se);
        var line: c.Text = .{};
        line.add("{d},{d},{s},{s},{s},{s},{s},{s}", .{ index, i + 1, real(value), real(se), real(value - confidence),
             real(value + confidence), real(value - interval), real(value + interval) });
        if (record[model.design.formula.response]) |actual| {
            model.with_actual += 1;
            const err = actual.number - value;
            const covered = value - interval <= actual.number and actual.number <= value + interval;
            model.covered += @intFromBool(covered);
            model.error_squares += err * err;
            line.add(",{s},{s},{s}", .{ real(actual.number), real(err), if (covered) "yes" else "no" });
        } else line.add(",NA,NA,NA", .{});
        out.add("{s}", .{line.value()});
    }
    return out;
}
const Candidate = struct { mask: usize, terms: []const usize, bic: f64, aic: f64, rank: usize };
fn candidateLess(_: void, a: Candidate, b: Candidate) bool {
    return if (a.bic != b.bic) a.bic < b.bic else a.mask < b.mask;
}
fn selection(model: Model, input: c.Input) c.Lines {
    const design = model.design;
    const p = input.params;
    var terms: std.ArrayList(usize) = .empty;
    for (model.terms) |term| c.append(usize, &terms, term);
    var out: c.Lines = .{};
    out.add("Backward elimination (model 1, alpha {s}, rows {d})", .{ real(p.alpha), design.y.len });
    var step: usize = 1;
    while (true) {
        const current = fitSubset(design, terms.items, p);
        out.add("Step {d}: {s} (RSS {s}, df {d}, AIC {s})", .{ step, formula.text(design.formula,
             terms.items, input.data), real(current.model.rss), current.stats.df, real(current.stats.aic) });
        if (terms.items.len == 0) {
            out.add("  stop: no removable terms", .{});
            break;
        }
        const drops = marginal(design, terms.items, current.model, current.stats, p);
        var selected: usize = 0;
        var largest: f64 = -1;
        for (drops) |drop| {
            out.add("  - {s}: F {s} on {d} and {d} DF, p-value {s}", .{ design.formula.terms[drop.term].name,
                 real(drop.f), drop.degrees, current.stats.df, pFormat(drop.p) });
            if (drop.p > largest) {
                largest = drop.p;
                selected = drop.term;
            }
        }
        if (largest > p.alpha) {
            out.add("  remove {s}", .{design.formula.terms[selected].name});
            _ = terms.orderedRemove(std.mem.indexOfScalar(usize, terms.items, selected).?);
            step += 1;
        } else {
            out.add("  stop: largest p-value {s} is not above {s}", .{ pFormat(largest), real(p.alpha) });
            break;
        }
    }
    out.add("Final model: {s}", .{formula.text(design.formula, terms.items, input.data)});
    out.add("", .{});
    out.add("Forward selection by AIC (model 1, rows {d})", .{design.y.len});
    terms = .empty;
    step = 1;
    while (true) {
        const current = subsetStatistics(design, terms.items, p);
        out.add("Step {d}: {s} (AIC {s})", .{ step, formula.text(design.formula, terms.items, input.data),
             real(current.stats.aic) });
        var candidates: std.ArrayList(usize) = .empty;
        for (design.formula.terms, 0..) |term, t| {
            if (std.mem.indexOfScalar(usize, terms.items, t) != null) continue;
            var eligible = true;
            for (design.formula.terms, 0..) |other, j| if (formula.contained(other, term) and std.mem.indexOfScalar(usize,
                 terms.items, j) == null) {
                eligible = false;
            };
            if (eligible) c.append(usize, &candidates, t);
        }
        if (candidates.items.len == 0) {
            out.add("  stop: no candidate terms remain", .{});
            break;
        }
        var selected: ?usize = null;
        var smallest: f64 = 0;
        for (candidates.items) |candidate| {
            var trial: std.ArrayList(usize) = .empty;
            for (terms.items) |term| c.append(usize, &trial, term);
            c.append(usize, &trial, candidate);
            std.mem.sort(usize, trial.items, {}, lessIndex);
            const aic = subsetStatistics(design, trial.items, p).stats.aic;
            out.add("  + {s}: AIC {s}", .{ design.formula.terms[candidate].name, real(aic) });
            if (selected == null or aic < smallest) {
                selected = candidate;
                smallest = aic;
            }
        }
        if (smallest < current.stats.aic) {
            out.add("  add {s}", .{design.formula.terms[selected.?].name});
            c.append(usize, &terms, selected.?);
            std.mem.sort(usize, terms.items, {}, lessIndex);
            step += 1;
        } else {
            out.add("  stop: no candidate lowers the AIC", .{});
            break;
        }
    }
    out.add("Final model: {s}", .{formula.text(design.formula, terms.items, input.data)});
    var candidates: std.ArrayList(Candidate) = .empty;
    const total = @as(usize, 1) << @as(std.math.Log2Int(usize), @intCast(design.formula.terms.len));
    for (0..total) |mask| {
        var included: std.ArrayList(usize) = .empty;
        for (0..design.formula.terms.len) |t| if (mask & (@as(usize, 1) << @as(std.math.Log2Int(usize),
             @intCast(t))) != 0) c.append(usize, &included, t);
        var hierarchical = true;
        for (included.items) |t| for (design.formula.terms, 0..) |other, j| {
            if (formula.contained(other, design.formula.terms[t]) and mask & (@as(usize, 1) << @as(std.math.Log2Int(usize),
                 @intCast(j))) == 0) hierarchical = false;
        };
        if (!hierarchical) continue;
        const candidate = subsetStatistics(design, included.items, p);
        c.append(Candidate, &candidates, .{ .mask = mask, .terms = included.items, .bic = candidate.stats.bic,
             .aic = candidate.stats.aic, .rank = candidate.rank });
    }
    std.mem.sort(Candidate, candidates.items, {}, candidateLess);
    out.add("", .{});
    out.add("Best subsets by BIC (model 1, rows {d}, subsets {d})", .{ design.y.len, candidates.items.len });
    for (candidates.items[0..@min(p.best_subsets, candidates.items.len)], 1..) |candidate, i| out.add("{d}. BIC {s}, AIC {s}, rank {d}: {s}",
         .{ i, real(candidate.bic), real(candidate.aic), candidate.rank, formula.text(design.formula,
         candidate.terms, input.data) });
    return out;
}
const Plot = struct { counts: [][]usize, rows: []usize };
fn countPlot(horizontal: []const f64, vertical: []const f64, low: f64, high: f64, p: c.Params) Plot {
    const counts = c.alloc([]usize, p.plot_height);
    const rows = c.alloc(usize, p.plot_height);
    @memset(rows, 0);
    for (counts) |*values| {
        values.* = c.alloc(usize, p.plot_width);
        @memset(values.*, 0);
    }
    for (horizontal, vertical) |x, y| {
        const column = @min(@as(usize, @intFromFloat(@floor((x - low) / (high - low) * c.f(p.plot_width)))), p.plot_width - 1);
        const raw: i64 = @intFromFloat(@floor((p.plot_limit - y) / (2 * p.plot_limit) * c.f(p.plot_height)));
        const r = c.u(@max(0, @min(c.n(p.plot_height) - 1, raw)));
        counts[r][column] += 1;
        rows[r] += 1;
    }
    return .{ .counts = counts, .rows = rows };
}
fn frame(chart: Plot, p: c.Params) c.Lines {
    var out: c.Lines = .{};
    const border = c.fmt("+{s}+", .{repeat('-', p.plot_width)});
    out.add("{s}", .{border});
    for (chart.counts, 0..) |values, r| {
        var line: c.Text = .{};
        line.add("|", .{});
        for (values) |count| line.add("{c}", .{if (count >= 10) @as(u8, '*') else if (count > 0) @as(u8,
             @intCast('0' + count)) else if (r == p.plot_height / 2) @as(u8, '-') else @as(u8, '.')});
        line.add("|", .{});
        out.add("{s}", .{line.value()});
    }
    out.add("{s}", .{border});
    return out;
}
fn residualPlots(models: []const Model, p: c.Params) c.Lines {
    var out: c.Lines = .{};
    for (models, 0..) |model, index| {
        if (index > 0) out.add("", .{});
        var low = model.fit_.fitted[0];
        var high = low;
        var max_h: f64 = 0;
        for (model.fit_.fitted, model.fit_.leverage) |value, h| {
            low = @min(low, value);
            high = @max(high, value);
            max_h = @max(max_h, h);
        }
        out.add("Model {d}: studentized residuals vs fitted values", .{index + 1});
        out.add("fitted {s} to {s}, studentized {s} to {s}", .{ real(low), real(high), real(-p.plot_limit), real(p.plot_limit) });
        const chart = countPlot(model.fit_.fitted, model.diag.studentized, low, high, p);
        out.extend(frame(chart, p));
        var above: usize = 0;
        var below: usize = 0;
        var outside: usize = 0;
        for (model.diag.studentized) |value| {
            above += @intFromBool(value > 2);
            below += @intFromBool(value < -2);
            outside += @intFromBool(@abs(value) > p.plot_limit);
        }
        out.add("points: {d}, above +2: {d}, below -2: {d}, outside range: {d}", .{ model.design.y.len, above, below, outside });
        out.add("Histogram of studentized residuals:", .{});
        var maximum: usize = 0;
        for (chart.rows) |count| maximum = @max(maximum, count);
        for (chart.rows, 0..) |count, r| {
            const length = (count * 40 + maximum - 1) / maximum;
            out.add("{s} to {s}: {d}{s}{s}", .{ real(p.plot_limit - 2 * p.plot_limit * c.f(r + 1) / c.f(p.plot_height)),
                 real(p.plot_limit - 2 * p.plot_limit * c.f(r) / c.f(p.plot_height)), count, if (length > 0) " " else "",
                 repeat('#', length) });
        }
        out.add("Model {d}: studentized residuals vs leverage", .{index + 1});
        out.add("leverage 0.0000 to {s}, studentized {s} to {s}", .{ real(max_h), real(-p.plot_limit), real(p.plot_limit) });
        out.extend(frame(countPlot(model.fit_.leverage, model.diag.studentized, 0, max_h, p), p));
    }
    return out;
}
fn write(io: std.Io, name: []const u8, lines: c.Lines) !void {
    var out: c.Text = .{};
    for (lines.data.items) |line| out.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = c.fmt("output/{s}", .{name}), .data = out.value() });
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    c.allocator = arena.allocator();
    try std.Io.Dir.cwd().createDirPath(init.io, "output");
    const input = try c.readInput(init.io);
    var models: std.ArrayList(Model) = .empty;
    for (input.formulas) |line| {
        const design = formula.build(formula.parse(line, input.data), input.data);
        const fit_ = qr.fit(design.x, design.y, design.weights, input.params.rank_tol);
        const stats = statistics(design.y, design.weights, fit_, input.params);
        const diag = diagnostic.diagnostics(design.x, fit_, input.params);
        const terms = c.alloc(usize, design.formula.terms.len);
        for (terms, 0..) |*term, i| term.* = i;
        c.append(Model, &models, .{ .design = design, .fit_ = fit_, .stats = stats, .diag = diag,
             .terms = terms, .drops = marginal(design, terms, fit_, stats, input.params) });
    }
    var summary = dataSummary(input.data);
    var diagnostic_lines: c.Lines = .{};
    diagnostic_lines.add("model,row,fitted,residual,leverage,studentized,cooks_d,dffits,flags", .{});
    var predictions: c.Lines = .{};
    predictions.add("model,row,fit,se_fit,conf_lower,conf_upper,pred_lower,pred_upper,actual,error,covered", .{});
    for (models.items, 0..) |*model, i| {
        if (i > 0) summary.add("", .{});
        summary.extend(modelSummary(model.*, input, i + 1));
        predictions.extend(predictionLines(model, input.prediction, i + 1));
        for (0..model.design.y.len) |r| diagnostic_lines.add("{d},{d},{s},{s},{s},{s},{s},{s},{s}",
             .{ i + 1, model.design.used[r] + 1, real(model.fit_.fitted[r]), real(model.fit_.residuals[r]),
             real(model.fit_.leverage[r]), real(model.diag.studentized[r]), real(model.diag.cooks[r]),
             real(model.diag.dffits[r]), model.diag.flags[r] });
    }
    add(&summary, &.{ "", "Model comparison:" });
    var comparison: std.ArrayList(Row) = .empty;
    for (models.items, 1..) |model, i| row(&comparison, &.{ integer(i), integer(model.design.y.len),
         integer(model.fit_.rank), real(model.stats.sigma), real(model.stats.r2), real(model.stats.adjusted),
         real(model.stats.predicted), real(model.stats.aic), real(model.stats.bic) }, "");
    summary.extend(table(&.{ "model", "n", "rank", "sigma", "R-squared", "Adj. R-squared", "Pred. R-squared",
         "AIC", "BIC" }, comparison.items));
    add(&summary, &.{ "", "Prediction check:" });
    for (models.items, 1..) |model, i| summary.add("model {d}: {d} predicted, {d} with actual values, RMSE {s}, inside prediction interval {d}",
         .{ i, model.predicted, model.with_actual, if (model.with_actual > 0) real(@sqrt(model.error_squares / c.f(model.with_actual))) else "NA",
         model.covered });
    try write(init.io, "summary.txt", summary);
    try write(init.io, "diagnostics.csv", diagnostic_lines);
    try write(init.io, "selection.txt", selection(models.items[0], input));
    try write(init.io, "predictions.csv", predictions);
    try write(init.io, "residual_plot.txt", residualPlots(models.items, input.params));
}
