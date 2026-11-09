const std = @import("std");
const io = @import("series_io.zig");
pub fn scaleDelta(training: []const f64, season: usize) f64 {
    var total: f64 = 0;
    for (season..training.len) |t| total += @abs(training[t] - training[t - season]);
    return total / io.f(training.len - season);
}
pub fn winkler(actual: f64, low: f64, high: f64, penalty: f64) f64 {
    return if (actual < low) high - low + penalty * (low - actual) else if (actual > high) high - low + penalty * (actual - high) else high - low;
}
pub const Accuracy = struct { me: f64 = 0, mae: f64 = 0, rmse: f64 = 0, mape: f64 = 0, smape: f64 = 0,
     mase: f64 = 0, fva: f64 = 0, cv_rmse: f64 = 0, cover80: usize = 0, cover95: usize = 0, winkler80: f64 = 0,
     winkler95: f64 = 0, rank: usize = 0 };
pub fn evaluate(actual: []const f64, forecast: []const f64, sigma: []const f64, z80: f64, z95: f64, delta: f64) Accuracy {
    var result: Accuracy = .{};
    var squares: f64 = 0;
    for (actual, forecast, sigma[0..actual.len]) |a, f, uncertainty| {
        const error_ = a - f;
        result.me += error_;
        result.mae += @abs(error_);
        squares += error_ * error_;
        result.mape += @abs(error_) / a;
        result.smape += 2 * @abs(error_) / (@abs(a) + @abs(f));
        const lo80 = f - z80 * uncertainty;
        const hi80 = f + z80 * uncertainty;
        const lo95 = f - z95 * uncertainty;
        const hi95 = f + z95 * uncertainty;
        if (lo80 <= a and a <= hi80) result.cover80 += 1;
        if (lo95 <= a and a <= hi95) result.cover95 += 1;
        result.winkler80 += winkler(a, lo80, hi80, 10);
        result.winkler95 += winkler(a, lo95, hi95, 40);
    }
    const count = io.f(actual.len);
    result.me /= count;
    result.mae /= count;
    result.rmse = @sqrt(squares / count);
    result.mape = 100 * result.mape / count;
    result.smape = 100 * result.smape / count;
    result.mase = result.mae / delta;
    result.winkler80 /= count;
    result.winkler95 /= count;
    return result;
}
fn less(measures: []const Accuracy, a: usize, b: usize) bool {
    return if (measures[a].rmse != measures[b].rmse) measures[a].rmse < measures[b].rmse else a < b;
}
pub fn rank(measures: []Accuracy) []usize {
    const order = io.alloc(usize, measures.len);
    for (order, 0..) |*value, index| value.* = index;
    std.mem.sort(usize, order, @as([]const Accuracy, measures), less);
    for (order, 1..) |id, number| measures[id].rank = number;
    return order;
}
