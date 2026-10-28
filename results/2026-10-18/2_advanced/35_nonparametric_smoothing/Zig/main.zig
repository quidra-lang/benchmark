const std = @import("std");
const d = @import("dataset.zig");
const kernels = @import("kernels.zig");
const loess = @import("loess.zig");
const spline_module = @import("spline.zig");
const selection = @import("selection.zig");
const Text = struct {
    data: std.ArrayList(u8) = .empty,
    fn add(self: *Text, comptime pattern: []const u8, args: anytype) void {
        self.data.appendSlice(d.allocator, d.fmt(pattern, args)) catch @panic("allocation failed");
    }
    fn value(self: Text) []const u8 {
        return self.data.items;
    }
};
const Lines = struct {
    data: std.ArrayList([]const u8) = .empty,
    fn add(self: *Lines, comptime pattern: []const u8, args: anytype) void {
        d.append([]const u8, &self.data, d.fmt(pattern, args));
    }
    fn extend(self: *Lines, other: Lines) void {
        for (other.data.items) |line| self.add("{s}", .{line});
    }
};
fn sum(values: []const f64) f64 {
    var total: f64 = 0;
    for (values) |value| total += value;
    return total;
}
fn rss(observed: []const f64, fitted: []const f64) f64 {
    var total: f64 = 0;
    for (observed, fitted) |value, fit| {
        const error_ = value - fit;
        total += error_ * error_;
    }
    return total;
}
const IsoBlock = struct { first: usize, last: usize, sum: i64, count: usize };
const IsoFit = struct { fitted: []f64, blocks: []IsoBlock };
fn pava(data: d.Data, direction: []const u8) IsoFit {
    var blocks: std.ArrayList(IsoBlock) = .empty;
    for (data.y, 0..) |y, i| {
        d.append(IsoBlock, &blocks, .{ .first = i, .last = i, .sum = y, .count = 1 });
        while (blocks.items.len >= 2) {
            const a = blocks.items[blocks.items.len - 2];
            const b = blocks.items[blocks.items.len - 1];
            const violate = if (d.eq(direction, "increasing")) a.sum * d.n(b.count) > b.sum * d.n(a.count) else a.sum * d.n(b.count) < b.sum * d.n(a.count);
            if (!violate) break;
            blocks.items.len -= 1;
            blocks.items[blocks.items.len - 1] = .{ .first = a.first, .last = b.last, .sum = a.sum + b.sum,
                 .count = a.count + b.count };
        }
    }
    const fitted = d.alloc(f64, data.x.len);
    for (blocks.items) |block| @memset(fitted[block.first .. block.last + 1], d.f(block.sum) / d.f(100 * block.count));
    return .{ .fitted = fitted, .blocks = blocks.items };
}
fn nearest(data: d.Data, position: i64) usize {
    var best: usize = 0;
    for (1..data.x.len) |i| if (@abs(data.x[i] - position) < @abs(data.x[best] - position)) {
        best = i;
    };
    return best;
}
const Fit = struct { data: d.Data, method: d.Method, parameter: d.Parameter, fitted: []f64 = &.{},
     leverage: []f64 = &.{}, rho: []f64 = &.{}, edf: ?f64 = null, intercept: f64 = 0, slope: f64 = 0,
     xbar: f64 = 0, sxx: f64 = 0, spline: ?*spline_module.Spline = null, spline_values: spline_module.Values = .{ .fitted = &.{},
     .gamma = &.{} }, blocks: []IsoBlock = &.{}, robust: []loess.Robust = &.{}, direction: []const u8 = "",
     increasing_rss: f64 = 0, decreasing_rss: f64 = 0, defined: bool = true };
