const std = @import("std");
const d = @import("dataset.zig");
const l = @import("logistic.zig");
const o = @import("optimizers.zig");
const s = @import("softmax.zig");
const metrics = @import("metrics.zig");
fn r4(value: f64) []const u8 {
    return metrics.real(value, 4);
}
fn r6(value: f64) []const u8 {
    return metrics.real(value, 6);
}
fn ratio(a: anytype, b: anytype) []const u8 {
    return metrics.ratio(d.n(a), d.n(b));
}
fn select(comptime T: type, source: []const T, ids: []const usize) []T {
    const result = d.alloc(T, ids.len);
    for (ids, result) |id, *value| value.* = source[id];
    return result;
}
fn inverse(matrix: d.Matrix) d.Matrix {
    const lower = o.cholesky(matrix);
    const result = d.matrix(matrix.len, matrix.len);
    for (0..matrix.len) |k| {
        const basis = d.zeros(matrix.len);
        basis[k] = 1;
        const column = o.solve(lower, basis);
        for (column, 0..) |value, j| result[j][k] = value;
    }
    return result;
}
fn correct(probabilities: []const f64, targets: []const usize, threshold: f64) i64 {
    const c = metrics.confusion(probabilities, targets, threshold);
    return c.tp + c.tn;
}
fn trained(data: d.Matrix, targets: []const usize, lambda: f64) []const f64 {
    const trace = o.newton(data, targets, lambda);
    return trace[trace.len - 1].weights;
}
const CrossValidation = struct { folds: [5]f64, probabilities: []f64, loss: f64 = 0, errors: usize = 0 };
const Influence = struct { covariance: d.Matrix, probabilities: []f64, leverage: []f64, residual: []f64,
     cook: []f64, edf: f64 = 0, deviance: f64 = 0, aic: f64 = 0, bic: f64 = 0 };
fn influence(weights: []const f64, data: d.Matrix, targets: []const usize, lambda: f64) Influence {
    var fit: Influence = .{ .covariance = inverse(l.hessian(weights, data, lambda)), .probabilities = l.probabilities(weights,
         data), .leverage = d.alloc(f64, data.len), .residual = d.alloc(f64, data.len), .cook = d.alloc(f64,
         data.len) };
    for (data, targets, fit.probabilities, 0..) |row, target, pi, i| {
        const variance = pi * (1 - pi);
        var q: f64 = 0;
        for (weights, 0..) |_, j| for (weights, 0..) |_, k| {
            q += row[j] * fit.covariance[j][k] * row[k];
        };
        const h = variance * q / d.f(data.len);
        const e = (d.f(target) - pi) / @sqrt(variance);
        fit.leverage[i] = h;
        fit.residual[i] = e / @sqrt(1 - h);
        fit.cook[i] = e * e * h / (d.f(weights.len) * ((1 - h) * (1 - h)));
        fit.edf += h;
    }
    fit.deviance = 2 * d.f(data.len) * l.averageLoss(weights, data, targets);
    fit.aic = fit.deviance + 2 * fit.edf;
    fit.bic = fit.deviance + @log(d.f(data.len)) * fit.edf;
    return fit;
}
const Model = struct { name: []const u8, checkpoints: []const o.Checkpoint, weights: []const f64,
     train_probabilities: []f64, test_probabilities: []f64 };
const Calibration = struct { counts: [10]i64 = @splat(0), hits: [10]i64 = @splat(0), sums: [10]f64 = @splat(0),
     ece: f64 = 0, mce: f64 = 0, hl: f64 = 0, groups: usize = 0 };
