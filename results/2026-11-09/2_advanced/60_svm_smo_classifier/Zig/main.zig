const std = @import("std");
const c = @import("dataset.zig");
const kernels = @import("kernels.zig");
const smo = @import("smo.zig");
const multi_module = @import("multiclass.zig");
const e = @import("evaluation.zig");
fn selectedData(data: []const c.Example, indices: []const usize) []const c.Example {
    const out = c.alloc(c.Example, indices.len);
    for (indices, out) |index, *example| example.* = data[index];
    return out;
}
fn selectedMatrix(matrix: c.Matrix, indices: []const usize) c.Matrix {
    const out = c.alloc([]f64, indices.len);
    for (out, 0..) |*row, i| {
        row.* = c.alloc(f64, indices.len);
        for (row.*, 0..) |*value, j| value.* = matrix[indices[i]][indices[j]];
    }
    return out;
}
fn decisions(model: smo.Model, data: []const c.Example) []f64 {
    const out = c.alloc(f64, data.len);
    for (data, out) |example, *value| value.* = model.decision(example.point);
    return out;
}
const Support = struct { total: i64 = 0, bound: i64 = 0, free: i64 = 0, by_bound: [2]i64 = .{ 0,
     0 }, by_free: [2]i64 = .{ 0, 0 } };
fn support(model: smo.Model) Support {
    var out: Support = .{};
    for (model.alpha, model.data) |alpha, example| if (alpha > 0) {
        out.total += 1;
        const label: usize = if (example.label == 1) 0 else 1;
        if (alpha == model.c) {
            out.bound += 1;
            out.by_bound[label] += 1;
        } else {
            out.free += 1;
            out.by_free[label] += 1;
        }
    };
    return out;
}
fn supportText(model: smo.Model) []const u8 {
    const value = support(model);
    return c.fmt("support_vectors {d} bound {d} free {d}", .{ value.total, value.bound, value.free });
}
fn runInfo(model: smo.Model) []const u8 {
    return c.fmt("passes {d} steps {d} converged {s}", .{ model.passes.items.len, model.steps,
         if (model.converged) "yes" else "no" });
}
const Objectives = struct { q: f64, dual: f64 };
fn objectives(alpha: []const f64, data: []const c.Example, matrix: c.Matrix) Objectives {
    var q: f64 = 0;
    var total: f64 = 0;
    for (alpha, data, 0..) |value, example, i| {
        var sum: f64 = 0;
        for (alpha, data, 0..) |other, point, j| if (other > 0) {
            sum += other * c.f(point.label) * matrix[i][j];
        };
        q += value * c.f(example.label) * sum;
        total += value;
    }
    return .{ .q = q, .dual = total - q / 2 };
}
const FoldResult = struct { train: usize, test_count: usize, correct: i64, sv: i64, passes: usize,
     steps: usize, converged: bool };
const CV = struct { kernel: usize, candidate: usize, correct: i64 = 0, sv: i64 = 0, passes: usize = 0,
     steps: usize = 0, values: []f64, folds: []FoldResult };
fn foldModel(input: c.Input, kernel: c.Kernel, matrix: c.Matrix, coefficient: f64, fold: e.Fold,
     values: []f64) FoldResult {
    var scratch = std.heap.ArenaAllocator.init(c.backing_allocator);
    defer scratch.deinit();
    const previous = c.allocator;
    c.allocator = scratch.allocator();
    defer c.allocator = previous;
    const model = smo.train(selectedData(input.train, fold.train), kernel, selectedMatrix(matrix,
         fold.train), coefficient, input.params);
    var correct: i64 = 0;
    for (fold.test_data) |index| {
        values[index] = model.decision(input.train[index].point);
        correct += @intFromBool(e.sign(values[index]) == input.train[index].label);
    }
    return .{ .train = fold.train.len, .test_count = fold.test_data.len, .correct = correct,
         .sv = support(model).total, .passes = model.passes.items.len, .steps = model.steps,
         .converged = model.converged };
}
fn crossValidate(input: c.Input, kernel: usize, candidate: usize, matrix: c.Matrix) CV {
    var out: CV = .{ .kernel = kernel, .candidate = candidate, .values = c.alloc(f64, input.train.len),
         .folds = c.alloc(FoldResult, input.params.folds) };
    for (e.folds(input.train.len, input.params.folds), out.folds) |fold, *record| {
        record.* = foldModel(input, input.params.kernels.items[kernel], matrix, input.params.c_grid[candidate],
             fold, out.values);
        out.correct += record.correct;
        out.sv += record.sv;
        out.passes += record.passes;
        out.steps += record.steps;
    }
    return out;
}
const Metrics = struct { training: []f64, testing: []f64, sv: Support, weights: c.Point = .{ 0,
     0 }, alignment: f64 = 0, equality: f64 = 0, q: f64 = 0, dual: f64 = 0, primal: f64 = 0,
     violation: f64 = 0, radius: f64 = 0, positive_mean: f64 = 0, negative_mean: f64 = 0, violations: i64 = 0,
     estimated_errors: i64 = 0, train_correct: i64 = 0, inside: i64 = 0, evaluation: e.Evaluation = .{} };
