const d = @import("dataset.zig");
pub const types = [_][]const u8{ "euclidean", "manhattan", "correlation" };
pub fn sum(values: []const f64) f64 {
    var total: f64 = 0;
    for (values) |value| total += value;
    return total;
}
pub fn squaredDistance(first: []const f64, second: []const f64) f64 {
    var total: f64 = 0;
    for (first, second) |a, b| total += (a - b) * (a - b);
    return total;
}
pub const Statistics = struct { means: []f64, deviations: []f64 };
pub fn featureStatistics(rows: d.Matrix) Statistics {
    const means = d.alloc(f64, rows[0].len);
    const deviations = d.alloc(f64, means.len);
    for (0..means.len) |feature| {
        var total: f64 = 0;
        for (rows) |row| total += row[feature];
        const mean = total / d.f(rows.len);
        var squares: f64 = 0;
        for (rows) |row| squares += (row[feature] - mean) * (row[feature] - mean);
        means[feature] = mean;
        deviations[feature] = @sqrt(squares / d.f(rows.len - 1));
    }
    return .{ .means = means, .deviations = deviations };
}
pub fn standardize(rows: d.Matrix, statistics: Statistics) d.Matrix {
    const result = d.matrix(rows.len, rows[0].len);
    for (rows, result) |source, target| {
        for (source, target, statistics.means, statistics.deviations) |value, *entry, mean, deviation| entry.* = (value - mean) / deviation;
    }
    return result;
}
pub fn distance(first: []const f64, second: []const f64, kind: []const u8) f64 {
    if (d.eq(kind, "euclidean")) return @sqrt(squaredDistance(first, second));
    if (d.eq(kind, "manhattan")) {
        var total: f64 = 0;
        for (first, second) |a, b| total += @abs(a - b);
        return total;
    }
    const mean_first = sum(first) / d.f(first.len);
    const mean_second = sum(second) / d.f(second.len);
    var cross: f64 = 0;
    var spread_first: f64 = 0;
    var spread_second: f64 = 0;
    for (first, second) |a, b| {
        const centered_first = a - mean_first;
        const centered_second = b - mean_second;
        cross += centered_first * centered_second;
        spread_first += centered_first * centered_first;
        spread_second += centered_second * centered_second;
    }
    return 1 - cross / @sqrt(spread_first * spread_second);
}
pub fn distanceMatrix(vectors: d.Matrix, kind: []const u8) d.Matrix {
    const result = d.matrix(vectors.len, vectors.len);
    for (0..vectors.len) |i| {
        for (i + 1..vectors.len) |j| {
            const value = distance(vectors[i], vectors[j], kind);
            result[i][j] = value;
            result[j][i] = value;
        }
    }
    return result;
}
