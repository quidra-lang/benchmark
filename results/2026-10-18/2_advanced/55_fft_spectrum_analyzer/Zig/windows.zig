const c = @import("signal_io.zig");
const fft = @import("fft.zig");
pub const names = [_][]const u8{ "rectangular", "hann", "hamming", "blackman", "flattop" };
pub fn window(name: []const u8, length: usize) []f64 {
    const coefficients: []const f64 = if (c.eq(name, "rectangular")) &.{1} else if (c.eq(name, "hann")) &.{ 0.5,
         0.5 } else if (c.eq(name, "hamming")) &.{ 0.54, 0.46 } else if (c.eq(name, "blackman")) &.{ 0.42,
         0.5, 0.08 } else &.{ 0.21557895, 0.41663158, 0.277263158, 0.083578947, 0.006947368 };
    const out = c.alloc(f64, length);
    @memset(out, 0);
    for (out, 0..) |*value, n| for (coefficients, 0..) |coefficient, j| {
        value.* += (if (j % 2 == 1) @as(f64, -1) else @as(f64, 1)) * coefficient * @cos(2 * fft.pi * c.f(j) * c.f(n) / c.f(length));
    };
    return out;
}
pub const Figures = struct { s1: f64 = 0, s2: f64 = 0, coherent: f64 = 0, enbw: f64 = 0, enbw_hz: f64 = 0, scalloping: f64 = 0 };
pub fn figures(values: []const f64, fs: i64) Figures {
    var out: Figures = .{};
    var sum: fft.Complex = .{};
    for (values, 0..) |value, n| {
        out.s1 += value;
        out.s2 += value * value;
        sum = sum.add(fft.rot(fft.pi * c.f(n) / c.f(values.len)).scale(value));
    }
    out.coherent = out.s1 / c.f(values.len);
    out.enbw = c.f(values.len) * out.s2 / (out.s1 * out.s1);
    out.enbw_hz = out.enbw * c.f(fs) / c.f(values.len);
    out.scalloping = -20 * @log10(sum.absolute() / out.s1);
    return out;
}
