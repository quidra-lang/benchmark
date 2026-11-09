const io = @import("series_io.zig");
const d = @import("decomposition.zig");
pub fn offset(kind: usize, season: usize) usize {
    return if (kind == 0) 0 else if (kind == 1) 1 else if (kind == 2) season else season + 1;
}
pub fn difference(values: []const f64, kind: usize, season: usize) []f64 {
    const first = offset(kind, season);
    const result = io.alloc(f64, values.len - first);
    for (result, first..) |*value, t| value.* = if (kind == 0) values[t] else if (kind == 1) values[t] - values[t - 1] else if (kind == 2) values[t] - values[t - season] else (values[t] - values[t - 1]) - (values[t - season] - values[t - season - 1]);
    return result;
}
pub const Correlation = struct { mean: f64 = 0, variance: f64 = 0, acf: []f64 = &.{} };
pub fn autocorrelation(values: []const f64, lag: usize) Correlation {
    const average = d.mean(values);
    const deltas = io.alloc(f64, values.len);
    var squares: f64 = 0;
    for (values, deltas) |value, *delta| {
        delta.* = value - average;
        squares += delta.* * delta.*;
    }
    const result: Correlation = .{ .mean = average, .variance = squares / io.f(values.len), .acf = io.alloc(f64, lag + 1) };
    result.acf[0] = 1;
    for (1..lag + 1) |k| {
        var value: f64 = 0;
        for (0..values.len - k) |i| value += deltas[i] * deltas[i + k];
        result.acf[k] = value / io.f(values.len) / result.variance;
    }
    return result;
}
pub const Levinson = struct { coefficients: [][]f64 = &.{}, partial: []f64 = &.{}, variance: []f64 = &.{} };
pub fn durbin(acf: []const f64, lag: usize) Levinson {
    const result: Levinson = .{ .coefficients = io.alloc([]f64, lag + 1), .partial = io.zeros(lag + 1),
         .variance = io.zeros(lag + 1) };
    for (result.coefficients) |*row| row.* = io.zeros(lag + 1);
    result.variance[0] = 1;
    for (1..lag + 1) |k| {
        var value: f64 = 0;
        for (1..k) |j| value += result.coefficients[k - 1][j] * acf[k - j];
        const theta = (acf[k] - value) / result.variance[k - 1];
        result.partial[k] = theta;
        for (1..k) |j| result.coefficients[k][j] = result.coefficients[k - 1][j] - theta * result.coefficients[k - 1][k - j];
        result.coefficients[k][k] = theta;
        result.variance[k] = result.variance[k - 1] * (1 - theta * theta);
    }
    return result;
}
pub fn residuals(values: []const f64, average: f64, coefficients: []const f64) []f64 {
    const result = io.alloc(f64, values.len - coefficients.len);
    for (result, coefficients.len..) |*error_, i| {
        var value: f64 = 0;
        for (coefficients, 1..) |coefficient, j| value += coefficient * (values[i - j] - average);
        error_.* = values[i] - average - value;
    }
    return result;
}
pub fn forecast(values: []const f64, differenced: []const f64, kind: usize, season: usize, origin: usize,
     steps: usize, average: f64, coefficients: []const f64) []f64 {
    const first = origin - offset(kind, season);
    const working = io.alloc(f64, first + steps);
    @memcpy(working[0..first], differenced[0..first]);
    const predictions = io.alloc(f64, steps);
    for (predictions, 0..) |*prediction, k| {
        var value: f64 = 0;
        for (coefficients, 1..) |coefficient, j| value += coefficient * (working[first + k - j] - average);
        working[first + k] = average + value;
        prediction.* = working[first + k];
    }
    const levels = io.alloc(f64, origin + steps);
    @memcpy(levels[0..origin], values[0..origin]);
    const result = io.alloc(f64, steps);
    for (predictions, result, 0..) |prediction, *value, k| {
        const end = origin + k;
        value.* = if (kind == 0) prediction else if (kind == 1) prediction + levels[end - 1] else if (kind == 2) prediction + levels[end - season] else prediction + levels[end - 1] + levels[end - season] - levels[end - season - 1];
        levels[end] = value.*;
    }
    return result;
}
pub fn ljungBox(values: []const f64, lag: usize) [2]f64 {
    const acf = autocorrelation(values, lag).acf;
    var value: f64 = 0;
    for (1..lag + 1) |k| value += acf[k] * acf[k] / io.f(values.len - k);
    const q = io.f(values.len) * io.f(values.len + 2) * value;
    const x = q / 2;
    var term: f64 = 1;
    var sum: f64 = 1;
    for (1..lag / 2) |i| {
        term = term * x / io.f(i);
        sum += term;
    }
    return .{ q, @exp(-x) * sum };
}
