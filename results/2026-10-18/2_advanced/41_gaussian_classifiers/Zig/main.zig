const std = @import("std");
const c = @import("dataset.zig");
const linalg = @import("linalg.zig");
const gaussian = @import("gaussian_models.zig");
const evaluation = @import("evaluation.zig");
const plot = @import("plot.zig");
const model_names = [_][]const u8{ "NB", "LDA", "QDA", "ENSEMBLE" };
fn paragraph(out: *c.Lines, part: *c.Lines) void {
    if (out.data.items.len > 0) out.add("", .{});
    out.extend(part.*);
    part.* = .{};
}
fn fit(data: c.Dataset, rows: c.Rows, features: c.Features, kind: usize) gaussian.Model {
    return gaussian.train(rows, features, data.classes.len, kind, data.params.empirical, data.params.smoothing,
         data.params.gamma);
}
fn predictions(data: c.Dataset, model: gaussian.Model, rows: c.Rows) []const usize {
    const out = c.alloc(usize, rows.len);
    for (rows, out) |row, *value| value.* = gaussian.predict(model, row.values, data.costs).predicted;
    return out;
}
fn correctCount(rows: c.Rows, predicted: []const usize) usize {
    var count: usize = 0;
    for (rows, predicted) |row, value| count += @intFromBool(row.label == value);
    return count;
}
fn modelCorrect(data: c.Dataset, model: gaussian.Model, rows: c.Rows) usize {
    return correctCount(rows, predictions(data, model, rows));
}
const CrossValidation = struct { prediction: []usize, fold_correct: []usize, correct: usize = 0 };
fn crossValidateValues(data: c.Dataset, features: c.Features, kind: usize, smoothing: f64, gamma: f64) CrossValidation {
    var out: CrossValidation = .{ .prediction = c.alloc(usize, data.train.len), .fold_correct = c.alloc(usize,
         data.params.folds) };
    @memset(out.fold_correct, 0);
    for (0..data.params.folds) |fold| {
        var training: std.ArrayList(c.Row) = .empty;
        for (data.train) |row| if (c.u(@mod(row.id, c.n(data.params.folds))) != fold) c.append(c.Row, &training, row);
        const model = gaussian.train(training.items, features, data.classes.len, kind, data.params.empirical, smoothing, gamma);
        for (data.train, 0..) |row, i| if (c.u(@mod(row.id, c.n(data.params.folds))) == fold) {
            out.prediction[i] = gaussian.predict(model, row.values, data.costs).predicted;
            if (out.prediction[i] == row.label) {
                out.fold_correct[fold] += 1;
                out.correct += 1;
            }
        };
    }
    return out;
}
fn crossValidate(data: c.Dataset, features: c.Features, kind: usize) CrossValidation {
    return crossValidateValues(data, features, kind, data.params.smoothing, data.params.gamma);
}
fn confusionLines(out: *c.Lines, measures: evaluation.Measures, classes: []const []const u8) void {
    for (classes, 0..) |name, a| {
        var line: c.Text = .{};
        line.add("confusion {s}", .{name});
        for (0..classes.len) |b| line.add(" {d}", .{measures.confusion[a][b]});
        out.add("{s}", .{line.value()});
    }
}
fn mcnemarLine(a: []const u8, b: []const u8, comparison: evaluation.McNemar) []const u8 {
    return c.fmt("{s} {s} b01 {d} b10 {d} chi2 {s} significant {s}", .{ a, b, comparison.b01, comparison.b10,
         plot.real(comparison.chi2), if (comparison.chi2 > 3.841) "yes" else "no" });
}
fn eigenLess(eigen: linalg.Eigen, a: usize, b: usize) bool {
    return if (eigen.values[a] != eigen.values[b]) eigen.values[a] > eigen.values[b] else a < b;
}
fn eigenOrder(eigen: linalg.Eigen, size: usize) []usize {
    const out = c.alloc(usize, size);
    for (out, 0..) |*value, i| value.* = i;
    std.mem.sort(usize, out, eigen, eigenLess);
    return out;
}
const App = struct { data: c.Dataset, all: c.Features, models: [3]gaussian.Model, tests: [3][]const gaussian.Prediction,
     labels: [4][]const usize, cv: [3]CrossValidation };
