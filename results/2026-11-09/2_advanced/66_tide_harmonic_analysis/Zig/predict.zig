const std = @import("std");
const d = @import("records.zig");
const harmonic = @import("harmonic_fit.zig");
pub fn prediction(model: *const harmonic.Model, time: f64) f64 {
    var out = model.coefficients[0];
    for (0..model.count) |k| {
        const theta = harmonic.angle(model.speeds[k], time);
        out += model.coefficients[2 * k + 1] * @cos(theta) + model.coefficients[2 * k + 2] * @sin(theta);
    }
    return out;
}
pub const Extremum = struct { high: bool, mu: f64, height: f64, minute: i64 = 0, label: usize = 0 };
pub fn extrema(model: *const harmonic.Model, start: i64, length: usize, grid: usize) std.ArrayList(Extremum) {
    const count = length * 60 / grid;
    const values = d.alloc(f64, count + 1);
    for (values, 0..) |*value, j| value.* = prediction(model, d.f(60 * start + d.n(j * grid)) / 60);
    var out: std.ArrayList(Extremum) = .empty;
    for (1..count) |j| {
        const high = values[j - 1] < values[j] and values[j] > values[j + 1];
        const low = values[j - 1] > values[j] and values[j] < values[j + 1];
        if (!high and !low) continue;
        const delta = (values[j - 1] - values[j + 1]) / (2 * (values[j - 1] - 2 * values[j] + values[j + 1]));
        const mu = d.f(60 * start + d.n(j * grid)) + delta * d.f(grid);
        const height = values[j] - (values[j - 1] - values[j + 1]) * delta / 4;
        d.append(Extremum, &out, .{ .high = high, .mu = mu, .height = height });
    }
    return out;
}
