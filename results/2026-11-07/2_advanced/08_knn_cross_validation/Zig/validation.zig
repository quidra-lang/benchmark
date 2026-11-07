const std = @import("std");
const d = @import("dataset.zig");
const s = @import("scaling.zig");
const n = @import("neighbors.zig");
pub const Model = struct { k: usize, metric: d.Metric, weighting: d.Weighting, scaling: d.Scaling };
fn stratifiedLess(rows: []const d.Row, a: usize, b: usize) bool { return if (rows[a].label == rows[b].label) d.textLess(rows[a].id, rows[b].id) else rows[a].label.? < rows[b].label.?; }
fn naturalLess(_: void, a: usize, b: usize) bool { return a < b; }
pub fn stratified(rows: []const d.Row, count: usize) []const []const usize {
    const ordered = d.indices(rows.len); std.mem.sort(usize, ordered, rows, stratifiedLess); const folds = d.alloc(std.ArrayList(usize), count); @memset(folds, .empty);
    for (ordered, 0..) |index, position| d.append(usize, &folds[position % count], index);
    const result = d.alloc([]const usize, count); for (folds, result) |fold, *indices| { std.mem.sort(usize, fold.items, {}, naturalLess); indices.* = fold.items; } return result;
}
pub fn without(rows: []const d.Row, excluded: []const usize) []const d.Row { var result: std.ArrayList(d.Row) = .empty; for (rows, 0..) |row, i| { if (!d.contains(excluded, i)) d.append(d.Row, &result, row); } return result.items; }
pub fn choose(rows: []const d.Row, indices: []const usize) []const d.Row { const result = d.alloc(d.Row, indices.len); for (indices, result) |i, *row| row.* = rows[i]; return result; }
pub fn neighborOrders(training: []const d.Row, queries: []const d.Row, method: d.Scaling, metric: d.Metric, features: []const usize) []const []const n.Neighbor {
    const scale = s.compute(training, method); const vectors = d.alloc([]const f64, training.len); for (training, vectors) |row, *vector| vector.* = s.transform(scale, row.values, features);
    const orders = d.alloc([]const n.Neighbor, queries.len); for (queries, orders) |row, *ordered| ordered.* = n.order(s.transform(scale, row.values, features), training, vectors, metric); return orders;
}
pub fn predictRows(model: Model, training: []const d.Row, queries: []const d.Row, features: []const usize, classes: usize) []const n.Prediction { const orders = neighborOrders(training, queries, model.scaling, model.metric, features); const predictions = d.alloc(n.Prediction, queries.len); for (orders, predictions) |ordered, *prediction| prediction.* = n.predict(ordered, model.k, model.weighting, classes); return predictions; }
pub fn residuals(predictions: []const n.Prediction, rows: []const d.Row) []const f64 { const errors = d.alloc(f64, rows.len); for (predictions, rows, errors) |prediction, row, *value| value.* = prediction.estimate - row.target.?; return errors; }
pub fn rmse(errors: []const f64) ?f64 { if (errors.len == 0) return null; var total: f64 = 0; for (errors) |value| total += value * value; return @sqrt(total / d.real(errors.len)); }
pub fn mae(errors: []const f64) f64 { var total: f64 = 0; for (errors) |value| total += @abs(value); return total / d.real(errors.len); }
pub fn rSquared(errors: []const f64, targets: []const f64) f64 { var total: f64 = 0; for (targets) |target| total += target; const mean = total / d.real(targets.len); var residual: f64 = 0; var spread: f64 = 0; for (errors) |value| residual += value * value; for (targets) |target| { const delta = target - mean; spread += delta * delta; } return 1 - residual / spread; }