fn integerLess(_: void, a: i64, b: i64) bool {
    return a < b;
}
fn realLess(_: void, a: f64, b: f64) bool {
    return a < b;
}
fn makeFit(data: d.Data, method: d.Method, parameter: d.Parameter, direction: []const u8, robust_iterations: usize,
     full: bool) Fit {
    var fit: Fit = .{ .data = data, .method = method, .parameter = parameter };
    const n = data.x.len;
    switch (method.kind) {
        .linear => {
            fit.xbar = sum(data.real_x) / d.f(n);
            const ybar = sum(data.real_y) / d.f(n);
            var sxy: f64 = 0;
            for (data.real_x, data.real_y) |x, y| {
                fit.sxx += (x - fit.xbar) * (x - fit.xbar);
                sxy += (x - fit.xbar) * (y - ybar);
            }
            fit.slope = sxy / fit.sxx;
            fit.intercept = ybar - fit.slope * fit.xbar;
            fit.edf = 2;
            fit.fitted = d.alloc(f64, n);
            fit.leverage = d.alloc(f64, n);
            for (data.real_x, fit.fitted, fit.leverage) |x, *value, *lev| {
                value.* = fit.intercept + fit.slope * x;
                lev.* = 1 / d.f(n) + (x - fit.xbar) * (x - fit.xbar) / fit.sxx;
            }
        },
        .mean, .median => {
            const k = d.u(@divTrunc(parameter.integer - 1, 2));
            fit.fitted = d.alloc(f64, n);
            fit.leverage = d.alloc(f64, n);
            for (fit.fitted, 0..) |*value, i| {
                const radius = @min(k, @min(i, n - 1 - i));
                const count = 2 * radius + 1;
                var total: i64 = 0;
                const values = d.alloc(i64, count);
                for (data.y[i - radius .. i + radius + 1], values) |y, *target| {
                    total += y;
                    target.* = y;
                }
                if (method.kind == .mean) {
                    value.* = d.f(total) / d.f(100 * count);
                    fit.leverage[i] = 1 / d.f(count);
                } else {
                    std.mem.sort(i64, values, {}, integerLess);
                    value.* = d.f(values[radius]) / 100;
                }
            }
            if (method.kind == .mean) fit.edf = sum(fit.leverage);
        },
        .nw, .ll => {
            if (full) {
                fit.fitted = d.alloc(f64, n);
                fit.leverage = d.alloc(f64, n);
                for (data.x, fit.fitted, fit.leverage) |position, *value, *lev| {
                    const local = kernels.estimate(data, method.kernel, parameter.integer, position, method.kind == .ll);
                    if (local.estimate == null) {
                        fit.defined = false;
                        break;
                    }
                    value.* = local.estimate.?;
                    lev.* = local.leverage.?;
                }
                if (fit.defined) fit.edf = sum(fit.leverage);
            }
        },
        .loess => {
            if (full) {
                const local = loess.fit(data, parameter.integer, method.degree, robust_iterations);
                fit.fitted = local.fitted;
                fit.leverage = local.leverage;
                fit.rho = local.rho;
                fit.robust = local.iterations;
                fit.edf = local.edf;
            } else {
                fit.rho = d.alloc(f64, n);
                @memset(fit.rho, 1);
            }
        },
        .spline => {
            fit.spline = spline_module.Spline.init(data.x, parameter.value);
            fit.spline_values = fit.spline.?.fit(data.real_y);
            fit.fitted = fit.spline_values.fitted;
            if (full) {
                fit.leverage = fit.spline.?.leverage();
                fit.edf = sum(fit.leverage);
            }
        },
        .isotonic => {
            fit.direction = direction;
            var selected: IsoFit = undefined;
            if (d.eq(direction, "auto")) {
                const increasing = pava(data, "increasing");
                const decreasing = pava(data, "decreasing");
                fit.increasing_rss = rss(data.real_y, increasing.fitted);
                fit.decreasing_rss = rss(data.real_y, decreasing.fitted);
                fit.direction = if (fit.increasing_rss <= fit.decreasing_rss) "increasing" else "decreasing";
                selected = if (d.eq(fit.direction, "increasing")) increasing else decreasing;
            } else selected = pava(data, direction);
            fit.fitted = selected.fitted;
            fit.blocks = selected.blocks;
            fit.edf = d.f(fit.blocks.len);
            fit.parameter.text = fit.direction;
        },
    }
    return fit;
}
fn estimate(fit: Fit, position: i64) ?f64 {
    return switch (fit.method.kind) {
        .linear => fit.intercept + fit.slope * (d.f(position) / 100),
        .mean, .median => fit.fitted[nearest(fit.data, position)],
        .nw, .ll => kernels.estimate(fit.data, fit.method.kernel, fit.parameter.integer, position,
             fit.method.kind == .ll).estimate,
        .loess => loess.localFit(fit.data, position, fit.parameter.integer, fit.method.degree, fit.rho).value,
        .spline => fit.spline.?.evaluate(fit.spline_values, position),
        .isotonic => value: {
            var index: usize = 0;
            while (index + 1 < fit.data.x.len and fit.data.x[index + 1] <= position) index += 1;
            break :value fit.fitted[index];
        },
    };
}
fn weights(fit: Fit, position: i64) []f64 {
    const data = fit.data;
    const n = data.x.len;
    switch (fit.method.kind) {
        .linear => {
            const values = d.alloc(f64, n);
            const x0 = d.f(position) / 100;
            for (values, data.real_x) |*value, x| value.* = 1 / d.f(n) + (x0 - fit.xbar) * (x - fit.xbar) / fit.sxx;
            return values;
        },
        .mean => {
            const values = d.zero(f64, n);
            const c = nearest(data, position);
            const radius = @min(d.u(@divTrunc(fit.parameter.integer - 1, 2)), @min(c, n - 1 - c));
            @memset(values[c - radius .. c + radius + 1], 1 / d.f(2 * radius + 1));
            return values;
        },
        .nw, .ll => return kernels.estimate(data, fit.method.kernel, fit.parameter.integer, position,
             fit.method.kind == .ll).weights,
        .loess => return loess.localFit(data, position, fit.parameter.integer, fit.method.degree, fit.rho).weights,
        .spline => return fit.spline.?.weights(position),
        else => unreachable,
    }
}
fn subset(data: d.Data, excluded: ?usize, fold: ?usize, folds: usize) d.Data {
    var indices: std.ArrayList(usize) = .empty;
    for (0..data.x.len) |i| {
        if (excluded != null and i == excluded.?) continue;
        if (fold != null and i % folds == fold.?) continue;
        d.append(usize, &indices, i);
    }
    const out: d.Data = .{ .x = d.alloc(i64, indices.items.len), .y = d.alloc(i64, indices.items.len),
         .real_x = d.alloc(f64, indices.items.len), .real_y = d.alloc(f64, indices.items.len) };
    for (indices.items, 0..) |i, j| {
        out.x[j] = data.x[i];
        out.y[j] = data.y[i];
        out.real_x[j] = data.real_x[i];
        out.real_y[j] = data.real_y[i];
    }
    return out;
}
fn crossValidation(data: d.Data, method: d.Method, parameter: d.Parameter, direction: []const u8, folds: usize) ?f64 {
    const predictions = d.alloc(?f64, data.x.len);
    const parent = d.allocator;
    if (folds == 0) {
        for (data.x, 0..) |position, i| {
            var arena = std.heap.ArenaAllocator.init(parent);
            d.allocator = arena.allocator();
            const training = subset(data, i, null, 0);
            const fit = makeFit(training, method, parameter, direction, 0, false);
            predictions[i] = estimate(fit, position);
            d.allocator = parent;
            arena.deinit();
        }
    } else for (0..folds) |fold| {
        var arena = std.heap.ArenaAllocator.init(parent);
        d.allocator = arena.allocator();
        const training = subset(data, null, fold, folds);
        const fit = makeFit(training, method, parameter, direction, 0, false);
        for (data.x, 0..) |position, i| if (i % folds == fold) {
            predictions[i] = estimate(fit, position);
        };
        d.allocator = parent;
        arena.deinit();
    };
    return selection.looScore(data.real_y, predictions);
}
fn methods(p: d.Params) []d.Method {
    var out: std.ArrayList(d.Method) = .empty;
    d.append(d.Method, &out, .{ .name = "linear", .kind = .linear });
    d.append(d.Method, &out, .{ .name = "running_mean", .kind = .mean });
    d.append(d.Method, &out, .{ .name = "running_median", .kind = .median });
    for (p.rows[1]) |kernel| d.append(d.Method, &out, .{ .name = d.fmt("nw_{s}", .{kernel}), .kind = .nw, .kernel = kernel });
    for (p.rows[1]) |kernel| d.append(d.Method, &out, .{ .name = d.fmt("ll_{s}", .{kernel}), .kind = .ll, .kernel = kernel });
    for (p.rows[3]) |degree| d.append(d.Method, &out, .{ .name = d.fmt("loess{s}", .{degree}), .kind = .loess,
         .degree = d.u(d.integer(degree)) });
    d.append(d.Method, &out, .{ .name = "spline", .kind = .spline });
    d.append(d.Method, &out, .{ .name = "isotonic", .kind = .isotonic });
    for (out.items) |*method| {
        const row: ?usize = switch (method.kind) {
            .mean, .median => 0,
            .nw, .ll => 2,
            .loess => 4,
            .spline => 6,
            else => null,
        };
        const index = row orelse continue;
        method.candidates = d.alloc(d.Parameter, p.rows[index].len);
        for (p.rows[index], method.candidates) |text, *parameter| parameter.* = .{ .text = text, .value = d.real(text),
             .integer = if (index == 0) d.integer(text) else if (index == 2 or index == 4) d.hundredths(text) else 0 };
    }
    return out.items;
}
fn real(value: ?f64) []const u8 {
    const number = value orelse return "NA";
    const text = d.fmt("{d:.4}", .{number});
    return if (d.eq(text, "-0.0000")) "0.0000" else text;
}
fn positionText(value: i64) []const u8 {
    const magnitude = @abs(value);
    return d.fmt("{s}{d}.{d:0>2}", .{ if (value < 0) "-" else "", magnitude / 100, magnitude % 100 });
}
fn methodIndex(methods_: []const d.Method, name: []const u8) usize {
    for (methods_, 0..) |method, i| if (d.eq(method.name, name)) return i;
    unreachable;
}
const Diagnostic = struct { residuals: []f64, rss: f64 = 0, r2: f64 = 0, dw: f64 = 0, z: f64 = 0,
     df: ?f64 = null, rse: ?f64 = null, nonlinear: ?f64 = null, acf: [5]f64 = @splat(0), quantiles: [5]f64 = @splat(0),
     runs: i64 = 0, positive: i64 = 0, negative: i64 = 0, turning: usize = 0, largest: usize = 0 };
