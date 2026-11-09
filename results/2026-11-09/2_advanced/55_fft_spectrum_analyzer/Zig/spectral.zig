const std = @import("std");
const c = @import("signal_io.zig");
const fft = @import("fft.zig");
const windows = @import("windows.zig");
pub fn localMaximum(values: []const f64, k: usize) bool {
    return k > 0 and k + 1 < values.len and values[k] > values[k - 1] and values[k] > values[k + 1];
}
pub const Interpolation = struct { position: f64, value: f64 };
pub fn interpolate(values: []const f64, k: usize, logarithmic: bool) Interpolation {
    if (!localMaximum(values, k)) return .{ .position = c.f(k), .value = values[k] };
    const a = if (logarithmic) @log(values[k - 1]) else values[k - 1];
    const b = if (logarithmic) @log(values[k]) else values[k];
    const g = if (logarithmic) @log(values[k + 1]) else values[k + 1];
    const delta = (a - g) / (2 * (a - 2 * b + g));
    const value = b - (a - g) * delta / 4;
    return .{ .position = c.f(k) + delta, .value = if (logarithmic) @exp(value) else value };
}
fn less(_: void, a: f64, b: f64) bool {
    return a < b;
}
pub fn median(values: []const f64) f64 {
    const ordered = c.dupe(f64, values);
    std.mem.sort(f64, ordered, {}, less);
    const middle = ordered.len / 2;
    return if (ordered.len % 2 == 1) ordered[middle] else (ordered[middle - 1] + ordered[middle]) / 2;
}
pub const Spectrum = struct { windowed: []f64, amplitude: []f64, transformed: []fft.Complex, figures: windows.Figures };
pub fn spectrum(signal: []const f64, length: usize, name: []const u8, fs: i64) Spectrum {
    const weights = windows.window(name, length);
    const values = c.alloc(f64, length);
    for (signal[0..length], weights, values) |sample, weight, *value| value.* = sample * weight;
    const transformed = fft.dft(fft.complexValues(values, length));
    const amplitude = c.alloc(f64, length / 2 + 1);
    const figures = windows.figures(weights, fs);
    for (amplitude, 0..) |*value, k| value.* = (if (k == 0 or 2 * k == length) @as(f64, 1) else @as(f64,
         2)) * transformed[k].absolute() / figures.s1;
    return .{ .windowed = values, .amplitude = amplitude, .transformed = transformed, .figures = figures };
}
fn packedChecked(values: []const f64, error_value: *f64) []fft.Complex {
    const packed_values = fft.packedReal(values);
    const full = fft.radix2(fft.complexValues(values, values.len), false);
    for (packed_values, full[0..packed_values.len]) |a, b| error_value.* = @max(error_value.*, a.sub(b).absolute());
    return packed_values;
}
pub const Welch = struct { psd: []f64, coherence: []f64, transfer: []fft.Complex, segments: usize, packing_error: f64 = 0 };
pub fn welch(x: []const f64, y: []const f64, p: c.Params, fs: i64) Welch {
    const length = p.welch_length;
    const half = length / 2;
    const weights = windows.window(p.welch_window, length);
    var energy: f64 = 0;
    for (weights) |weight| energy += weight * weight;
    var out: Welch = .{ .psd = c.alloc(f64, half + 1), .coherence = c.alloc(f64, half + 1), .transfer = c.alloc(fft.Complex,
         half + 1), .segments = (x.len - length) / half + 1 };
    const xx = c.alloc(f64, half + 1);
    const yy = c.alloc(f64, half + 1);
    const xy = c.alloc(fft.Complex, half + 1);
    @memset(xx, 0);
    @memset(yy, 0);
    @memset(xy, .{});
    const a = c.alloc(f64, length);
    const b = c.alloc(f64, length);
    for (0..out.segments) |segment| {
        for (0..length) |i| {
            a[i] = x[segment * half + i] * weights[i];
            b[i] = y[segment * half + i] * weights[i];
        }
        var scratch = std.heap.ArenaAllocator.init(c.backing_allocator);
        const permanent = c.allocator;
        c.allocator = scratch.allocator();
        const af = packedChecked(a, &out.packing_error);
        const bf = packedChecked(b, &out.packing_error);
        for (0..half + 1) |k| {
            xx[k] += af[k].norm();
            yy[k] += bf[k].norm();
            xy[k] = xy[k].add(af[k].conjugate().mul(bf[k]));
        }
        c.allocator = permanent;
        scratch.deinit();
    }
    for (0..half + 1) |k| {
        out.psd[k] = (if (k == 0 or k == half) @as(f64, 1) else @as(f64, 2)) * xx[k] / (c.f(out.segments) * c.f(fs) * energy);
        out.coherence[k] = xy[k].norm() / (xx[k] * yy[k]);
        out.transfer[k] = xy[k].divide(xx[k]);
    }
    return out;
}
pub const Frames = struct { magnitudes: [][]f64, packing_error: f64 = 0 };
pub fn frames(x: []const f64, p: c.Params) Frames {
    const weights = windows.window(p.frame_window, p.frame_length);
    const count = (x.len - p.frame_length) / p.hop + 1;
    const values = c.alloc(f64, p.frame_length);
    var out: Frames = .{ .magnitudes = c.alloc([]f64, count) };
    for (out.magnitudes, 0..) |*row, frame| {
        for (0..p.frame_length) |i| values[i] = x[frame * p.hop + i] * weights[i];
        row.* = c.alloc(f64, p.frame_length / 2 + 1);
        var scratch = std.heap.ArenaAllocator.init(c.backing_allocator);
        const permanent = c.allocator;
        c.allocator = scratch.allocator();
        const transformed = packedChecked(values, &out.packing_error);
        for (transformed, row.*) |value, *magnitude| magnitude.* = value.absolute();
        c.allocator = permanent;
        scratch.deinit();
    }
    return out;
}
