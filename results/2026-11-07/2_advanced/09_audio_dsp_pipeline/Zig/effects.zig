const S = @import("signals.zig");
pub fn gain(samples: []const i64, num: i64, den: i64) S.Result { const result = S.alloc(i64, samples.len); var clipped: i64 = 0; for (samples, result) |x, *y| y.* = S.saturate(&clipped, S.rdiv(x * num, den)); return .{ .samples = result, .clipped = clipped }; }
pub fn mix(tracks: []const *const S.Signal, weights: []const i64, den: i64) S.Result {
    var count: usize = 0; for (tracks) |track| count = @max(count, track.samples.len); const result = S.alloc(i64, count); var clipped: i64 = 0;
    for (result, 0..) |*y, i| { var total: i64 = 0; for (tracks, weights) |track, weight| { if (i < track.samples.len) total += weight * track.samples[i]; } y.* = S.saturate(&clipped, S.rdiv(total, den)); }
    return .{ .samples = result, .clipped = clipped };
}
pub fn delay(samples: []const i64, count: usize) []const i64 { const result = S.alloc(i64, samples.len + count); @memset(result[0..count], 0); @memcpy(result[count..], samples); return result; }
pub fn echo(samples: []const i64, lag: usize, num: i64, den: i64, tail: usize) S.Result {
    const result = S.alloc(i64, samples.len + tail); @memcpy(result[0..samples.len], samples); @memset(result[samples.len..], 0); var clipped: i64 = 0; var i = lag;
    while (i < result.len) : (i += 1) result[i] = S.saturate(&clipped, result[i] + S.rdiv(num * result[i - lag], den));
    return .{ .samples = result, .clipped = clipped };
}
pub fn resampledLength(count: usize, old_rate: i64, new_rate: i64) usize { return S.index(@divFloor(S.int(count - 1) * new_rate, old_rate) + 1); }
pub fn resample(samples: []const i64, old_rate: i64, new_rate: i64) []const i64 {
    const result = S.alloc(i64, resampledLength(samples.len, old_rate, new_rate));
    for (result, 0..) |*value, j| { const p = S.index(@divFloor(S.int(j) * old_rate, new_rate)); const q = @mod(S.int(j) * old_rate, new_rate); value.* = samples[p]; if (q > 0) value.* += S.rdiv((samples[p + 1] - value.*) * q, new_rate); }
    return result;
}
pub fn fade(samples: []const i64, fade_in: usize, fade_out: usize) []const i64 {
    const result = S.clone(i64, samples); for (0..fade_in) |i| result[i] = S.rdiv(result[i] * S.int(i), S.int(fade_in));
    for (samples.len - fade_out..samples.len) |i| result[i] = S.rdiv(result[i] * S.int(samples.len - 1 - i), S.int(fade_out)); return result;
}
