const std = @import("std");
const c = @import("dataset.zig");
const stumps = @import("stumps.zig");
const adaboost = @import("adaboost.zig");
const variants_module = @import("variants.zig");
const evaluation = @import("evaluation.zig");
const ratio = evaluation.ratio;
fn real(value: f64) []const u8 {
    return evaluation.real(value, 4);
}
fn scores(model: adaboost.Model, rows: []const c.Row, limit: ?usize) c.Vector {
    const count = @min(limit orelse model.rounds.len, model.rounds.len);
    const out = c.vector(rows.len);
    for (rows, 0..) |row, i| for (model.rounds[0..count]) |round| {
        out[i] += round.stump.output(row.values);
    };
    return out;
}
fn magnitude(round: adaboost.Round, variant: []const u8) f64 {
    if (c.eq(variant, "samme")) return round.alpha;
    var out: f64 = 0;
    for (round.stump.values) |value| out = @max(out, @abs(value));
    return out;
}
fn scale(model: adaboost.Model, limit: ?usize) f64 {
    var out: f64 = 0;
    for (model.rounds[0 .. limit orelse model.rounds.len]) |round| out += magnitude(round, model.variant);
    return out;
}
fn errorCount(rows: []const c.Row, values: []const f64) usize {
    var out: usize = 0;
    for (rows, values) |row, value| out += @intFromBool(evaluation.prediction(value) != row.label);
    return out;
}
fn loss(rows: []const c.Row, values: []const f64, variant: []const u8) f64 {
    var out: f64 = 0;
    for (rows, values) |row, value| out += if (c.eq(variant, "logit")) @log(1 + @exp(-2 * c.f(row.label) * value)) else @exp(-c.f(row.label) * value);
    return out / c.f(rows.len);
}
fn metrics(out: *c.Lines, kind: []const u8, variant: []const u8, rounds: usize, rows: []const c.Row, values: []const f64) void {
    var tp: usize = 0;
    var fp: usize = 0;
    var tn: usize = 0;
    var fn_: usize = 0;
    for (rows, values) |row, value| {
        const yes = evaluation.prediction(value) == 1;
        if (row.label == 1) {
            tp += @intFromBool(yes);
            fn_ += @intFromBool(!yes);
        } else {
            fp += @intFromBool(yes);
            tn += @intFromBool(!yes);
        }
    }
    const area = evaluation.auc(rows, values);
    out.add("{s} {s} rounds {d} correct {d}/{d} accuracy {s} tp {d} fp {d} tn {d} fn {d} precision {s} recall {s} f1 {s} auc {s} loss {s}",
         .{ kind, variant, rounds, tp + tn, rows.len, ratio(tp + tn, rows.len), tp, fp, tn, fn_, ratio(tp,
         tp + fp), ratio(tp, tp + fn_), ratio(2 * tp, 2 * tp + fp + fn_), ratio(area.numerator, area.denominator),
         real(loss(rows, values, variant)) });
}
const OrderContext = struct { values: []const f64, decreasing: bool };
fn valueLess(context: OrderContext, a: usize, b: usize) bool {
    return if (context.values[a] != context.values[b]) (if (context.decreasing) context.values[a] > context.values[b] else context.values[a] < context.values[b]) else a < b;
}
fn ordered(values: []const f64, decreasing: bool) []usize {
    const out = c.alloc(usize, values.len);
    for (out, 0..) |*value, i| value.* = i;
    std.mem.sort(usize, out, OrderContext{ .values = values, .decreasing = decreasing }, valueLess);
    return out;
}
const Importance = struct { value: c.Vector, count: []usize, order: []usize };
fn importance(model: adaboost.Model, features: usize) Importance {
    const values = c.vector(features);
    const counts = c.alloc(usize, features);
    @memset(counts, 0);
    for (model.rounds) |round| {
        values[round.stump.feature] += magnitude(round, model.variant);
        counts[round.stump.feature] += 1;
    }
    return .{ .value = values, .count = counts, .order = ordered(values, true) };
}
fn importanceLines(out: *c.Lines, values: Importance, names: []const []const u8) void {
    var total: f64 = 0;
    for (values.value) |value| total += value;
    for (values.order, 1..) |j, rank| out.add("{d} {s} score {s} share {s} rounds {d}", .{ rank, names[j],
         real(values.value[j]), real(values.value[j] / total), values.count[j] });
}
const Curve = struct { train: []usize, test_rows: []usize, train_loss: c.Vector, test_loss: c.Vector, minimum: c.Vector };
fn curve(model: adaboost.Model, train: []const c.Row, test_rows: []const c.Row) Curve {
    const count = model.rounds.len;
    const out: Curve = .{ .train = c.alloc(usize, count), .test_rows = c.alloc(usize, count), .train_loss = c.vector(count),
         .test_loss = c.vector(count), .minimum = c.vector(count) };
    for (1..count + 1) |t| {
        const a = scores(model, train, t);
        const b = scores(model, test_rows, t);
        out.train[t - 1] = errorCount(train, a);
        out.test_rows[t - 1] = errorCount(test_rows, b);
        out.train_loss[t - 1] = loss(train, a, model.variant);
        out.test_loss[t - 1] = loss(test_rows, b, model.variant);
        var minimum = c.f(train[0].label) * a[0];
        for (train[1..], a[1..]) |row, value| minimum = @min(minimum, c.f(row.label) * value);
        out.minimum[t - 1] = minimum / scale(model, t);
    }
    return out;
}
fn firstMinimum(values: []const usize) usize {
    var out: usize = 0;
    for (values[1..], 1..) |value, i| if (value < values[out]) {
        out = i;
    };
    return out;
}
fn draw(state: *i64) i64 {
    state.* = @mod(48271 * state.*, 2147483647);
    return state.*;
}
fn relabel(rows: []const c.Row, positive: i64) []const c.Row {
    const out = c.dupe(c.Row, rows);
    for (out) |*row| row.label = if (row.label == positive) 1 else -1;
    return out;
}
fn classScores(model: adaboost.Model, rows: []const c.Row, classes: usize, limit: ?usize) c.Matrix {
    const out = c.matrix(rows.len, classes);
    for (rows, 0..) |row, i| for (model.rounds[0 .. limit orelse model.rounds.len]) |round| {
        out[i][@as(usize, @intFromFloat(round.stump.output(row.values))) - 1] += round.alpha;
    };
    return out;
}
fn classPredictions(values: c.Matrix) []usize {
    const out = c.alloc(usize, values.len);
    for (values, out) |row, *value| {
        var largest: usize = 0;
        for (row[1..], 1..) |entry, k| if (entry > row[largest]) {
            largest = k;
        };
        value.* = largest + 1;
    }
    return out;
}
fn multiclassErrors(rows: []const c.Row, values: []const usize) usize {
    var out: usize = 0;
    for (rows, values) |row, value| out += @intFromBool(row.label != c.n(value));
    return out;
}
fn confusionLines(out: *c.Lines, rows: []const c.Row, predictions: []const usize, classes: usize) void {
    const table = evaluation.confusion(rows, predictions, classes);
    out.add("confusion", .{});
    for (table) |row| {
        var line: c.Text = .{};
        for (row, 0..) |value, j| line.add("{s}{d}", .{ if (j == 0) "" else " ", value });
        out.add("{s}", .{line.value()});
    }
    for (0..classes) |k| {
        var row: usize = 0;
        var column: usize = 0;
        for (0..classes) |h| {
            row += table[k][h];
            column += table[h][k];
        }
        out.add("class {d} precision {s} recall {s}", .{ k + 1, ratio(table[k][k], column), ratio(table[k][k], row) });
    }
}
fn restricted(rows: []const c.Row, features: []const usize) []const c.Row {
    const out = c.dupe(c.Row, rows);
    for (out) |*row| {
        const values = c.vector(features.len);
        for (features, values) |j, *value| value.* = row.values[j];
        row.values = values;
    }
    return out;
}
fn lessFloat(_: void, a: f64, b: f64) bool {
    return a < b;
}
fn lessIndex(_: void, a: usize, b: usize) bool {
    return a < b;
}
fn unique(values: []const f64) c.Vector {
    const sorted = c.dupe(f64, values);
    std.mem.sort(f64, sorted, {}, lessFloat);
    var count: usize = 0;
    for (sorted) |value| {
        if (count == 0 or value != sorted[count - 1]) {
            sorted[count] = value;
            count += 1;
        }
    }
    return sorted[0..count];
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    c.allocator = arena.allocator();
    try std.Io.Dir.cwd().createDirPath(init.io, "output");
    const input = try c.readInput(init.io);
    const p = input.params;
    const train = input.train;
    const test_rows = input.test_rows;
    const n = train.len;
    const m = test_rows.len;
    const d = input.names.len;
    const nv = p.variants.len;
    var ensemble: c.Lines = .{};
    var error_curve: c.Lines = .{};
    var prediction_file: c.Lines = .{};
    var roc: c.Lines = .{};
    var margins: c.Lines = .{};
    var shapes: c.Lines = .{};
    var multi: c.Lines = .{};
    var summary: c.Lines = .{};
    var experiments: c.Lines = .{};
    var line: c.Text = .{};
    error_curve.add("variant,round,train_error,test_error,train_loss,test_loss,min_margin", .{});
    line.add("id,variant,score,label", .{});
    for (input.names) |name| line.add(",{s}", .{name});
    prediction_file.add("{s}", .{line.value()});
    roc.add("variant,threshold,tp,fp", .{});
    const folds = c.alloc(adaboost.Model, p.folds);
    const fold_errors = c.alloc([]usize, p.folds);
    const cv = c.alloc(usize, p.rounds);
    @memset(cv, 0);
    for (0..p.folds) |fold| {
        var validation: usize = 0;
        for (0..n) |i| validation += @intFromBool(i % p.folds == fold);
        const weights = c.vector(n);
        for (0..n) |i| if (i % p.folds != fold) {
            weights[i] = 1 / c.f(n - validation);
        };
        folds[fold] = adaboost.discrete(train, p, p.rounds, 1, weights);
        fold_errors[fold] = c.alloc(usize, p.rounds);
        @memset(fold_errors[fold], 0);
        for (1..p.rounds + 1) |t| {
            const values = scores(folds[fold], train, t);
            for (train, 0..) |row, i| if (i % p.folds == fold) {
                fold_errors[fold][t - 1] += @intFromBool(evaluation.prediction(values[i]) != row.label);
            };
            cv[t - 1] += fold_errors[fold][t - 1];
        }
    }
    const selected = firstMinimum(cv) + 1;
    const oof = c.vector(n);
    for (0..p.folds) |fold| {
        const values = scores(folds[fold], train, selected);
        for (0..n) |i| if (i % p.folds == fold) {
            oof[i] = values[i];
        };
    }
    const full = c.alloc(adaboost.Model, nv);
    const final = c.alloc(adaboost.Model, nv);
    const curves = c.alloc(Curve, nv);
    const train_scores = c.alloc(c.Vector, nv);
    const test_scores = c.alloc(c.Vector, nv);
    const importances = c.alloc(Importance, nv);
    var permutation_state = p.permutation_seed;
    for (p.variants, 0..) |variant, v| {
        full[v] = variants_module.train(train, p, variant);
        final[v] = full[v];
        if (c.eq(variant, "discrete")) final[v].rounds = full[v].rounds[0..@min(selected, full[v].rounds.len)];
        curves[v] = curve(full[v], train, test_rows);
        train_scores[v] = scores(final[v], train, null);
        test_scores[v] = scores(final[v], test_rows, null);
        importances[v] = importance(final[v], d);
        if (v > 0) {
            ensemble.add("", .{});
            margins.add("", .{});
            shapes.add("", .{});
        }
        const trained = full[v];
        const fit = final[v];
        line = .{};
        line.add("variant {s} rounds {d} stop {s}", .{ variant, trained.rounds.len, trained.stop });
        if (c.eq(variant, "real")) line.add(" bins {d} smoothing {s} convergence {s}", .{ p.bins,
             real(p.smoothing), evaluation.real(p.convergence, 6) });
        if (c.eq(variant, "logit")) line.add(" clip {s}", .{real(p.clip)});
        ensemble.add("{s}", .{line.value()});
        if (c.eq(variant, "real")) for (input.names, trained.cuts) |name, cuts| {
            line = .{};
            line.add("cuts {s}", .{name});
            for (cuts) |value| line.add(" {s}", .{real(value)});
            ensemble.add("{s}", .{line.value()});
        };
        for (trained.rounds, 0..) |round, t| {
            line = .{};
            line.add("round {d} feature {s}", .{ t + 1, input.names[round.stump.feature] });
            if (c.eq(variant, "real")) {
                line.add(" z {s} bound {s} values", .{ real(round.z), real(round.bound) });
                for (round.stump.values) |value| line.add(" {s}", .{real(value)});
            } else {
                line.add(" threshold {s}", .{real(round.stump.thresholds[0])});
                if (c.eq(variant, "discrete")) line.add(" polarity {d} error {s} alpha {s} z {s} bound {s}",
                     .{ round.polarity, real(round.error_), real(round.alpha), real(round.z), real(round.bound) }) else {
                    line.add(" left {s} right {s} error {s}", .{ real(round.stump.values[0]), real(round.stump.values[1]),
                         real(round.error_) });
                    if (c.eq(variant, "logit")) line.add(" loss {s}", .{real(round.loss)});
                }
            }
            ensemble.add("{s}", .{line.value()});
            if (c.eq(variant, "discrete")) {
                var maximum: usize = 0;
                var squares: f64 = 0;
                for (round.weights, 0..) |weight, i| {
                    if (weight > round.weights[maximum]) maximum = i;
                    squares += weight * weight;
                }
                ensemble.add("weights {d} max {s} id {s} ess {s}", .{ t + 1, evaluation.real(round.weights[maximum],
                     6), train[maximum].id, real(1 / squares) });
            }
            error_curve.add("{s},{d},{s},{s},{s},{s},{s}", .{ variant, t + 1, ratio(curves[v].train[t],
                 n), ratio(curves[v].test_rows[t], m), real(curves[v].train_loss[t]), real(curves[v].test_loss[t]),
                 real(curves[v].minimum[t]) });
        }
        if (c.eq(variant, "discrete")) {
            ensemble.add("cv folds {d} selected {d} errors {d}/{d}", .{ p.folds, selected, cv[selected - 1], n });
            for (0..p.folds) |fold| {
                var validation: usize = 0;
                for (0..n) |i| validation += @intFromBool(i % p.folds == fold);
                ensemble.add("fold {d} train {d} validation {d} rounds {d} stop {s} selected {d}/{d} final {d}/{d}",
                     .{ fold + 1, n - validation, validation, folds[fold].rounds.len, folds[fold].stop,
                     fold_errors[fold][selected - 1], validation, fold_errors[fold][p.rounds - 1],
                     validation });
            }
            line = .{};
            line.add("cv_errors", .{});
            for (cv) |value| line.add(" {d}", .{value});
            ensemble.add("{s}", .{line.value()});
        }
        const total = scale(fit, null);
        const train_margin = c.vector(n);
        const test_margin = c.vector(m);
        for (train, train_scores[v], train_margin) |row, value, *margin| margin.* = c.f(row.label) * value / total;
        for (test_rows, test_scores[v], test_margin) |row, value, *margin| margin.* = c.f(row.label) * value / total;
        margins.add("variant {s} rounds {d} scale {s}", .{ variant, fit.rounds.len, real(total) });
        for (0..2) |set| {
            const values = if (set == 0) train_margin else test_margin;
            const kind = if (set == 0) "train" else "test";
            var sum: f64 = 0;
            var minimum = values[0];
            for (values) |value| {
                sum += value;
                minimum = @min(minimum, value);
            }
            margins.add("{s} min {s} mean {s}", .{ kind, real(minimum), real(sum / c.f(values.len)) });
            for (p.margins) |theta| {
                const count = evaluation.marginCount(values, theta);
                margins.add("{s} le {s} {d}/{d} {s}", .{ kind, real(theta), count, values.len, ratio(count, values.len) });
            }
            if (set == 0) {
                var histogram = [_]usize{0} ** 20;
                for (values) |value| histogram[@min(@as(usize, @intFromFloat(@floor((value + 1) * 10))), 19)] += 1;
                line = .{};
                line.add("histogram", .{});
                for (histogram) |count| line.add(" {d}", .{count});
                margins.add("{s}", .{line.value()});
                const order = ordered(values, false);
                for (order[0..5]) |i| margins.add("hardest {s} label {d} margin {s}", .{ train[i].id,
                     train[i].label, real(values[i]) });
            } else for (p.margins) |theta| {
                var count: usize = 0;
                var correct: usize = 0;
                for (values, test_rows, test_scores[v]) |value, row, score| if (@abs(value) > theta) {
                    count += 1;
                    correct += @intFromBool(evaluation.prediction(score) == row.label);
                };
                margins.add("test confident {s} {d}/{d} correct {d}/{d} {s}", .{ real(theta), count,
                     m, correct, count, ratio(correct, count) });
            };
        }
        margins.add("importance", .{});
        importanceLines(&margins, importances[v], input.names);
        const base = m - errorCount(test_rows, test_scores[v]);
        margins.add("permutation repeats {d} base {d}/{d}", .{ p.permutations, base, m });
        const drops = c.vector(d);
        const minimum = c.alloc(usize, d);
        @memset(minimum, m);
        const maximum = c.alloc(usize, d);
        @memset(maximum, 0);
        for (0..d) |j| for (0..p.permutations) |_| {
            const permutation = c.alloc(usize, m);
            for (permutation, 0..) |*index, i| index.* = i;
            var remaining = m;
            while (remaining > 1) {
                remaining -= 1;
                const other = c.u(@mod(draw(&permutation_state), c.n(remaining + 1)));
                std.mem.swap(usize, &permutation[remaining], &permutation[other]);
            }
            var correct: usize = 0;
            for (test_rows, 0..) |row, i| {
                const values = c.dupe(f64, row.values);
                values[j] = test_rows[permutation[i]].values[j];
                var value: f64 = 0;
                for (fit.rounds) |round| value += round.stump.output(values);
                correct += @intFromBool(evaluation.prediction(value) == row.label);
            }
            drops[j] += c.f(c.n(base) - c.n(correct));
            minimum[j] = @min(minimum[j], correct);
            maximum[j] = @max(maximum[j], correct);
        };
        const permutation_order = ordered(drops, true);
        for (permutation_order, 1..) |j, rank| margins.add("{d} {s} drop {s} min {d}/{d} max {d}/{d}",
             .{ rank, input.names[j], real(drops[j] / c.f(p.permutations * m)), minimum[j], m, maximum[j],
             m });
        shapes.add("variant {s} rounds {d}", .{ variant, fit.rounds.len });
        for (input.names, 0..) |name, j| {
            var collected: std.ArrayList(stumps.Stump) = .empty;
            var all_thresholds: std.ArrayList(f64) = .empty;
            for (fit.rounds) |round| if (round.stump.feature == j) {
                c.append(stumps.Stump, &collected, round.stump);
                for (round.stump.thresholds) |threshold| c.append(f64, &all_thresholds, threshold);
            };
            const ends = unique(all_thresholds.items);
            const values = c.vector(ends.len + 1);
            for (0..values.len) |interval| for (collected.items) |stump| {
                var bin: usize = 0;
                if (interval > 0) for (stump.thresholds) |threshold| {
                    bin += @intFromBool(threshold <= ends[interval - 1]);
                };
                values[interval] += stump.values[bin];
            };
            var low = values[0];
            var high = low;
            for (values[1..]) |value| {
                low = @min(low, value);
                high = @max(high, value);
            }
            shapes.add("feature {s} rounds {d} cuts {d} range {s}", .{ name, collected.items.len, ends.len, real(high - low) });
            for (values, 0..) |value, interval| shapes.add("interval {s} {s} value {s}", .{ if (interval == 0) "-inf" else real(ends[interval - 1]),
                 if (interval == ends.len) "inf" else real(ends[interval]), real(value) });
        }
        const thresholds = unique(test_scores[v]);
        var remaining = thresholds.len;
        while (remaining > 0) {
            remaining -= 1;
            const threshold = thresholds[remaining];
            var tp: usize = 0;
            var fp: usize = 0;
            for (test_rows, test_scores[v]) |row, value| if (value >= threshold) {
                tp += @intFromBool(row.label == 1);
                fp += @intFromBool(row.label == -1);
            };
            roc.add("{s},{s},{d},{d}", .{ variant, real(threshold), tp, fp });
        }
    }
    for (test_rows, 0..) |row, i| for (p.variants, 0..) |variant, v| {
        line = .{};
        line.add("{s},{s},{s},{d}", .{ row.id, variant, real(test_scores[v][i]), evaluation.prediction(test_scores[v][i]) });
        const contributions = c.vector(d);
        for (final[v].rounds) |round| contributions[round.stump.feature] += round.stump.output(row.values);
        for (contributions) |value| line.add(",{s}", .{real(value)});
        prediction_file.add("{s}", .{line.value()});
    };
    const multi_model = adaboost.samme(input.multi_train, p);
    const same_train_scores = classScores(multi_model, input.multi_train, p.classes, null);
    const same_test_scores = classScores(multi_model, input.multi_test, p.classes, null);
    const same_train = classPredictions(same_train_scores);
    const same_test = classPredictions(same_test_scores);
    multi.add("samme classes {d} train {d} test {d} rounds {d} stop {s}", .{ p.classes, input.multi_train.len,
         input.multi_test.len, multi_model.rounds.len, multi_model.stop });
    for (multi_model.rounds, 0..) |round, t| {
        multi.add("round {d} feature {s} threshold {s} left {d} right {d} error {s} alpha {s}", .{ t + 1,
             input.multi_names[round.stump.feature], real(round.stump.thresholds[0]), @as(i64, @intFromFloat(round.stump.values[0])),
             @as(i64, @intFromFloat(round.stump.values[1])), real(round.error_), real(round.alpha) });
        const a = multiclassErrors(input.multi_train, classPredictions(classScores(multi_model, input.multi_train,
             p.classes, t + 1)));
        const b = multiclassErrors(input.multi_test, classPredictions(classScores(multi_model, input.multi_test,
             p.classes, t + 1)));
        error_curve.add("samme,{d},{s},{s},-,-,-", .{ t + 1, ratio(a, input.multi_train.len), ratio(b, input.multi_test.len) });
    }
    const multi_train_error = multiclassErrors(input.multi_train, same_train);
    const multi_test_error = multiclassErrors(input.multi_test, same_test);
    multi.add("train errors {d}/{d} rate {s}", .{ multi_train_error, input.multi_train.len, ratio(multi_train_error,
         input.multi_train.len) });
    multi.add("test errors {d}/{d} rate {s}", .{ multi_test_error, input.multi_test.len, ratio(multi_test_error,
         input.multi_test.len) });
    confusionLines(&multi, input.multi_test, same_test, p.classes);
    multi.add("importance", .{});
    importanceLines(&multi, importance(multi_model, input.multi_names.len), input.multi_names);
    multi.add("", .{});
    multi.add("ovr classes {d} rounds {d}", .{ p.classes, p.samme_rounds });
    const ovr_train = c.matrix(input.multi_train.len, p.classes);
    const ovr_test = c.matrix(input.multi_test.len, p.classes);
    for (1..p.classes + 1) |k| {
        const a = relabel(input.multi_train, c.n(k));
        const b = relabel(input.multi_test, c.n(k));
        const model = adaboost.discrete(a, p, p.samme_rounds, 1, null);
        const av = scores(model, a, null);
        const bv = scores(model, b, null);
        var positives: usize = 0;
        for (a) |row| positives += @intFromBool(row.label == 1);
        multi.add("class {d} rounds {d} stop {s} positives {d} train_errors {d}/{d} test_errors {d}/{d}",
             .{ k, model.rounds.len, model.stop, positives, errorCount(a, av), a.len, errorCount(b,
             bv), b.len });
        for (av, 0..) |value, i| ovr_train[i][k - 1] = value;
        for (bv, 0..) |value, i| ovr_test[i][k - 1] = value;
    }
    const ovr_train_prediction = classPredictions(ovr_train);
    const ovr_test_prediction = classPredictions(ovr_test);
    const ovr_train_error = multiclassErrors(input.multi_train, ovr_train_prediction);
    const ovr_test_error = multiclassErrors(input.multi_test, ovr_test_prediction);
    multi.add("train errors {d}/{d} rate {s}", .{ ovr_train_error, input.multi_train.len, ratio(ovr_train_error,
         input.multi_train.len) });
    multi.add("test errors {d}/{d} rate {s}", .{ ovr_test_error, input.multi_test.len, ratio(ovr_test_error,
         input.multi_test.len) });
    confusionLines(&multi, input.multi_test, ovr_test_prediction, p.classes);
    var same: usize = 0;
    for (same_test, ovr_test_prediction) |a, b| same += @intFromBool(a == b);
    multi.add("agreement {d}/{d}", .{ same, input.multi_test.len });
    multi.add("", .{});
    multi.add("predictions", .{});
    for (input.multi_test, 0..) |row, i| {
        line = .{};
        line.add("{s} class {d} samme {d} ovr {d} scores", .{ row.id, row.label, same_test[i], ovr_test_prediction[i] });
        for (same_test_scores[i]) |value| line.add(" {s}", .{real(value)});
        multi.add("{s}", .{line.value()});
    }
    var train_positive: usize = 0;
    var test_positive: usize = 0;
    for (train) |row| train_positive += @intFromBool(row.label == 1);
    for (test_rows) |row| test_positive += @intFromBool(row.label == 1);
    summary.add("data train {d} test {d} features {d} positives {d} {d}", .{ n, m, d, train_positive, test_positive });
    for (input.names, 0..) |name, j| {
        line = .{};
        line.add("feature {s}", .{name});
        for (0..2) |set| {
            const rows = if (set == 0) train else test_rows;
            const values = c.vector(rows.len);
            var sum: f64 = 0;
            var minimum = rows[0].values[j];
            var maximum = minimum;
            for (rows, values) |row, *value| {
                value.* = row.values[j];
                sum += value.*;
                minimum = @min(minimum, value.*);
                maximum = @max(maximum, value.*);
            }
            line.add(" {s} {s} {s} {s} {d}", .{ if (set == 0) "train" else "test", real(minimum),
                 real(maximum), real(sum / c.f(rows.len)), unique(values).len });
        }
        summary.add("{s}", .{line.value()});
    }
    summary.add("cv selected {d} errors {d}/{d} rate {s}", .{ selected, cv[selected - 1], n, ratio(cv[selected - 1], n) });
    metrics(&summary, "oof", "discrete", selected, train, oof);
    const committee_train = c.vector(n);
    const committee_test = c.vector(m);
    var committee_rounds: usize = 0;
    for (p.variants, 0..) |variant, v| {
        metrics(&summary, "train", variant, final[v].rounds.len, train, train_scores[v]);
        metrics(&summary, "test", variant, final[v].rounds.len, test_rows, test_scores[v]);
        const total = scale(final[v], null);
        for (committee_train, train_scores[v]) |*value, score| value.* += score / total;
        for (committee_test, test_scores[v]) |*value, score| value.* += score / total;
        committee_rounds += final[v].rounds.len;
    }
    metrics(&summary, "train", "committee", committee_rounds, train, committee_train);
    metrics(&summary, "test", "committee", committee_rounds, test_rows, committee_test);
    for (p.variants, 0..) |variant, v| {
        const a = firstMinimum(curves[v].train);
        const b = firstMinimum(curves[v].test_rows);
        summary.add("curve {s} rounds {d} train_min {d}/{d} at {d} test_min {d}/{d} at {d}", .{ variant,
             full[v].rounds.len, curves[v].train[a], n, a + 1, curves[v].test_rows[b], m, b + 1 });
    }
    var wrong: std.ArrayList(usize) = .empty;
    for (test_rows, 0..) |row, i| {
        var all = true;
        for (0..nv) |v| all = all and evaluation.prediction(test_scores[v][i]) != row.label;
        if (all) c.append(usize, &wrong, i);
    }
    line = .{};
    line.add("all_wrong {d}", .{wrong.items.len});
    for (wrong.items) |i| line.add(" {s}", .{test_rows[i].id});
    summary.add("{s}", .{line.value()});
    summary.add("agreement", .{});
    for (0..nv - 1) |a| for (a + 1..nv) |b| {
        var agreement: usize = 0;
        var n1: i64 = 0;
        var n2: i64 = 0;
        for (test_rows, 0..) |row, i| {
            const x = evaluation.prediction(test_scores[a][i]);
            const y = evaluation.prediction(test_scores[b][i]);
            agreement += @intFromBool(x == y);
            n1 += @intFromBool(x == row.label and y != row.label);
            n2 += @intFromBool(y == row.label and x != row.label);
        }
        const delta = @as(i64, @intCast(@abs(n1 - n2))) - 1;
        summary.add("{s} {s} agree {d}/{d} only_first {d} only_second {d} chi2 {s}", .{ p.variants[a],
             p.variants[b], agreement, m, n1, n2, ratio(delta * delta, n1 + n2) });
    };
    summary.add("bootstrap samples {d} seed {d}", .{ p.bootstrap, p.bootstrap_seed });
    var bootstrap_state = p.bootstrap_seed;
    const bootstrap = c.alloc([]usize, nv);
    for (bootstrap) |*values| {
        values.* = c.alloc(usize, p.bootstrap);
        @memset(values.*, 0);
    }
    for (0..p.bootstrap) |sample| for (0..m) |_| {
        const i = c.u(@mod(draw(&bootstrap_state), c.n(m)));
        for (0..nv) |v| bootstrap[v][sample] += @intFromBool(evaluation.prediction(test_scores[v][i]) == test_rows[i].label);
    };
    for (p.variants, 0..) |variant, v| {
        const values = c.dupe(usize, bootstrap[v]);
        std.mem.sort(usize, values, {}, lessIndex);
        var sum: usize = 0;
        for (values) |count| sum += count;
        const g = p.bootstrap / 40;
        summary.add("{s} mean {s} low {s} high {s}", .{ variant, ratio(sum, p.bootstrap * m), ratio(values[g],
             m), ratio(values[p.bootstrap - g - 1], m) });
    }
    for (0..nv - 1) |a| for (a + 1..nv) |b| {
        var first: usize = 0;
        var tie: usize = 0;
        var second: usize = 0;
        for (bootstrap[a], bootstrap[b]) |x, y| {
            first += @intFromBool(x > y);
            tie += @intFromBool(x == y);
            second += @intFromBool(x < y);
        }
        summary.add("{s} {s} first {d} tie {d} second {d}", .{ p.variants[a], p.variants[b], first, tie, second });
    };
    for (p.variants, 0..) |variant, v| {
        var counts = [_]usize{0} ** 5;
        var positives = [_]usize{0} ** 5;
        var sums = [_]f64{0} ** 5;
        var brier: f64 = 0;
        for (test_rows, test_scores[v]) |row, score| {
            const probability = 1 / (1 + @exp(-2 * score));
            const delta = probability - (if (row.label == 1) @as(f64, 1) else 0);
            brier += delta * delta;
            const bin = @min(@as(usize, @intFromFloat(@floor(probability * 5))), 4);
            counts[bin] += 1;
            sums[bin] += probability;
            positives[bin] += @intFromBool(row.label == 1);
        }
        summary.add("calibration {s} brier {s}", .{ variant, real(brier / c.f(m)) });
        const ranges = [_][]const u8{ "0.0-0.2", "0.2-0.4", "0.4-0.6", "0.6-0.8", "0.8-1.0" };
        for (0..5) |bin| summary.add("bin {s} count {d} mean {s} positives {d}", .{ ranges[bin], counts[bin],
             if (counts[bin] > 0) real(sums[bin] / c.f(counts[bin])) else "-", positives[bin] });
    }
    for (p.sizes) |percent| {
        const size = c.u(@divFloor(c.n(n) * percent, 100));
        const rows = train[0..size];
        experiments.add("size {d} rows {d}", .{ percent, size });
        for (p.variants) |variant| {
            const model = variants_module.train(rows, p, variant);
            experiments.add("{s} rounds {d} stop {s} train_errors {d}/{d} test_errors {d}/{d}", .{ variant,
                 model.rounds.len, model.stop, errorCount(rows, scores(model, rows, null)), size,
                 errorCount(test_rows, scores(model, test_rows, null)), m });
        }
    }
    for (p.shrinkage) |shrinkage| {
        const model = adaboost.discrete(train, p, p.rounds, shrinkage, null);
        const values = curve(model, train, test_rows);
        const minimum = firstMinimum(values.test_rows);
        experiments.add("shrinkage {s} rounds {d} stop {s} train_errors {d}/{d} test_errors {d}/{d} test_min {d}/{d} at {d}",
             .{ real(shrinkage), model.rounds.len, model.stop, errorCount(train, scores(model, train,
             null)), n, errorCount(test_rows, scores(model, test_rows, null)), m, values.test_rows[minimum],
             m, minimum + 1 });
    }
    var discrete_index: usize = 0;
    for (p.variants, 0..) |variant, v| if (c.eq(variant, "discrete")) {
        discrete_index = v;
    };
    const feature_order = importances[discrete_index].order;
    for (1..d + 1) |count| {
        const features = c.dupe(usize, feature_order[0..count]);
        std.mem.sort(usize, features, {}, lessIndex);
        const a = restricted(train, features);
        const b = restricted(test_rows, features);
        const model = adaboost.discrete(a, p, selected, 1, null);
        line = .{};
        line.add("top {d} features", .{count});
        for (features) |j| line.add(" {s}", .{input.names[j]});
        line.add(" rounds {d} train_errors {d}/{d} test_errors {d}/{d}", .{ model.rounds.len, errorCount(a,
             scores(model, a, null)), n, errorCount(b, scores(model, b, null)), m });
        experiments.add("{s}", .{line.value()});
    }
    for (p.noise) |percent| {
        const flipped = c.u(@divFloor(c.n(n) * percent, 100));
        var state = p.noise_seed;
        const permutation = c.alloc(usize, n);
        for (permutation, 0..) |*value, i| value.* = i;
        for (0..flipped) |i| {
            const other = c.u(@mod(draw(&state), c.n(n - i))) + i;
            std.mem.swap(usize, &permutation[i], &permutation[other]);
        }
        const rows = c.dupe(c.Row, train);
        const changed = c.alloc(bool, n);
        @memset(changed, false);
        for (permutation[0..flipped]) |i| {
            rows[i].label = -rows[i].label;
            changed[i] = true;
        }
        experiments.add("noise {d} flipped {d}", .{ percent, flipped });
        for (p.variants) |variant| {
            const model = variants_module.train(rows, p, variant);
            const values = curve(model, rows, test_rows);
            const minimum = firstMinimum(values.test_rows);
            var weight: f64 = 0;
            for (changed, model.rounds[model.rounds.len - 1].weights) |flipped_, value| if (flipped_) {
                weight += value;
            };
            experiments.add("{s} rounds {d} stop {s} train_errors {d}/{d} test_errors {d}/{d} test_min {d}/{d} at {d} flipped_weight {s}",
                 .{ variant, model.rounds.len, model.stop, errorCount(rows, scores(model, rows, null)),
                 n, errorCount(test_rows, scores(model, test_rows, null)), m, values.test_rows[minimum],
                 m, minimum + 1, real(weight) });
        }
    }
    try evaluation.write(init.io, "ensemble.txt", ensemble);
    try evaluation.write(init.io, "error_curve.csv", error_curve);
    try evaluation.write(init.io, "predictions.csv", prediction_file);
    try evaluation.write(init.io, "roc.csv", roc);
    try evaluation.write(init.io, "margins.txt", margins);
    try evaluation.write(init.io, "shapes.txt", shapes);
    try evaluation.write(init.io, "samme.txt", multi);
    try evaluation.write(init.io, "summary.txt", summary);
    try evaluation.write(init.io, "experiments.txt", experiments);
}
