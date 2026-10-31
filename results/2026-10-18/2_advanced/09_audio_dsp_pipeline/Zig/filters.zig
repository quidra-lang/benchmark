const S = @import("signals.zig");
pub fn fir(samples: []const i64, divisor: i64, taps: []const i64) S.Result {
    const result = S.alloc(i64, samples.len); var clipped: i64 = 0;
    for (result, 0..) |*value, n| { var total: i64 = 0; for (0..@min(taps.len, n + 1)) |k| total += taps[k] * samples[n - k]; value.* = S.saturate(&clipped, @divFloor(total, divisor)); }
    return .{ .samples = result, .clipped = clipped };
}
pub fn biquad(samples: []const i64, coefficients: []const i64) S.Result {
    var signal = samples; var clipped: i64 = 0; var first: usize = 0;
    while (first < coefficients.len) : (first += 5) { const b = coefficients[first..first + 5]; const result = S.alloc(i64, samples.len); var u1: i64 = 0; var u2: i64 = 0; var v1: i64 = 0; var v2: i64 = 0;
        for (signal, result) |u, *value| { const v = S.saturate(&clipped, @divFloor(b[0] * u + b[1] * u1 + b[2] * u2 - b[3] * v1 - b[4] * v2, 16384)); value.* = v; u2 = u1; u1 = u; v2 = v1; v1 = v; }
        signal = result;
    }
    return .{ .samples = signal, .clipped = clipped };
}
pub fn movingAverage(samples: []const i64, width: usize) []const i64 { const result = S.alloc(i64, samples.len); var total: i64 = 0; for (samples, result, 0..) |x, *y, n| { total += x; if (n >= width) total -= samples[n - width]; y.* = S.rdiv(total, S.int(width)); } return result; }
pub fn dcBlock(samples: []const i64, num: i64, den: i64) S.Result {
    const result = S.alloc(i64, samples.len); var clipped: i64 = 0; var previous_input: i64 = 0; var previous_output: i64 = 0;
    for (samples, result) |x, *y| { previous_output = S.saturate(&clipped, x - previous_input + S.rdiv(num * previous_output, den)); previous_input = x; y.* = previous_output; }
    return .{ .samples = result, .clipped = clipped };
}
