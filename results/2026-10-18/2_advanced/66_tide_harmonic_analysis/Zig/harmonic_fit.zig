const std = @import("std");
const d = @import("records.zig");
const pi: f64 = 3.141592653589793;
pub const Model = struct { count: usize = 0, size: usize = 0, speeds: [30]f64 = [_]f64{0} ** 30,
     coefficients: [61]f64 = [_]f64{0} ** 61, amplitudes: [30]f64 = [_]f64{0} ** 30, phases: [30]f64 = [_]f64{0} ** 30,
     inverse: [61][61]f64 = std.mem.zeroes([61][61]f64) };
pub fn angle(speed: f64, time: f64) f64 {
    const degrees = speed * time;
    const reduced = degrees - 360 * @floor(degrees / 360);
    return reduced * pi / 180;
}
pub fn regressors(speeds: []const f64, time: f64) [61]f64 {
    var out: [61]f64 = [_]f64{0} ** 61;
    out[0] = 1;
    for (speeds, 0..) |speed, k| {
        const theta = angle(speed, time);
        out[2 * k + 1] = @cos(theta);
        out[2 * k + 2] = @sin(theta);
    }
    return out;
}
pub fn fit(samples: []const d.Sample, speeds: []const f64) *Model {
    const size = 2 * speeds.len + 1;
    var augmented: [61][123]f64 = std.mem.zeroes([61][123]f64);
    for (samples) |sample| {
        const x = regressors(speeds, d.f(sample.time));
        for (0..size) |i| {
            augmented[i][size] += x[i] * sample.value;
            for (0..size) |j| augmented[i][j] += x[i] * x[j];
        }
    }
    for (0..size) |i| augmented[i][size + 1 + i] = 1;
    for (0..size) |column| {
        var pivot = column;
        for (column + 1..size) |i| {
            if (@abs(augmented[i][column]) > @abs(augmented[pivot][column])) pivot = i;
        }
        if (pivot != column) std.mem.swap([123]f64, &augmented[pivot], &augmented[column]);
        for (column + 1..size) |i| {
            const factor = augmented[i][column] / augmented[column][column];
            for (column..2 * size + 1) |c| augmented[i][c] = augmented[i][c] - factor * augmented[column][c];
        }
    }
    const out = d.create(Model, .{ .count = speeds.len, .size = size });
    @memcpy(out.speeds[0..speeds.len], speeds);
    for (size..2 * size + 1) |c| {
        var solution: [61]f64 = undefined;
        var i = size;
        while (i > 0) {
            i -= 1;
            var sum = augmented[i][c];
            for (i + 1..size) |j| sum = sum - augmented[i][j] * solution[j];
            solution[i] = sum / augmented[i][i];
        }
        if (c == size) @memcpy(out.coefficients[0..size], solution[0..size]) else {
            for (0..size) |row| out.inverse[row][c - size - 1] = solution[row];
        }
    }
    for (0..speeds.len) |k| {
        const a = out.coefficients[2 * k + 1];
        const b = out.coefficients[2 * k + 2];
        out.amplitudes[k] = @sqrt(a * a + b * b);
        var phase = std.math.atan2(b, a) * 180 / pi;
        if (phase < 0) phase += 360;
        out.phases[k] = phase;
    }
    return out;
}
