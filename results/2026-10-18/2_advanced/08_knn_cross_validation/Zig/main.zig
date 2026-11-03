const std = @import("std");
const d = @import("dataset.zig");
const scaling = @import("scaling.zig");
const n = @import("neighbors.zig");
const v = @import("validation.zig");
const r = @import("report.zig");
const Orders = []const []const n.Neighbor;
const Result = struct { model: v.Model, predictions: []const n.Prediction, correct: usize, rmse: f64 };
const Results = struct { owner: *std.heap.ArenaAllocator, scores: []const Result };
fn notation(model: v.Model) []const u8 { return d.fmt("k={d} metric={s} weighting={s} scaling={s}", .{ model.k, @tagName(model.metric), @tagName(model.weighting), @tagName(model.scaling) }); }
fn extend(lines: *std.ArrayList([]const u8), more: d.Strings) void { for (more) |line| d.append([]const u8, lines, line); }
fn part(lines: *std.ArrayList([]const u8), more: d.Strings) void { if (lines.items.len > 0) d.append([]const u8, lines, ""); extend(lines, more); }
fn correctCount(predictions: []const n.Prediction, rows: []const d.Row) usize { var count: usize = 0; for (predictions, rows) |prediction, row| { if (row.label) |label| { if (prediction.label == label) count += 1; } } return count; }
fn labelCount(rows: []const d.Row) usize { var count: usize = 0; for (rows) |row| { if (row.label != null) count += 1; } return count; }
fn subPredictions(predictions: []const n.Prediction, indices: []const usize) []const n.Prediction { const result = d.alloc(n.Prediction, indices.len); for (indices, result) |i, *prediction| prediction.* = predictions[i]; return result; }
fn crossValidate(models: []const v.Model, rows: []const d.Row, fold_count: usize, features: []const usize, classes: usize) Results {
    const owner = &d.alloc(std.heap.ArenaAllocator, 1)[0]; owner.* = std.heap.ArenaAllocator.init(d.backing); const previous_allocator = d.allocator; d.allocator = owner.allocator(); defer d.allocator = previous_allocator;
    const predictions = d.alloc([]n.Prediction, models.len); for (predictions) |*values| values.* = d.alloc(n.Prediction, rows.len);
    for (v.stratified(rows, fold_count)) |fold| {
        const training = v.without(rows, fold); const queries = v.choose(rows, fold); var cache: [2][4]?Orders = @splat(@splat(null));
        for (models, predictions) |model, values| {
            const method = @intFromEnum(model.scaling); const metric = @intFromEnum(model.metric);
            if (cache[method][metric] == null) cache[method][metric] = v.neighborOrders(training, queries, model.scaling, model.metric, features);
            for (fold, cache[method][metric].?) |index, ordered| values[index] = n.predict(ordered, model.k, model.weighting, classes);
        }
    }
    const scores = d.alloc(Result, models.len); for (models, predictions, scores) |model, values, *score| score.* = .{ .model = model, .predictions = values, .correct = correctCount(values, rows), .rmse = v.rmse(v.residuals(values, rows)).? };
    return .{ .owner = owner, .scores = scores };
}
fn bestClassifier(results: []const Result, indices: []const usize) usize { var best = indices[0]; for (indices) |i| { if (results[i].correct > results[best].correct) best = i; } return best; }
fn bestRegressor(results: []const Result, indices: []const usize) usize { var best = indices[0]; for (indices) |i| { if (r.four(results[i].rmse) < r.four(results[best].rmse)) best = i; } return best; }
fn leaveOneOut(models: []const v.Model, rows: []const d.Row, features: []const usize, classes: usize) []const []const n.Prediction {
    const result = d.alloc([]const n.Prediction, models.len); const predictions = d.alloc([]n.Prediction, models.len); for (predictions, result) |*values, *output| { values.* = d.alloc(n.Prediction, rows.len); output.* = values.*; }
    for (rows, 0..) |_, i| {
        const training = v.without(rows, &.{i}); var cache: [2][4]?[]const n.Neighbor = @splat(@splat(null));
        for (models, predictions) |model, values| { const method = @intFromEnum(model.scaling); const metric = @intFromEnum(model.metric); if (cache[method][metric] == null) cache[method][metric] = v.neighborOrders(training, rows[i..i + 1], model.scaling, model.metric, features)[0]; values[i] = n.predict(cache[method][metric].?, model.k, model.weighting, classes); }
    }
    return result;
}
fn labelCounts(rows: []const d.Row, labels: d.Strings) []const u8 { var counts: [300]usize = @splat(0); for (rows) |row| counts[row.label.?] += 1; var parts: std.ArrayList([]const u8) = .empty; for (labels, 0..) |label, i| d.append([]const u8, &parts, d.fmt("{s} {d}", .{ label, counts[i] })); return d.join(parts.items, " "); }
fn evaluation(rows: []const d.Row, predictions: []const n.Prediction, labels: d.Strings) d.Strings {
    const classes = labels.len; const matrix = d.alloc(usize, classes * classes); @memset(matrix, 0); for (rows, predictions) |row, prediction| { if (row.label) |truth| matrix[truth * classes + prediction.label] += 1; }
    var lines: std.ArrayList([]const u8) = .empty; d.append([]const u8, &lines, d.fmt("true\\predicted {s}", .{d.join(labels, " ")}));
    for (labels, 0..) |label, i| { var cells: std.ArrayList([]const u8) = .empty; d.append([]const u8, &cells, label); for (matrix[i * classes..][0..classes]) |count| d.append([]const u8, &cells, d.fmt("{d}", .{count})); d.append([]const u8, &lines, d.join(cells.items, " ")); }
    var totals: [3]f64 = @splat(0); var valued: [3]usize = @splat(0);
    for (labels, 0..) |label, i| {
        const hits = matrix[i * classes + i]; var predicted: usize = 0; var actual: usize = 0; for (0..classes) |j| { predicted += matrix[j * classes + i]; actual += matrix[i * classes + j]; }
        const numerators = [_]usize{ hits, hits, 2 * hits }; const denominators = [_]usize{ predicted, actual, predicted + actual };
        for (numerators, denominators, 0..) |numerator, denominator, j| { if (denominator > 0) { totals[j] += d.real(numerator) / d.real(denominator); valued[j] += 1; } }
        d.append([]const u8, &lines, d.fmt("class {s} precision {s} recall {s} f1 {s} support {d}", .{ label, r.fraction(d.int(hits), d.int(predicted)), r.fraction(d.int(hits), d.int(actual)), r.fraction(d.int(2 * hits), d.int(predicted + actual)), actual }));
    }
    var averages: [3][]const u8 = undefined; for (totals, valued, &averages) |total, count, *average| average.* = if (count == 0) "-" else r.fixed(total / d.real(count));
    d.append([]const u8, &lines, d.fmt("macro precision {s} recall {s} f1 {s}", .{ averages[0], averages[1], averages[2] })); return lines.items;
}
fn reliability(rows: []const d.Row, predictions: []const n.Prediction, bounds: []const f64) d.Strings {
    const counts = d.alloc(usize, bounds.len + 1); const hits = d.alloc(usize, bounds.len + 1); const shares = d.alloc(f64, bounds.len + 1); @memset(counts, 0); @memset(hits, 0); @memset(shares, 0);
    for (rows, predictions) |row, prediction| { const truth = row.label orelse continue; var index: usize = 0; while (index < bounds.len and bounds[index] <= prediction.share) index += 1; counts[index] += 1; if (prediction.label == truth) hits[index] += 1; shares[index] += prediction.share; }
    var lines: std.ArrayList([]const u8) = .empty; for (counts, hits, shares, 0..) |count, hit, share, i| { const lower = r.fixedPlaces(if (i == 0) 0 else bounds[i - 1], 2); d.append([]const u8, &lines, if (count == 0) d.fmt("bin {s} rows 0", .{lower}) else d.fmt("bin {s} rows {d} correct {s} share {s}", .{ lower, count, r.ratio(hit, count), r.fixed(share / d.real(count)) })); } return lines.items;
}
fn nestedPart(data: d.Data, grid: []const v.Model, features: []const usize) d.Strings {
    const rows = data.train; const settings = data.settings; const estimates = d.alloc(f64, rows.len); var correct: usize = 0; var lines: std.ArrayList([]const u8) = .empty; d.append([]const u8, &lines, d.fmt("nested_cross_validation folds {d}", .{settings.folds}));
    for (v.stratified(rows, settings.folds), 1..) |fold, f| {
        const training = v.without(rows, fold); const queries = v.choose(rows, fold); const inner = crossValidate(grid, training, settings.folds, features, data.labels.len);
        const all_indices = d.indices(inner.scores.len); const classifier = inner.scores[bestClassifier(inner.scores, all_indices)]; const regressor = inner.scores[bestRegressor(inner.scores, all_indices)];
        const classifier_model = classifier.model; const regressor_model = regressor.model; const inner_correct = classifier.correct; const inner_rmse = regressor.rmse; inner.owner.deinit();
        const cp = v.predictRows(classifier_model, training, queries, features, data.labels.len); const rp = v.predictRows(regressor_model, training, queries, features, data.labels.len); const hits = correctCount(cp, queries); correct += hits;
        for (fold, rp) |i, prediction| estimates[i] = prediction.estimate;
        d.append([]const u8, &lines, d.fmt("fold {d} classifier {s} inner {s} outer {s}", .{ f, notation(classifier_model), r.fixed(d.real(inner_correct) / d.real(training.len)), r.ratio(hits, fold.len) }));
        d.append([]const u8, &lines, d.fmt("fold {d} regressor {s} inner {s} outer {s}", .{ f, notation(regressor_model), r.fixed(inner_rmse), r.fixed(v.rmse(v.residuals(rp, queries)).?) }));
    }
    const errors = d.alloc(f64, rows.len); for (estimates, rows, errors) |estimate, row, *error_value| error_value.* = estimate - row.target.?;
    d.append([]const u8, &lines, d.fmt("nested accuracy {s} rmse {s}", .{ r.ratio(correct, rows.len), r.fixed(v.rmse(errors).?) })); return lines.items;
}
fn removeFeature(features: []const usize, removed: usize) []const usize { var result: std.ArrayList(usize) = .empty; for (features) |feature| { if (feature != removed) d.append(usize, &result, feature); } return result.items; }
fn featureNames(features: []const usize, names: d.Strings) []const u8 { var result: std.ArrayList([]const u8) = .empty; for (features) |feature| d.append([]const u8, &result, names[feature]); return d.join(result.items, " "); }
fn featurePart(data: d.Data, classifier: Result, features: []const usize) d.Strings {
    var current = features; var selected = features; var best = classifier.correct; var step: usize = 0; var lines: std.ArrayList([]const u8) = .empty;
    extend(&lines, &.{ d.fmt("feature_selection {s}", .{notation(classifier.model)}), d.fmt("start features {s} correct {s}", .{ featureNames(features, data.features), r.ratio(best, data.train.len) }) });
    while (current.len >= 3) {
        step += 1; const counts = d.alloc(usize, current.len); var winner: usize = 0; var candidates: std.ArrayList([]const u8) = .empty;
        for (current, counts, 0..) |feature, *count, i| { const used = removeFeature(current, feature); const trial = crossValidate(&.{classifier.model}, data.train, data.settings.folds, used, data.labels.len); count.* = trial.scores[0].correct; trial.owner.deinit(); if (count.* > counts[winner]) winner = i; d.append([]const u8, &candidates, d.fmt("{s} {d}", .{ data.features[feature], count.* })); }
        const removed = current[winner]; const correct = counts[winner]; d.append([]const u8, &lines, d.fmt("step {d} remove {s} correct {s} candidates {s}", .{ step, data.features[removed], r.ratio(correct, data.train.len), d.join(candidates.items, " ") }));
        current = removeFeature(current, removed); if (correct >= best) { best = correct; selected = current; }
    }
    d.append([]const u8, &lines, d.fmt("selected features {s} correct {s}", .{ featureNames(selected, data.features), r.ratio(best, data.train.len) }));
    const predictions = v.predictRows(classifier.model, data.train, data.queries, selected, data.labels.len); d.append([]const u8, &lines, d.fmt("selected test {s}", .{r.ratio(correctCount(predictions, data.queries), labelCount(data.queries))})); return lines.items;
}
const IdContext = struct { rows: []const d.Row };
fn idLess(context: IdContext, a: usize, b: usize) bool { return d.textLess(context.rows[a].id, context.rows[b].id); }
fn filteredOrder(ordered: []const n.Neighbor, present: []const bool, excluded: ?usize, buffer: *[300]n.Neighbor) []const n.Neighbor { var count: usize = 0; for (ordered) |neighbor| { const i = neighbor.row.index; if (present[i] and (excluded == null or excluded.? != i)) { buffer[count] = neighbor; count += 1; } } return buffer[0..count]; }
const Condensed = struct { rows: []const usize, scans: usize };
fn condense(rows: []const usize, train: []const d.Row, orders: Orders) Condensed {
    var store: std.ArrayList(usize) = .empty; d.append(usize, &store, rows[0]); const present = d.alloc(bool, train.len); @memset(present, false); present[rows[0]] = true; var scans: usize = 0;
    while (true) {
        scans += 1; var added = false;
        for (rows) |i| { if (present[i]) continue; var nearest: ?usize = null; for (orders[i]) |neighbor| { if (present[neighbor.row.index]) { nearest = neighbor.row.label.?; break; } } if (nearest.? != train[i].label.?) { present[i] = true; d.append(usize, &store, i); added = true; } }
        if (!added) break;
    }
    std.mem.sort(usize, store.items, IdContext{ .rows = train }, idLess); return .{ .rows = store.items, .scans = scans };
}
const HubContext = struct { rows: []const d.Row, counts: []const usize };
fn hubLess(context: HubContext, a: usize, b: usize) bool { return if (context.counts[a] == context.counts[b]) d.textLess(context.rows[a].id, context.rows[b].id) else context.counts[a] > context.counts[b]; }
fn prototypeLines(data: d.Data, model: v.Model, features: []const usize, class_orders: Orders, class_predictions: []const n.Prediction) d.Strings {
    const train = data.train; const settings = data.settings; const classes = data.labels.len; const orders = v.neighborOrders(train, train, model.scaling, model.metric, features); const ids = d.indices(train.len); std.mem.sort(usize, ids, IdContext{ .rows = train }, idLess);
    var edited: []const usize = ids; var editing: std.ArrayList([]const u8) = .empty; d.append([]const u8, &editing, d.fmt("editing k={d}", .{settings.edit})); var pass: usize = 0; const present = d.alloc(bool, train.len);
    const Removal = struct { index: usize, label: usize, share: f64 };
    while (true) {
        pass += 1; @memset(present, false); for (edited) |i| present[i] = true; var removals: std.ArrayList(Removal) = .empty;
        for (edited) |i| { var buffer: [300]n.Neighbor = undefined; const vote = n.predict(filteredOrder(orders[i], present, i, &buffer), settings.edit, model.weighting, classes); if (vote.label != train[i].label.?) d.append(Removal, &removals, .{ .index = i, .label = vote.label, .share = vote.share }); }
        d.append([]const u8, &editing, d.fmt("pass {d} removed {d}", .{ pass, removals.items.len }));
        for (removals.items) |removal| { const row = train[removal.index]; d.append([]const u8, &editing, d.fmt("  {s} true {s} predicted {s} share {s}", .{ row.id, data.labels[row.label.?], data.labels[removal.label], r.fixed(removal.share) })); }
        if (removals.items.len == 0) break;
        var removed: [300]bool = @splat(false); for (removals.items) |removal| removed[removal.index] = true; var next: std.ArrayList(usize) = .empty; for (edited) |i| { if (!removed[i]) d.append(usize, &next, i); } edited = next.items;
    }
    d.append([]const u8, &editing, d.fmt("edited size {d} removed {d}", .{ edited.len, train.len - edited.len }));
    const condensed = condense(ids, train, orders); const edited_condensed = condense(edited, train, orders); var lines: std.ArrayList([]const u8) = .empty;
    part(&lines, &.{d.fmt("space {s}", .{notation(model)})}); part(&lines, editing.items); part(&lines, &.{ d.fmt("condensing original scans {d} size {d}", .{ condensed.scans, condensed.rows.len }), d.fmt("condensing edited scans {d} size {d}", .{ edited_condensed.scans, edited_condensed.rows.len }) });
    const PrototypeSet = struct { name: []const u8, rows: []const usize }; const sets = [_]PrototypeSet{ .{ .name = "original", .rows = ids }, .{ .name = "edited", .rows = edited }, .{ .name = "condensed", .rows = condensed.rows }, .{ .name = "edited_condensed", .rows = edited_condensed.rows } }; var set_lines: std.ArrayList([]const u8) = .empty; const labelled = labelCount(data.queries);
    for (sets) |set| {
        @memset(present, false); for (set.rows) |i| present[i] = true; var knn: usize = 0; var one: usize = 0;
        for (data.queries, class_orders) |query, ordered| { const truth = query.label orelse continue; var buffer: [300]n.Neighbor = undefined; const nearest = filteredOrder(ordered, present, null, &buffer); const vote = n.predict(nearest, model.k, model.weighting, classes); if (vote.label == truth) knn += 1; if (nearest[0].row.label.? == truth) one += 1; }
        d.append([]const u8, &set_lines, d.fmt("set {s} size {d} {s} knn {s} 1nn {s}", .{ set.name, set.rows.len, labelCounts(v.choose(train, set.rows), data.labels), r.ratio(knn, labelled), r.ratio(one, labelled) }));
    }
    part(&lines, set_lines.items);
    for (sets[2..]) |set| { var rows: std.ArrayList([]const u8) = .empty; d.append([]const u8, &rows, d.fmt("prototypes {s}", .{set.name})); var offset: usize = 0; while (offset < set.rows.len) : (offset += 10) { var names: std.ArrayList([]const u8) = .empty; for (set.rows[offset..@min(offset + 10, set.rows.len)]) |i| d.append([]const u8, &names, train[i].id); d.append([]const u8, &rows, d.join(names.items, " ")); } part(&lines, rows.items); }
    var borders: std.ArrayList([]const u8) = .empty; d.append([]const u8, &borders, "borders"); var total_border: usize = 0;
    for (data.labels, 0..) |label, c| {
        var count: usize = 0; var border: usize = 0; var same: f64 = 0; var other: f64 = 0;
        for (ids) |i| {
            if (train[i].label.? != c) continue; count += 1; var first = true; var found_same = false; var found_other = false;
            for (orders[i]) |neighbor| { if (neighbor.row.index == i) continue; if (first) { if (neighbor.row.label.? != c) border += 1; first = false; } if (neighbor.row.label.? == c and !found_same) { same += neighbor.distance; found_same = true; } if (neighbor.row.label.? != c and !found_other) { other += neighbor.distance; found_other = true; } if (found_same and found_other) break; }
        }
        total_border += border; d.append([]const u8, &borders, d.fmt("class {s} size {d} border {d} same {s} other {s}", .{ label, count, border, r.fixed(same / d.real(count)), r.fixed(other / d.real(count)) }));
    }
    d.append([]const u8, &borders, d.fmt("border total {s}", .{r.ratio(total_border, train.len)})); part(&lines, borders.items);
    const occurrences = d.alloc(usize, train.len); @memset(occurrences, 0); for (class_predictions) |prediction| for (prediction.nearest) |neighbor| { occurrences[neighbor.row.index] += 1; };
    const ranked = d.indices(train.len); std.mem.sort(usize, ranked, HubContext{ .rows = train, .counts = occurrences }, hubLess); var hubs: std.ArrayList([]const u8) = .empty; d.append([]const u8, &hubs, d.fmt("hubs k={d} queries {d}", .{ model.k, data.queries.len }));
    for (ranked[0..@min(settings.top, ranked.len)]) |i| d.append([]const u8, &hubs, d.fmt("{s} {s} {d}", .{ train[i].id, data.labels[train[i].label.?], occurrences[i] })); var anti: usize = 0; for (occurrences) |count| { if (count == 0) anti += 1; } d.append([]const u8, &hubs, d.fmt("anti_hubs {d}", .{anti})); part(&lines, hubs.items); return lines.items;
}
const RankContext = struct { scores: []const Result, regression: bool };
fn rankLess(context: RankContext, a: usize, b: usize) bool { if (context.regression) { const first = r.four(context.scores[a].rmse); const second = r.four(context.scores[b].rmse); if (first != second) return first < second; } else if (context.scores[a].correct != context.scores[b].correct) return context.scores[a].correct > context.scores[b].correct; return a < b; }
const ResidualContext = struct { rows: []const d.Row, residuals: []const f64 };
fn residualLess(context: ResidualContext, a: usize, b: usize) bool { const first = r.four(@abs(context.residuals[a])); const second = r.four(@abs(context.residuals[b])); return if (first == second) d.textLess(context.rows[a].id, context.rows[b].id) else first > second; }
const UncertainContext = struct { predictions: []const n.Prediction };
fn uncertainLess(context: UncertainContext, a: usize, b: usize) bool { const first = r.four(context.predictions[a].share - context.predictions[a].runner_share); const second = r.four(context.predictions[b].share - context.predictions[b].runner_share); return if (first == second) a < b else first < second; }
fn targetResiduals(predictions: []const n.Prediction, rows: []const d.Row) []const f64 { var errors: std.ArrayList(f64) = .empty; for (predictions, rows) |prediction, row| { if (row.target) |target| d.append(f64, &errors, prediction.estimate - target); } return errors.items; }
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa); defer arena.deinit(); d.allocator = arena.allocator(); d.backing = init.gpa; const cwd = std.Io.Dir.cwd();
    const train_text = try cwd.readFileAlloc(init.io, "input/train.csv", d.allocator, .unlimited); const query_text = try cwd.readFileAlloc(init.io, "input/test.csv", d.allocator, .unlimited); const params_text = try cwd.readFileAlloc(init.io, "input/params.txt", d.allocator, .unlimited);
    const data = d.read(train_text, query_text, params_text); const train = data.train; const queries = data.queries; const settings = data.settings; const labels = data.labels; const features = d.indices(data.features.len); var grid: std.ArrayList(v.Model) = .empty;
    for (settings.ks) |k| for (settings.metrics) |metric| for (settings.weightings) |weighting| for (settings.scalings) |method| d.append(v.Model, &grid, .{ .k = k, .metric = metric, .weighting = weighting, .scaling = method });
    const results = crossValidate(grid.items, train, settings.folds, features, labels.len); defer results.owner.deinit(); const all_indices = d.indices(results.scores.len); const scores = results.scores; const classifier = scores[bestClassifier(scores, all_indices)]; const regressor = scores[bestRegressor(scores, all_indices)];
    const class_orders = v.neighborOrders(train, queries, classifier.model.scaling, classifier.model.metric, features); const cp = d.alloc(n.Prediction, queries.len); for (class_orders, cp) |ordered, *prediction| prediction.* = n.predict(ordered, classifier.model.k, classifier.model.weighting, labels.len);
    const reg_orders = if (classifier.model.scaling == regressor.model.scaling and classifier.model.metric == regressor.model.metric) class_orders else v.neighborOrders(train, queries, regressor.model.scaling, regressor.model.metric, features); const rp = d.alloc(n.Prediction, queries.len); for (reg_orders, rp) |ordered, *prediction| prediction.* = n.predict(ordered, regressor.model.k, regressor.model.weighting, labels.len);
    const labelled = labelCount(queries); const test_errors = targetResiduals(rp, queries); const folds = v.stratified(train, settings.folds); var metrics: std.ArrayList([]const u8) = .empty;
    part(&metrics, &.{ d.fmt("data train {d} test {d} labelled {d} targets {d} features {d} classes {d}", .{ train.len, queries.len, labelled, test_errors.len, features.len, labels.len }), d.fmt("classes {s}", .{labelCounts(train, labels)}) });
    for (settings.scalings) |method| {
        const scale = scaling.compute(train, method); var lines: std.ArrayList([]const u8) = .empty; d.append([]const u8, &lines, d.fmt("scaling {s}", .{@tagName(method)})); for (data.features, scale.centers, scale.scales) |name, center, value| d.append([]const u8, &lines, d.fmt("{s} center {s} scale {s}", .{ name, r.fixedPlaces(center, 6), r.fixedPlaces(value, 6) })); part(&metrics, lines.items);
    }
    var fold_lines: std.ArrayList([]const u8) = .empty; d.append([]const u8, &fold_lines, d.fmt("folds {d}", .{settings.folds})); for (folds, 1..) |fold, f| d.append([]const u8, &fold_lines, d.fmt("fold {d} size {d} {s}", .{ f, fold.len, labelCounts(v.choose(train, fold), labels) })); part(&metrics, fold_lines.items);
    part(&metrics, &.{ d.fmt("grid {d}", .{grid.items.len}), d.fmt("best_classifier {s} correct {s} rmse {s}", .{ notation(classifier.model), r.ratio(classifier.correct, train.len), r.fixed(classifier.rmse) }), d.fmt("best_regressor {s} rmse {s} correct {s}", .{ notation(regressor.model), r.fixed(regressor.rmse), r.ratio(regressor.correct, train.len) }) });
    for ([_]bool{ false, true }) |regression| {
        const ranked = d.indices(scores.len); std.mem.sort(usize, ranked, RankContext{ .scores = scores, .regression = regression }, rankLess); var lines: std.ArrayList([]const u8) = .empty; d.append([]const u8, &lines, d.fmt("top {d} by {s}", .{ settings.top, if (regression) "rmse" else "accuracy" }));
        for (ranked[0..@min(settings.top, ranked.len)], 1..) |i, rank| { const result = scores[i]; d.append([]const u8, &lines, if (regression) d.fmt("{d} {s} rmse {s} correct {s}", .{ rank, notation(result.model), r.fixed(result.rmse), r.ratio(result.correct, train.len) }) else d.fmt("{d} {s} correct {s} rmse {s}", .{ rank, notation(result.model), r.ratio(result.correct, train.len), r.fixed(result.rmse) })); } part(&metrics, lines.items);
    }
    inline for (.{ .{ "k", "ks" }, .{ "metric", "metrics" }, .{ "weighting", "weightings" }, .{ "scaling", "scalings" } }) |selection_fields| {
        const field = selection_fields[0]; const values = @field(settings, selection_fields[1]); var lines: std.ArrayList([]const u8) = .empty; d.append([]const u8, &lines, d.fmt("best per {s}", .{field}));
        for (values) |value| { var matching: std.ArrayList(usize) = .empty; for (grid.items, 0..) |model, i| { if (@field(model, field) == value) d.append(usize, &matching, i); } const c = scores[bestClassifier(scores, matching.items)]; const reg = scores[bestRegressor(scores, matching.items)]; const text = if (comptime @TypeOf(value) == usize) d.fmt("{d}", .{value}) else @tagName(value); d.append([]const u8, &lines, d.fmt("{s}={s} classifier {s} accuracy {s} regressor {s} rmse {s}", .{ field, text, notation(c.model), r.fixed(d.real(c.correct) / d.real(train.len)), notation(reg.model), r.fixed(reg.rmse) })); } part(&metrics, lines.items);
    }
    var classifier_folds: std.ArrayList([]const u8) = .empty; var regressor_folds: std.ArrayList([]const u8) = .empty; d.append([]const u8, &classifier_folds, "classifier folds"); d.append([]const u8, &regressor_folds, "regressor folds");
    for (folds, 1..) |fold, f| { const rows = v.choose(train, fold); d.append([]const u8, &classifier_folds, d.fmt("fold {d} correct {s}", .{ f, r.ratio(correctCount(subPredictions(classifier.predictions, fold), rows), fold.len) })); d.append([]const u8, &regressor_folds, d.fmt("fold {d} size {d} rmse {s}", .{ f, fold.len, r.fixed(v.rmse(v.residuals(subPredictions(regressor.predictions, fold), rows)).?) })); }
    part(&metrics, classifier_folds.items); part(&metrics, regressor_folds.items);
    var cv_classes: std.ArrayList([]const u8) = .empty; d.append([]const u8, &cv_classes, "cross_validation classes"); extend(&cv_classes, evaluation(train, classifier.predictions, labels)); part(&metrics, cv_classes.items);
    var cv_reliability: std.ArrayList([]const u8) = .empty; d.append([]const u8, &cv_reliability, "cross_validation reliability"); extend(&cv_reliability, reliability(train, classifier.predictions, settings.bins)); part(&metrics, cv_reliability.items);
    var mcnemar: std.ArrayList([]const u8) = .empty; d.append([]const u8, &mcnemar, "mcnemar");
    for (settings.metrics) |metric| {
        var matching: std.ArrayList(usize) = .empty; for (grid.items, 0..) |model, i| { if (model.metric == metric) d.append(usize, &matching, i); } const comparison = scores[bestClassifier(scores, matching.items)]; var first: usize = 0; var second: usize = 0;
        for (train, classifier.predictions, comparison.predictions) |row, p, q| { if (p.label == row.label.? and q.label != row.label.?) first += 1; if (p.label != row.label.? and q.label == row.label.?) second += 1; }
        const magnitude: i64 = @intCast(@abs(d.int(first) - d.int(second))); const base = @max(0, magnitude - 1); const u = base * base; const denominator = d.int(first + second); const statistic = if (denominator == 0) r.fraction(0, 1) else r.fraction(u, denominator);
        d.append([]const u8, &mcnemar, d.fmt("{s} b {d} c {d} statistic {s} significant {s}", .{ notation(comparison.model), first, second, statistic, if (1000 * u > 3841 * denominator) "yes" else "no" }));
    }
    part(&metrics, mcnemar.items);
    var variants: std.ArrayList(v.Model) = .empty; var selected_k: usize = 0; for (settings.ks, 0..) |k, i| { d.append(v.Model, &variants, .{ .k = k, .metric = classifier.model.metric, .weighting = classifier.model.weighting, .scaling = classifier.model.scaling }); if (k == classifier.model.k) selected_k = i; } d.append(v.Model, &variants, regressor.model);
    const loo = leaveOneOut(variants.items, train, features, labels.len); const lc = loo[selected_k]; const lr = loo[loo.len - 1]; var errors: std.ArrayList(usize) = .empty; var class_errors: [300]usize = @splat(0);
    for (train, lc, 0..) |row, prediction, i| { if (prediction.label != row.label.?) { d.append(usize, &errors, i); class_errors[row.label.?] += 1; } } std.mem.sort(usize, errors.items, IdContext{ .rows = train }, idLess);
    var descriptions: std.ArrayList([]const u8) = .empty; for (labels, 0..) |label, c| d.append([]const u8, &descriptions, d.fmt("{s} {d}", .{ label, class_errors[c] })); var loo_classifier: std.ArrayList([]const u8) = .empty;
    extend(&loo_classifier, &.{ d.fmt("leave_one_out classifier {s}", .{notation(classifier.model)}), d.fmt("errors {s}", .{r.ratio(errors.items.len, train.len)}), d.fmt("class_errors {s}", .{d.join(descriptions.items, " ")}) });
    for (errors.items) |i| d.append([]const u8, &loo_classifier, d.fmt("{s} true {s} predicted {s} share {s}", .{ train[i].id, labels[train[i].label.?], labels[lc[i].label], r.fixed(lc[i].share) })); part(&metrics, loo_classifier.items);
    const residuals = v.residuals(lr, train); const largest = d.indices(train.len); std.mem.sort(usize, largest, ResidualContext{ .rows = train, .residuals = residuals }, residualLess); var loo_regressor: std.ArrayList([]const u8) = .empty;
    extend(&loo_regressor, &.{ d.fmt("leave_one_out regressor {s}", .{notation(regressor.model)}), d.fmt("rmse {s} mae {s}", .{ r.fixed(v.rmse(residuals).?), r.fixed(v.mae(residuals)) }), d.fmt("largest {d} residuals", .{settings.top}) });
    for (largest[0..@min(settings.top, largest.len)]) |i| d.append([]const u8, &loo_regressor, d.fmt("{s} target {s} estimate {s} residual {s}", .{ train[i].id, r.fixed(train[i].target.?), r.fixed(lr[i].estimate), r.fixed(residuals[i]) })); part(&metrics, loo_regressor.items);
    var loo_k: std.ArrayList([]const u8) = .empty; d.append([]const u8, &loo_k, d.fmt("leave_one_out by k metric={s} weighting={s} scaling={s}", .{ @tagName(classifier.model.metric), @tagName(classifier.model.weighting), @tagName(classifier.model.scaling) })); for (settings.ks, loo[0..settings.ks.len]) |k, predictions| d.append([]const u8, &loo_k, d.fmt("k={d} correct {s} rmse {s}", .{ k, r.ratio(correctCount(predictions, train), train.len), r.fixed(v.rmse(v.residuals(predictions, train)).?) })); part(&metrics, loo_k.items);
    part(&metrics, nestedPart(data, grid.items, features)); part(&metrics, featurePart(data, classifier, features));
    var test_classes: std.ArrayList([]const u8) = .empty; extend(&test_classes, &.{ d.fmt("test classification {s}", .{notation(classifier.model)}), d.fmt("labelled {d} correct {s}", .{ labelled, r.ratio(correctCount(cp, queries), labelled) }) }); extend(&test_classes, evaluation(queries, cp, labels)); part(&metrics, test_classes.items);
    var test_reliability: std.ArrayList([]const u8) = .empty; d.append([]const u8, &test_reliability, "test reliability"); extend(&test_reliability, reliability(queries, cp, settings.bins)); part(&metrics, test_reliability.items);
    const uncertain = d.indices(queries.len); std.mem.sort(usize, uncertain, UncertainContext{ .predictions = cp }, uncertainLess); var uncertainty: std.ArrayList([]const u8) = .empty; d.append([]const u8, &uncertainty, d.fmt("uncertain {d} test rows", .{settings.top}));
    for (uncertain[0..@min(settings.top, uncertain.len)]) |i| { const prediction = cp[i]; const row = queries[i]; d.append([]const u8, &uncertainty, d.fmt("{s} predicted {s} share {s} runner_up {s} share {s} margin {s} true {s}", .{ row.id, labels[prediction.label], r.fixed(prediction.share), if (prediction.runner) |label| labels[label] else "-", r.fixed(prediction.runner_share), r.fixed(prediction.share - prediction.runner_share), if (row.label) |label| labels[label] else "-" })); } part(&metrics, uncertainty.items);
    var targets: std.ArrayList(f64) = .empty; for (queries) |row| { if (row.target) |target| d.append(f64, &targets, target); } var regression_lines: std.ArrayList([]const u8) = .empty;
    extend(&regression_lines, &.{ d.fmt("test regression {s}", .{notation(regressor.model)}), d.fmt("targets {d} rmse {s} mae {s} r2 {s}", .{ test_errors.len, r.fixed(v.rmse(test_errors).?), r.fixed(v.mae(test_errors)), r.fixed(v.rSquared(test_errors, targets.items)) }) });
    for (labels, 0..) |label, c| { var class_residuals: std.ArrayList(f64) = .empty; for (queries, rp) |row, prediction| { if (row.label != null and row.label.? == c and row.target != null) d.append(f64, &class_residuals, prediction.estimate - row.target.?); } d.append([]const u8, &regression_lines, d.fmt("class {s} targets {d} rmse {s}", .{ label, class_residuals.items.len, r.optional(v.rmse(class_residuals.items)) })); } part(&metrics, regression_lines.items);
    var misclassified: std.ArrayList([]const u8) = .empty; d.append([]const u8, &misclassified, "misclassified test rows"); var misclassified_count: usize = 0;
    for (queries, cp) |row, prediction| { const truth = row.label orelse continue; if (prediction.label == truth) continue; misclassified_count += 1; d.append([]const u8, &misclassified, d.fmt("{s} true {s} predicted {s} share {s}", .{ row.id, labels[truth], labels[prediction.label], r.fixed(prediction.share) })); for (prediction.nearest) |neighbor| d.append([]const u8, &misclassified, d.fmt("  {s} {s} {s}", .{ neighbor.row.id, labels[neighbor.row.label.?], r.fixed(neighbor.distance) })); }
    d.append([]const u8, &misclassified, d.fmt("count {d}", .{misclassified_count})); part(&metrics, misclassified.items);
    var curve: std.ArrayList([]const u8) = .empty; d.append([]const u8, &curve, "n,train_size,correct,accuracy,rmse");
    for (settings.curve) |limit| { var taken: [300]usize = @splat(0); var selected: std.ArrayList(d.Row) = .empty; for (train) |row| { const label = row.label.?; if (taken[label] < limit) { taken[label] += 1; d.append(d.Row, &selected, row); } } const predictions = v.predictRows(classifier.model, selected.items, queries, features, labels.len); const reg_predictions = v.predictRows(regressor.model, selected.items, queries, features, labels.len); const correct = correctCount(predictions, queries); d.append([]const u8, &curve, d.fmt("{d},{d},{d},{s},{s}", .{ limit, selected.items.len, correct, r.fixed(d.real(correct) / d.real(labelled)), r.fixed(v.rmse(targetResiduals(reg_predictions, queries)).?) })); }
    var grid_lines: std.ArrayList([]const u8) = .empty; d.append([]const u8, &grid_lines, "k,metric,weighting,scaling,correct,accuracy,rmse"); for (scores) |result| { const model = result.model; d.append([]const u8, &grid_lines, d.fmt("{d},{s},{s},{s},{d},{s},{s}", .{ model.k, @tagName(model.metric), @tagName(model.weighting), @tagName(model.scaling), result.correct, r.fixed(d.real(result.correct) / d.real(train.len)), r.fixed(result.rmse) })); }
    var prediction_lines: std.ArrayList([]const u8) = .empty; d.append([]const u8, &prediction_lines, "id,label,vote_share,estimate"); for (queries, cp, rp) |row, prediction, estimate| d.append([]const u8, &prediction_lines, d.fmt("{s},{s},{s},{s}", .{ row.id, labels[prediction.label], r.fixed(prediction.share), r.fixed(estimate.estimate) }));
    const prototype_lines = prototypeLines(data, classifier.model, features, class_orders, cp); const names = [_][]const u8{ "cv_grid.csv", "predictions.csv", "metrics.txt", "learning_curve.csv", "prototypes.txt" }; const reports = [_]d.Strings{ grid_lines.items, prediction_lines.items, metrics.items, curve.items, prototype_lines }; for (names, reports) |name, lines| try r.write(init.io, name, lines);
}