fn calibration(probabilities: []const f64, targets: []const usize) Calibration {
    var result: Calibration = .{};
    for (probabilities, targets) |pi, target| {
        const bin: usize = @intFromFloat(@min(9, @floor(pi * 10)));
        result.counts[bin] += 1;
        result.hits[bin] += d.n(target);
        result.sums[bin] += pi;
    }
    for (result.counts, result.hits, result.sums) |count, observed, total| if (count > 0) {
        result.groups += 1;
        result.ece += @abs(total - d.f(observed));
        result.mce = @max(result.mce, @abs(total / d.f(count) - d.f(observed) / d.f(count)));
        result.hl += (d.f(observed) - total) * (d.f(observed) - total) / (total * (1 - total / d.f(count)));
    };
    result.ece /= d.f(targets.len);
    return result;
}
fn binRange(bin: usize) []const u8 {
    return if (bin == 9) "0.9-1.0" else d.fmt("0.{d}-0.{d}", .{ bin, bin + 1 });
}
fn fractionOrder(_: void, a: metrics.Fraction, b: metrics.Fraction) bool {
    return a.numerator * b.denominator < b.numerator * a.denominator;
}
const Study = struct {
    train: d.Table,
    test_data: d.Table,
    params: d.Params,
    terms: []d.Feature,
    stats: d.Statistics,
    train_expanded: d.Matrix,
    test_expanded: d.Matrix,
    x: d.Matrix,
    z: d.Matrix,
    y: []usize,
    yt: []usize,
    class_train: []usize,
    class_test: []usize,
    classes: usize,
    validations: []CrossValidation = &.{},
    selected: usize = 0,
    one_se: usize = 0,
    se: f64 = 0,
    lambda: f64 = 0,
    models: [3]Model = undefined,
    soft_checkpoints: []s.Checkpoint = &.{},
    soft_weights: d.Matrix = &.{},
    soft_points: []s.Point = &.{},
    soft_correct: i64 = 0,
    fit: Influence = undefined,
    fn create(train: d.Table, test_data: d.Table, params: d.Params) Study {
        const terms = d.features(train.names, params.degree);
        const raw = d.expanded(train.rows, terms);
        const test_raw = d.expanded(test_data.rows, terms);
        const stats = d.statistics(raw, terms.len);
        var classes: usize = 0;
        for (train.rows) |row| classes = @max(classes, row.label + 1);
        return .{
            .train = train,
            .test_data = test_data,
            .params = params,
            .terms = terms,
            .stats = stats,
            .train_expanded = raw,
            .test_expanded = test_raw,
            .x = d.standardize(raw, stats, terms.len),
            .z = d.standardize(test_raw, stats, terms.len),
            .y = d.labels(train.rows, params.positive),
            .yt = d.labels(test_data.rows, params.positive),
            .class_train = d.labels(train.rows, null),
            .class_test = d.labels(test_data.rows, null),
            .classes = classes,
        };
    }
    fn crossValidate(self: *const Study, coefficient: f64, count: usize) CrossValidation {
        var result: CrossValidation = .{ .folds = undefined, .probabilities = d.alloc(f64, self.y.len) };
        const losses = d.alloc(f64, self.y.len);
        for (0..5) |fold| {
            var training: std.ArrayList(usize) = .empty;
            var validation: std.ArrayList(usize) = .empty;
            for (0..self.y.len) |id| {
                if (id % 5 == fold) d.append(usize, &validation, id) else d.append(usize, &training, id);
            }
            const raw = select([]f64, self.train_expanded, training.items);
            const stats = d.statistics(raw, count);
            const x = d.standardize(raw, stats, count);
            const vx = d.standardize(select([]f64, self.train_expanded, validation.items), stats, count);
            const targets = select(usize, self.y, training.items);
            const weights = trained(x, targets, coefficient);
            var total: f64 = 0;
            for (validation.items, vx) |id, row| {
                const score = l.score(weights, row);
                losses[id] = l.loss(score, self.y[id]);
                result.probabilities[id] = l.sigmoid(score);
                total += losses[id];
                if (@intFromBool(result.probabilities[id] >= self.params.threshold) != self.y[id]) result.errors += 1;
            }
            result.folds[fold] = total / d.f(validation.items.len);
        }
        var total: f64 = 0;
        for (losses) |value| total += value;
        result.loss = total / d.f(self.y.len);
        return result;
    }
    fn original(self: *const Study, weights: []const f64) []f64 {
        const result = d.alloc(f64, weights.len);
        var total: f64 = 0;
        for (weights[1..], 1..) |weight, j| {
            result[j] = weight / self.stats.deviation[j - 1];
            total += result[j] * self.stats.mean[j - 1];
        }
        result[0] = weights[0] - total;
        return result;
    }
    fn addTerms(self: *const Study, out: *d.Lines, weights: []const f64) void {
        const units = self.original(weights);
        for (weights, units, 0..) |weight, unit, j| out.add(
            "term {s} standardized {s} original {s}",
            .{ if (j == 0) "intercept" else self.terms[j - 1].name, r4(weight), r4(unit) },
        );
    }
    fn weightsReport(self: *const Study) d.Lines {
        const q = self.terms.len;
        var out: d.Lines = .{};
        out.add("features {d} degree {d} expanded {d}", .{ self.train.names.len, self.params.degree, q });
        out.add("standardization", .{});
        const correlation = d.matrix(q, q);
        for (0..q) |j| for (0..q) |k| {
            var total: f64 = 0;
            for (self.x) |row| total += row[j + 1] * row[k + 1];
            correlation[j][k] = total / d.f(self.x.len - 1);
        };
        const vif = inverse(correlation);
        for (self.terms, 0..) |term, j| out.add(
            "{s} mean {s} sd {s} vif {s}",
            .{ term.name, r6(self.stats.mean[j]), r6(self.stats.deviation[j]), r4(vif[j][j]) },
        );
        out.add("correlation", .{});
        for (correlation) |row| {
            var text: d.Text = .{};
            for (row, 0..) |value, index| text.add("{s}{s}", .{ if (index > 0) " " else "", r4(value) });
            out.add("{s}", .{text.value()});
        }
        for (self.models, 0..) |model, index| {
            out.blank();
            out.add("model {s} lambda {s}", .{ model.name, r4(self.lambda) });
            self.addTerms(&out, model.weights);
            out.add("norm {s}", .{r4(l.length(model.weights[1..]))});
            if (index < 2) {
                const delta = d.alloc(f64, q + 1);
                for (model.weights, self.models[2].weights, delta) |a, b, *value| value.* = a - b;
                out.add("distance_to_newton {s}", .{r6(l.length(delta))});
            }
        }
        out.blank();
        out.add("coefficients newton lambda {s}", .{r4(self.lambda)});
        for (self.models[2].weights, 0..) |weight, j| {
            const se = @sqrt(self.fit.covariance[j][j] / d.f(self.x.len));
            out.add("{s} weight {s} se {s} z {s} lower {s} upper {s} odds_ratio {s}", .{
                if (j == 0) "intercept" else self.terms[j - 1].name, r4(weight),             r4(se),
                r4(weight / se),                                     r4(weight - 1.96 * se), r4(weight + 1.96 * se),
                r4(@exp(weight)),
            });
        }
        out.blank();
        out.add("model softmax lambda {s}", .{r4(self.params.softmax_lambda)});
        for (self.soft_weights, 0..) |weights, class| {
            out.add("class {d}", .{class});
            self.addTerms(&out, weights);
        }
        return out;
    }
    fn tracesReport(self: *const Study) d.Lines {
        var out: d.Lines = .{};
        out.add("optimizer,iteration,loss,gradient_norm,test_loss", .{});
        for (self.models) |model| for (model.checkpoints) |checkpoint| out.add("{s},{d},{s},{s},{s}", .{
            model.name,                                                       checkpoint.iteration,
            r6(l.objective(checkpoint.weights, self.x, self.y, self.lambda)), r6(l.length(l.gradient(checkpoint.weights,
                 self.x, self.y, self.lambda))),
            r6(l.averageLoss(checkpoint.weights, self.z, self.yt)),
        });
        for (self.soft_checkpoints) |checkpoint| {
            const gradient = s.gradient(checkpoint.weights, self.x, self.class_train, self.params.softmax_lambda);
            var total: f64 = 0;
            for (gradient) |row| for (row) |value| {
                total += value * value;
            };
            out.add("softmax,{d},{s},{s},{s}", .{
                checkpoint.iteration,
                r6(s.objective(checkpoint.weights, self.x, self.class_train, self.params.softmax_lambda)),
                r6(@sqrt(total)),
                r6(s.loss(checkpoint.weights, self.z, self.class_test)),
            });
        }
        return out;
    }
    fn predictionsReport(self: *const Study) d.Lines {
        var out: d.Lines = .{};
        out.add("id,model,probability,predicted,actual", .{});
        for (self.models) |model| for (self.test_data.rows, model.test_probabilities, self.yt) |row, pi, target| {
            out.add("{s},{s},{s},{d},{d}", .{ row.id, model.name, r6(pi), @intFromBool(pi >= self.params.threshold), target });
        };
        for (self.test_data.rows, self.soft_points) |row, point| out.add(
            "{s},softmax,{s},{d},{d}",
            .{ row.id, r6(point.probabilities[point.predicted]), point.predicted, row.label },
        );
        return out;
    }
    fn binaryReport(self: *const Study, out: *d.Lines, roc_out: *d.Lines, model: Model) void {
        const m = self.yt.len;
        const c = metrics.confusion(model.test_probabilities, self.yt, self.params.threshold);
        const pos = c.tp + c.fn_;
        const neg = c.fp + c.tn;
        const train_correct = correct(model.train_probabilities, self.y, self.params.threshold);
        out.add("model {s} lambda {s}", .{ model.name, r4(self.lambda) });
        out.add("train correct {d}/{d} accuracy {s}", .{ train_correct, self.y.len, ratio(train_correct, self.y.len) });
        out.add("test tp {d} fp {d} tn {d} fn {d}", .{ c.tp, c.fp, c.tn, c.fn_ });
        out.add("test accuracy {s} precision {s} recall {s} specificity {s} f1 {s}", .{
            ratio(c.tp + c.tn, m), ratio(c.tp, c.tp + c.fp),                 ratio(c.tp, pos),
            ratio(c.tn, neg),      ratio(2 * c.tp, 2 * c.tp + c.fp + c.fn_),
        });
        var brier: f64 = 0;
        for (model.test_probabilities, self.yt) |pi, target| {
            const delta = pi - d.f(target);
            brier += delta * delta;
        }
        out.add("log_loss {s} brier {s}", .{ r6(l.averageLoss(model.weights, self.z, self.yt)), r6(brier / d.f(m)) });
        const points = metrics.roc(model.test_probabilities, self.yt);
        var ap: f64 = 0;
        var prior: i64 = 0;
        var youden: usize = 0;
        var f1: usize = 0;
        var cost: usize = 0;
        for (points, 0..) |point, index| {
            ap += d.f((point.tp - prior) * point.tp) / d.f(point.tp + point.fp);
            prior = point.tp;
            const a = points[youden];
            const b = points[f1];
            const e = points[cost];
            if (point.tp * neg - point.fp * pos > a.tp * neg - a.fp * pos) youden = index;
            if (point.tp * (pos + b.tp + b.fp) > b.tp * (pos + point.tp + point.fp)) f1 = index;
            if (self.params.fp_cost * point.fp + self.params.fn_cost * (pos - point.tp) <
                self.params.fp_cost * e.fp + self.params.fn_cost * (pos - e.tp)) cost = index;
        }
        ap /= d.f(pos);
        out.add("auc {s} average_precision {s}", .{ metrics.auc(model.test_probabilities, self.yt).text(), r4(ap) });
        const a = points[youden];
        const b = points[f1];
        const e = points[cost];
        out.add("youden threshold {s} tpr {s} fpr {s} j {s}", .{
            r6(a.threshold), ratio(a.tp, pos), ratio(a.fp, neg), ratio(a.tp * neg - a.fp * pos, pos * neg),
        });
        out.add("best_f1 threshold {s} precision {s} recall {s} f1 {s}", .{
            r6(b.threshold), ratio(b.tp, b.tp + b.fp), ratio(b.tp, pos), ratio(2 * b.tp, pos + b.tp + b.fp),
        });
        out.add("min_cost threshold {s} cost {d} fp {d} fn {d}", .{
            r6(e.threshold), self.params.fp_cost * e.fp + self.params.fn_cost * (pos - e.tp), e.fp, pos - e.tp,
        });
        const table = calibration(model.test_probabilities, self.yt);
        out.add("calibration", .{});
        for (0..10) |bin| out.add("bin {s} count {d} mean_probability {s} positive_rate {s}", .{
            binRange(bin),                                                                    table.counts[bin],
            if (table.counts[bin] > 0) r4(table.sums[bin] / d.f(table.counts[bin])) else "-", ratio(table.hits[bin],
                 table.counts[bin]),
        });
        out.add("ece {s} mce {s} hosmer_lemeshow {s} groups {d}", .{ r4(table.ece), r4(table.mce), r4(table.hl), table.groups });
        out.add("gains", .{});
        const order = metrics.scoreOrder(model.test_probabilities, true);
        for (1..11) |decile| {
            const size = decile * m / 10;
            var hits: i64 = 0;
            for (order[0..size]) |id| hits += d.n(self.yt[id]);
            out.add("decile {d} rows {d} positives {d} gain {s} lift {s}", .{
                decile, size, hits, ratio(hits, pos), ratio(hits * d.n(m), d.n(size) * pos),
            });
        }
        roc_out.add("{s},inf,0.0000,0.0000,-", .{model.name});
        for (points) |point| roc_out.add("{s},{s},{s},{s},{s}", .{
            model.name, r6(point.threshold), ratio(point.tp, pos), ratio(point.fp, neg), ratio(point.tp, point.tp + point.fp),
        });
    }
    fn slope(self: *const Study, units: []const f64, feature: usize, values: []const f64) f64 {
        var total: f64 = 0;
        for (self.terms, 0..) |term, j| {
            var count: usize = 0;
            var removed = false;
            var product: f64 = 1;
            for (term.indices) |index| {
                if (index == feature) {
                    count += 1;
                    if (!removed) {
                        removed = true;
                        continue;
                    }
                }
                product *= values[index];
            }
            if (count > 0) total += units[j + 1] * (d.f(count) * product);
        }
        return total;
    }
    fn diagnostics(self: *const Study, out: *d.Lines) void {
        const model = self.models[2];
        const n = self.y.len;
        const m = self.yt.len;
        var positives: usize = 0;
        for (self.y) |target| positives += target;
        const pi_bar = d.f(positives) / d.f(n);
        const null_loss = -(pi_bar * @log(pi_bar) + (1 - pi_bar) * @log(1 - pi_bar));
        const loss = l.averageLoss(model.weights, self.x, self.y);
        out.add("diagnostics newton lambda {s}", .{r4(self.lambda)});
        out.add("fit null_loss {s} train_loss {s} mcfadden_r2 {s} deviance {s} edf {s} aic {s} bic {s}", .{
            r6(null_loss), r6(loss), r4(1 - loss / null_loss), r4(self.fit.deviance), r4(self.fit.edf),
                 r4(self.fit.aic), r4(self.fit.bic),
        });
        const order = metrics.scoreOrder(self.fit.probabilities, false);
        var expected: [10]f64 = undefined;
        var observed: [10]i64 = undefined;
        var counts: [10]usize = undefined;
        var hl: f64 = 0;
        for (0..10) |group| {
            const first = group * n / 10;
            const end = (group + 1) * n / 10;
            var sum: f64 = 0;
            var hits: i64 = 0;
            for (order[first..end]) |id| {
                sum += self.fit.probabilities[id];
                hits += d.n(self.y[id]);
            }
            counts[group] = end - first;
            expected[group] = sum;
            observed[group] = hits;
            hl += (d.f(hits) - sum) * (d.f(hits) - sum) / (sum * (1 - sum / d.f(end - first)));
        }
        out.add("hosmer_lemeshow_train groups 10 statistic {s}", .{r4(hl)});
        for (0..10) |group| out.add("group {d} rows {d} observed {d} expected {s}", .{ group + 1,
             counts[group], observed[group], r4(expected[group]) });
        out.add("newton_iterations", .{});
        for (1..11) |iteration| {
            const weights = model.checkpoints[iteration - 1].weights;
            const gradient = l.gradient(weights, self.x, self.y, self.lambda);
            const delta = o.solve(o.cholesky(l.hessian(weights, self.x, self.lambda)), gradient);
            var product: f64 = 0;
            for (gradient, delta) |value, change| product += value * change;
            out.add("iteration {d} objective {s} gradient_norm {s} step_norm {s} predicted_decrease {s}", .{
                iteration, r6(l.objective(weights, self.x, self.y, self.lambda)), r6(l.length(gradient)),
                     r6(l.length(delta)), r6(product / 2),
            });
        }
        const units = self.original(model.weights);
        const base_mean = self.stats.mean[0..self.train.names.len];
        const center = l.sigmoid(l.score(model.weights, d.standardizePoint(d.expand(base_mean, self.terms),
             self.stats, self.terms.len)));
        for (self.train.names, 0..) |name, feature| {
            var total: f64 = 0;
            for (self.train.rows, self.fit.probabilities) |row, pi| total += pi * (1 - pi) * self.slope(units,
                 feature, row.values);
            out.add("marginal {s} average {s} at_mean {s}", .{ name, r4(total / d.f(n)), r4(center * (1 - center) * self.slope(units,
                 feature, base_mean)) });
        }
        for (1..10) |k| {
            const c = metrics.confusion(model.test_probabilities, self.yt, d.f(k) / 10);
            out.add("cut 0.{d} positive {d} tp {d} fp {d} precision {s} recall {s} accuracy {s}", .{
                k, c.tp + c.fp, c.tp, c.fp, ratio(c.tp, c.tp + c.fp), ratio(c.tp, c.tp + c.fn_), ratio(c.tp + c.tn, m),
            });
        }
        const distances = d.alloc(f64, m);
        for (model.test_probabilities, distances) |pi, *value| value.* = @abs(pi - self.params.threshold);
        var written: usize = 0;
        for (metrics.scoreOrder(distances, true)) |id| if (@intFromBool(model.test_probabilities[id] >= self.params.threshold) != self.yt[id]) {
            out.add("error {s} actual {d} probability {s}", .{ self.test_data.rows[id].id, self.yt[id],
                 r6(model.test_probabilities[id]) });
            written += 1;
            if (written == 5) break;
        };
        var random: o.Minstd = .{ .state = self.params.bootstrap_seed };
        const fractions = d.alloc(metrics.Fraction, self.params.bootstrap);
        const values = d.alloc(f64, self.params.bootstrap);
        var mean: f64 = 0;
        for (fractions, values) |*fraction, *value| {
            const sample = d.alloc(f64, m);
            const targets = d.alloc(usize, m);
            for (sample, targets) |*pi, *target| {
                const id: usize = @intCast(@mod(random.draw(), d.n(m)));
                pi.* = model.test_probabilities[id];
                target.* = self.yt[id];
            }
            fraction.* = metrics.auc(sample, targets);
            value.* = fraction.value();
            mean += value.*;
        }
        mean /= d.f(values.len);
        var squares: f64 = 0;
        for (values) |value| squares += (value - mean) * (value - mean);
        std.mem.sort(metrics.Fraction, fractions, {}, fractionOrder);
        out.add("bootstrap resamples {d} seed {d} auc_mean {s} auc_sd {s} lower {s} upper {s}", .{
            self.params.bootstrap,             self.params.bootstrap_seed,                         r4(mean),
                 r4(@sqrt(squares / d.f(values.len - 1))),
            fractions[values.len / 40].text(), fractions[values.len - values.len / 40 - 1].text(),
        });
        var large: usize = 0;
        for (self.fit.residual) |value| if (@abs(value) > 2) {
            large += 1;
        };
        out.add("influence effective_parameters {s} large_residuals {d}", .{ r4(self.fit.edf), large });
        const cook_order = metrics.scoreOrder(self.fit.cook, true);
        for (cook_order[0..@min(5, n)]) |id| out.add("cook {s} actual {d} probability {s} leverage {s} residual {s} distance {s}",
             .{
            self.train.rows[id].id, self.y[id], r4(self.fit.probabilities[id]), r4(self.fit.leverage[id]),
                 r4(self.fit.residual[id]), r4(self.fit.cook[id]),
        });
    }
    fn importanceProfiles(self: *const Study, out: *d.Lines) void {
        const model = self.models[2];
        const m = self.yt.len;
        const baseline_loss = l.averageLoss(model.weights, self.z, self.yt);
        const baseline_auc = metrics.auc(model.test_probabilities, self.yt);
        out.add("importance repeats {d} seed {d}", .{ self.params.permutations, self.params.permutation_seed });
        out.add("baseline log_loss {s} auc {s} softmax_accuracy {s}", .{ r6(baseline_loss), baseline_auc.text(),
             ratio(self.soft_correct, m) });
        var random: o.Minstd = .{ .state = self.params.permutation_seed };
        for (self.train.names, 0..) |name, feature| {
            var total_loss: f64 = 0;
            var total_auc: i64 = 0;
            var total_correct: i64 = 0;
            for (0..self.params.permutations) |_| {
                const order = d.sequence(m);
                random.shuffle(order);
                const rows = d.alloc(d.Row, m);
                for (self.test_data.rows, rows, order) |row, *target, id| {
                    const values = d.dupe(f64, row.values);
                    values[feature] = self.test_data.rows[id].values[feature];
                    target.* = .{ .id = row.id, .values = values, .label = row.label };
                }
                const data = d.standardize(d.expanded(rows, self.terms), self.stats, self.terms.len);
                total_loss += l.averageLoss(model.weights, data, self.yt);
                total_auc += metrics.auc(l.probabilities(model.weights, data), self.yt).numerator;
                for (data, self.class_test) |row, label| if (s.point(self.soft_weights, row, label).predicted == label) {
                    total_correct += 1;
                };
            }
            out.add("feature {s} log_loss_increase {s} auc {s} softmax_accuracy {s}", .{ name, r6(total_loss / d.f(self.params.permutations) - baseline_loss),
                 (metrics.Fraction{ .numerator = total_auc, .denominator = d.n(self.params.permutations) * baseline_auc.denominator }).text(),
                 ratio(total_correct, self.params.permutations * m) });
        }
        out.blank();
        out.add("profiles", .{});
        const mean = self.stats.mean[0..self.train.names.len];
        for (self.train.names, 0..) |name, feature| {
            var lo = self.train.rows[0].values[feature];
            var hi = lo;
            for (self.train.rows) |row| {
                lo = @min(lo, row.values[feature]);
                hi = @max(hi, row.values[feature]);
            }
            for (0..5) |point| {
                const values = d.dupe(f64, mean);
                values[feature] = lo + (hi - lo) * d.f(point) / 4;
                const row = d.standardizePoint(d.expand(values, self.terms), self.stats, self.terms.len);
                const soft = s.point(self.soft_weights, row, 0);
                var probabilities: d.Text = .{};
                for (soft.probabilities) |pi| probabilities.add(" {s}", .{r4(pi)});
                out.add("profile {s} value {s} newton {s} softmax{s}", .{ name, r4(values[feature]),
                     r4(l.sigmoid(l.score(model.weights, row))), probabilities.value() });
            }
        }
    }
    fn multiclass(self: *const Study, out: *d.Lines) void {
        const m = self.yt.len;
        out.add("softmax classes {d} lambda {s} iterations {d}", .{ self.classes, r4(self.params.softmax_lambda),
             self.params.softmax_iterations });
        out.add("confusion", .{});
        const table = d.alloc([]i64, self.classes);
        for (table) |*row| {
            row.* = d.alloc(i64, self.classes);
            @memset(row.*, 0);
        }
        const rows = d.alloc(i64, self.classes);
        const columns = d.alloc(i64, self.classes);
        @memset(rows, 0);
        @memset(columns, 0);
        var diagonal: i64 = 0;
        for (self.soft_points, self.class_test) |point, label| table[label][point.predicted] += 1;
        for (table, 0..) |row, k| {
            var text: d.Text = .{};
            for (row, 0..) |value, j| {
                text.add("{s}{d}", .{ if (j > 0) " " else "", value });
                rows[k] += value;
                columns[j] += value;
            }
            out.add("{s}", .{text.value()});
            diagonal += row[k];
        }
        for (0..self.classes) |k| {
            const scores = d.alloc(f64, m);
            const targets = d.alloc(usize, m);
            for (self.soft_points, self.class_test, scores, targets) |point, label, *pi, *target| {
                pi.* = point.probabilities[k];
                target.* = @intFromBool(label == k);
            }
            out.add("class {d} precision {s} recall {s} f1 {s} auc {s}", .{ k, ratio(table[k][k],
                 columns[k]), ratio(table[k][k], rows[k]), ratio(2 * table[k][k], columns[k] + rows[k]),
                 metrics.auc(scores, targets).text() });
        }
        var chance: i64 = 0;
        for (rows, columns) |row, column| chance += row * column;
        out.add("accuracy {s} kappa {s}", .{ ratio(diagonal, m), ratio(d.n(m) * diagonal - chance, d.n(m) * d.n(m) - chance) });
        var brier: f64 = 0;
        for (self.soft_points, self.class_test) |point, label| {
            var total: f64 = 0;
            for (point.probabilities, 0..) |pi, k| {
                const delta = pi - @as(f64, if (label == k) 1 else 0);
                total += delta * delta;
            }
            brier += total;
        }
        out.add("log_loss {s} brier {s}", .{ r6(s.loss(self.soft_weights, self.z, self.class_test)), r6(brier / d.f(m)) });
        const scores = d.alloc(f64, m);
        const confidence = d.alloc(f64, m);
        const hits = d.alloc(usize, m);
        var binary_loss: f64 = 0;
        var agreement: i64 = 0;
        for (self.soft_points, self.yt, self.class_test, 0..) |point, target, label, i| {
            const pi = point.probabilities[self.params.positive];
            scores[i] = pi;
            binary_loss += -@log(if (target == 1) pi else 1 - pi);
            if ((pi >= self.params.threshold) == (self.models[2].test_probabilities[i] >= self.params.threshold)) agreement += 1;
            confidence[i] = point.probabilities[point.predicted];
            hits[i] = @intFromBool(point.predicted == label);
        }
        out.add("binary_view positive_class {d} auc {s} log_loss {s} accuracy {s} agreement_with_newton {d}/{d}",
             .{ self.params.positive, metrics.auc(scores, self.yt).text(), r6(binary_loss / d.f(m)),
             ratio(correct(scores, self.yt, self.params.threshold), m), agreement, m });
        out.add("confidence", .{});
        const bins = calibration(confidence, hits);
        for (0..10) |bin| out.add("bin {s} count {d} mean_confidence {s} accuracy {s}", .{ binRange(bin),
             bins.counts[bin], if (bins.counts[bin] > 0) r4(bins.sums[bin] / d.f(bins.counts[bin])) else "-",
             ratio(bins.hits[bin], bins.counts[bin]) });
        out.add("ece {s}", .{r4(bins.ece)});
        out.blank();
        out.add("one_vs_rest lambda {s} newton_iterations 10", .{r4(self.params.softmax_lambda)});
        const ovr = d.alloc([]f64, self.classes);
        for (ovr, 0..) |*values, k| {
            const targets = d.labels(self.train.rows, k);
            const weights = trained(self.x, targets, self.params.softmax_lambda);
            values.* = l.probabilities(weights, self.z);
            out.add("class {d} objective {s} auc {s}", .{ k, r6(l.objective(weights, self.x, targets,
                 self.params.softmax_lambda)), metrics.auc(values.*, test_targets).text() });
        }
        var correct_count: i64 = 0;
        var same: usize = 0;
        for (self.soft_points, self.class_test, 0..) |point, label, i| {
            var predicted: usize = 0;
            for (1..self.classes) |k| if (ovr[k][i] > ovr[predicted][i]) {
                predicted = k;
            };
            if (predicted == label) correct_count += 1;
            if (predicted == point.predicted) same += 1;
        }
        out.add("accuracy {s} agreement_with_softmax {d}/{d}", .{ ratio(correct_count, m), same, m });
    }
    fn maps(self: *const Study, out: *d.Lines) void {
        out.add("map {s} {s} width {d} height {d}", .{ self.train.names[0], self.train.names[1], self.params.width,
             self.params.height });
        out.add("softmax_classes", .{});
        const lo = d.dupe(f64, self.train.rows[0].values);
        const hi = d.dupe(f64, lo);
        for (self.train.rows) |row| for (row.values, 0..) |value, j| {
            lo[j] = @min(lo[j], value);
            hi[j] = @max(hi[j], value);
        };
        const cells = d.alloc(usize, self.classes);
        @memset(cells, 0);
        var probability_map: d.Lines = .{};
        for (0..self.params.height) |r| {
            const class_line = d.alloc(u8, self.params.width);
            const probability_line = d.alloc(u8, self.params.width);
            for (0..self.params.width) |c| {
                const values = d.dupe(f64, self.stats.mean[0..self.train.names.len]);
                values[0] = lo[0] + (d.f(c) + 0.5) * (hi[0] - lo[0]) / d.f(self.params.width);
                values[1] = hi[1] - (d.f(r) + 0.5) * (hi[1] - lo[1]) / d.f(self.params.height);
                const row = d.standardizePoint(d.expand(values, self.terms), self.stats, self.terms.len);
                const predicted = s.point(self.soft_weights, row, 0).predicted;
                class_line[c] = '0' + @as(u8, @intCast(predicted));
                cells[predicted] += 1;
                probability_line[c] = '0' + @as(u8, @intFromFloat(@min(9, @floor(l.sigmoid(l.score(self.models[2].weights,
                     row)) * 10))));
            }
            out.add("{s}", .{class_line});
            probability_map.add("{s}", .{probability_line});
        }
        var text: d.Text = .{};
        for (cells) |count| text.add(" {d}", .{count});
        out.add("cells{s}", .{text.value()});
        out.add("newton_probability", .{});
        for (probability_map.data.items) |row| out.add("{s}", .{row});
    }
    fn evaluationReport(self: *const Study, roc_out: *d.Lines) d.Lines {
        const n = self.y.len;
        const m = self.yt.len;
        var out: d.Lines = .{};
        roc_out.add("model,threshold,tpr,fpr,precision", .{});
        out.add("data train {d} test {d} base_features {d} degree {d} features {d}", .{ n, m, self.train.names.len,
             self.params.degree, self.terms.len });
        var train_positive: usize = 0;
        var test_positive: usize = 0;
        for (self.y) |target| train_positive += target;
        for (self.yt) |target| test_positive += target;
        out.add("binary positive_class {d} train {d}/{d} test {d}/{d}", .{ self.params.positive, train_positive,
             n, test_positive, m });
        var counts: d.Text = .{};
        counts.add("classes {d} train", .{self.classes});
        for (0..self.classes) |k| {
            var count: usize = 0;
            for (self.class_train) |label| if (label == k) {
                count += 1;
            };
            counts.add(" {d}", .{count});
        }
        counts.add(" test", .{});
        for (0..self.classes) |k| {
            var count: usize = 0;
            for (self.class_test) |label| if (label == k) {
                count += 1;
            };
            counts.add(" {d}", .{count});
        }
        out.add("{s}", .{counts.value()});
        out.blank();
        out.add("cross_validation folds 5 newton_iterations 10", .{});
        for (self.params.lambdas, self.validations) |lambda, cv| {
            var losses: d.Text = .{};
            for (cv.folds) |value| losses.add(" {s}", .{r6(value)});
            out.add("lambda {s} fold_loss{s} cv_loss {s} errors {d}/{d}", .{ r4(lambda), losses.value(),
                 r6(cv.loss), cv.errors, n });
        }
        out.add("selected lambda {s} cv_loss {s} se {s} lambda_1se {s}", .{ r4(self.lambda), r6(self.validations[self.selected].loss),
             r6(self.se), r4(self.params.lambdas[self.one_se]) });
        const c = metrics.confusion(self.validations[self.selected].probabilities, self.y, self.params.threshold);
        out.add("out_of_fold tp {d} fp {d} tn {d} fn {d} accuracy {s} auc {s}", .{ c.tp, c.fp, c.tn,
             c.fn_, ratio(c.tp + c.tn, n), metrics.auc(self.validations[self.selected].probabilities,
             self.y).text() });
        out.blank();
        out.add("lambda_path", .{});
        for (self.params.lambdas) |lambda| {
            const weights = trained(self.x, self.y, lambda);
            out.add("lambda {s} objective {s} train_loss {s} test_loss {s} train_accuracy {s} test_accuracy {s} norm {s}",
                 .{ r4(lambda), r6(l.objective(weights, self.x, self.y, lambda)), r6(l.averageLoss(weights,
                 self.x, self.y)), r6(l.averageLoss(weights, self.z, self.yt)), ratio(correct(l.probabilities(weights,
                 self.x), self.y, self.params.threshold), n), ratio(correct(l.probabilities(weights,
                 self.z), self.yt, self.params.threshold), m), r4(l.length(weights[1..])) });
        }
        out.blank();
        out.add("degrees lambda {s}", .{r4(self.lambda)});
        for (1..self.params.degree + 1) |degree| {
            var count: usize = 0;
            for (self.terms) |term| if (term.indices.len <= degree) {
                count += 1;
            };
            const x = d.standardize(self.train_expanded, self.stats, count);
            const z = d.standardize(self.test_expanded, self.stats, count);
            const weights = trained(x, self.y, self.lambda);
            const measures = influence(weights, x, self.y, self.lambda);
            const probabilities = l.probabilities(weights, z);
            out.add("degree {d} features {d} cv_loss {s} train_loss {s} test_loss {s} test_accuracy {s} auc {s} edf {s} aic {s} bic {s}",
                 .{ degree, count, r6(self.crossValidate(self.lambda, count).loss), r6(l.averageLoss(weights,
                 x, self.y)), r6(l.averageLoss(weights, z, self.yt)), ratio(correct(probabilities,
                 self.yt, self.params.threshold), m), metrics.auc(probabilities, self.yt).text(),
                 r4(measures.edf), r4(measures.aic), r4(measures.bic) });
        }
        out.blank();
        out.add("learning_curve lambda {s}", .{r4(self.lambda)});
        for (1..5) |k| {
            const size = k * n / 4;
            const raw = self.train_expanded[0..size];
            const stats = d.statistics(raw, self.terms.len);
            const x = d.standardize(raw, stats, self.terms.len);
            const z = d.standardize(self.test_expanded, stats, self.terms.len);
            const targets = self.y[0..size];
            const weights = trained(x, targets, self.lambda);
            const probabilities = l.probabilities(weights, z);
            out.add("size {d} train_loss {s} test_loss {s} test_accuracy {s} auc {s}", .{ size, r6(l.averageLoss(weights,
                 x, targets)), r6(l.averageLoss(weights, z, self.yt)), ratio(correct(probabilities,
                 self.yt, self.params.threshold), m), metrics.auc(probabilities, self.yt).text() });
        }
        for (self.models) |model| {
            out.blank();
            self.binaryReport(&out, roc_out, model);
        }
        out.blank();
        for ([_][2]usize{ .{ 0, 1 }, .{ 0, 2 }, .{ 1, 2 } }) |pair| {
            var same: usize = 0;
            var first: i64 = 0;
            var second: i64 = 0;
            for (self.models[pair[0]].test_probabilities, self.models[pair[1]].test_probabilities, self.yt) |a, b, target| {
                const pa = @intFromBool(a >= self.params.threshold);
                const pb = @intFromBool(b >= self.params.threshold);
                if (pa == pb) same += 1;
                if (pa == target and pb != target) first += 1;
                if (pb == target and pa != target) second += 1;
            }
            const delta = @as(i64, @intCast(@abs(first - second))) - 1;
            out.add("agreement {s} {s} same {d}/{d} only_first {d} only_second {d} mcnemar {s}", .{ self.models[pair[0]].name,
                 self.models[pair[1]].name, same, m, first, second, ratio(delta * delta, first + second) });
        }
        out.blank();
        self.diagnostics(&out);
        out.blank();
        self.importanceProfiles(&out);
        out.blank();
        self.multiclass(&out);
        out.blank();
        self.maps(&out);
        return out;
    }
    fn run(self: *Study, io: std.Io) !void {
        self.validations = d.alloc(CrossValidation, self.params.lambdas.len);
        for (self.params.lambdas, self.validations) |lambda, *cv| cv.* = self.crossValidate(lambda, self.terms.len);
        for (self.validations, 0..) |cv, index| if (cv.loss <= self.validations[self.selected].loss) {
            self.selected = index;
        };
        self.lambda = self.params.lambdas[self.selected];
        var mean: f64 = 0;
        for (self.validations[self.selected].folds) |value| mean += value;
        mean /= 5;
        var squares: f64 = 0;
        for (self.validations[self.selected].folds) |value| squares += (value - mean) * (value - mean);
        self.se = @sqrt(squares / 4) / @sqrt(@as(f64, 5));
        for (self.validations, 0..) |cv, index| if (cv.loss <= self.validations[self.selected].loss + self.se) {
            self.one_se = index;
        };
        const traces = [_][]o.Checkpoint{ o.gradientDescent(self.x, self.y, self.lambda, self.params.gd_rate,
             self.params.gd_iterations), o.stochastic(self.x, self.y, self.lambda, self.params), o.newton(self.x,
             self.y, self.lambda) };
        const names = [_][]const u8{ "gd", "sgd", "newton" };
        for (&self.models, traces, names) |*model, trace, name| {
            const weights = trace[trace.len - 1].weights;
            model.* = .{ .name = name, .checkpoints = trace, .weights = weights, .train_probabilities = l.probabilities(weights,
                 self.x), .test_probabilities = l.probabilities(weights, self.z) };
        }
        self.fit = influence(self.models[2].weights, self.x, self.y, self.lambda);
        self.soft_checkpoints = s.train(self.x, self.class_train, self.classes, self.params);
        self.soft_weights = self.soft_checkpoints[self.soft_checkpoints.len - 1].weights;
        self.soft_points = d.alloc(s.Point, self.yt.len);
        for (self.z, self.class_test, self.soft_points) |row, label, *point| {
            point.* = s.point(self.soft_weights, row, label);
            if (point.predicted == label) self.soft_correct += 1;
        }
        var roc_out: d.Lines = .{};
        const evaluation = self.evaluationReport(&roc_out);
        try d.writeLines(io, "weights.txt", self.weightsReport());
        try d.writeLines(io, "loss_trace.csv", self.tracesReport());
        try d.writeLines(io, "predictions.csv", self.predictionsReport());
        try d.writeLines(io, "evaluation.txt", evaluation);
        try d.writeLines(io, "roc.csv", roc_out);
    }
};
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    d.allocator = arena.allocator();
    const train = try d.readTable(init.io, "train.csv");
    const test_data = try d.readTable(init.io, "test.csv");
    const params = try d.Params.read(init.io);
    var study = Study.create(train, test_data, params);
    try study.run(init.io);
}
