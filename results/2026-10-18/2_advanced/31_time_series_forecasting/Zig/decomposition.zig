const std = @import("std");
const io = @import("series_io.zig");
pub fn total(values: []const f64) f64 {
    var result: f64 = 0;
    for (values) |value| result += value;
    return result;
}
pub fn mean(values: []const f64) f64 {
    return total(values) / io.f(values.len);
}
pub fn sampleVariance(values: []const f64) f64 {
    const average = mean(values);
    var squares: f64 = 0;
    for (values) |value| squares += (value - average) * (value - average);
    return squares / io.f(values.len - 1);
}
pub fn rmse(values: []const f64) f64 {
    var squares: f64 = 0;
    for (values) |value| squares += value * value;
    return @sqrt(squares / io.f(values.len));
}
pub const Decomposition = struct { trend: []f64, additive: []f64, multiplicative: []f64, residual_add: []f64,
     residual_mult: []f64 };
pub fn decompose(values: []const f64, season: usize) Decomposition {
    const half = season / 2;
    const result: Decomposition = .{ .trend = io.alloc(f64, values.len), .additive = io.zeros(season),
         .multiplicative = io.zeros(season), .residual_add = io.alloc(f64, values.len), .residual_mult = io.alloc(f64,
         values.len) };
    @memset(result.trend, std.math.nan(f64));
    @memset(result.residual_add, std.math.nan(f64));
    @memset(result.residual_mult, std.math.nan(f64));
    for (half..values.len - half) |t| {
        var value = 0.5 * values[t - half];
        for (values[t - half + 1 .. t + half]) |observed| value += observed;
        value += 0.5 * values[t + half];
        result.trend[t] = value / io.f(season);
    }
    for (0..season) |j| {
        var additive: f64 = 0;
        var multiplicative: f64 = 0;
        var count: usize = 0;
        for (half..values.len - half) |t| if (t % season == j) {
            additive += values[t] - result.trend[t];
            multiplicative += values[t] / result.trend[t];
            count += 1;
        };
        result.additive[j] = additive / io.f(count);
        result.multiplicative[j] = multiplicative / io.f(count);
    }
    const average_add = mean(result.additive);
    const average_mult = mean(result.multiplicative);
    for (result.additive, result.multiplicative) |*additive, *multiplicative| {
        additive.* -= average_add;
        multiplicative.* /= average_mult;
    }
    for (half..values.len - half) |t| {
        result.residual_add[t] = values[t] - result.trend[t] - result.additive[t % season];
        result.residual_mult[t] = values[t] / (result.trend[t] * result.multiplicative[t % season]);
    }
    return result;
}
pub fn regression(values: []const f64) [2]f64 {
    const center = (io.f(values.len) + 1) / 2;
    const average = mean(values);
    var numerator: f64 = 0;
    var denominator: f64 = 0;
    for (values, 1..) |value, t| {
        const delta = io.f(t) - center;
        numerator += delta * (value - average);
        denominator += delta * delta;
    }
    const slope = numerator / denominator;
    return .{ average - slope * center, slope };
}
