const d = @import("dataset.zig");
pub const Result = struct { estimate: ?f64 = null, weights: []f64, leverage: ?f64 = null };
pub fn estimate(data: d.Data, kernel: []const u8, bandwidth: i64, position: i64, local_linear: bool) Result {
    const count_points = data.x.len;
    var result: Result = .{ .weights = d.zero(f64, count_points) };
    const values = d.zero(f64, count_points);
    const distances = d.zero(f64, count_points);
    const h = d.f(bandwidth) / 100;
    const x0 = d.f(position) / 100;
    var count: usize = 0;
    var s0: f64 = 0;
    var s1: f64 = 0;
    var s2: f64 = 0;
    var t0: f64 = 0;
    var t1: f64 = 0;
    for (data.x, 0..) |x, i| {
        if (@abs(x - position) >= @as(u64, @intCast(bandwidth))) continue;
        count += 1;
        const u = (data.real_x[i] - x0) / h;
        const t = 1 - u * u;
        const distance = data.real_x[i] - x0;
        const value = if (d.eq(kernel, "epanechnikov")) 0.75 * t else if (d.eq(kernel, "biweight")) 0.9375 * t * t else 1.09375 * t * t * t;
        values[i] = value;
        distances[i] = distance;
        s0 += value;
        s1 += value * distance;
        s2 += value * distance * distance;
        t0 += value * data.real_y[i];
        t1 += value * distance * data.real_y[i];
    }
    if (count < (if (local_linear) @as(usize, 2) else 1)) return result;
    const kappa: f64 = if (d.eq(kernel, "epanechnikov")) 0.75 else if (d.eq(kernel, "biweight")) 0.9375 else 1.09375;
    if (local_linear) {
        const q = s0 * s2 - s1 * s1;
        result.estimate = (s2 * t0 - s1 * t1) / q;
        result.leverage = kappa * s2 / q;
        for (values, distances, result.weights) |value, distance, *weight| if (value != 0) {
            weight.* = value * (s2 - s1 * distance) / q;
        };
    } else {
        result.estimate = t0 / s0;
        result.leverage = kappa / s0;
        for (values, result.weights) |value, *weight| if (value != 0) {
            weight.* = value / s0;
        };
    }
    return result;
}
