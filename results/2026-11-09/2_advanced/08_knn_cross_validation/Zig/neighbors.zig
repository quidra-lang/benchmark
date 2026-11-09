const std = @import("std");
const d = @import("dataset.zig");
pub const Neighbor = struct { row: *const d.Row, distance: f64 };
pub const Prediction = struct { label: usize, share: f64, runner: ?usize, runner_share: f64, estimate: f64, nearest: []const Neighbor };
pub fn distance(a: []const f64, b: []const f64, metric: d.Metric) f64 {
    var total: f64 = 0; var dot: f64 = 0; var aa: f64 = 0; var bb: f64 = 0;
    for (a, b) |x, y| { const delta = x - y; switch (metric) { .squared_euclidean => total += delta * delta, .manhattan => total += @abs(delta), .chebyshev => total = @max(total, @abs(delta)), .cosine => { dot += x * y; aa += x * x; bb += y * y; } } }
    if (metric == .cosine) { const na = @sqrt(aa); const nb = @sqrt(bb); return if (na == 0 or nb == 0) 1 else 1 - dot / (na * nb); }
    return total;
}
fn neighborLess(_: void, a: Neighbor, b: Neighbor) bool { return if (a.distance == b.distance) d.textLess(a.row.id, b.row.id) else a.distance < b.distance; }
pub fn order(query: []const f64, references: []const d.Row, vectors: []const []const f64, metric: d.Metric) []const Neighbor { const result = d.alloc(Neighbor, references.len); for (references, vectors, result) |*row, vector, *neighbor| neighbor.* = .{ .row = row, .distance = distance(query, vector, metric) }; std.mem.sort(Neighbor, result, {}, neighborLess); return result; }
const VoteContext = struct { weighting: d.Weighting, counts: *const [300]usize, distances: *const [300]f64, weights: *const [300]f64 };
fn voteLess(c: VoteContext, a: usize, b: usize) bool { if (c.weighting == .uniform) { if (c.counts[a] != c.counts[b]) return c.counts[a] > c.counts[b]; } else if (c.weights[a] != c.weights[b]) return c.weights[a] > c.weights[b]; return if (c.distances[a] == c.distances[b]) a < b else c.distances[a] < c.distances[b]; }
pub fn predict(ordered: []const Neighbor, k: usize, weighting: d.Weighting, classes: usize) Prediction {
    const nearest = ordered[0..@min(k, ordered.len)]; var counts: [300]usize = @splat(0); var distances: [300]f64 = @splat(0); var weights: [300]f64 = @splat(0); var labels: [300]usize = undefined; var label_count: usize = 0; var total_weight: f64 = 0; var total: f64 = 0; var weighted: f64 = 0;
    for (nearest) |neighbor| { const label = neighbor.row.label.?; const weight = 1 / (neighbor.distance + 0.000000001); counts[label] += 1; distances[label] += neighbor.distance; weights[label] += weight; total_weight += weight; total += neighbor.row.target.?; weighted += weight * neighbor.row.target.?; }
    for (counts[0..classes], 0..) |count, label| { if (count > 0) { labels[label_count] = label; label_count += 1; } }
    std.mem.sort(usize, labels[0..label_count], VoteContext{ .weighting = weighting, .counts = &counts, .distances = &distances, .weights = &weights }, voteLess);
    const label = labels[0]; const runner: ?usize = if (label_count > 1) labels[1] else null;
    return .{ .label = label, .share = if (weighting == .uniform) d.real(counts[label]) / d.real(nearest.len) else weights[label] / total_weight, .runner = runner, .runner_share = if (runner) |c| (if (weighting == .uniform) d.real(counts[c]) / d.real(nearest.len) else weights[c] / total_weight) else 0, .estimate = if (weighting == .uniform) total / d.real(nearest.len) else weighted / total_weight, .nearest = nearest };
}
