const std = @import("std");
const c = @import("dataset.zig");
const net = @import("network.zig");
const optimizers = @import("optimizers.zig");
const e = @import("evaluation.zig");
const Evaluated = struct { loss: f64 = 0, correct: i64 = 0, predictions: []usize, records: []net.Forward = &.{} };
fn evaluate(network: *const net.Network, weights: []const f64, images: []const c.Image, retain: bool) Evaluated {
    var out: Evaluated = .{ .predictions = c.alloc(usize, images.len), .records = if (retain) c.alloc(net.Forward,
         images.len) else &.{} };
    for (images, out.predictions, 0..) |image, *chosen, i| {
        const record = net.forward(network, weights, image.input[0..network.inputs], image.label);
        chosen.* = e.prediction(record.scores[0..network.classes]);
        out.loss += record.loss;
        out.correct += @intFromBool(chosen.* == image.label);
        if (retain) out.records[i] = record;
    }
    out.loss /= c.f(images.len);
    return out;
}
fn meanGradient(network: *const net.Network, weights: []const f64, images: []const c.Image,
     order: []const usize, gradient: []f64) void {
    @memset(gradient, 0);
    for (order) |index| {
        const record = net.forward(network, weights, images[index].input[0..network.inputs], images[index].label);
        const value = net.backward(network, weights, &record);
        for (gradient, value.parameters[0..network.param_count]) |*sum, part| sum.* += part;
    }
    for (gradient) |*value| value.* /= c.f(order.len);
}
fn batchLoss(network: *const net.Network, weights: []const f64, images: []const c.Image, batch: []const usize) f64 {
    var loss: f64 = 0;
    for (batch) |index| loss += net.forward(network, weights, images[index].input[0..network.inputs],
         images[index].label).loss;
    return loss / c.f(batch.len);
}
fn gradientCheck(input: c.Input, training: []const c.Image) c.Lines {
    var out: c.Lines = .{};
    for (input.networks, 0..) |*network, index| {
        if (index > 0) out.add("", .{});
        var random: c.Random = .{ .state = input.params.seed };
        const order = c.alloc(usize, training.len);
        for (order, 0..) |*value, i| value.* = i;
        random.shuffle(order);
        const batch = order[0..@min(input.params.batch, training.len)];
        var analytic: [1066]f64 = undefined;
        var weights = network.initial;
        meanGradient(network, weights[0..network.param_count], training, batch, analytic[0..network.param_count]);
        var counts = [_][2]usize{.{ 0, 0 }} ** 3;
        var checked: usize = 0;
        var passed = true;
        var parameter: usize = 0;
        while (parameter < network.param_count) : (parameter += input.params.stride) {
            const original = weights[parameter];
            const h: f64 = 0.00001;
            weights[parameter] = original + h;
            const plus = batchLoss(network, weights[0..network.param_count], training, batch);
            weights[parameter] = original - h;
            const minus = batchLoss(network, weights[0..network.param_count], training, batch);
            weights[parameter] = original;
            const numeric = (plus - minus) / (2 * h);
            const relative_error = @abs(analytic[parameter] - numeric) / @max(1, @abs(analytic[parameter]) + @abs(numeric));
            passed = passed and relative_error < 0.000001;
            checked += 1;
            for (network.layers[0..network.layer_count], 0..) |layer, l| {
                if (parameter >= layer.weights and parameter < layer.biases) counts[l][0] += 1 else if (parameter >= layer.biases and parameter < layer.biases + layer.units) counts[l][1] += 1;
            }
        }
        out.add("network {s}", .{network.name});
        out.add("parameters {d}", .{network.param_count});
        var ids: c.Text = .{};
        ids.add("batch", .{});
        for (batch) |i| ids.add(" {s}", .{training[i].id});
        out.add("{s}", .{ids.value()});
        for (counts[0..network.layer_count], 0..) |count, l| out.add("layer {d} weights {d} biases {d}",
             .{ l + 1, count[0], count[1] });
        out.add("checked {d}", .{checked});
        out.add("result {s}", .{if (passed) "PASS" else "FAIL"});
    }
    return out;
}
const Epoch = struct { number: usize, eta: f64, magnitude: f64, train_loss: f64, val_loss: f64,
     train_correct: i64, val_correct: i64, improved: bool, correct: [200]bool = [_]bool{false} ** 200 };