const Ranked = struct { row: usize, q: f64, nearest: usize = 0 };
fn rankedLess(_: void, a: Ranked, b: Ranked) bool {
    return if (a.q != b.q) a.q > b.q else a.row < b.row;
}
fn modelReport(app: App) c.Lines {
    const data = app.data;
    const size = app.all.len;
    const classes = data.classes.len;
    const stats = app.models[0].stats;
    var out: c.Lines = .{};
    var part: c.Lines = .{};
    part.add("features {s}", .{plot.names(app.all, data.features)});
    var class_line: c.Text = .{};
    class_line.add("classes", .{});
    for (data.classes) |name| class_line.add(" {s}", .{name});
    part.add("{s}", .{class_line.value()});
    part.add("prior_mode {s}", .{if (data.params.empirical) "empirical" else "uniform"});
    for (data.classes, 0..) |name, k| part.add("class {s} letter {c} count {d} prior {s} mean {s}",
         .{ name, name[0] - 'a' + 'A', stats.counts[k], plot.real(stats.priors[k]), plot.numbers(stats.means[k],
         size) });
    paragraph(&out, &part);
    part.add("model NB", .{});
    part.add("smoothing epsilon {s} max_variance {s} added {s}", .{ plot.real(data.params.smoothing),
         plot.real(app.models[0].max_variance), plot.real(app.models[0].added) });
    for (data.classes, 0..) |name, k| {
        var diagonal = std.mem.zeroes(c.Vector);
        for (0..size) |j| diagonal[j] = app.models[0].covariance[k][j][j];
        part.add("class {s} variance {s} log_det {s}", .{ name, plot.numbers(diagonal, size), plot.real(app.models[0].log_det[k]) });
    }
    paragraph(&out, &part);
    part.add("model LDA", .{});
    part.add("log_det {s}", .{plot.real(app.models[1].log_det[0])});
    for (app.models[1].covariance[0][0..size]) |row| part.add("  {s}", .{plot.numbers(row, size)});
    for (data.classes, 0..) |name, k| {
        const coefficient = linalg.backward(app.models[1].lower[0], linalg.forward(app.models[1].lower[0],
             stats.means[k], size), size);
        var product: f64 = 0;
        for (0..size) |j| product += stats.means[k][j] * coefficient[j];
        part.add("class {s} intercept {s} coef {s}", .{ name, plot.real(@log(stats.priors[k]) - product / 2),
             plot.numbers(coefficient, size) });
    }
    paragraph(&out, &part);
    part.add("model QDA gamma {s}", .{plot.real(data.params.gamma)});
    for (data.classes, 0..) |name, k| {
        const eigen = linalg.jacobi(app.models[2].covariance[k], size);
        const order = eigenOrder(eigen, size);
        var values = std.mem.zeroes(c.Vector);
        for (order, 0..) |index, j| values[j] = eigen.values[index];
        part.add("class {s} log_det {s} eigenvalues {s} condition {s}", .{ name, plot.real(app.models[2].log_det[k]),
             plot.numbers(values, size), plot.real(values[0] / values[size - 1]) });
        for (app.models[2].covariance[k][0..size]) |row| part.add("  {s}", .{plot.numbers(row, size)});
    }
    paragraph(&out, &part);
    part.add("separation", .{});
    for (0..classes) |a| for (a + 1..classes) |b| {
        var delta = std.mem.zeroes(c.Vector);
        var average = std.mem.zeroes(c.Matrix);
        for (0..size) |j| delta[j] = stats.means[a][j] - stats.means[b][j];
        for (0..size) |i| for (0..size) |j| {
            average[i][j] = (app.models[2].covariance[a][i][j] + app.models[2].covariance[b][i][j]) / 2;
        };
        const lower = linalg.cholesky(average, size);
        const distance = linalg.quadratic(lower, delta, size) / 8 + (linalg.logDeterminant(lower,
             size) - (app.models[2].log_det[a] + app.models[2].log_det[b]) / 2) / 2;
        part.add("{s} {s} mahalanobis {s} bhattacharyya {s}", .{ data.classes[a], data.classes[b],
             plot.real(@sqrt(linalg.quadratic(app.models[1].lower[0], delta, size))), plot.real(distance) });
    };
    paragraph(&out, &part);
    part.add("outliers threshold {s}", .{plot.real(data.params.outlier)});
    var outliers: std.ArrayList(Ranked) = .empty;
    for (data.train, 0..) |row, i| {
        const q = gaussian.predict(app.models[2], row.values, data.costs).distance[row.label];
        if (q > data.params.outlier) c.append(Ranked, &outliers, .{ .row = i, .q = q });
    }
    std.mem.sort(Ranked, outliers.items, {}, rankedLess);
    for (outliers.items) |outlier| {
        const row = data.train[outlier.row];
        part.add("{d} {s} q {s}", .{ row.id, data.classes[row.label], plot.real(outlier.q) });
    }
    part.add("count {d}", .{outliers.items.len});
    paragraph(&out, &part);
    return out;
}
fn evaluationReport(app: App) c.Lines {
    const data = app.data;
    const classes = data.classes.len;
    const size = app.all.len;
    const n = data.train.len;
    const m = data.test_rows.len;
    var out: c.Lines = .{};
    out.add("test rows {d}", .{m});
    var part: c.Lines = .{};
    for (0..3) |kind| {
        const measures = evaluation.evaluate(data.test_rows, app.labels[kind], classes);
        part.add("model {s}", .{model_names[kind]});
        confusionLines(&part, measures, data.classes);
        part.add("accuracy {s}", .{plot.fraction(measures.accuracy)});
        part.add("balanced_accuracy {s}", .{plot.fraction(measures.balanced)});
        part.add("kappa {s}", .{plot.fraction(measures.kappa)});
        for (data.classes, 0..) |name, k| part.add("class {s} support {d} recall {s} precision {s} f1 {s}",
             .{ name, measures.support[k], plot.fraction(measures.recall[k]), if (measures.predicted[k] > 0) plot.fraction(measures.precision[k]) else "-",
             plot.fraction(measures.f1[k]) });
        var log_loss: f64 = 0;
        for (data.test_rows, app.tests[kind]) |row, prediction| log_loss += prediction.log_posterior[row.label];
        part.add("macro_f1 {s}", .{plot.real(measures.macro_f1)});
        part.add("log_loss {s}", .{plot.real(-log_loss / c.f(m))});
        part.add("errors {d}", .{m - measures.correct});
        for (data.test_rows, app.labels[kind], app.tests[kind]) |row, predicted, prediction| if (predicted != row.label) part.add("error {d} actual {s} predicted {s} confidence {s}",
             .{ row.id, data.classes[row.label], data.classes[predicted], plot.real(prediction.confidence) });
        var ece: f64 = 0;
        for (0..data.params.calibration.len + 1) |bin| {
            var count: usize = 0;
            var correct: usize = 0;
            var confidence: f64 = 0;
            for (data.test_rows, app.labels[kind], app.tests[kind]) |row, predicted, prediction| {
                var selected: usize = 0;
                while (selected < data.params.calibration.len and prediction.confidence >= data.params.calibration[selected]) selected += 1;
                if (selected == bin) {
                    count += 1;
                    correct += @intFromBool(predicted == row.label);
                    confidence += prediction.confidence;
                }
            }
            const low = if (bin == 0) @as(f64, 0) else data.params.calibration[bin - 1];
            const high = if (bin == data.params.calibration.len) @as(f64, 1) else data.params.calibration[bin];
            part.add("bin {s} {s} count {d} confidence {s} accuracy {s}", .{ plot.real(low), plot.real(high),
                 count, if (count > 0) plot.real(confidence / c.f(count)) else "-", if (count > 0) plot.fraction(evaluation.Fraction.init(c.n(correct),
                 c.n(count))) else "-" });
            ece += @abs(c.f(correct) - confidence);
        }
        part.add("ece {s}", .{plot.real(ece / c.f(m))});
        for (data.params.reject) |threshold| {
            var count: usize = 0;
            var correct: usize = 0;
            for (data.test_rows, app.labels[kind], app.tests[kind]) |row, predicted, prediction| if (prediction.confidence >= threshold) {
                count += 1;
                correct += @intFromBool(predicted == row.label);
            };
            part.add("reject {s} accepted {d} coverage {s} accuracy {s}", .{ plot.real(threshold),
                 count, plot.fraction(evaluation.Fraction.init(c.n(count), c.n(m))), if (count > 0) plot.fraction(evaluation.Fraction.init(c.n(correct),
                 c.n(count))) else "-" });
        }
        paragraph(&out, &part);
    }
    const ensemble = evaluation.evaluate(data.test_rows, app.labels[3], classes);
    part.add("ensemble soft_vote", .{});
    part.add("accuracy {s} balanced_accuracy {s} kappa {s}", .{ plot.fraction(ensemble.accuracy),
         plot.fraction(ensemble.balanced), plot.fraction(ensemble.kappa) });
    paragraph(&out, &part);
    part.add("mcnemar test", .{});
    for (0..4) |a| for (a + 1..4) |b| part.add("{s}", .{mcnemarLine(model_names[a], model_names[b],
         evaluation.mcnemar(data.test_rows, app.labels[a], app.labels[b]))});
    paragraph(&out, &part);
    part.add("costs", .{});
    for (0..3) |kind| {
        var argmax: f64 = 0;
        var decision: f64 = 0;
        var changed: usize = 0;
        var correct: usize = 0;
        for (data.test_rows, app.labels[kind], app.tests[kind]) |row, predicted, prediction| {
            argmax += data.costs[row.label][predicted];
            decision += data.costs[row.label][prediction.decision];
            changed += @intFromBool(prediction.decision != predicted);
            correct += @intFromBool(prediction.decision == row.label);
        }
        part.add("{s} argmax_total {s} decision_total {s} changed {d} decision_accuracy {s}", .{ model_names[kind],
             plot.real(argmax), plot.real(decision), changed, plot.fraction(evaluation.Fraction.init(c.n(correct),
             c.n(m))) });
    }
    paragraph(&out, &part);
    part.add("novelty threshold {s}", .{plot.real(data.params.outlier)});
    var novel: std.ArrayList(Ranked) = .empty;
    for (app.tests[2], 0..) |prediction, i| {
        var nearest: usize = 0;
        for (1..classes) |k| if (prediction.distance[k] < prediction.distance[nearest]) {
            nearest = k;
        };
        if (prediction.distance[nearest] > data.params.outlier) c.append(Ranked, &novel, .{ .row = i,
             .q = prediction.distance[nearest], .nearest = nearest });
    }
    std.mem.sort(Ranked, novel.items, {}, rankedLess);
    for (novel.items) |row| part.add("{d} nearest {s} q {s}", .{ data.test_rows[row.row].id, data.classes[row.nearest],
         plot.real(row.q) });
    part.add("count {d}", .{novel.items.len});
    paragraph(&out, &part);
    var generator: evaluation.Generator = .{ .state = data.params.seed };
    var bootstrap: [3][]usize = undefined;
    for (&bootstrap) |*counts| counts.* = c.alloc(usize, data.params.bootstrap);
    var comparisons = std.mem.zeroes([3][3]usize);
    for (0..data.params.bootstrap) |sample| {
        var counts = std.mem.zeroes([3]usize);
        for (0..m) |_| {
            const row = c.u(@mod(generator.draw(), c.n(m)));
            for (0..3) |kind| counts[kind] += @intFromBool(app.labels[kind][row] == data.test_rows[row].label);
        }
        for (0..3) |kind| bootstrap[kind][sample] = counts[kind];
        var pair: usize = 0;
        for (0..3) |a| for (a + 1..3) |b| {
            comparisons[pair][if (counts[a] > counts[b]) 0 else if (counts[a] == counts[b]) 1 else 2] += 1;
            pair += 1;
        };
    }
    part.add("bootstrap resamples {d} seed {d}", .{ data.params.bootstrap, data.params.seed });
    for (0..3) |kind| {
        var sum: usize = 0;
        for (bootstrap[kind]) |value| sum += value;
        std.mem.sort(usize, bootstrap[kind], {}, std.sort.asc(usize));
        const offset = data.params.bootstrap / 40;
        part.add("{s} mean {s} interval {s} {s}", .{ model_names[kind], plot.real(c.f(sum) / c.f(data.params.bootstrap) / c.f(m)),
             plot.fraction(evaluation.Fraction.init(c.n(bootstrap[kind][offset]), c.n(m))), plot.fraction(evaluation.Fraction.init(c.n(bootstrap[kind][data.params.bootstrap - 1 - offset]),
             c.n(m))) });
    }
    var pair: usize = 0;
    for (0..3) |a| for (a + 1..3) |b| {
        part.add("{s} {s} wins {d} ties {d} losses {d}", .{ model_names[a], model_names[b], comparisons[pair][0],
             comparisons[pair][1], comparisons[pair][2] });
        pair += 1;
    };
    paragraph(&out, &part);
    part.add("prior_sensitivity alternative {s}", .{if (data.params.empirical) "uniform" else "empirical"});
    for (0..3) |kind| {
        const model = gaussian.train(data.train, app.all, classes, kind, !data.params.empirical, data.params.smoothing,
             data.params.gamma);
        const predicted = predictions(data, model, data.test_rows);
        const measures = evaluation.evaluate(data.test_rows, predicted, classes);
        var changed: usize = 0;
        for (predicted, app.labels[kind]) |a, b| changed += @intFromBool(a != b);
        part.add("{s} accuracy {s} balanced_accuracy {s} changed {d}", .{ model_names[kind], plot.fraction(measures.accuracy),
             plot.fraction(measures.balanced), changed });
    }
    paragraph(&out, &part);
    part.add("learning_curve", .{});
    for (data.params.curve) |limit| {
        var rows: std.ArrayList(c.Row) = .empty;
        var seen = std.mem.zeroes([5]usize);
        for (data.train) |row| {
            if (seen[row.label] < limit) c.append(c.Row, &rows, row);
            seen[row.label] += 1;
        }
        var line: c.Text = .{};
        line.add("size {d} rows {d}", .{ limit, rows.items.len });
        for (0..3) |kind| {
            const model = fit(data, rows.items, app.all, kind);
            line.add(" {s} {s}", .{ model_names[kind], plot.fraction(evaluation.Fraction.init(c.n(modelCorrect(data,
                 model, data.test_rows)), c.n(m))) });
        }
        part.add("{s}", .{line.value()});
    }
    paragraph(&out, &part);
    part.add("cross_validation folds {d}", .{data.params.folds});
    const fold_sizes = c.alloc(usize, data.params.folds);
    @memset(fold_sizes, 0);
    for (data.train) |row| fold_sizes[c.u(@mod(row.id, c.n(data.params.folds)))] += 1;
    part.add("fold_sizes {s}", .{plot.integers(fold_sizes)});
    var best_subset: ?usize = null;
    var best_model: usize = 0;
    var best_correct: usize = 0;
    for (data.params.subsets.items, 0..) |selected, subset| {
        part.add("subset {s} features {s}", .{ selected.name, plot.names(selected.features, data.features) });
        for (0..3) |kind| {
            const result = crossValidate(data, selected.features, kind);
            part.add("  {s} fold_correct {s} correct {d} accuracy {s}", .{ model_names[kind], plot.integers(result.fold_correct),
                 result.correct, plot.fraction(evaluation.Fraction.init(c.n(result.correct), c.n(n))) });
            if (best_subset == null or result.correct > best_correct or (result.correct == best_correct and selected.features.len < data.params.subsets.items[best_subset.?].features.len)) {
                best_subset = subset;
                best_model = kind;
                best_correct = result.correct;
            }
        }
    }
    const selected = data.params.subsets.items[best_subset.?];
    part.add("best subset {s} model {s} correct {d} accuracy {s}", .{ selected.name, model_names[best_model],
         best_correct, plot.fraction(evaluation.Fraction.init(c.n(best_correct), c.n(n))) });
    const selected_model = fit(data, data.train, selected.features, best_model);
    const refit_correct = modelCorrect(data, selected_model, data.test_rows);
    part.add("refit_test correct {d} accuracy {s}", .{ refit_correct, plot.fraction(evaluation.Fraction.init(c.n(refit_correct),
         c.n(m))) });
    paragraph(&out, &part);
    part.add("mcnemar cross_validation", .{});
    for (0..3) |a| for (a + 1..3) |b| part.add("{s}", .{mcnemarLine(model_names[a], model_names[b],
         evaluation.mcnemar(data.train, app.cv[a].prediction, app.cv[b].prediction))});
    paragraph(&out, &part);
    for (0..3) |kind| {
        const measures = evaluation.evaluate(data.train, app.cv[kind].prediction, classes);
        part.add("cv_confusion model {s}", .{model_names[kind]});
        confusionLines(&part, measures, data.classes);
        part.add("balanced_accuracy {s} kappa {s}", .{ plot.fraction(measures.balanced), plot.fraction(measures.kappa) });
        paragraph(&out, &part);
    }
    part.add("leave_one_out", .{});
    for (0..3) |kind| {
        var correct: usize = 0;
        for (data.train, 0..) |row, i| {
            var rows: std.ArrayList(c.Row) = .empty;
            for (data.train, 0..) |other, j| if (i != j) c.append(c.Row, &rows, other);
            const model = fit(data, rows.items, app.all, kind);
            correct += @intFromBool(gaussian.predict(model, row.values, data.costs).predicted == row.label);
        }
        part.add("{s} correct {d} accuracy {s}", .{ model_names[kind], correct, plot.fraction(evaluation.Fraction.init(c.n(correct),
             c.n(n))) });
    }
    paragraph(&out, &part);
    for (0..3) |kind| {
        part.add("forward_selection model {s}", .{model_names[kind]});
        var features: std.ArrayList(usize) = .empty;
        var best_step: usize = 0;
        var best: ?usize = null;
        for (1..size + 1) |step| {
            var chosen: ?usize = null;
            var correct: usize = 0;
            for (0..size) |feature| if (std.mem.indexOfScalar(usize, features.items, feature) == null) {
                const trial = c.alloc(usize, features.items.len + 1);
                @memcpy(trial[0..features.items.len], features.items);
                trial[features.items.len] = feature;
                const value = crossValidate(data, trial, kind).correct;
                if (chosen == null or value > correct) {
                    chosen = feature;
                    correct = value;
                }
            };
            c.append(usize, &features, chosen.?);
            part.add("step {d} add {s} correct {d} accuracy {s}", .{ step, data.features[chosen.?],
                 correct, plot.fraction(evaluation.Fraction.init(c.n(correct), c.n(n))) });
            if (best == null or correct > best.?) {
                best = correct;
                best_step = step;
            }
        }
        part.add("best_step {d} features {s}", .{ best_step, plot.names(features.items[0..best_step], data.features) });
        paragraph(&out, &part);
    }
    for (0..2) |tuning| {
        const kind: usize = if (tuning == 0) 0 else 2;
        const grid = if (tuning == 0) data.params.smoothing_grid else data.params.gamma_grid;
        part.add("{s}", .{if (tuning == 0) "nb_smoothing_path" else "qda_gamma_path"});
        var best: ?usize = null;
        var chosen: f64 = 0;
        for (grid) |value| {
            const correct = crossValidateValues(data, app.all, kind, if (tuning == 0) value else data.params.smoothing,
                 if (tuning == 1) value else data.params.gamma).correct;
            part.add("value {s} correct {d} accuracy {s}", .{ plot.real(value), correct, plot.fraction(evaluation.Fraction.init(c.n(correct),
                 c.n(n))) });
            if (best == null or correct >= best.?) {
                best = correct;
                chosen = value;
            }
        }
        const model = gaussian.train(data.train, app.all, classes, kind, data.params.empirical, if (tuning == 0) chosen else data.params.smoothing,
             if (tuning == 1) chosen else data.params.gamma);
        const correct = modelCorrect(data, model, data.test_rows);
        part.add("best {s} test correct {d} accuracy {s}", .{ plot.real(chosen), correct, plot.fraction(evaluation.Fraction.init(c.n(correct),
             c.n(m))) });
        paragraph(&out, &part);
    }
    return out;
}
fn emptyMap(width: usize, height: usize, value: u8) [][]u8 {
    const out = c.alloc([]u8, height);
    for (out) |*row| {
        row.* = c.alloc(u8, width);
        @memset(row.*, value);
    }
    return out;
}
fn boundaries(data: c.Dataset) c.Lines {
    var out: c.Lines = .{};
    const width = data.params.map_width;
    const height = data.params.map_height;
    const classes = data.classes.len;
    for (data.params.pairs.items) |pair| {
        const features = c.dupe(usize, &.{ pair.x, pair.y });
        var xmin = data.train[0].values[pair.x];
        var xmax = xmin;
        var ymin = data.train[0].values[pair.y];
        var ymax = ymin;
        for (data.train) |row| {
            xmin = @min(xmin, row.values[pair.x]);
            xmax = @max(xmax, row.values[pair.x]);
            ymin = @min(ymin, row.values[pair.y]);
            ymax = @max(ymax, row.values[pair.y]);
        }
        const dx = (xmax - xmin) / c.f(width - 1);
        const dy = (ymax - ymin) / c.f(height - 1);
        var part: c.Lines = .{};
        part.add("pair {s} {s}", .{ data.features[pair.x], data.features[pair.y] });
        part.add("x {s} {s} {s} y {s} {s} {s} grid {d}x{d}", .{ data.features[pair.x], plot.real(xmin),
             plot.real(xmax), data.features[pair.y], plot.real(ymin), plot.real(ymax), width, height });
        var grid: [3][]gaussian.Prediction = undefined;
        for (0..3) |kind| {
            const model = fit(data, data.train, features, kind);
            const correct = modelCorrect(data, model, data.train);
            const cv = crossValidate(data, features, kind).correct;
            part.add("model {s} train_accuracy {s} cv_accuracy {s}", .{ model_names[kind], plot.fraction(evaluation.Fraction.init(c.n(correct),
                 c.n(data.train.len))), plot.fraction(evaluation.Fraction.init(c.n(cv), c.n(data.train.len))) });
            const map = emptyMap(width, height, ' ');
            var cells = std.mem.zeroes([5]usize);
            grid[kind] = c.alloc(gaussian.Prediction, width * height);
            for (0..height) |row| for (0..width) |column| {
                var values = std.mem.zeroes(c.Vector);
                values[pair.x] = xmin + c.f(column) * dx;
                values[pair.y] = ymax - c.f(row) * dy;
                const prediction = gaussian.predict(model, values, data.costs);
                grid[kind][row * width + column] = prediction;
                map[row][column] = data.classes[prediction.predicted][0] - 'a' + 'A';
                cells[prediction.predicted] += 1;
            };
            part.extend(plot.frame(map));
            var line: c.Text = .{};
            line.add("cells", .{});
            for (data.classes, 0..) |name, k| line.add(" {c} {d}", .{ name[0] - 'a' + 'A', cells[k] });
            part.add("{s}", .{line.value()});
        }
        const agreement = emptyMap(width, height, '.');
        const uncertainty = emptyMap(width, height, ' ');
        const points = emptyMap(width, height, ' ');
        var disagreement: usize = 0;
        const levels = " .:-=+*#%@";
        for (0..height) |row| for (0..width) |column| {
            const index = row * width + column;
            const a = grid[0][index].predicted;
            const b = grid[1][index].predicted;
            const d = grid[2][index].predicted;
            const distinct: usize = if (a == b and b == d) 1 else if (a == b or a == d or b == d) 2 else 3;
            if (distinct > 1) {
                agreement[row][column] = '0' + @as(u8, @intCast(distinct));
                disagreement += 1;
            }
            const u = (1 - grid[2][index].confidence) / (1 - 1 / c.f(classes));
            const level = @min(@as(usize, 9), @as(usize, @intFromFloat(@floor(10 * u))));
            uncertainty[row][column] = levels[level];
        };
        for (data.train) |row| {
            const column = plot.cell(row.values[pair.x], xmin, xmax, width);
            const r = height - 1 - plot.cell(row.values[pair.y], ymin, ymax, height);
            const letter = data.classes[row.label][0];
            points[r][column] = if (points[r][column] == ' ' or points[r][column] == letter) letter else '*';
        }
        part.add("agreement", .{});
        part.extend(plot.frame(agreement));
        part.add("disagreement_cells {d}", .{disagreement});
        part.add("uncertainty QDA", .{});
        part.extend(plot.frame(uncertainty));
        part.add("points", .{});
        part.extend(plot.frame(points));
        paragraph(&out, &part);
    }
    return out;
}
fn project(point: c.Vector, stats: gaussian.Statistics, directions: [2]c.Vector, size: usize) [2]f64 {
    var out: [2]f64 = .{ 0, 0 };
    for (0..2) |t| for (0..size) |j| {
        out[t] += directions[t][j] * (point[j] - stats.center[j]);
    };
    return out;
}
fn nearestCorrect(rows: c.Rows, stats: gaussian.Statistics, directions: [2]c.Vector, centers: [5][2]f64,
     classes: usize, size: usize, dims: usize) usize {
    var count: usize = 0;
    for (rows) |row| {
        const point = project(row.values, stats, directions, size);
        var selected: usize = 0;
        var smallest: f64 = 0;
        for (0..classes) |k| {
            var distance: f64 = 0;
            for (0..dims) |t| distance += (point[t] - centers[k][t]) * (point[t] - centers[k][t]);
            if (k == 0 or distance < smallest) {
                smallest = distance;
                selected = k;
            }
        }
        count += @intFromBool(selected == row.label);
    }
    return count;
}
fn valueLess(values: c.Vector, a: usize, b: usize) bool {
    return if (values[a] != values[b]) values[a] > values[b] else a < b;
}
fn projection(app: App) c.Lines {
    const data = app.data;
    const lda = app.models[1];
    const stats = lda.stats;
    const size = app.all.len;
    const classes = data.classes.len;
    var within = std.mem.zeroes(c.Matrix);
    var between = std.mem.zeroes(c.Matrix);
    var f_values = std.mem.zeroes(c.Vector);
    for (0..size) |a| for (0..size) |b| {
        for (0..classes) |k| within[a][b] += stats.scatter[k][a][b];
        for (0..classes) |k| between[a][b] += c.f(stats.counts[k]) * (stats.means[k][a] - stats.center[a]) * (stats.means[k][b] - stats.center[b]);
    };
    for (0..size) |j| f_values[j] = (between[j][j] / c.f(classes - 1)) / (within[j][j] / c.f(stats.count - classes));
    const feature_order = c.dupe(usize, app.all);
    std.mem.sort(usize, feature_order, f_values, valueLess);
    var out: c.Lines = .{};
    out.add("univariate", .{});
    for (feature_order, 1..) |j, rank| out.add("rank {d} {s} f {s} between {s} within {s}", .{ rank,
         data.features[j], plot.real(f_values[j]), plot.real(between[j][j]), plot.real(within[j][j]) });
    const lower = linalg.cholesky(within, size);
    var y = std.mem.zeroes(c.Matrix);
    var z = std.mem.zeroes(c.Matrix);
    var symmetric = std.mem.zeroes(c.Matrix);
    for (0..size) |j| {
        var column = std.mem.zeroes(c.Vector);
        for (0..size) |a| column[a] = between[a][j];
        const result = linalg.forward(lower, column, size);
        for (0..size) |a| y[a][j] = result[a];
    }
    for (0..size) |i| {
        const result = linalg.forward(lower, y[i], size);
        for (0..size) |a| z[a][i] = result[a];
    }
    for (0..size) |a| for (0..size) |b| {
        symmetric[a][b] = (z[a][b] + z[b][a]) / 2;
    };
    const eigen = linalg.jacobi(symmetric, size);
    const order = eigenOrder(eigen, size);
    var total: f64 = 0;
    for (eigen.values[0..size]) |value| total += value;
    var values = std.mem.zeroes(c.Vector);
    var ratios = std.mem.zeroes(c.Vector);
    for (order, 0..) |index, j| {
        values[j] = eigen.values[index];
        ratios[j] = values[j] / total;
    }
    var directions = std.mem.zeroes([2]c.Vector);
    var standardized = std.mem.zeroes([2]c.Vector);
    for (0..2) |t| {
        var column = std.mem.zeroes(c.Vector);
        for (0..size) |j| column[j] = eigen.vectors[j][order[t]];
        var direction = linalg.backward(lower, column, size);
        var squares: f64 = 0;
        for (direction[0..size]) |value| squares += value * value;
        const norm = @sqrt(squares);
        var largest: usize = 0;
        for (direction[0..size], 0..) |*value, j| {
            value.* /= norm;
            if (@abs(value.*) > @abs(direction[largest])) largest = j;
        }
        if (direction[largest] < 0) for (direction[0..size]) |*value| {
            value.* = -value.*;
        };
        directions[t] = direction;
        for (0..size) |j| standardized[t][j] = direction[j] * @sqrt(lda.covariance[0][j][j]);
    }
    var centers = std.mem.zeroes([5][2]f64);
    var spread = std.mem.zeroes([5][2]f64);
    for (0..classes) |k| {
        centers[k] = project(stats.means[k], stats, directions, size);
        for (0..2) |t| {
            var sum: f64 = 0;
            for (data.train) |row| if (row.label == k) {
                const point = project(row.values, stats, directions, size);
                sum += (point[t] - centers[k][t]) * (point[t] - centers[k][t]);
            };
            spread[k][t] = @sqrt(sum / c.f(stats.counts[k]));
        }
    }
    var part: c.Lines = .{};
    part.add("fisher features {s}", .{plot.names(app.all, data.features)});
    part.add("center {s}", .{plot.numbers(stats.center, size)});
    part.add("sweeps {d}", .{eigen.sweeps});
    part.add("eigenvalues {s}", .{plot.numbers(values, size)});
    part.add("ratios {s}", .{plot.numbers(ratios, size)});
    for (0..2) |t| {
        part.add("direction {d} {s}", .{ t + 1, plot.numbers(directions[t], size) });
        part.add("standardized {d} {s}", .{ t + 1, plot.numbers(standardized[t], size) });
    }
    for (data.classes, 0..) |name, k| part.add("centroid {s} {s} {s} spread {s} {s}", .{ name, plot.real(centers[k][0]),
         plot.real(centers[k][1]), plot.real(spread[k][0]), plot.real(spread[k][1]) });
    for (1..3) |dims| part.add("nearest_centroid dims {d} train {s} test {s}", .{ dims, plot.fraction(evaluation.Fraction.init(c.n(nearestCorrect(data.train,
         stats, directions, centers, classes, size, dims)), c.n(data.train.len))), plot.fraction(evaluation.Fraction.init(c.n(nearestCorrect(data.test_rows,
         stats, directions, centers, classes, size, dims)), c.n(data.test_rows.len))) });
    paragraph(&out, &part);
    const points = c.alloc([2]f64, data.train.len);
    for (data.train, points) |row, *point| point.* = project(row.values, stats, directions, size);
    var lo1 = points[0][0];
    var hi1 = lo1;
    var lo2 = points[0][1];
    var hi2 = lo2;
    for (points) |point| {
        lo1 = @min(lo1, point[0]);
        hi1 = @max(hi1, point[0]);
        lo2 = @min(lo2, point[1]);
        hi2 = @max(hi2, point[1]);
    }
    const width = data.params.plot_width;
    const height = data.params.plot_height;
    const cells = emptyMap(width, height, ' ');
    for (points, data.train) |point, row| {
        const column = plot.cell(point[0], lo1, hi1, width);
        const r = height - 1 - plot.cell(point[1], lo2, hi2, height);
        const letter = data.classes[row.label][0];
        cells[r][column] = if (cells[r][column] == ' ' or cells[r][column] == letter) letter else '*';
    }
    for (data.classes, 0..) |name, k| cells[height - 1 - plot.cell(centers[k][1], lo2, hi2, height)][plot.cell(centers[k][0],
         lo1, hi1, width)] = name[0] - 'a' + 'A';
    part.add("plot x {s} {s} y {s} {s} size {d}x{d}", .{ plot.real(lo1), plot.real(hi1), plot.real(lo2),
         plot.real(hi2), width, height });
    part.extend(plot.frame(cells));
    paragraph(&out, &part);
    return out;
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    c.allocator = arena.allocator();
    try std.Io.Dir.cwd().createDirPath(init.io, "output");
    const data = try c.readDataset(init.io);
    const all = c.alloc(usize, data.features.len);
    for (all, 0..) |*feature, j| feature.* = j;
    var app: App = .{ .data = data, .all = all, .models = undefined, .tests = undefined, .labels = undefined, .cv = undefined };
    for (0..3) |kind| {
        app.models[kind] = fit(data, data.train, all, kind);
        const tests = c.alloc(gaussian.Prediction, data.test_rows.len);
        const labels = c.alloc(usize, data.test_rows.len);
        for (data.test_rows, tests, labels) |row, *prediction, *label| {
            prediction.* = gaussian.predict(app.models[kind], row.values, data.costs);
            label.* = prediction.predicted;
        }
        app.tests[kind] = tests;
        app.labels[kind] = labels;
        app.cv[kind] = crossValidate(data, all, kind);
    }
    const ensemble = c.alloc(usize, data.test_rows.len);
    for (ensemble, 0..) |*label, i| {
        var selected: usize = 0;
        var posterior = std.mem.zeroes([5]f64);
        for (0..data.classes.len) |k| {
            var sum: f64 = 0;
            for (0..3) |kind| sum += app.tests[kind][i].posterior[k];
            posterior[k] = sum / 3;
            if (posterior[k] > posterior[selected]) selected = k;
        }
        label.* = selected;
    }
    app.labels[3] = ensemble;
    try plot.write(init.io, "models.txt", modelReport(app));
    var csv: c.Lines = .{};
    var header: c.Text = .{};
    header.add("id,model,actual,predicted,decision", .{});
    for (data.classes) |name| header.add(",{s}", .{name});
    csv.add("{s}", .{header.value()});
    for (data.test_rows, 0..) |row, i| for (0..3) |kind| {
        const prediction = app.tests[kind][i];
        var line: c.Text = .{};
        line.add("{d},{s},{s},{s},{s}", .{ row.id, model_names[kind], data.classes[row.label], data.classes[prediction.predicted],
             data.classes[prediction.decision] });
        for (prediction.posterior[0..data.classes.len]) |value| line.add(",{s}", .{plot.real(value)});
        csv.add("{s}", .{line.value()});
    };
    try plot.write(init.io, "predictions.csv", csv);
    try plot.write(init.io, "evaluation.txt", evaluationReport(app));
    try plot.write(init.io, "boundaries.txt", boundaries(data));
    try plot.write(init.io, "projection.txt", projection(app));
}
