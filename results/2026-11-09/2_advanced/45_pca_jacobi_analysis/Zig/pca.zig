const c = @import("dataset.zig");
const m = @import("matrix.zig");
pub fn means(rows: c.Matrix) c.Vector {
    const out = c.vector(rows[0].len);
    for (0..out.len) |j| {
        for (rows) |row| out[j] += row[j];
        out[j] /= c.f(rows.len);
    }
    return out;
}
pub fn covariance(rows: c.Matrix, mean: []const f64) c.Matrix {
    const out = c.matrix(mean.len, mean.len);
    for (0..mean.len) |j| for (j..mean.len) |k| {
        var sum: f64 = 0;
        for (rows) |row| sum += (row[j] - mean[j]) * (row[k] - mean[k]);
        out[j][k] = sum / c.f(rows.len - 1);
        out[k][j] = out[j][k];
    };
    return out;
}
pub fn correlation(cov: c.Matrix, sd: []const f64) c.Matrix {
    const out = c.matrix(cov.len, cov.len);
    for (0..cov.len) |j| for (0..cov.len) |k| {
        out[j][k] = if (j == k) 1 else cov[j][k] / (sd[j] * sd[k]);
    };
    return out;
}
pub fn standardize(row: c.Sample, mean: []const f64, scale: []const f64) c.Vector {
    const out = c.vector(mean.len);
    for (row.values, 0..) |value, j| out[j] = if (value) |observed| (observed - mean[j]) / scale[j] else 0;
    return out;
}
pub fn scores(row: []const f64, vectors: c.Matrix) c.Vector {
    const out = c.vector(vectors.len);
    for (vectors, out) |values, *value| value.* = m.dot(row, values);
    return out;
}
pub fn residuals(row: []const f64, score: []const f64, vectors: c.Matrix, count: usize) c.Vector {
    const out = c.vector(row.len);
    for (row, 0..) |value, j| {
        var sum: f64 = 0;
        for (0..count) |k| sum += score[k] * vectors[k][j];
        out[j] = value - sum;
    }
    return out;
}
pub fn hotelling(score: []const f64, values: []const f64, count: usize) f64 {
    var out: f64 = 0;
    for (0..count) |k| out += (score[k] * score[k]) / values[k];
    return out;
}
