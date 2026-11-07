const S = @import("signals.zig");
pub fn energy(samples: []const i64) i64 { var result: i64 = 0; for (samples) |x| result += x * x; return result; }
pub fn isqrt(n: i64) i64 { var low: i64 = 0; var high = n + 1; while (low + 1 < high) { const middle = @divFloor(low + high, 2); if (middle <= @divFloor(n, middle)) low = middle else high = middle; } return low; }
pub fn rms(samples: []const i64) i64 { return isqrt(@divFloor(energy(samples), S.int(samples.len))); }
pub fn zeroCrossings(samples: []const i64) i64 { var count: i64 = 0; for (1..samples.len) |i| { if ((samples[i - 1] < 0) != (samples[i] < 0)) count += 1; } return count; }
pub fn countClipped(samples: []const i64) i64 { var count: i64 = 0; for (samples) |x| { if (x == -32768 or x == 32767) count += 1; } return count; }
pub fn crestFraction(samples: []const i64) []const u8 { const denominator = energy(samples); if (denominator == 0) return "none"; const p = S.peak(samples); const numerator = p * p * S.int(samples.len); var a = numerator; var b = denominator; while (b != 0) { const next = @mod(a, b); a = b; b = next; } return S.fmt("{d}/{d}", .{ @divExact(numerator, a), @divExact(denominator, a) }); }
pub fn autocorrelation(samples: []const i64, lag: usize) i64 { var total: i64 = 0; for (0..samples.len - lag) |n| total += samples[n] * samples[n + lag]; return total; }
pub fn pitchLag(samples: []const i64, low: usize, high: usize) ?usize { var best_lag = low; var best_value = autocorrelation(samples, low); for (low + 1..high + 1) |lag| { const value = autocorrelation(samples, lag); if (value > best_value) { best_lag = lag; best_value = value; } } return if (best_value > 0) best_lag else null; }
