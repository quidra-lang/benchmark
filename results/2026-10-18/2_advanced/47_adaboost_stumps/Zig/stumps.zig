const std = @import("std");
const c = @import("dataset.zig");
pub const Stump = struct {
    feature: usize,
    thresholds: []const f64,
    values: []const f64,
    pub fn output(self: Stump, row: []const f64) f64 {
        var bin: usize = 0;
        for (self.thresholds) |threshold| bin += @intFromBool(row[self.feature] > threshold);
        return self.values[bin];
    }
};
pub const Feature = struct { order: []const usize, ends: []const usize, thresholds: []const f64, cuts: []const f64 };
pub const Search = struct { features: []const Feature };
const SortContext = struct { rows: []const c.Row, feature: usize };
fn rowLess(context: SortContext, a: usize, b: usize) bool {
    const x = context.rows[a].values[context.feature];
    const y = context.rows[b].values[context.feature];
    return if (x != y) x < y else a < b;
}
pub fn prepare(rows: []const c.Row, bins: usize) Search {
    const features = c.alloc(Feature, rows[0].values.len);
    for (features, 0..) |*feature, j| {
        const order = c.alloc(usize, rows.len);
        for (order, 0..) |*value, i| value.* = i;
        std.mem.sort(usize, order, SortContext{ .rows = rows, .feature = j }, rowLess);
        var thresholds: std.ArrayList(f64) = .empty;
        var ends: std.ArrayList(usize) = .empty;
        c.append(f64, &thresholds, rows[order[0]].values[j] - 1);
        c.append(usize, &ends, 0);
        for (1..rows.len) |i| {
            const left = rows[order[i - 1]].values[j];
            const right = rows[order[i]].values[j];
            if (left != right) {
                c.append(f64, &thresholds, (left + right) / 2);
                c.append(usize, &ends, i);
            }
        }
        const cuts = c.vector(if (bins == 0) 0 else bins - 1);
        if (bins > 0) for (1..bins) |b| {
            const r = b * rows.len / bins;
            cuts[b - 1] = (rows[order[r - 1]].values[j] + rows[order[r]].values[j]) / 2;
        };
        feature.* = .{ .order = order, .ends = ends.items, .thresholds = thresholds.items, .cuts = cuts };
    }
    return .{ .features = features };
}
pub const Result = struct { stump: Stump, error_: f64, polarity: i64 = 0 };
const Candidate = struct { feature: usize, threshold: f64, left: f64, right: f64, error_: f64, polarity: i64 = 0 };
fn choose(candidates: []const Candidate) Result {
    var minimum = candidates[0].error_;
    for (candidates[1..]) |candidate| minimum = @min(minimum, candidate.error_);
    for (candidates) |candidate| if (candidate.error_ <= minimum + 0.000000001) return .{ .stump = .{ .feature = candidate.feature,
         .thresholds = c.dupe(f64, &.{candidate.threshold}), .values = c.dupe(f64, &.{ candidate.left,
         candidate.right }) }, .error_ = candidate.error_, .polarity = candidate.polarity };
    unreachable;
}
pub fn discrete(rows: []const c.Row, search: Search, weights: []const f64) Result {
    var positive: f64 = 0;
    var negative: f64 = 0;
    for (rows, weights) |row, weight| if (row.label == 1) {
        positive += weight;
    } else {
        negative += weight;
    };
    var candidates: [8000]Candidate = undefined;
    var count: usize = 0;
    for (search.features, 0..) |feature, j| {
        var position: usize = 0;
        var lp: f64 = 0;
        var ln: f64 = 0;
        for (feature.thresholds, feature.ends) |threshold, end| {
            while (position < end) {
                const i = feature.order[position];
                position += 1;
                if (rows[i].label == 1) lp += weights[i] else ln += weights[i];
            }
            for ([_]i64{ 1, -1 }) |polarity| {
                candidates[count] = .{ .feature = j, .threshold = threshold, .left = -c.f(polarity),
                     .right = c.f(polarity), .error_ = if (polarity == 1) lp + (negative - ln) else ln + (positive - lp),
                     .polarity = polarity };
                count += 1;
            }
        }
    }
    return choose(candidates[0..count]);
}
pub fn regression(rows: []const c.Row, search: Search, targets: []const f64, weights: []const f64) Result {
    var w: f64 = 0;
    var s: f64 = 0;
    var q: f64 = 0;
    for (weights, targets) |weight, target| {
        w += weight;
        s += weight * target;
        q += weight * target * target;
    }
    var candidates: [8000]Candidate = undefined;
    var count: usize = 0;
    for (search.features, 0..) |feature, j| {
        var position: usize = 0;
        var wl: f64 = 0;
        var sl: f64 = 0;
        for (feature.thresholds, feature.ends, 0..) |threshold, end, k| {
            while (position < end) {
                const i = feature.order[position];
                position += 1;
                wl += weights[i];
                sl += weights[i] * targets[i];
            }
            const wr = w - wl;
            const sr = s - sl;
            const al = if (k == 0) @as(f64, 0) else sl / wl;
            const ar = sr / wr;
            const g = if (k == 0) sr * sr / wr else sl * sl / wl + sr * sr / wr;
            candidates[count] = .{ .feature = j, .threshold = threshold, .left = al, .right = ar, .error_ = q - g };
            count += 1;
        }
    }
    _ = rows;
    return choose(candidates[0..count]);
}
pub fn multiclass(rows: []const c.Row, search: Search, weights: []const f64, classes: usize) Result {
    var w: f64 = 0;
    var totals = [_]f64{0} ** 6;
    for (rows, weights) |row, weight| {
        w += weight;
        totals[c.u(row.label - 1)] += weight;
    }
    var candidates: [8000]Candidate = undefined;
    var count: usize = 0;
    for (search.features, 0..) |feature, j| {
        var position: usize = 0;
        var left = [_]f64{0} ** 6;
        for (feature.thresholds, feature.ends) |threshold, end| {
            while (position < end) {
                const i = feature.order[position];
                position += 1;
                left[c.u(rows[i].label - 1)] += weights[i];
            }
            var right: [6]f64 = undefined;
            for (0..classes) |k| right[k] = totals[k] - left[k];
            var a: usize = 0;
            var b: usize = 0;
            for (1..classes) |k| {
                if (left[k] > left[a]) a = k;
                if (right[k] > right[b]) b = k;
            }
            candidates[count] = .{ .feature = j, .threshold = threshold, .left = c.f(a + 1), .right = c.f(b + 1),
                 .error_ = w - (left[a] + right[b]) };
            count += 1;
        }
    }
    return choose(candidates[0..count]);
}
pub const RealResult = struct { stump: Stump, z: f64 };
pub fn realStump(rows: []const c.Row, search: Search, weights: []const f64, bins: usize, smoothing: f64) RealResult {
    var candidates: [10]RealResult = undefined;
    for (search.features, 0..) |feature, j| {
        var positive = [_]f64{0} ** 10;
        var negative = [_]f64{0} ** 10;
        for (rows, weights) |row, weight| {
            var bin: usize = 0;
            for (feature.cuts) |cut| bin += @intFromBool(row.values[j] > cut);
            if (row.label == 1) positive[bin] += weight else negative[bin] += weight;
        }
        var sum: f64 = 0;
        const values = c.vector(bins);
        for (0..bins) |b| {
            sum += @sqrt(positive[b] * negative[b]);
            values[b] = 0.5 * @log((positive[b] + smoothing) / (negative[b] + smoothing));
        }
        candidates[j] = .{ .stump = .{ .feature = j, .thresholds = feature.cuts, .values = values }, .z = 2 * sum };
    }
    var minimum = candidates[0].z;
    for (candidates[1..search.features.len]) |candidate| minimum = @min(minimum, candidate.z);
    for (candidates[0..search.features.len]) |candidate| if (candidate.z <= minimum + 0.000000001) return candidate;
    unreachable;
}