fn diagnose(fit: Fit, linear_rss: f64, grid: []const ?f64) Diagnostic {
    const n = fit.data.x.len;
    var out: Diagnostic = .{ .residuals = d.alloc(f64, n) };
    const mean = sum(fit.data.real_y) / d.f(n);
    var tss: f64 = 0;
    for (fit.data.real_y, fit.fitted, out.residuals, 0..) |y, value, *residual, i| {
        residual.* = y - value;
        out.rss += residual.* * residual.*;
        tss += (y - mean) * (y - mean);
        if (@abs(residual.*) > @abs(out.residuals[out.largest])) out.largest = i;
    }
    out.r2 = 1 - out.rss / tss;
    if (fit.edf) |edf| {
        out.df = d.f(n) - edf;
        out.rse = @sqrt(out.rss / out.df.?);
        if (fit.method.kind != .linear and edf > 2) out.nonlinear = ((linear_rss - out.rss) / (edf - 2)) / (out.rss / out.df.?);
    }
    const residual_mean = sum(out.residuals) / d.f(n);
    var denominator: f64 = 0;
    for (out.residuals) |residual| denominator += (residual - residual_mean) * (residual - residual_mean);
    for (1..6) |k| {
        var numerator: f64 = 0;
        for (0..n - k) |i| numerator += (out.residuals[i] - residual_mean) * (out.residuals[i + k] - residual_mean);
        out.acf[k - 1] = numerator / denominator;
    }
    var dw: f64 = 0;
    for (1..n) |i| dw += (out.residuals[i] - out.residuals[i - 1]) * (out.residuals[i] - out.residuals[i - 1]);
    out.dw = dw / out.rss;
    var sign: i8 = 0;
    for (out.residuals) |residual| {
        if (residual == 0) continue;
        const current: i8 = if (residual > 0) 1 else -1;
        if (current > 0) out.positive += 1 else out.negative += 1;
        if (current != sign) {
            out.runs += 1;
            sign = current;
        }
    }
    const nonzero = out.positive + out.negative;
    const product = 2 * out.positive * out.negative;
    const mu = 1 + d.f(product) / d.f(nonzero);
    const variance = d.f(product * (product - nonzero)) / d.f(nonzero * nonzero * (nonzero - 1));
    out.z = (d.f(out.runs) - mu) / @sqrt(variance);
    const sorted = d.alloc(f64, n);
    @memcpy(sorted, out.residuals);
    std.mem.sort(f64, sorted, {}, realLess);
    for (&out.quantiles, 0..) |*value, k| {
        const j = (n - 1) * k / 4;
        const remainder = (n - 1) * k - 4 * j;
        value.* = if (remainder == 0) sorted[j] else sorted[j] + d.f(remainder) / 4 * (sorted[j + 1] - sorted[j]);
    }
    var previous: ?f64 = null;
    var previous_sign: i8 = 0;
    for (grid) |value| {
        const defined = value orelse continue;
        if (previous) |old| {
            const delta = defined - old;
            if (delta != 0) {
                const current: i8 = if (delta > 0) 1 else -1;
                if (previous_sign != 0 and previous_sign != current) out.turning += 1;
                previous_sign = current;
            }
        }
        previous = defined;
    }
    return out;
}
const SelectionRow = struct { method: usize, candidate: usize, score: ?f64, edf: ?f64, selected: bool };
const Study = struct { series: d.Series, fits: []Fit, loo: []?f64, kfold: []?f64, selection: []SelectionRow,
     grid: []i64, estimates: [][]?f64, diagnostics: []Diagnostic, ranking: []usize, best: usize, outlier: usize,
     standardized: []f64, cook: []f64 };