const Result = struct {
    definition: c.Run,
    weights: []const f64 = &.{},
    epochs: std.ArrayList(Epoch) = .empty,
    best_epoch: usize = 0,
    best_correct: i64 = 0,
    updates: usize = 0,
    best_loss: f64 = 0,
    stop: []const u8 = "",
    testing: Evaluated = undefined,
    confusion: e.Counts = undefined,
};
fn trainRun(input: c.Input, training: []const c.Image, validation: []const c.Image, definition: c.Run) Result {
    const network = &input.networks[definition.network];
    var out: Result = .{ .definition = definition };
    var weights = network.initial;
    var optimizer: optimizers.State = .{};
    var random: c.Random = .{ .state = input.params.seed };
    const order = c.alloc(usize, training.len);
    for (order, 0..) |*value, i| value.* = i;
    var wait: usize = 0;
    for (1..input.params.epochs + 1) |epoch| {
        const eta = optimizers.learningRate(definition, input.params, epoch);
        random.shuffle(order);
        var magnitude: f64 = 0;
        var batches: usize = 0;
        var first: usize = 0;
        while (first < order.len) : (first += input.params.batch) {
            const last = @min(order.len, first + input.params.batch);
            var gradient: [1066]f64 = undefined;
            meanGradient(network, weights[0..network.param_count], training, order[first..last],
                 gradient[0..network.param_count]);
            for (0..network.param_count) |parameter| if (network.is_weight[parameter]) {
                gradient[parameter] = gradient[parameter] + definition.decay * weights[parameter];
            };
            var squared: f64 = 0;
            for (gradient[0..network.param_count]) |value| squared += value * value;
            magnitude += @sqrt(squared);
            batches += 1;
            optimizer.update(weights[0..network.param_count], gradient[0..network.param_count], definition, eta);
            out.updates += 1;
        }
        const trained = evaluate(network, weights[0..network.param_count], training, false);
        const validated = evaluate(network, weights[0..network.param_count], validation, false);
        const improved = epoch == 1 or validated.loss < out.best_loss;
        var record: Epoch = .{ .number = epoch, .eta = eta, .magnitude = magnitude / c.f(batches),
             .train_loss = trained.loss, .val_loss = validated.loss, .train_correct = trained.correct,
             .val_correct = validated.correct, .improved = improved };
        for (training, trained.predictions, 0..) |image, chosen, i| record.correct[i] = chosen == image.label;
        c.append(Epoch, &out.epochs, record);
        if (improved) {
            out.best_loss = validated.loss;
            out.best_epoch = epoch;
            out.best_correct = validated.correct;
            out.weights = c.dupe(f64, weights[0..network.param_count]);
            wait = 0;
        } else wait += 1;
        if (wait >= input.params.patience) {
            out.stop = "early";
            break;
        }
        if (epoch == input.params.epochs) out.stop = "max_epochs";
    }
    out.testing = evaluate(network, out.weights, input.test_data, true);
    out.confusion = e.confusion(input.test_data, out.testing.predictions);
    return out;
}
const Noise = struct { rate: i64, flipped: usize = 0, images: []c.Image };
fn noisy(input: c.Input) []const Noise {
    const out = c.alloc(Noise, input.params.noise.len);
    const pixels = input.width * input.height;
    for (input.params.noise, out) |rate, *result| {
        result.* = .{ .rate = rate, .images = c.dupe(c.Image, input.test_data) };
        var random: c.Random = .{ .state = input.params.seed };
        for (result.images) |*image| {
            const bits = c.dupe(u8, image.pixels);
            for (0..pixels) |parameter| if (@mod(random.draw(), 100) < rate) {
                image.input[parameter] = 1 - image.input[parameter];
                bits[parameter] = if (bits[parameter] == '1') '0' else '1';
                result.flipped += 1;
            };
            image.pixels = bits;
        }
    }
    return out;
}
fn classHeading(prefix: []const u8, count: usize) []const u8 {
    var out: c.Text = .{};
    out.add("{s}", .{prefix});
    for (0..count) |label| out.add(" {d}", .{label});
    return out.value();
}
fn dataSummary(input: c.Input, training: []const c.Image, validation: []const c.Image) c.Lines {
    var out: c.Lines = .{};
    out.add("data", .{});
    const pixels = input.width * input.height;
    out.add("train {d} validation {d} test {d} pixels {d}", .{ training.len, validation.len,
         input.test_data.len, pixels });
    var train_counts = [_]i64{0} ** 10;
    var val_counts = [_]i64{0} ** 10;
    var test_counts = [_]i64{0} ** 10;
    var ink = [_]i64{0} ** 10;
    var sums = [_][64]usize{[_]usize{0} ** 64} ** 10;
    var levels = [_][64]usize{[_]usize{0} ** 64} ** 10;
    for (training) |image| {
        train_counts[image.label] += 1;
        for (image.pixels, 0..) |pixel, parameter| {
            const value = @intFromBool(pixel == '1');
            ink[image.label] += value;
            sums[image.label][parameter] += value;
        }
    }
    for (validation) |image| val_counts[image.label] += 1;
    for (input.test_data) |image| test_counts[image.label] += 1;
    for (0..input.classes) |label| {
        out.add("class {d} train {d} validation {d} test {d} ink {s}", .{ label, train_counts[label],
             val_counts[label], test_counts[label], e.ratio(ink[label], train_counts[label]) });
        for (0..pixels) |parameter| levels[label][parameter] = if (train_counts[label] > 0) @min(9,
             10 * sums[label][parameter] / c.u(train_counts[label])) else 0;
    }
    out.add("{s}", .{classHeading("mean_images", input.classes)});
    e.levelMaps(&out, levels[0..input.classes], input.width, input.height);
    return out;
}
fn runReport(input: c.Input, training: []const c.Image, validation: []const c.Image, result: *const Result,
     noise: []const Noise) c.Lines {
    var out: c.Lines = .{};
    const run = result.definition;
    const network = &input.networks[run.network];
    const count = c.n(input.test_data.len);
    out.add("run {s} network {s} optimizer {s}", .{ run.name, network.name, @tagName(run.optimizer) });
    out.add("epochs {d} best_epoch {d} stop {s} updates {d}", .{ result.epochs.items.len, result.best_epoch,
         result.stop, result.updates });
    out.add("best_val_loss {s} best_val_acc {s} correct {d}/{d}", .{ e.real(result.best_loss,
         6), e.ratio(result.best_correct, c.n(validation.len)), result.best_correct, validation.len });
    out.add("test_loss {s} test_acc {s} correct {d}/{d}", .{ e.real(result.testing.loss, 6),
         e.ratio(result.testing.correct, count), result.testing.correct, count });
    var top2: i64 = 0;
    var correct_count: i64 = 0;
    var wrong_count: i64 = 0;
    var correct_confidence: f64 = 0;
    var wrong_confidence: f64 = 0;
    for (input.test_data, result.testing.predictions, result.testing.records) |image, chosen, record| {
        const correct = chosen == image.label;
        top2 += @intFromBool(correct or e.secondClass(record.scores[0..input.classes], chosen) == image.label);
        if (correct) {
            correct_count += 1;
            correct_confidence += record.scores[chosen];
        } else {
            wrong_count += 1;
            wrong_confidence += record.scores[chosen];
        }
    }
    out.add("top2_acc {s} correct {d}/{d}", .{ e.ratio(top2, count), top2, count });
    out.add("confidence correct {s} wrong {s}", .{ if (correct_count > 0) e.real(correct_confidence / c.f(correct_count),
         4) else "-", if (wrong_count > 0) e.real(wrong_confidence / c.f(wrong_count), 4) else "-" });
    var forgetting: usize = 0;
    var forgotten: usize = 0;
    var never: usize = 0;
    for (0..training.len) |image| {
        var events: usize = 0;
        var learned = false;
        for (result.epochs.items, 0..) |epoch, index| {
            const correct = epoch.correct[image];
            learned = learned or correct;
            if (index > 0 and result.epochs.items[index - 1].correct[image] and !correct) events += 1;
        }
        forgetting += events;
        forgotten += @intFromBool(events > 0);
        never += @intFromBool(!learned);
    }
    out.add("forgetting events {d} rows {d} never_learned {d}", .{ forgetting, forgotten, never });
    var norms: c.Text = .{};
    var changes: c.Text = .{};
    norms.add("weight_norms", .{});
    changes.add("weight_changes", .{});
    for (network.layers[0..network.layer_count]) |layer| {
        var norm: f64 = 0;
        var change: f64 = 0;
        for (layer.weights..layer.biases) |parameter| {
            norm += result.weights[parameter] * result.weights[parameter];
            const difference = result.weights[parameter] - network.initial[parameter];
            change += difference * difference;
        }
        norms.add(" {s}", .{e.real(@sqrt(norm), 4)});
        changes.add(" {s}", .{e.real(@sqrt(change), 4)});
    }
    out.add("{s}", .{norms.value()});
    out.add("{s}", .{changes.value()});
    out.add("curve", .{});
    var maximum: f64 = 0;
    for (result.epochs.items) |epoch| maximum = @max(maximum, @max(epoch.train_loss, epoch.val_loss));
    for (result.epochs.items) |epoch| {
        var cells = [_]u8{' '} ** 40;
        const train_col: usize = @intFromFloat(@floor(39 * epoch.train_loss / maximum + 0.5));
        const val_col: usize = @intFromFloat(@floor(39 * epoch.val_loss / maximum + 0.5));
        cells[train_col] = 't';
        cells[val_col] = if (train_col == val_col) '*' else 'v';
        out.add("{d: >2} |{s}|{s}", .{ epoch.number, &cells, if (epoch.number == result.best_epoch) " best" else "" });
    }
    out.add("confusion", .{});
    for (0..input.classes) |label| {
        var row: c.Text = .{};
        row.add("{d}:", .{label});
        for (result.confusion[label][0..input.classes]) |value| row.add(" {d}", .{value});
        out.add("{s}", .{row.value()});
    }
    for (0..input.classes) |label| {
        const stats = e.classStats(result.confusion, label, input.classes);
        out.add("class {d} support {d} predicted {d} precision {s} recall {s} f1 {s}", .{ label,
             stats.support, stats.predicted, e.ratio(stats.true_positive, stats.predicted),
             e.ratio(stats.true_positive, stats.support), e.ratio(2 * stats.true_positive,
             stats.support + stats.predicted) });
    }
    out.add("calibration", .{});
    var bin_counts = [_]i64{0} ** 10;
    var bin_correct = [_]i64{0} ** 10;
    var bin_sums = [_]f64{0} ** 10;
    for (input.test_data, result.testing.predictions, result.testing.records) |image, chosen, record| {
        const confidence = record.scores[chosen];
        const bin = @min(input.params.bins - 1, @as(usize, @intFromFloat(@floor(confidence * c.f(input.params.bins)))));
        bin_counts[bin] += 1;
        bin_correct[bin] += @intFromBool(chosen == image.label);
        bin_sums[bin] += confidence;
    }
    var ece: f64 = 0;
    for (0..input.params.bins) |bin| {
        const number = bin_counts[bin];
        out.add("bin {d} {s} {s} count {d} accuracy {s} confidence {s}", .{ bin + 1, e.real(c.f(bin) / c.f(input.params.bins),
             2), e.real(c.f(bin + 1) / c.f(input.params.bins), 2), number, e.ratio(bin_correct[bin],
             number), if (number > 0) e.real(bin_sums[bin] / c.f(number), 4) else "-" });
        if (number > 0) ece += (c.f(number) / c.f(count)) * @abs(c.f(bin_correct[bin]) / c.f(number) - bin_sums[bin] / c.f(number));
    }
    out.add("ece {s}", .{e.real(ece, 4)});
    var class_counts = [_]i64{0} ** 10;
    for (input.test_data) |image| class_counts[image.label] += 1;
    for (network.layers[0 .. network.layer_count - 1], 0..) |layer, l| {
        out.add("hidden {d} {s} units {d}", .{ l + 1, @tagName(layer.function), layer.units });
        var means = [_][12]f64{[_]f64{0} ** 12} ** 10;
        var zeros = [_]usize{0} ** 12;
        for (input.test_data, result.testing.records) |image, record| for (0..layer.units) |j| {
            const value = record.activations[l + 1][j];
            means[image.label][j] += value;
            zeros[j] += @intFromBool(value == 0);
        };
        for (0..input.classes) |label| {
            var row: c.Text = .{};
            row.add("class {d} mean", .{label});
            if (class_counts[label] == 0) row.add(" -", .{}) else for (means[label][0..layer.units]) |*value| {
                value.* /= c.f(class_counts[label]);
                row.add(" {s}", .{e.real(value.*, 4)});
            };
            out.add("{s}", .{row.value()});
        }
        var preferred: c.Text = .{};
        preferred.add("preferred", .{});
        for (0..layer.units) |j| {
            var best: ?usize = null;
            for (0..input.classes) |label| if (class_counts[label] > 0 and (best == null or means[label][j] > means[best.?][j])) {
                best = label;
            };
            preferred.add(" {d}", .{best.?});
        }
        out.add("{s}", .{preferred.value()});
        if (layer.function == .RELU) {
            var row: c.Text = .{};
            row.add("zero_counts", .{});
            for (zeros[0..layer.units]) |number| row.add(" {d}", .{number});
            out.add("{s}", .{row.value()});
        }
    }
    out.add("pruning", .{});
    const weights = c.alloc(usize, network.weight_count);
    var next: usize = 0;
    for (network.is_weight[0..network.param_count], 0..) |is_weight, parameter| if (is_weight) {
        weights[next] = parameter;
        next += 1;
    };
    const CompareWeights = struct {
        fn less(values: []const f64, a: usize, b: usize) bool {
            const x = @abs(values[a]);
            const y = @abs(values[b]);
            return if (x != y) x < y else a < b;
        }
    };
    std.mem.sort(usize, weights, result.weights, CompareWeights.less);
    for (input.params.prune) |q| {
        const removed = q * network.weight_count / 100;
        var pruned: [1066]f64 = undefined;
        @memcpy(pruned[0..network.param_count], result.weights);
        for (weights[0..removed]) |parameter| pruned[parameter] = 0;
        const value = evaluate(network, pruned[0..network.param_count], input.test_data, false);
        out.add("prune {d} removed {d} correct {d} test_acc {s} test_loss {s}", .{ q, removed,
             value.correct, e.ratio(value.correct, count), e.real(value.loss, 6) });
    }
    out.add("noise", .{});
    for (noise) |item| {
        const correct = evaluate(network, result.weights, item.images, false).correct;
        out.add("noise {d} correct {d} test_acc {s}", .{ item.rate, correct, e.ratio(correct, count) });
    }
    var missed: c.Text = .{};
    missed.add("misclassified {d}", .{count - result.testing.correct});
    for (input.test_data, result.testing.predictions) |image, chosen| if (chosen != image.label) missed.add(" {s}",
         .{image.id});
    out.add("{s}", .{missed.value()});
    return out;
}
fn finalWeights(input: c.Input, results: []const Result) c.Lines {
    var out: c.Lines = .{};
    for (results, 0..) |result, index| {
        if (index > 0) out.add("", .{});
        const network = &input.networks[result.definition.network];
        out.add("RUN {s} NETWORK {s} EPOCH {d}", .{ result.definition.name, network.name, result.best_epoch });
        for (network.layers[0..network.layer_count], 0..) |layer, l| {
            out.add("LAYER {d} {d} {d}", .{ l + 1, layer.units, layer.inputs });
            for (0..layer.units) |j| {
                var row: c.Text = .{};
                row.add("W", .{});
                for (0..layer.inputs) |i| row.add(" {s}", .{e.real(result.weights[layer.weights + j * layer.inputs + i],
                     4)});
                out.add("{s}", .{row.value()});
            }
            var row: c.Text = .{};
            row.add("B", .{});
            for (0..layer.units) |j| row.add(" {s}", .{e.real(result.weights[layer.biases + j], 4)});
            out.add("{s}", .{row.value()});
        }
    }
    return out;
}
const ConfusedPair = struct {
    actual: usize,
    predicted: usize,
    count: i64,
    fn less(_: void, a: ConfusedPair, b: ConfusedPair) bool {
        if (a.count != b.count) return a.count > b.count;
        if (a.actual != b.actual) return a.actual < b.actual;
        return a.predicted < b.predicted;
    }
};
fn comparison(input: c.Input, training: []const c.Image, results: []const Result, noise: []const Noise) c.Lines {
    var out: c.Lines = .{};
    out.add("comparison", .{});
    const ranking = c.alloc(usize, results.len);
    for (ranking, 0..) |*index, i| index.* = i;
    const Rank = struct {
        fn less(values: []const Result, a: usize, b: usize) bool {
            const x = values[a];
            const y = values[b];
            if (x.testing.correct != y.testing.correct) return x.testing.correct > y.testing.correct;
            if (x.best_loss != y.best_loss) return x.best_loss < y.best_loss;
            return a < b;
        }
    };
    std.mem.sort(usize, ranking, results, Rank.less);
    const count = c.n(input.test_data.len);
    const top_index = ranking[0];
    const top = &results[top_index];
    const network = &input.networks[top.definition.network];
    for (ranking, 0..) |index, rank| {
        const result = &results[index];
        out.add("rank {d} {s} correct {d} test_acc {s} best_val_loss {s} test_loss {s} best_epoch {d} epochs {d} updates {d}",
             .{ rank + 1, result.definition.name, result.testing.correct, e.ratio(result.testing.correct,
             count), e.real(result.best_loss, 6), e.real(result.testing.loss, 6), result.best_epoch,
             result.epochs.items.len, result.updates });
    }
    out.add("agreement", .{});
    for (results) |a| {
        var row: c.Text = .{};
        row.add("{s}", .{a.definition.name});
        for (results) |b| {
            var agreement: i64 = 0;
            for (a.testing.predictions, b.testing.predictions) |x, y| agreement += @intFromBool(x == y);
            row.add(" {d}", .{agreement});
        }
        out.add("{s}", .{row.value()});
    }
    out.add("mcnemar {s}", .{top.definition.name});
    for (ranking) |index| if (index != top_index) {
        const other = &results[index];
        var b: i64 = 0;
        var second: i64 = 0;
        for (input.test_data, top.testing.predictions, other.testing.predictions) |image, x, y| {
            const good_x = x == image.label;
            const good_y = y == image.label;
            b += @intFromBool(good_x and !good_y);
            second += @intFromBool(good_y and !good_x);
        }
        const difference = @max(@as(i64, @intCast(@abs(b - second))) - 1, 0);
        const numerator = difference * difference;
        const denominator = b + second;
        out.add("vs {s} b {d} c {d} chi2 {s} significant {s}", .{ other.definition.name, b,
             second, if (denominator > 0) e.ratio(numerator, denominator) else "0.0000", if (numerator * 1000 > 3841 * denominator) "yes" else "no" });
    };
    const ensemble = c.alloc(usize, input.test_data.len);
    var correct: i64 = 0;
    var fixed: i64 = 0;
    var broken: i64 = 0;
    for (input.test_data, ensemble, 0..) |image, *chosen, i| {
        var votes = [_]usize{0} ** 10;
        for (results) |result| votes[result.testing.predictions[i]] += 1;
        var maximum: usize = 0;
        for (votes[0..input.classes]) |value| maximum = @max(maximum, value);
        for (ranking) |index| if (votes[results[index].testing.predictions[i]] == maximum) {
            chosen.* = results[index].testing.predictions[i];
            break;
        };
        const good = chosen.* == image.label;
        const top_good = top.testing.predictions[i] == image.label;
        correct += @intFromBool(good);
        fixed += @intFromBool(good and !top_good);
        broken += @intFromBool(top_good and !good);
    }
    out.add("ensemble correct {d}/{d} test_acc {s} fixed {d} broken {d}", .{ correct, count,
         e.ratio(correct, count), fixed, broken });
    var soft: std.ArrayList(usize) = .empty;
    for (results, 0..) |result, index| {
        const layout = &input.networks[result.definition.network];
        if (layout.layers[layout.layer_count - 1].function == .SOFTMAX) c.append(usize, &soft, index);
    }
    if (soft.items.len == 0) out.add("soft_ensemble none", .{}) else {
        var soft_correct: i64 = 0;
        for (input.test_data, 0..) |image, i| {
            var scores = [_]f64{0} ** 10;
            for (soft.items) |index| for (0..input.classes) |label| {
                scores[label] += results[index].testing.records[i].scores[label];
            };
            for (scores[0..input.classes]) |*score| score.* /= c.f(soft.items.len);
            soft_correct += @intFromBool(e.prediction(scores[0..input.classes]) == image.label);
        }
        out.add("soft_ensemble runs {d} correct {d}/{d} test_acc {s}", .{ soft.items.len, soft_correct,
             count, e.ratio(soft_correct, count) });
    }
    for (noise) |item| out.add("noise {d} flipped {d}", .{ item.rate, item.flipped });
    var summed = [_][10]i64{[_]i64{0} ** 10} ** 10;
    for (results) |result| for (0..input.classes) |actual| for (0..input.classes) |predicted| {
        summed[actual][predicted] += result.confusion[actual][predicted];
    };
    var pairs: std.ArrayList(ConfusedPair) = .empty;
    for (0..input.classes) |actual| for (0..input.classes) |predicted| if (actual != predicted and summed[actual][predicted] > 0) c.append(ConfusedPair,
         &pairs, .{ .actual = actual, .predicted = predicted, .count = summed[actual][predicted] });
    std.mem.sort(ConfusedPair, pairs.items, {}, ConfusedPair.less);
    out.add("confused_pairs", .{});
    for (pairs.items[0..@min(5, pairs.items.len)]) |pair| out.add("{d} as {d} count {d}", .{ pair.actual,
         pair.predicted, pair.count });
    out.add("", .{});
    out.add("saliency {s}", .{top.definition.name});
    out.add("{s}", .{classHeading("classes", input.classes)});
    const pixels = input.width * input.height;
    var class_counts = [_]usize{0} ** 10;
    var saliency = [_][64]f64{[_]f64{0} ** 64} ** 10;
    for (input.test_data, top.testing.records) |image, record| {
        class_counts[image.label] += 1;
        const gradient = net.backward(network, top.weights, &record);
        for (gradient.input[0..pixels], 0..) |value, parameter| saliency[image.label][parameter] += @abs(value);
    }
    var levels = [_][64]usize{[_]usize{0} ** 64} ** 10;
    for (0..input.classes) |label| {
        if (class_counts[label] > 0) for (saliency[label][0..pixels]) |*value| {
            value.* /= c.f(class_counts[label]);
        };
        var maximum: f64 = 0;
        for (saliency[label][0..pixels]) |value| maximum = @max(maximum, value);
        if (class_counts[label] > 0 and maximum > 0) for (0..pixels) |parameter| {
            levels[label][parameter] = @min(9, @as(usize, @intFromFloat(@floor(10 * saliency[label][parameter] / maximum))));
        };
    }
    e.levelMaps(&out, levels[0..input.classes], input.width, input.height);
    out.add("", .{});
    out.add("hardest_training_examples {s}", .{top.definition.name});
    const trained = evaluate(network, top.weights, training, true);
    const hardest = c.alloc(usize, training.len);
    for (hardest, 0..) |*index, i| index.* = i;
    const Hardest = struct {
        fn less(records: []const net.Forward, a: usize, b: usize) bool {
            const x = records[a].loss;
            const y = records[b].loss;
            return if (x != y) x > y else a < b;
        }
    };
    std.mem.sort(usize, hardest, @as([]const net.Forward, trained.records), Hardest.less);
    for (hardest[0..@min(5, hardest.len)]) |index| out.add("{s} label {d} predicted {d} loss {s}",
         .{ training[index].id, training[index].label, trained.predictions[index], e.real(trained.records[index].loss,
         6) });
    out.add("", .{});
    out.add("misclassified_examples {s}", .{top.definition.name});
    for (input.test_data, top.testing.predictions, 0..) |image, chosen, i| if (chosen != image.label) {
        var runs: c.Text = .{};
        for (results) |result| runs.add(" {d}", .{result.testing.predictions[i]});
        out.add("{s} label {d} predicted {d} confidence {s} true_score {s} runs{s} ensemble {d}",
             .{ image.id, image.label, chosen, e.real(top.testing.records[i].scores[chosen],
             4), e.real(top.testing.records[i].scores[image.label], 4), runs.value(), ensemble[i] });
        var nearest: usize = 0;
        var distance = pixels + 1;
        for (input.train, 0..) |candidate, index| {
            var d: usize = 0;
            for (image.pixels, candidate.pixels) |x, y| d += @intFromBool(x != y);
            if (d < distance) {
                distance = d;
                nearest = index;
            }
        }
        out.add("nearest {s} label {d} distance {d}", .{ input.train[nearest].id, input.train[nearest].label,
             distance });
        e.imageLines(&out, image, input.width, input.height);
    };
    return out;
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    c.allocator = arena.allocator();
    const io = init.io;
    const input = try c.load(io);
    const validation_count = input.train.len / 5;
    const training_count = input.train.len - validation_count;
    const training = input.train[0..training_count];
    const validation = input.train[training_count..];
    const check = gradientCheck(input, training);
    const noise = noisy(input);
    const results = c.alloc(Result, input.params.runs.items.len);
    for (input.params.runs.items, results) |run, *result| result.* = trainRun(input, training, validation, run);
    var log: c.Lines = .{};
    log.add("run,epoch,lr,grad_norm,train_loss,train_acc,val_loss,val_acc,improved", .{});
    var predictions: c.Lines = .{};
    predictions.add("run,id,label,predicted,confidence", .{});
    for (results) |result| {
        for (result.epochs.items) |epoch| log.add("{s},{d},{s},{s},{s},{s},{s},{s},{d}", .{ result.definition.name,
             epoch.number, e.real(epoch.eta, 6), e.real(epoch.magnitude, 4), e.real(epoch.train_loss,
             6), e.ratio(epoch.train_correct, c.n(training_count)), e.real(epoch.val_loss,
             6), e.ratio(epoch.val_correct, c.n(validation_count)), @intFromBool(epoch.improved) });
        for (input.test_data, result.testing.predictions, result.testing.records) |image, chosen,
             record| predictions.add("{s},{s},{d},{d},{s}", .{ result.definition.name, image.id,
             image.label, chosen, e.real(record.scores[chosen], 4) });
    }
    var evaluation = dataSummary(input, training, validation);
    evaluation.add("", .{});
    for (results) |*result| {
        evaluation.extend(runReport(input, training, validation, result, noise));
        evaluation.add("", .{});
    }
    evaluation.extend(comparison(input, training, results, noise));
    try std.Io.Dir.cwd().createDirPath(io, "output");
    try e.save(io, "gradient_check.txt", check);
    try e.save(io, "training_log.csv", log);
    try e.save(io, "final_weights.txt", finalWeights(input, results));
    try e.save(io, "predictions.csv", predictions);
    try e.save(io, "evaluation.txt", evaluation);
}
