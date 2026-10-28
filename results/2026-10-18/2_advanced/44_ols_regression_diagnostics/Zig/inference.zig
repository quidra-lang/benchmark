const c = @import("dataframe.zig");
pub fn logGamma(x: f64) f64 {
    const coefficients = [_]f64{ 76.18009172947146, -86.50532032941677, 24.01409824083091, -1.231739572450155,
         0.001208650973866179, -0.000005395239384953 };
    const t = x + 5.5;
    const temporary = t - (x + 0.5) * @log(t);
    var sum: f64 = 1.000000000190015;
    for (coefficients, 1..) |coefficient, j| sum = sum + coefficient / (x + c.f(j));
    return -temporary + @log(2.5066282746310005 * sum / x);
}
fn replace(value: f64) f64 {
    return if (@abs(value) < 1e-300) 1e-300 else value;
}
pub fn betaFraction(a: f64, b: f64, x: f64) f64 {
    var value_c: f64 = 1;
    var d = 1 - (a + b) * x / (a + 1);
    d = 1 / replace(d);
    var h = d;
    for (1..1001) |index| {
        const m = c.f(index);
        var q = m * (b - m) * x / ((a - 1 + 2 * m) * (a + 2 * m));
        d = 1 / replace(1 + q * d);
        value_c = replace(1 + q / value_c);
        h = h * (d * value_c);
        q = -(a + m) * (a + b + m) * x / ((a + 2 * m) * (a + 1 + 2 * m));
        d = 1 / replace(1 + q * d);
        value_c = replace(1 + q / value_c);
        const delta = d * value_c;
        h = h * delta;
        if (@abs(delta - 1) < 1e-15) break;
    }
    return h;
}
pub fn betaI(x: f64, a: f64, b: f64) f64 {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    const factor = @exp(logGamma(a + b) - logGamma(a) - logGamma(b) + a * @log(x) + b * @log(1 - x));
    return if (x < (a + 1) / (a + b + 2)) factor * betaFraction(a, b, x) / a else 1 - factor * betaFraction(b, a, 1 - x) / b;
}
pub fn gammaQ(a: f64, x: f64) f64 {
    if (x == 0) return 1;
    const factor = @exp(-x + a * @log(x) - logGamma(a));
    if (x < a + 1) {
        var t = 1 / a;
        var sum = t;
        var e = a;
        for (0..1000) |_| {
            e = e + 1;
            t = t * (x / e);
            sum = sum + t;
            if (@abs(t) < @abs(sum) * 1e-15) break;
        }
        return 1 - sum * factor;
    }
    var beta = x + 1 - a;
    var value_c: f64 = 1 / 1e-300;
    var d = 1 / beta;
    var h = d;
    for (1..1001) |i| {
        const q = -c.f(i) * (c.f(i) - a);
        beta = beta + 2;
        d = 1 / replace(q * d + beta);
        value_c = replace(beta + q / value_c);
        const delta = d * value_c;
        h = h * delta;
        if (@abs(delta - 1) < 1e-15) break;
    }
    return factor * h;
}
pub fn pT(value: f64, degrees: f64) f64 {
    return betaI(degrees / (degrees + value * value), degrees / 2, 0.5);
}
pub fn pF(value: f64, first: f64, second: f64) f64 {
    return betaI(second / (second + first * value), second / 2, first / 2);
}
pub fn pChi(value: f64, degrees: f64) f64 {
    return gammaQ(degrees / 2, value / 2);
}
pub fn tQuantile(confidence: f64, degrees: f64) f64 {
    var low: f64 = 0;
    var high: f64 = 1000;
    for (0..100) |_| {
        const middle = (low + high) / 2;
        if (pT(middle, degrees) > 1 - confidence) low = middle else high = middle;
    }
    return (low + high) / 2;
}
pub fn significance(p: f64) []const u8 {
    return if (p < 0.001) "***" else if (p < 0.01) "**" else if (p < 0.05) "*" else if (p < 0.1) "." else "";
}
pub fn real(value: f64) []const u8 {
    return c.fmt("{d:.4}", .{if (@abs(value) < 0.00005) @as(f64, 0) else value});
}
pub fn pFormat(value: f64) []const u8 {
    return if (value < 0.0001) "<0.0001" else real(value);
}