fn metrics(input: c.Input, model: smo.Model) Metrics {
    var out: Metrics = .{ .training = model.trainingDecisions(), .testing = decisions(model,
         input.test_data), .sv = support(model) };
    const objective = objectives(model.alpha, model.data, model.matrix);
    out.q = objective.q;
    out.dual = objective.dual;
    var sy: f64 = 0;
    var sg: f64 = 0;
    var xi: f64 = 0;
    var maximum_diagonal = model.matrix[0][0];
    var minimum = model.matrix[0][0];
    for (model.data, model.alpha, 0..) |example, alpha, i| {
        for (model.data, 0..) |other, j| {
            const value = model.matrix[i][j];
            sy += c.f(example.label * other.label) * value;
            sg += value * value;
            minimum = @min(minimum, value);
        }
        maximum_diagonal = @max(maximum_diagonal, model.matrix[i][i]);
        out.equality += alpha * c.f(example.label);
        for (0..2) |coordinate| out.weights[coordinate] += alpha * c.f(example.label) * example.point[coordinate];
        const residual = c.f(example.label) * out.training[i] - 1;
        const violation = if (alpha == 0) @max(0, -residual) else if (alpha == model.c) @max(0,
             residual) else @abs(residual);
        out.violations += @intFromBool(violation > input.params.tolerance);
        out.violation = @max(out.violation, violation);
        xi += @max(0, 1 - c.f(example.label) * out.training[i]);
        out.train_correct += @intFromBool(e.sign(out.training[i]) == example.label);
    }
    out.alignment = sy / (c.f(model.data.len) * @sqrt(sg));
    out.radius = maximum_diagonal - minimum;
    out.primal = out.q / 2 + model.c * xi;
    for (model.data, model.alpha, 0..) |example, alpha, i| out.estimated_errors += @intFromBool(2 * alpha * out.radius + @max(0,
         1 - c.f(example.label) * out.training[i]) >= 1);
    var positive: i64 = 0;
    var negative: i64 = 0;
    for (input.test_data, out.testing) |example, value| {
        out.inside += @intFromBool(@abs(value) < 1);
        if (example.label == 1) {
            out.positive_mean += value;
            positive += 1;
        } else {
            out.negative_mean += value;
            negative += 1;
        }
    }
    out.positive_mean /= c.f(positive);
    out.negative_mean /= c.f(negative);
    out.evaluation = e.evaluate(input.test_data, out.testing);
    return out;
}
fn modelReport(out: *c.Lines, input: c.Input, model: smo.Model, value: Metrics) void {
    const n = c.n(input.train.len);
    const m = c.n(input.test_data.len);
    const test_eval = value.evaluation;
    out.add("model {s}", .{model.kernel.name});
    out.add("kernel {s}", .{kernels.description(model.kernel)});
    out.add("C {s}", .{e.real(model.c, 4)});
    out.add("alignment {s}", .{e.real(value.alignment, 6)});
    out.add("passes {d} full {d} nonbound {d} converged {s}", .{ model.passes.items.len, model.full,
         model.nonbound, if (model.converged) "yes" else "no" });
    out.add("examined {d} steps {d}", .{ model.examined, model.steps });
    out.add("choice heuristic {d} nonbound_loop {d} full_loop {d}", .{ model.choices[0], model.choices[1],
         model.choices[2] });
    out.add("clipping none {d} lower {d} upper {d}", .{ model.clipping[0], model.clipping[1], model.clipping[2] });
    out.add("{s}", .{supportText(model)});
    out.add("b {s}", .{e.real(model.b, 6)});
    out.add("equality {s}", .{e.real(value.equality, 6)});
    if (model.kernel.kind == .linear) out.add("w {s} {s}", .{ e.real(value.weights[0], 6),
         e.real(value.weights[1], 6) });
    out.add("sv_by_class positive bound {d} free {d} negative bound {d} free {d}", .{ value.sv.by_bound[0],
         value.sv.by_free[0], value.sv.by_bound[1], value.sv.by_free[1] });
    out.add("norm {s} margin {s}", .{ e.real(@sqrt(value.q), 6), e.real(2 / @sqrt(value.q), 6) });
    out.add("dual_objective {s}", .{e.real(value.dual, 6)});
    out.add("primal_objective {s}", .{e.real(value.primal, 6)});
    out.add("duality_gap {s}", .{e.real(value.primal - value.dual, 6)});
    out.add("kkt_violations {d} max {s}", .{ value.violations, e.real(value.violation, 6) });
    out.add("xi_alpha radius {s} errors {d}/{d} accuracy {s}", .{ e.real(value.radius, 6),
         value.estimated_errors, n, e.ratio(n - value.estimated_errors, n) });
    out.add("train correct {d}/{d} accuracy {s}", .{ value.train_correct, n, e.ratio(value.train_correct, n) });
    out.add("test correct {d}/{d} accuracy {s} tp {d} fp {d} tn {d} fn {d}", .{ test_eval.correct(),
         m, e.ratio(test_eval.correct(), m), test_eval.tp, test_eval.fp, test_eval.tn, test_eval.fn_count });
    out.add("test precision {s} recall {s} f1 {s} auc {s}", .{ e.ratio(test_eval.tp, test_eval.tp + test_eval.fp),
         e.ratio(test_eval.tp, test_eval.tp + test_eval.fn_count), e.ratio(2 * test_eval.tp,
         2 * test_eval.tp + test_eval.fp + test_eval.fn_count), e.real(e.auc(input.test_data,
         value.testing), 4) });
    out.add("test inside_margin {d}", .{value.inside});
    out.add("test mean_decision positive {s} negative {s}", .{ e.real(value.positive_mean,
         4), e.real(value.negative_mean, 4) });
    for (model.data, model.alpha, 0..) |example, alpha, i| if (alpha > 0) out.add("sv {s} y {d} alpha {s} f {s} {s}",
         .{ example.id, example.label, e.real(alpha, 6), e.real(value.training[i], 4), if (alpha == model.c) "bound" else "free" });
}
fn probability(value: f64, a: f64, b: f64) f64 {
    return 1 / (1 + @exp(a * value + b));
}
fn nll(values: []const f64, targets: []const f64, a: f64, b: f64) f64 {
    var out: f64 = 0;
    for (values, targets) |value, target| {
        const p = probability(value, a, b);
        out += target * @log(p) + (1 - target) * @log(1 - p);
    }
    return -out;
}
const Calibration = struct { a: f64 = 0, b: f64 = 0, probabilities: []f64, lines: c.Lines = .{} };
fn calibrate(input: c.Input, model: smo.Model, cv: []const f64, test_values: []const f64) Calibration {
    var out: Calibration = .{ .probabilities = c.alloc(f64, test_values.len) };
    var positive: i64 = 0;
    for (input.train) |example| {
        if (example.label == 1) positive += 1;
    }
    const negative = c.n(input.train.len) - positive;
    const targets = c.alloc(f64, input.train.len);
    for (input.train, targets) |example, *target| target.* = if (example.label == 1) c.f(positive + 1) / c.f(positive + 2) else 1 / c.f(negative + 2);
    out.b = @log(c.f(negative + 1) / c.f(positive + 1));
    out.lines.add("calibration {s} C {s} positives {d} negatives {d}", .{ model.kernel.name,
         e.real(model.c, 4), positive, negative });
    out.lines.add("start A {s} B {s} nll {s}", .{ e.real(out.a, 6), e.real(out.b, 6), e.real(nll(cv,
         targets, out.a, out.b), 6) });
    for (0..input.params.newton_iterations) |iteration| {
        var g1: f64 = 0;
        var g2: f64 = 0;
        var h11: f64 = 0;
        var h21: f64 = 0;
        var h22: f64 = 0;
        for (cv, targets) |value, target| {
            const p = probability(value, out.a, out.b);
            g1 += value * (target - p);
            g2 += target - p;
            h11 += value * value * p * (1 - p);
            h21 += value * p * (1 - p);
            h22 += p * (1 - p);
        }
        const determinant = h11 * h22 - h21 * h21;
        const a = out.a - (h22 * g1 - h21 * g2) / determinant;
        const b = out.b - (h11 * g2 - h21 * g1) / determinant;
        out.a = a;
        out.b = b;
        out.lines.add("iteration {d} A {s} B {s} nll {s}", .{ iteration + 1, e.real(a, 6),
             e.real(b, 6), e.real(nll(cv, targets, a, b), 6) });
    }
    var count = [_]i64{0} ** 5;
    var positives = [_]i64{0} ** 5;
    var sums = [_]f64{0} ** 5;
    var loss: f64 = 0;
    var brier: f64 = 0;
    for (input.test_data, test_values, out.probabilities) |example, value, *stored| {
        const p = probability(value, out.a, out.b);
        stored.* = p;
        loss += if (example.label == 1) @log(p) else @log(1 - p);
        const probability_error = p - @as(f64, if (example.label == 1) 1 else 0);
        brier += probability_error * probability_error;
        const bin = @min(4, @as(usize, @intFromFloat(@floor(p * 5))));
        count[bin] += 1;
        sums[bin] += p;
        positives[bin] += @intFromBool(example.label == 1);
    }
    out.lines.add("test log_loss {s} brier {s}", .{ e.real(-loss / c.f(test_values.len), 6),
         e.real(brier / c.f(test_values.len), 6) });
    const ranges = [_][]const u8{ "0.0-0.2", "0.2-0.4", "0.4-0.6", "0.6-0.8", "0.8-1.0" };
    for (ranges, 0..) |range, bin| out.lines.add("bin {s} count {d} mean_probability {s} positive_rate {s}",
         .{ range, count[bin], if (count[bin] > 0) e.real(sums[bin] / c.f(count[bin]), 4) else "-",
         e.ratio(positives[bin], count[bin]) });
    const closest = c.alloc(usize, test_values.len);
    for (closest, 0..) |*index, i| index.* = i;
    const Compare = struct {
        fn less(values: []const f64, a: usize, b: usize) bool {
            const x = @abs(values[a]);
            const y = @abs(values[b]);
            return if (x != y) x < y else a < b;
        }
    };
    std.mem.sort(usize, closest, test_values, Compare.less);
    for (closest[0..5]) |index| out.lines.add("closest {s} label {d} decision {s} probability {s}",
         .{ input.test_data[index].id, input.test_data[index].label, e.real(test_values[index],
         4), e.real(out.probabilities[index], 4) });
    return out;
}
fn psi(weights: [3]f64, point: c.Point) f64 {
    return weights[0] * point[0] + weights[1] * point[1] + weights[2];
}
const Pegasos = struct { weights: [3]f64 = .{ 0, 0, 0 }, average: [3]f64 = .{ 0, 0, 0 }, testing: []f64,
     lines: c.Lines = .{} };