fn rankLess(scores: []const ?f64, a: usize, b: usize) bool {
    return if (scores[a].? != scores[b].?) scores[a].? < scores[b].? else a < b;
}
fn study(series: d.Series, p: d.Params, methods_: []const d.Method, series_index: usize) Study {
    const robust = d.u(d.integer(p.rows[5][0]));
    const folds = d.u(d.integer(p.rows[7][0]));
    const fits = d.alloc(Fit, methods_.len);
    const loo = d.alloc(?f64, methods_.len);
    const kfold = d.alloc(?f64, methods_.len);
    var records: std.ArrayList(SelectionRow) = .empty;
    for (methods_, fits, 0..) |method, *fit, m| {
        const direction = p.rows[8][series_index];
        var parameter: d.Parameter = .{};
        var score: ?f64 = null;
        if (method.candidates.len > 0) {
            const scores = d.alloc(?f64, method.candidates.len);
            const edfs = d.alloc(?f64, method.candidates.len);
            for (method.candidates, scores, edfs) |candidate, *candidate_score, *edf| {
                const parent = d.allocator;
                var arena = std.heap.ArenaAllocator.init(parent);
                d.allocator = arena.allocator();
                const candidate_fit = makeFit(series.data, method, candidate, direction, 0, true);
                candidate_score.* = if (method.kind == .spline) selection.gcvScore(series.data.real_y,
                     candidate_fit.fitted, candidate_fit.edf.?) else crossValidation(series.data,
                     method, candidate, direction, 0);
                edf.* = candidate_fit.edf;
                d.allocator = parent;
                arena.deinit();
            }
            const selected = selection.selected(scores);
            parameter = method.candidates[selected];
            score = scores[selected];
            for (scores, edfs, 0..) |candidate_score, edf, c| d.append(SelectionRow, &records, .{ .method = m,
                 .candidate = c, .score = candidate_score, .edf = edf, .selected = c == selected });
        }
        fit.* = makeFit(series.data, method, parameter, direction, robust, true);
        loo[m] = if (method.kind == .linear or method.kind == .spline or method.kind == .isotonic) crossValidation(series.data,
             method, parameter, fit.direction, 0) else score;
        kfold[m] = crossValidation(series.data, method, parameter, fit.direction, folds);
    }
    const data = series.data;
    const count = d.u(d.integer(p.rows[9][0]));
    const grid = d.alloc(i64, count);
    for (grid, 0..) |*value, k| value.* = data.x[0] + @divTrunc(d.n(k) * (data.x[data.x.len - 1] - data.x[0]), d.n(count - 1));
    const estimates = d.alloc([]?f64, fits.len);
    for (fits, estimates) |fit, *values| {
        values.* = d.alloc(?f64, count);
        for (grid, values.*) |position, *value| value.* = estimate(fit, position);
    }
    const diagnostics = d.alloc(Diagnostic, fits.len);
    const linear_rss = rss(data.real_y, fits[0].fitted);
    for (fits, estimates, diagnostics) |fit, values, *diagnostic| diagnostic.* = diagnose(fit, linear_rss, values);
    const ranking = d.alloc(usize, fits.len);
    for (ranking, 0..) |*value, i| value.* = i;
    std.mem.sort(usize, ranking, @as([]const ?f64, loo), rankLess);
    const best = ranking[0];
    var outlier: usize = 0;
    for (ranking) |m| if (methods_[m].kind != .median and methods_[m].kind != .isotonic) {
        outlier = m;
        break;
    };
    const standardized = d.zero(f64, data.x.len);
    const cook = d.zero(f64, data.x.len);
    const fit = fits[outlier];
    const diagnostic = diagnostics[outlier];
    for (fit.leverage, diagnostic.residuals, standardized, cook) |leverage, residual, *t, *distance| if (leverage < 1) {
        t.* = residual / (diagnostic.rse.? * @sqrt(1 - leverage));
        distance.* = t.* * t.* * leverage / ((1 - leverage) * fit.edf.?);
    };
    return .{ .series = series, .fits = fits, .loo = loo, .kfold = kfold, .selection = records.items,
         .grid = grid, .estimates = estimates, .diagnostics = diagnostics, .ranking = ranking, .best = best,
         .outlier = outlier, .standardized = standardized, .cook = cook };
}
fn standardError(fit: Fit, diagnostic: Diagnostic, position: i64) f64 {
    const values = weights(fit, position);
    var total: f64 = 0;
    for (values) |value| total += value * value;
    return diagnostic.rse.? * @sqrt(total);
}
fn minimumY(data: d.Data) i64 {
    var value = data.y[0];
    for (data.y) |y| value = @min(value, y);
    return value;
}
fn maximumY(data: d.Data) i64 {
    var value = data.y[0];
    for (data.y) |y| value = @max(value, y);
    return value;
}
fn magnitudeLess(values: []const f64, a: usize, b: usize) bool {
    return if (@abs(values[a]) != @abs(values[b])) @abs(values[a]) > @abs(values[b]) else a < b;
}
fn influenceLess(values: []const f64, a: usize, b: usize) bool {
    return if (values[a] != values[b]) values[a] > values[b] else a < b;
}
fn diagnosticsLines(s: Study, p: d.Params, methods_: []const d.Method) Lines {
    const data = s.series.data;
    var out: Lines = .{};
    out.add("series {s} n {d} x {s} {s} y {s} {s}", .{ s.series.name, data.x.len, positionText(data.x[0]),
         positionText(data.x[data.x.len - 1]), positionText(minimumY(data)), positionText(maximumY(data)) });
    for (methods_, s.fits, s.diagnostics, 0..) |method, fit, diagnostic, m| {
        var first: Text = .{};
        first.add("method {s} parameter {s} loo {s}", .{ method.name, fit.parameter.text, real(s.loo[m]) });
        if (method.kind == .spline) for (s.selection) |row| {
            if (row.method == m and row.selected) first.add(" gcv {s}", .{real(row.score)});
        };
        out.add("{s}", .{first.value()});
        out.add("  rss {s} edf {s} df {s} rse {s} r2 {s} f_nonlinear {s}", .{ real(diagnostic.rss),
             real(fit.edf), real(diagnostic.df), real(diagnostic.rse), real(diagnostic.r2), real(diagnostic.nonlinear) });
        out.add("  acf {s} {s} {s} {s} {s} dw {s}", .{ real(diagnostic.acf[0]), real(diagnostic.acf[1]),
             real(diagnostic.acf[2]), real(diagnostic.acf[3]), real(diagnostic.acf[4]), real(diagnostic.dw) });
        out.add("  runs {d} positive {d} negative {d} z {s}", .{ diagnostic.runs, diagnostic.positive,
             diagnostic.negative, real(diagnostic.z) });
        out.add("  max_residual {s} at {s} turning {d}", .{ real(diagnostic.residuals[diagnostic.largest]),
             positionText(data.x[diagnostic.largest]), diagnostic.turning });
        out.add("  quantiles {s} {s} {s} {s} {s}", .{ real(diagnostic.quantiles[0]), real(diagnostic.quantiles[1]),
             real(diagnostic.quantiles[2]), real(diagnostic.quantiles[3]), real(diagnostic.quantiles[4]) });
        if (method.kind == .loess) {
            for (fit.robust, 1..) |record, t| out.add("  robust {d} scale {s} zero_weight {d} max_change {s}",
                 .{ t, real(record.scale), record.zero, real(record.change) });
            var zero: Text = .{};
            zero.add("  zero_weight_points", .{});
            var any = false;
            for (fit.rho, data.x) |weight, x| if (weight == 0) {
                zero.add(" {s}", .{positionText(x)});
                any = true;
            };
            if (!any) zero.add(" none", .{});
            out.add("{s}", .{zero.value()});
        }
    }
    out.add("ranking", .{});
    for (s.ranking, 1..) |m, rank| out.add("  {d} {s} {s} kfold {s}", .{ rank, methods_[m].name, real(s.loo[m]),
         real(s.kfold[m]) });
    out.add("agreement with {s}", .{methods_[s.best].name});
    for (methods_, 0..) |method, m| {
        if (m == s.best) continue;
        var count: usize = 0;
        var at: usize = 0;
        var squared: f64 = 0;
        var maximum: f64 = -1;
        for (s.grid, 0..) |_, k| {
            if (s.estimates[m][k] == null or s.estimates[s.best][k] == null) continue;
            count += 1;
            const delta = @abs(s.estimates[m][k].? - s.estimates[s.best][k].?);
            squared += delta * delta;
            if (delta > maximum) {
                maximum = delta;
                at = k;
            }
        }
        out.add("  {s} points {d} rms {s} max {s} at {s}", .{ method.name, count, real(@sqrt(squared / d.f(count))),
             real(maximum), positionText(s.grid[at]) });
    }
    const spline_index = methodIndex(methods_, "spline");
    var maximum: f64 = 0;
    var minimum: f64 = 0;
    var max_at: usize = 1;
    var min_at: usize = 1;
    for (1..s.grid.len - 1) |k| {
        const slope = (s.estimates[spline_index][k + 1].? - s.estimates[spline_index][k - 1].?) / (d.f(s.grid[k + 1] - s.grid[k - 1]) / 100);
        if (k == 1 or slope > maximum) {
            maximum = slope;
            max_at = k;
        }
        if (k == 1 or slope < minimum) {
            minimum = slope;
            min_at = k;
        }
    }
    out.add("slope spline max {s} at {s} min {s} at {s}", .{ real(maximum), positionText(s.grid[max_at]),
         real(minimum), positionText(s.grid[min_at]) });
    const fit = s.fits[s.outlier];
    const diagnostic = s.diagnostics[s.outlier];
    const threshold = d.f(d.hundredths(p.rows[12][0])) / 100;
    out.add("outliers method {s} threshold {s}", .{ methods_[s.outlier].name, positionText(d.hundredths(p.rows[12][0])) });
    var outliers: std.ArrayList(usize) = .empty;
    var influence: std.ArrayList(usize) = .empty;
    for (fit.leverage, s.standardized, 0..) |leverage, t, i| if (leverage < 1) {
        d.append(usize, &influence, i);
        if (@abs(t) > threshold) d.append(usize, &outliers, i);
    };
    std.mem.sort(usize, outliers.items, @as([]const f64, s.standardized), magnitudeLess);
    if (outliers.items.len == 0) out.add("  none", .{});
    for (outliers.items) |i| out.add("  x {s} y {s} fit {s} residual {s} standardized {s}", .{ positionText(data.x[i]),
         positionText(data.y[i]), real(fit.fitted[i]), real(diagnostic.residuals[i]), real(s.standardized[i]) });
    out.add("influence method {s}", .{methods_[s.outlier].name});
    std.mem.sort(usize, influence.items, @as([]const f64, s.cook), influenceLess);
    for (influence.items[0..@min(3, influence.items.len)]) |i| out.add("  x {s} lev {s} cook {s}",
         .{ positionText(data.x[i]), real(fit.leverage[i]), real(s.cook[i]) });
    out.add("bands", .{});
    const z = d.real(p.rows[10][0]);
    for (p.rows[11]) |name| {
        const m = methodIndex(methods_, name);
        var total: f64 = 0;
        var count: usize = 0;
        var coverage: usize = 0;
        for (s.grid, s.estimates[m]) |position, value| if (value != null) {
            total += standardError(s.fits[m], s.diagnostics[m], position);
            count += 1;
        };
        for (data.x, s.diagnostics[m].residuals) |position, residual| {
            const se = standardError(s.fits[m], s.diagnostics[m], position);
            const rse = s.diagnostics[m].rse.?;
            if (@abs(residual) <= z * @sqrt(rse * rse + se * se)) coverage += 1;
        }
        out.add("  {s} mean_se {s} coverage {d} of {d}", .{ name, real(total / d.f(count)), coverage, data.x.len });
    }
    return out;
}
fn framed(rows: []const []u8) Lines {
    const middle = d.alloc(u8, rows[0].len);
    @memset(middle, '-');
    const frame = d.fmt("+{s}+", .{middle});
    var out: Lines = .{};
    out.add("{s}", .{frame});
    for (rows) |row| out.add("|{s}|", .{row});
    out.add("{s}", .{frame});
    return out;
}
fn plotGrid(width: usize, height: usize) [][]u8 {
    const rows = d.alloc([]u8, height);
    for (rows) |*row| {
        row.* = d.alloc(u8, width);
        @memset(row.*, ' ');
    }
    return rows;
}
fn clampedRow(value: f64, height: usize) usize {
    return if (value < 0) 0 else if (value >= d.f(height)) height - 1 else @intFromFloat(value);
}
fn plotLines(s: Study, p: d.Params, methods_: []const d.Method) Lines {
    const data = s.series.data;
    const width = d.u(d.integer(p.rows[16][0]));
    const height = d.u(d.integer(p.rows[16][1]));
    const xa = data.x[0];
    const xb = data.x[data.x.len - 1];
    const ya = minimumY(data);
    const yb = maximumY(data);
    const ymin = d.f(ya) / 100;
    const ymax = d.f(yb) / 100;
    var out: Lines = .{};
    out.add("plot {s} size {d}x{d} x {s} {s} y {s} {s}", .{ s.series.name, width, height, positionText(xa),
         positionText(xb), positionText(ya), positionText(yb) });
    var legend: Text = .{};
    legend.add("legend . data", .{});
    for (p.rows[15], 1..) |name, m| legend.add(" {d} {s}", .{ m, name });
    out.add("{s}", .{legend.value()});
    var rows = plotGrid(width, height);
    const columns = d.alloc(usize, data.x.len);
    for (data.x, data.y, columns) |x, y, *column| {
        const col = @min(width - 1, d.u(@divTrunc(d.n(width) * (x - xa), xb - xa)));
        const row = @min(height - 1, d.u(@divTrunc(d.n(height) * (yb - y), yb - ya)));
        column.* = col;
        rows[row][col] = '.';
    }
    for (p.rows[15], 0..) |name, m| {
        const method = methodIndex(methods_, name);
        const digit = @as(u8, '1') + @as(u8, @intCast(m));
        for (0..width) |col| {
            const position = xa + @divTrunc((2 * d.n(col) + 1) * (xb - xa), 2 * d.n(width));
            const value = estimate(s.fits[method], position) orelse continue;
            const row = clampedRow(d.f(height) * (ymax - value) / (ymax - ymin), height);
            const cell = rows[row][col];
            rows[row][col] = if (cell == ' ' or cell == '.' or cell == digit) digit else '*';
        }
    }
    out.extend(framed(rows));
    var dots: usize = 0;
    var curves: usize = 0;
    var overlaps: usize = 0;
    for (rows) |row| for (row) |c| {
        if (c == '.') dots += 1 else if (c == '*') overlaps += 1 else if (c >= '1' and c <= '9') curves += 1;
    };
    out.add("cells data {d} curve {d} overlap {d}", .{ dots, curves, overlaps });
    out.add("", .{});
    const diagnostic = s.diagnostics[s.best];
    var limit: f64 = 0;
    for (diagnostic.residuals) |residual| limit = @max(limit, @abs(residual));
    out.add("residuals {s} method {s} limit {s}", .{ s.series.name, methods_[s.best].name, real(limit) });
    rows = plotGrid(width, height);
    @memset(rows[height / 2], '-');
    for (diagnostic.residuals, columns) |residual, col| {
        const pi = d.f(height) * ((limit - residual) / (2 * limit));
        rows[clampedRow(pi, height)][col] = 'o';
    }
    out.extend(framed(rows));
    out.add("", .{});
    out.add("histogram {s} method {s}", .{ s.series.name, methods_[s.outlier].name });
    var counts = std.mem.zeroes([14]usize);
    for (s.fits[s.outlier].leverage, s.standardized) |leverage, t| if (leverage < 1) {
        const bin = if (t < -3) @as(usize, 0) else if (t >= 3) 13 else 1 + @as(usize, @intFromFloat((t + 3) / 0.5));
        counts[bin] += 1;
    };
    for (counts, 0..) |count, bin| {
        const lower = if (bin == 0) "-inf" else positionText(-300 + 50 * (d.n(bin) - 1));
        const upper = if (bin == 13) "inf" else positionText(-300 + 50 * d.n(bin));
        const marks = d.alloc(u8, count);
        @memset(marks, '#');
        out.add("{s} {s} {d} |{s}", .{ lower, upper, count, marks });
    }
    return out;
}
fn write(io: std.Io, name: []const u8, lines: Lines) !void {
    var text: Text = .{};
    for (lines.data.items) |line| text.add("{s}\n", .{line});
    try std.Io.Dir.cwd().createDirPath(io, "output");
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = d.fmt("output/{s}", .{name}), .data = text.value() });
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    d.allocator = arena.allocator();
    const input = try d.readInput(init.io);
    const p = input.params;
    const methods_ = methods(p);
    const studies = d.alloc(Study, input.series.len);
    for (input.series, studies, 0..) |series, *result, i| result.* = study(series, p, methods_, i);
    var selections: Lines = .{};
    var fits: Lines = .{};
    var predictions: Lines = .{};
    var bands: Lines = .{};
    var diagnostics: Lines = .{};
    var isotonic: Lines = .{};
    var plots: Lines = .{};
    selections.add("series,method,parameter,score,edf,selected", .{});
    bands.add("series,method,x,fit,se,lower,upper", .{});
    var header: Text = .{};
    header.add("series,x", .{});
    for (methods_) |method| header.add(",{s}", .{method.name});
    fits.add("{s}", .{header.value()});
    predictions.add("{s}", .{header.value()});
    var random = d.integer(p.rows[13][2]);
    const repetitions = d.u(d.integer(p.rows[13][0]));
    const trim = d.u(d.integer(p.rows[13][1]));
    const z = d.real(p.rows[10][0]);
    for (studies, 0..) |s, series_index| {
        const data = s.series.data;
        for (s.selection) |row| selections.add("{s},{s},{s},{s},{s},{d}", .{ s.series.name, methods_[row.method].name,
             methods_[row.method].candidates[row.candidate].text, real(row.score), real(row.edf),
             @intFromBool(row.selected) });
        for (s.grid, 0..) |position, k| {
            var line: Text = .{};
            line.add("{s},{s}", .{ s.series.name, positionText(position) });
            for (s.estimates) |values| line.add(",{s}", .{real(values[k])});
            fits.add("{s}", .{line.value()});
        }
        for (p.rows[11]) |name| {
            const m = methodIndex(methods_, name);
            for (s.grid, s.estimates[m]) |position, fit_| {
                const value = fit_ orelse {
                    bands.add("{s},{s},{s},NA,NA,NA,NA", .{ s.series.name, name, positionText(position) });
                    continue;
                };
                const se = standardError(s.fits[m], s.diagnostics[m], position);
                bands.add("{s},{s},{s},{s},{s},{s},{s}", .{ s.series.name, name, positionText(position),
                     real(value), real(se), real(value - z * se), real(value + z * se) });
            }
        }
        const m = methodIndex(methods_, "spline");
        const spline = s.fits[m];
        const diagnostic = s.diagnostics[m];
        const mean = sum(diagnostic.residuals) / d.f(data.x.len);
        const centered = d.alloc(f64, data.x.len);
        for (diagnostic.residuals, centered) |residual, *value| value.* = residual - mean;
        const bootstrap = d.alloc([]f64, s.grid.len);
        for (bootstrap) |*values| values.* = d.alloc(f64, repetitions);
        for (0..repetitions) |b| {
            const sampled = d.alloc(f64, data.x.len);
            for (sampled, spline.fitted) |*value, fitted| {
                random = @mod(48271 * random, 2147483647);
                value.* = fitted + centered[d.u(@mod(random, d.n(data.x.len)))];
            }
            const fit_ = spline.spline.?.fit(sampled);
            for (s.grid, bootstrap) |position, values| values[b] = spline.spline.?.evaluate(fit_, position);
        }
        for (s.grid, bootstrap, s.estimates[m]) |position, values, fitted| {
            const average = sum(values) / d.f(repetitions);
            var total: f64 = 0;
            for (values) |value| total += (value - average) * (value - average);
            const se = @sqrt(total / d.f(repetitions - 1));
            std.mem.sort(f64, values, {}, realLess);
            bands.add("{s},spline_bootstrap,{s},{s},{s},{s},{s}", .{ s.series.name, positionText(position),
                 real(fitted), real(se), real(values[trim]), real(values[repetitions - trim - 1]) });
        }
        if (series_index > 0) {
            diagnostics.add("", .{});
            isotonic.add("", .{});
        }
        diagnostics.extend(diagnosticsLines(s, p, methods_));
        const iso = methodIndex(methods_, "isotonic");
        const fit = s.fits[iso];
        var first: Text = .{};
        first.add("series {s} direction {s} mode {s}", .{ s.series.name, fit.direction, p.rows[8][series_index] });
        if (d.eq(p.rows[8][series_index], "auto")) first.add(" rss_increasing {s} rss_decreasing {s}",
             .{ real(fit.increasing_rss), real(fit.decreasing_rss) });
        isotonic.add("{s}", .{first.value()});
        isotonic.add("blocks {d} rss {s} loo {s}", .{ fit.blocks.len, real(s.diagnostics[iso].rss), real(s.loo[iso]) });
        for (fit.blocks, 1..) |block, b| isotonic.add("block {d} x {s} {s} count {d} value {s}", .{ b,
             positionText(data.x[block.first]), positionText(data.x[block.last]), block.count, real(d.f(block.sum) / d.f(100 * block.count)) });
    }
    for (input.tests) |point| {
        var selected: ?Study = null;
        for (studies) |s| if (d.eq(s.series.name, point.series)) {
            selected = s;
            break;
        };
        var line: Text = .{};
        line.add("{s},{s}", .{ point.series, positionText(point.x) });
        for (selected.?.fits) |fit| line.add(",{s}", .{real(estimate(fit, point.x))});
        predictions.add("{s}", .{line.value()});
    }
    for (p.rows[14], 0..) |name, i| {
        if (i > 0) plots.add("", .{});
        for (studies) |s| if (d.eq(s.series.name, name)) {
            plots.extend(plotLines(s, p, methods_));
            break;
        };
    }
    try write(init.io, "selection.csv", selections);
    try write(init.io, "fits.csv", fits);
    try write(init.io, "predictions.csv", predictions);
    try write(init.io, "bands.csv", bands);
    try write(init.io, "diagnostics.txt", diagnostics);
    try write(init.io, "isotonic.txt", isotonic);
    try write(init.io, "plots.txt", plots);
}
