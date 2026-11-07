const S = @import("signals.zig");
pub fn envelope(samples: []const i64, attack: i64, release: i64) []const i64 { const result = S.alloc(i64, samples.len); var level: i64 = 0; for (samples, result) |x, *y| { const magnitude = @min(S.abs(x), 32767); const coefficient = if (magnitude > level) attack else release; level += S.rdiv((magnitude - level) * coefficient, 32768); y.* = level; } return result; }
pub const Normalized = struct { samples: []const i64, source_peak: i64 };
pub fn normalize(samples: []const i64, target: i64) Normalized { const p = S.peak(samples); const result = S.clone(i64, samples); if (p > 0) { for (result) |*value| value.* = S.rdiv(value.* * target, p); } return .{ .samples = result, .source_peak = p }; }
pub const Gated = struct { samples: []const i64, muted: i64 };
pub fn gate(samples: []const i64, threshold: i64, hold: i64) Gated {
    const result = S.alloc(i64, samples.len); var last_loud: ?usize = null; var muted: i64 = 0;
    for (samples, result, 0..) |x, *y, i| { if (S.abs(x) >= threshold) last_loud = i; const open = if (last_loud) |last| S.int(i - last) <= hold else false; if (open) y.* = x else { y.* = 0; muted += 1; } }
    return .{ .samples = result, .muted = muted };
}
pub const Compressed = struct { samples: []const i64, min_gain: i64, reduced: i64 };
pub fn compress(samples: []const i64, threshold: i64, ratio_num: i64, ratio_den: i64, attack: i64, release: i64) Compressed {
    const levels = envelope(samples, attack, release); const result = S.alloc(i64, samples.len); var gain: i64 = 32768; var minimum: i64 = 32768; var reduced: i64 = 0;
    for (samples, levels, result) |x, level, *y| { const limited = threshold + S.rdiv((level - threshold) * ratio_den, ratio_num); const target = if (level > threshold) S.rdiv(limited * 32768, level) else 32768; gain = if (target < gain) target else gain + S.rdiv((target - gain) * release, 32768); minimum = @min(minimum, gain); if (gain < 32768) reduced += 1; y.* = S.rdiv(x * gain, 32768); }
    return .{ .samples = result, .min_gain = minimum, .reduced = reduced };
}