fn pegasos(input: c.Input, linear: smo.Model, linear_metrics: Metrics) Pegasos {
    var out: Pegasos = .{ .testing = c.alloc(f64, input.test_data.len) };
    const params = input.params;
    var state = params.seed;
    var sums = [_]f64{0} ** 3;
    var updates: usize = 0;
    const n = c.n(input.train.len);
    const m = c.n(input.test_data.len);
    out.lines.add("pegasos lambda {s} iterations {d} seed {d}", .{ e.real(params.lambda, 4),
         params.pegasos_iterations, params.seed });
    for (1..params.pegasos_iterations + 1) |t| {
        state = @mod(48271 * state, 2147483647);
        const example = input.train[c.u(@mod(state, n))];
        const eta = 1 / (params.lambda * c.f(t));
        const sigma = 1 - eta * params.lambda;
        if (c.f(example.label) * psi(out.weights, example.point) < 1) {
            out.weights[0] = sigma * out.weights[0] + eta * c.f(example.label) * example.point[0];
            out.weights[1] = sigma * out.weights[1] + eta * c.f(example.label) * example.point[1];
            out.weights[2] = sigma * out.weights[2] + eta * c.f(example.label);
            updates += 1;
        } else for (&out.weights) |*weight| {
            weight.* = sigma * weight.*;
        };
        for (&sums, out.weights) |*sum, weight| sum.* += weight;
        if (t % (params.pegasos_iterations / 10) == 0) {
            var xi: f64 = 0;
            var correct: i64 = 0;
            for (input.train) |point| {
                const value = psi(out.weights, point.point);
                xi += @max(0, 1 - c.f(point.label) * value);
                correct += @intFromBool(e.sign(value) == point.label);
            }
            const w = out.weights;
            const objective = params.lambda / 2 * (w[0] * w[0] + w[1] * w[1] + w[2] * w[2]) + xi / c.f(n);
            out.lines.add("checkpoint {d} objective {s} train {d}/{d}", .{ t, e.real(objective, 6), correct, n });
        }
    }
    for (&out.average, sums) |*average, sum| average.* = sum / c.f(params.pegasos_iterations);
    var train_correct: i64 = 0;
    var test_correct: i64 = 0;
    var average_correct: i64 = 0;
    var agreement: i64 = 0;
    for (input.train) |example| train_correct += @intFromBool(e.sign(psi(out.weights, example.point)) == example.label);
    for (input.test_data, out.testing, linear_metrics.testing) |example, *stored, other| {
        const value = psi(out.weights, example.point);
        stored.* = value;
        test_correct += @intFromBool(e.sign(value) == example.label);
        average_correct += @intFromBool(e.sign(psi(out.average, example.point)) == example.label);
        agreement += @intFromBool(e.sign(value) == e.sign(other));
    }
    const w = out.weights;
    const v = linear_metrics.weights;
    const cosine = (w[0] * v[0] + w[1] * v[1]) / (@sqrt(w[0] * w[0] + w[1] * w[1]) * @sqrt(v[0] * v[0] + v[1] * v[1]));
    out.lines.add("updates {d}", .{updates});
    out.lines.add("w {s} {s} bias {s}", .{ e.real(w[0], 6), e.real(w[1], 6), e.real(w[2], 6) });
    out.lines.add("train correct {d}/{d} accuracy {s}", .{ train_correct, n, e.ratio(train_correct, n) });
    out.lines.add("test correct {d}/{d} accuracy {s}", .{ test_correct, m, e.ratio(test_correct, m) });
    out.lines.add("average w {s} {s} bias {s} test correct {d}/{d}", .{ e.real(out.average[0],
         6), e.real(out.average[1], 6), e.real(out.average[2], 6), average_correct, m });
    out.lines.add("compare {s} cosine {s} test_agreement {d}/{d}", .{ linear.kernel.name, e.real(cosine,
         6), agreement, m });
    return out;
}
fn multiSummary(prefix: []const u8, data: []const c.Example, predictions: []const multi_module.Prediction) []const u8 {
    var rest: i64 = 0;
    var one: i64 = 0;
    var agreement: i64 = 0;
    var ties: i64 = 0;
    for (data, predictions) |example, prediction| {
        rest += @intFromBool(prediction.ovr == example.label);
        one += @intFromBool(prediction.ovo == example.label);
        agreement += @intFromBool(prediction.ovr == prediction.ovo);
        ties += @intFromBool(prediction.tie);
    }
    const count = c.n(data.len);
    return c.fmt("{s} ovr {d}/{d} {s} ovo {d}/{d} {s} agreement {d}/{d} vote_ties {d}", .{ prefix,
         rest, count, e.ratio(rest, count), one, count, e.ratio(one, count), agreement, count,
         ties });
}
fn multiReport(input: c.Input, models: *const multi_module.Multi) c.Lines {
    var out: c.Lines = .{};
    const n = input.multi_train.len;
    const m = input.multi_test.len;
    out.add("multiclass kernel {s} C {s} classes 3 train {d} test {d}", .{ input.params.multi_name,
         e.real(input.params.multi_c, 4), n, m });
    out.add("ovr", .{});
    for (models.rest, 0..) |model, k| {
        var positive: i64 = 0;
        var correct: i64 = 0;
        for (model.data) |example| positive += @intFromBool(example.label == 1);
        for (input.multi_test) |example| correct += @intFromBool(e.sign(model.decision(example.point)) == @as(i64,
             if (example.label == c.n(k + 1)) 1 else -1));
        out.add("model {d}-rest examples {d} positives {d} {s} b {s} {s} test {d}/{d}", .{ k + 1,
             n, positive, supportText(model), e.real(model.b, 6), runInfo(model), correct,
             m });
    }
    out.add("ovo", .{});
    for (models.one, multi_module.pairs) |model, pair| {
        var positive: i64 = 0;
        var correct: i64 = 0;
        var count: usize = 0;
        for (model.data) |example| positive += @intFromBool(example.label == 1);
        for (input.multi_test) |example| if (example.label == pair[0] or example.label == pair[1]) {
            count += 1;
            correct += @intFromBool(e.sign(model.decision(example.point)) == @as(i64, if (example.label == pair[0]) 1 else -1));
        };
        out.add("model {d}-{d} examples {d} positives {d} {s} b {s} {s} test {d}/{d}", .{ pair[0],
             pair[1], model.data.len, positive, supportText(model), e.real(model.b, 6), runInfo(model),
             correct, count });
    }
    const training = c.alloc(multi_module.Prediction, n);
    const testing = c.alloc(multi_module.Prediction, m);
    for (input.multi_train, training) |example, *prediction| prediction.* = multi_module.classify(models,
         example.point);
    for (input.multi_test, testing) |example, *prediction| prediction.* = multi_module.classify(models, example.point);
    out.add("predictions", .{});
    for (input.multi_test, testing) |example, prediction| out.add("{s} class {d} ovr {s} {s} {s} pred {d} ovo {s} {s} {s} votes {d} {d} {d} pred {d}",
         .{ example.id, example.label, e.real(prediction.rest[0], 4), e.real(prediction.rest[1],
         4), e.real(prediction.rest[2], 4), prediction.ovr, e.real(prediction.one[0], 4), e.real(prediction.one[1],
         4), e.real(prediction.one[2], 4), prediction.votes[0], prediction.votes[1], prediction.votes[2],
         prediction.ovo });
    out.add("{s}", .{multiSummary("train", input.multi_train, training)});
    out.add("{s}", .{multiSummary("test", input.multi_test, testing)});
    for ([_]bool{ true, false }) |rest| {
        const confusion = e.confusion(input.multi_test, testing, rest);
        out.add("confusion {s}", .{if (rest) "ovr" else "ovo"});
        for (confusion) |row| out.add("{d} {d} {d}", .{ row[0], row[1], row[2] });
        for (0..3) |k| {
            var column: i64 = 0;
            var row: i64 = 0;
            for (0..3) |j| {
                column += confusion[j][k];
                row += confusion[k][j];
            }
            out.add("class {d} precision {s} recall {s}", .{ k + 1, e.ratio(confusion[k][k],
                 column), e.ratio(confusion[k][k], row) });
        }
    }
    return out;
}
fn frame(out: *c.Lines, cells: []const u8, width: usize, height: usize) void {
    const border = c.alloc(u8, width);
    @memset(border, '-');
    out.add("+{s}+", .{border});
    for (0..height) |row| out.add("|{s}|", .{cells[row * width .. (row + 1) * width]});
    out.add("+{s}+", .{border});
}
fn location(params: c.Params, point: c.Point, dx: f64, dy: f64) ?usize {
    const column = @floor((point[0] - params.x_min) / dx);
    const row = @floor((params.y_max - point[1]) / dy);
    if (column < 0 or column >= c.f(params.width) or row < 0 or row >= c.f(params.height)) return null;
    return @as(usize, @intFromFloat(row)) * params.width + @as(usize, @intFromFloat(column));
}
fn plots(input: c.Input, models: []const smo.Model, selected: usize, calibration: Calibration,
     multi: *const multi_module.Multi) c.Lines {
    const params = input.params;
    const model = models[selected];
    const dx = (params.x_max - params.x_min) / c.f(params.width);
    const dy = (params.y_max - params.y_min) / c.f(params.height);
    const size = params.width * params.height;
    const binary = c.alloc(u8, size);
    const probabilities = c.alloc(u8, size);
    const multiclass = c.alloc(u8, size);
    const signs = c.alloc([]i64, models.len);
    for (signs) |*values| values.* = c.alloc(i64, size);
    for (0..params.height) |row| for (0..params.width) |column| {
        const cell = row * params.width + column;
        const point: c.Point = .{ params.x_min + (c.f(column) + 0.5) * dx, params.y_max - (c.f(row) + 0.5) * dy };
        const value = model.decision(point);
        binary[cell] = if (value >= 1) '+' else if (value > 0) '.' else if (value > -1) '-' else ' ';
        probabilities[cell] = '0' + @as(u8, @intFromFloat(@min(9, @floor(probability(value,
             calibration.a, calibration.b) * 10))));
        const prediction = multi_module.classify(multi, point);
        multiclass[cell] = if (prediction.ovr != prediction.ovo) '?' else if (prediction.ovr == 1) ' ' else if (prediction.ovr == 2) '.' else ':';
        for (models, signs) |current, values| values[cell] = e.sign(current.decision(point));
    };
    const assigned = c.alloc(?usize, size);
    @memset(assigned, null);
    const multi_assigned = c.alloc(?usize, size);
    @memset(multi_assigned, null);
    var outside: usize = 0;
    var multi_outside: usize = 0;
    for (input.train, 0..) |example, i| {
        const cell = location(params, example.point, dx, dy) orelse {
            outside += 1;
            continue;
        };
        if (assigned[cell] == null or (model.alpha[i] > 0 and model.alpha[assigned[cell].?] == 0)) assigned[cell] = i;
    }
    for (input.multi_train, 0..) |example, i| {
        const cell = location(params, example.point, dx, dy) orelse {
            multi_outside += 1;
            continue;
        };
        if (multi_assigned[cell] == null) multi_assigned[cell] = i;
    }
    var points: usize = 0;
    var multi_points: usize = 0;
    var count = [_]usize{0} ** 4;
    var multi_count = [_]usize{0} ** 4;
    var levels = [_]usize{0} ** 10;
    for (0..size) |cell| {
        if (assigned[cell]) |i| {
            points += 1;
            binary[cell] = if (input.train[i].label == 1) (if (model.alpha[i] > 0) @as(u8,
                 'X') else 'x') else (if (model.alpha[i] > 0) @as(u8, 'O') else 'o');
        }
        if (multi_assigned[cell]) |i| {
            multi_points += 1;
            multiclass[cell] = '0' + @as(u8, @intCast(input.multi_train[i].label));
        }
        switch (binary[cell]) {
            '+' => count[0] += 1,
            '.' => count[1] += 1,
            '-' => count[2] += 1,
            ' ' => count[3] += 1,
            else => {},
        }
        switch (multiclass[cell]) {
            ' ' => multi_count[0] += 1,
            '.' => multi_count[1] += 1,
            ':' => multi_count[2] += 1,
            '?' => multi_count[3] += 1,
            else => {},
        }
        levels[probabilities[cell] - '0'] += 1;
    }
    var out: c.Lines = .{};
    out.add("binary {s} C {s}", .{ model.kernel.name, e.real(model.c, 4) });
    out.add("x {s} {s} y {s} {s} grid {d}x{d}", .{ e.real(params.x_min, 4), e.real(params.x_max,
         4), e.real(params.y_min, 4), e.real(params.y_max, 4), params.width, params.height });
    frame(&out, binary, params.width, params.height);
    out.add("cells outer_positive {d} inner_positive {d} inner_negative {d} outer_negative {d} points {d} outside {d}",
         .{ count[0], count[1], count[2], count[3], points, outside });
    out.add("", .{});
    out.add("probability {s} A {s} B {s}", .{ model.kernel.name, e.real(calibration.a, 6), e.real(calibration.b, 6) });
    frame(&out, probabilities, params.width, params.height);
    var level_line: c.Text = .{};
    level_line.add("levels", .{});
    for (levels) |value| level_line.add(" {d}", .{value});
    out.add("{s}", .{level_line.value()});
    out.add("", .{});
    out.add("grid_agreement", .{});
    for (models, 0..) |a, i| for (models[i + 1 ..], i + 1..) |b, j| {
        var agreement: i64 = 0;
        var positive_a: i64 = 0;
        var positive_b: i64 = 0;
        for (signs[i], signs[j]) |x, y| {
            agreement += @intFromBool(x == y);
            positive_a += @intFromBool(x == 1);
            positive_b += @intFromBool(y == 1);
        }
        out.add("{s} {s} {d}/{d} positive {d} {d}", .{ a.kernel.name, b.kernel.name, agreement,
             size, positive_a, positive_b });
    };
    out.add("", .{});
    out.add("multiclass {s} C {s}", .{ params.multi_name, e.real(params.multi_c, 4) });
    frame(&out, multiclass, params.width, params.height);
    out.add("cells class1 {d} class2 {d} class3 {d} disagree {d} points {d} outside {d}", .{ multi_count[0],
         multi_count[1], multi_count[2], multi_count[3], multi_points, multi_outside });
    return out;
}
const ModelSummary = struct { sv: Support, dual: f64, training: i64, testing: i64, passes: usize,
     steps: usize, converged: bool };
