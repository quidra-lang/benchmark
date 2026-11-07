const std = @import("std");
const c = @import("signal_io.zig");
pub const pi: f64 = 3.141592653589793;
pub const Complex = struct {
    re: f64 = 0,
    im: f64 = 0,
    pub fn add(a: Complex, b: Complex) Complex {
        return .{ .re = a.re + b.re, .im = a.im + b.im };
    }
    pub fn sub(a: Complex, b: Complex) Complex {
        return .{ .re = a.re - b.re, .im = a.im - b.im };
    }
    pub fn mul(a: Complex, b: Complex) Complex {
        return .{ .re = a.re * b.re - a.im * b.im, .im = a.re * b.im + a.im * b.re };
    }
    pub fn scale(a: Complex, value: f64) Complex {
        return .{ .re = a.re * value, .im = a.im * value };
    }
    pub fn divide(a: Complex, value: f64) Complex {
        return .{ .re = a.re / value, .im = a.im / value };
    }
    pub fn conjugate(a: Complex) Complex {
        return .{ .re = a.re, .im = -a.im };
    }
    pub fn norm(a: Complex) f64 {
        return a.re * a.re + a.im * a.im;
    }
    pub fn absolute(a: Complex) f64 {
        return @sqrt(a.norm());
    }
    pub fn argument(a: Complex) f64 {
        return std.math.atan2(a.im, a.re);
    }
};
pub fn complexValues(values: []const f64, length: usize) []Complex {
    const out = c.alloc(Complex, length);
    @memset(out, .{});
    for (values, out[0..values.len]) |value, *target| target.* = .{ .re = value };
    return out;
}
pub fn realParts(values: []const Complex) []f64 {
    const out = c.alloc(f64, values.len);
    for (values, out) |value, *target| target.* = value.re;
    return out;
}
pub fn pow2(value: usize) usize {
    var out: usize = 1;
    while (out < value) out *= 2;
    return out;
}
pub fn powerOfTwo(value: usize) bool {
    return (value & (value - 1)) == 0;
}
pub fn rot(angle: f64) Complex {
    return .{ .re = @cos(angle), .im = -@sin(angle) };
}
pub fn radix2(source: []const Complex, inverse: bool) []Complex {
    const count = source.len;
    const values = c.dupe(Complex, source);
    var bits: usize = 0;
    var value = count;
    while (value > 1) : (value /= 2) bits += 1;
    for (1..count) |n| {
        var reversed: usize = 0;
        value = n;
        for (0..bits) |_| {
            reversed = 2 * reversed + value % 2;
            value /= 2;
        }
        if (n < reversed) std.mem.swap(Complex, &values[n], &values[reversed]);
    }
    const twiddle = c.backing_allocator.alloc(Complex, count / 2) catch @panic("allocation failed");
    defer c.backing_allocator.free(twiddle);
    for (twiddle, 0..) |*factor, k| {
        factor.* = rot(2 * pi * c.f(k) / c.f(count));
        if (inverse) factor.* = factor.conjugate();
    }
    var size: usize = 2;
    while (size <= count) : (size *= 2) {
        const half = size / 2;
        const stride = count / size;
        var start: usize = 0;
        while (start < count) : (start += size) {
            for (0..half) |j| {
                const t = twiddle[j * stride].mul(values[start + j + half]);
                const old = values[start + j];
                values[start + j] = old.add(t);
                values[start + j + half] = old.sub(t);
            }
        }
    }
    if (inverse) for (values) |*element| {
        element.* = element.divide(c.f(count));
    };
    return values;
}
fn bluestein(values: []const Complex) []Complex {
    const m = values.len;
    const q = pow2(2 * m - 1);
    const chirp = c.alloc(Complex, m);
    const a = c.alloc(Complex, q);
    const b = c.alloc(Complex, q);
    @memset(a, .{});
    @memset(b, .{});
    for (0..m) |n| {
        chirp[n] = rot(pi * c.f((n * n) % (2 * m)) / c.f(m));
        a[n] = values[n].mul(chirp[n]);
        b[n] = chirp[n].conjugate();
        if (n > 0) b[q - n] = b[n];
    }
    const af = radix2(a, false);
    const bf = radix2(b, false);
    for (af, bf) |*first, second| first.* = first.mul(second);
    const g = radix2(af, true);
    const out = c.alloc(Complex, m);
    for (out, 0..) |*value, k| value.* = chirp[k].mul(g[k]);
    return out;
}
pub fn dft(values: []const Complex) []Complex {
    return if (powerOfTwo(values.len)) radix2(values, false) else bluestein(values);
}
pub fn idft(values: []const Complex) []Complex {
    if (powerOfTwo(values.len)) return radix2(values, true);
    const conjugates = c.alloc(Complex, values.len);
    for (values, conjugates) |value, *target| target.* = value.conjugate();
    const out = bluestein(conjugates);
    for (out) |*value| value.* = value.conjugate().divide(c.f(values.len));
    return out;
}
pub fn packedReal(values: []const f64) []Complex {
    const q = values.len;
    const half = q / 2;
    const z = c.alloc(Complex, half);
    for (z, 0..) |*value, j| value.* = .{ .re = values[2 * j], .im = values[2 * j + 1] };
    const transformed = radix2(z, false);
    const out = c.alloc(Complex, half + 1);
    for (out, 0..) |*value, k| {
        const a = transformed[k % half];
        const b = transformed[(half - k) % half].conjugate();
        const even = a.add(b).divide(2);
        const difference = a.sub(b);
        const odd: Complex = .{ .re = difference.im / 2, .im = -difference.re / 2 };
        value.* = even.add(rot(2 * pi * c.f(k) / c.f(q)).mul(odd));
    }
    return out;
}
pub fn convolution(a: []const f64, b: []const f64) []f64 {
    const length = a.len + b.len - 1;
    const q = pow2(length);
    const af = radix2(complexValues(a, q), false);
    const bf = radix2(complexValues(b, q), false);
    for (af, bf) |*first, second| first.* = first.mul(second);
    const result = radix2(af, true);
    return realParts(result[0..length]);
}
pub fn chirpZ(windowed: []const f64, fs: i64, low: i64, high: i64, points: usize) []Complex {
    const m = windowed.len;
    const q = pow2(m + points - 1);
    const step = c.f(high - low) / c.f(points - 1);
    const a = c.alloc(Complex, q);
    const b = c.alloc(Complex, q);
    @memset(a, .{});
    @memset(b, .{});
    for (windowed, 0..) |sample, n| a[n] = rot(2 * pi * c.f(low) * c.f(n) / c.f(fs)).scale(sample).mul(rot(pi * step * c.f(n) * c.f(n) / c.f(fs)));
    var offset = -c.n(m - 1);
    while (offset < c.n(points)) : (offset += 1) {
        const index = c.u(if (offset < 0) offset + c.n(q) else offset);
        b[index] = rot(pi * step * c.f(offset) * c.f(offset) / c.f(fs)).conjugate();
    }
    const af = radix2(a, false);
    const bf = radix2(b, false);
    for (af, bf) |*first, second| first.* = first.mul(second);
    const g = radix2(af, true);
    const out = c.alloc(Complex, points);
    for (out, 0..) |*value, j| value.* = rot(pi * step * c.f(j) * c.f(j) / c.f(fs)).mul(g[j]);
    return out;
}
