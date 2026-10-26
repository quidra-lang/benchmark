const D = @import("transactions.zig");
const K = @import("kmeans.zig");
pub fn distanceTable(points: K.Points) []f64 {
    const count = points.values.len;
    const result = D.alloc(f64, count * count);
    @memset(result, 0);
    for (0..count) |i| {
        for (i + 1..count) |j| {
            const value = @sqrt(K.squaredDistance(points.values[i], points.values[j], points.dimensions));
            result[i * count + j] = value;
            result[j * count + i] = value;
        }
    }
    return result;
}
pub fn silhouettes(table: []const f64, labels: []const usize, sizes: []const usize, result: []f64) void {
    for (labels, 0..) |own, i| {
        if (sizes[own] == 1) { result[i] = 0; continue; }
        var totals = [_]f64{0} ** 10;
        for (labels, 0..) |label, j| { if (i != j) totals[label] += table[i * labels.len + j]; }
        const inner = totals[own] / D.real(sizes[own] - 1);
        var outer: ?f64 = null;
        for (sizes, 0..) |size, j| {
            if (j == own) continue;
            const value = totals[j] / D.real(size);
            if (outer == null or value < outer.?) outer = value;
        }
        const largest = @max(inner, outer.?);
        result[i] = if (largest == 0) 0 else (outer.? - inner) / largest;
    }
}
pub fn calinskiHarabasz(points: K.Points, centers: []const K.Point, sizes: []const usize, within: f64) f64 {
    const overall = K.meanPoint(points);
    var between: f64 = 0;
    for (centers, sizes) |center, size| between += D.real(size) * K.squaredDistance(center, overall, points.dimensions);
    return (between / D.real(centers.len - 1)) / (within / D.real(points.values.len - centers.len));
}
pub fn daviesBouldin(points: K.Points, labels: []const usize, centers: []const K.Point, sizes: []const usize) f64 {
    var spreads = [_]f64{0} ** 10;
    for (points.values, labels) |point, label| spreads[label] += @sqrt(K.squaredDistance(point, centers[label], points.dimensions));
    for (sizes, 0..) |size, j| spreads[j] /= D.real(size);
    var total: f64 = 0;
    for (centers, 0..) |first, a| {
        var worst: f64 = 0;
        for (centers, 0..) |second, e| {
            if (a == e) continue;
            const value = (spreads[a] + spreads[e]) / @sqrt(K.squaredDistance(first, second, points.dimensions));
            worst = @max(worst, value);
        }
        total += worst;
    }
    return total / D.real(centers.len);
}
pub fn elbow(k: usize, first_k: usize, last_k: usize, within: f64, first: f64, last: f64) f64 {
    const x = D.real(k - first_k) / D.real(last_k - first_k);
    const y = (within - last) / (first - last);
    return ((1 - x) - y) / @sqrt(@as(f64, 2));
}
pub fn hartigan(within: f64, next: f64, count: usize, k: usize) f64 { return (within / next - 1) * D.real(count - k - 1); }
fn pairs(count: i64) i64 { return @divTrunc(count * (count - 1), 2); }
pub fn adjustedRand(first: []const usize, second: []const usize) f64 {
    var sx: i64 = 0;
    var sy: i64 = 0;
    var shared: i64 = 0;
    const z = pairs(D.n(first.len));
    for (0..first.len) |i| {
        var seen_x = false;
        var seen_y = false;
        var seen_pair = false;
        for (0..i) |j| {
            if (first[j] == first[i]) seen_x = true;
            if (second[j] == second[i]) seen_y = true;
            if (first[j] == first[i] and second[j] == second[i]) seen_pair = true;
        }
        var nx: i64 = 0;
        var ny: i64 = 0;
        var both: i64 = 0;
        for (i..first.len) |j| {
            if (first[j] == first[i]) nx += 1;
            if (second[j] == second[i]) ny += 1;
            if (first[j] == first[i] and second[j] == second[i]) both += 1;
        }
        if (!seen_x) sx += pairs(nx);
        if (!seen_y) sy += pairs(ny);
        if (!seen_pair) shared += pairs(both);
    }
    const numerator = 2 * (z * shared - sx * sy);
    const denominator = z * (sx + sy) - 2 * sx * sy;
    return if (denominator == 0) 1 else D.real(numerator) / D.real(denominator);
}