fn temporarySummary(input: c.Input, kernel: c.Kernel, matrix: c.Matrix, coefficient: f64, size: usize) ModelSummary {
    var scratch = std.heap.ArenaAllocator.init(c.backing_allocator);
    defer scratch.deinit();
    const previous = c.allocator;
    c.allocator = scratch.allocator();
    defer c.allocator = previous;
    const model = smo.train(input.train[0..size], kernel, matrix[0..size], coefficient, input.params);
    return .{ .sv = support(model), .dual = objectives(model.alpha, model.data, model.matrix).dual,
         .training = e.evaluate(model.data, model.trainingDecisions()).correct(), .testing = e.evaluate(input.test_data,
         decisions(model, input.test_data)).correct(), .passes = model.passes.items.len, .steps = model.steps,
         .converged = model.converged };
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    c.allocator = arena.allocator();
    c.backing_allocator = init.gpa;
    const io = init.io;
    const input = try c.load(io);
    const params = input.params;
    const n = c.n(input.train.len);
    const m = c.n(input.test_data.len);
    const definitions = params.kernels.items;
    const matrices = c.alloc(c.Matrix, definitions.len);
    var cv: std.ArrayList(CV) = .empty;
    const best = c.alloc(usize, definitions.len);
    for (definitions, 0..) |kernel, k| {
        matrices[k] = kernels.matrix(kernel, input.train);
        best[k] = cv.items.len;
        for (params.c_grid, 0..) |_, candidate| {
            c.append(CV, &cv, crossValidate(input, k, candidate, matrices[k]));
            if (cv.items[cv.items.len - 1].correct > cv.items[best[k]].correct) best[k] = cv.items.len - 1;
        }
    }
    var selected: usize = 0;
    for (1..definitions.len) |k| if (cv.items[best[k]].correct > cv.items[best[selected]].correct or (cv.items[best[k]].correct == cv.items[best[selected]].correct and params.c_grid[cv.items[best[k]].candidate] < params.c_grid[cv.items[best[selected]].candidate])) {
        selected = k;
    };
    const selected_c = params.c_grid[cv.items[best[selected]].candidate];
    const models = c.alloc(smo.Model, definitions.len);
    const evaluations = c.alloc(Metrics, definitions.len);
    var linear: usize = 0;
    var multi_kernel: usize = 0;
    var found_linear = false;
    for (definitions, 0..) |kernel, k| {
        models[k] = smo.train(input.train, kernel, matrices[k], params.c_grid[cv.items[best[k]].candidate], params);
        evaluations[k] = metrics(input, models[k]);
        if (!found_linear and kernel.kind == .linear) {
            linear = k;
            found_linear = true;
        }
        if (c.eq(kernel.name, params.multi_name)) multi_kernel = k;
    }
    const ranking = c.alloc(usize, cv.items.len);
    for (ranking, 0..) |*index, i| index.* = i;
    const RankContext = struct {
        values: []const CV,
        grid: []const f64,
        fn less(ctx: @This(), a: usize, b: usize) bool {
            const x = ctx.values[a];
            const y = ctx.values[b];
            if (x.correct != y.correct) return x.correct > y.correct;
            if (ctx.grid[x.candidate] != ctx.grid[y.candidate]) return ctx.grid[x.candidate] < ctx.grid[y.candidate];
            return x.kernel < y.kernel;
        }
    };
    std.mem.sort(usize, ranking, RankContext{ .values = cv.items, .grid = params.c_grid }, RankContext.less);
    var report: c.Lines = .{};
    report.add("cross_validation folds {d} examples {d}", .{ params.folds, n });
    for (definitions, best) |kernel, index| {
        const value = cv.items[index];
        report.add("best {s} C {s} correct {d}/{d} accuracy {s}", .{ kernel.name, e.real(params.c_grid[value.candidate],
             4), value.correct, n, e.ratio(value.correct, n) });
    }
    report.add("selected {s} C {s}", .{ definitions[selected].name, e.real(selected_c, 4) });
    report.add("ranking", .{});
    for (ranking, 0..) |index, i| {
        const value = cv.items[index];
        report.add("{d} {s} C {s} correct {d}/{d}", .{ i + 1, definitions[value.kernel].name,
             e.real(params.c_grid[value.candidate], 4), value.correct, n });
    }
    report.add("cv_detail {s} C {s}", .{ definitions[selected].name, e.real(selected_c, 4) });
    for (cv.items[best[selected]].folds, 0..) |fold, i| report.add("fold {d} train {d} test {d} correct {d} support_vectors {d} passes {d} steps {d} converged {s}",
         .{ i + 1, fold.train, fold.test_count, fold.correct, fold.sv, fold.passes, fold.steps,
         if (fold.converged) "yes" else "no" });
    for (models, evaluations) |model, value| {
        report.add("", .{});
        modelReport(&report, input, model, value);
    }
    const model = models[selected];
    report.add("", .{});
    report.add("training_log {s}", .{model.kernel.name});
    var i: usize = 0;
    while (i < model.passes.items.len) {
        const pass = model.passes.items[i];
        if (pass.full) {
            report.add("pass {d} full examined {d} changed {d} dual_objective {s}", .{ i + 1,
                 pass.examined, pass.changed, e.real(objectives(pass.alpha, model.data, model.matrix).dual,
                 6) });
            i += 1;
        } else {
            const first = i;
            var examined: usize = 0;
            var changed: usize = 0;
            while (i < model.passes.items.len and !model.passes.items[i].full) : (i += 1) {
                examined += model.passes.items[i].examined;
                changed += model.passes.items[i].changed;
            }
            report.add("passes {d}-{d} nonbound examined {d} changed {d}", .{ first + 1, i, examined, changed });
        }
    }
    report.add("", .{});
    report.add("c_path {s}", .{model.kernel.name});
    for (params.c_grid) |coefficient| {
        const value = temporarySummary(input, model.kernel, model.matrix, coefficient, input.train.len);
        report.add("C {s} support_vectors {d} bound {d} free {d} dual_objective {s} train {d}/{d} test {d}/{d} passes {d} steps {d} converged {s}",
             .{ e.real(coefficient, 4), value.sv.total, value.sv.bound, value.sv.free, e.real(value.dual,
             6), value.training, n, value.testing, m, value.passes, value.steps, if (value.converged) "yes" else "no" });
    }
    report.add("", .{});
    report.add("learning_curve {s} C {s}", .{ model.kernel.name, e.real(selected_c, 4) });
    for (params.learning) |q| {
        const size = input.train.len * q / 100;
        const value = temporarySummary(input, model.kernel, model.matrix, selected_c, size);
        report.add("size {d} support_vectors {d} train {d}/{d} test {d}/{d} passes {d} steps {d} converged {s}",
             .{ size, value.sv.total, value.training, size, value.testing, m, value.passes,
             value.steps, if (value.converged) "yes" else "no" });
    }
    const calibration = calibrate(input, model, cv.items[best[selected]].values, evaluations[selected].testing);
    report.add("", .{});
    report.extend(calibration.lines);
    const peg = pegasos(input, models[linear], evaluations[linear]);
    report.add("", .{});
    report.extend(peg.lines);
    report.add("", .{});
    report.add("mcnemar", .{});
    const comparison_values = c.alloc([]const f64, models.len + 1);
    const names = c.alloc([]const u8, models.len + 1);
    for (models, evaluations, 0..) |current, value, k| {
        comparison_values[k] = value.testing;
        names[k] = current.kernel.name;
    }
    comparison_values[models.len] = peg.testing;
    names[models.len] = "pegasos";
    for (names, 0..) |first, a| for (names[a + 1 ..], a + 1..) |second, b| {
        var only_first: i64 = 0;
        var only_second: i64 = 0;
        for (input.test_data, comparison_values[a], comparison_values[b]) |example, x, y| {
            const good_x = e.sign(x) == example.label;
            const good_y = e.sign(y) == example.label;
            only_first += @intFromBool(good_x and !good_y);
            only_second += @intFromBool(good_y and !good_x);
        }
        const difference = @as(i64, @intCast(@abs(only_first - only_second))) - 1;
        const numerator = difference * difference;
        const denominator = only_first + only_second;
        report.add("{s} {s} only_first {d} only_second {d} chi2 {s}", .{ first, second, only_first,
             only_second, if (denominator > 0) e.real(c.f(numerator) / c.f(denominator), 4) else "-" });
    };
    var grid: c.Lines = .{};
    var header: c.Text = .{};
    header.add("kernel,C", .{});
    for (1..params.folds + 1) |fold| header.add(",fold{d}", .{fold});
    header.add(",correct,accuracy,support_vectors,passes,steps", .{});
    grid.add("{s}", .{header.value()});
    for (cv.items) |value| {
        var row: c.Text = .{};
        row.add("{s},{s}", .{ definitions[value.kernel].name, e.real(params.c_grid[value.candidate], 4) });
        for (value.folds) |fold| row.add(",{d}", .{fold.correct});
        row.add(",{d},{s},{d},{d},{d}", .{ value.correct, e.ratio(value.correct, n), value.sv,
             value.passes, value.steps });
        grid.add("{s}", .{row.value()});
    }
    var predictions: c.Lines = .{};
    header = .{};
    header.add("id,label", .{});
    for (definitions) |kernel| header.add(",{s}", .{kernel.name});
    header.add(",pegasos,predicted,probability", .{});
    predictions.add("{s}", .{header.value()});
    for (input.test_data, 0..) |example, index| {
        var row: c.Text = .{};
        row.add("{s},{d}", .{ example.id, example.label });
        for (evaluations) |value| row.add(",{s}", .{e.real(value.testing[index], 4)});
        row.add(",{s},{d},{s}", .{ e.real(peg.testing[index], 4), e.sign(evaluations[selected].testing[index]),
             e.real(calibration.probabilities[index], 4) });
        predictions.add("{s}", .{row.value()});
    }
    const multi = multi_module.train(input, definitions[multi_kernel]);
    try std.Io.Dir.cwd().createDirPath(io, "output");
    try e.save(io, "model.txt", report);
    try e.save(io, "cv_grid.csv", grid);
    try e.save(io, "predictions.csv", predictions);
    try e.save(io, "multiclass.txt", multiReport(input, &multi));
    try e.save(io, "decision_plot.txt", plots(input, models, selected, calibration, &multi));
}
