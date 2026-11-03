const std = @import("std");
const c = @import("dataset.zig");
pub fn solve(matrix_: c.Matrix, right_: c.Vector, size: usize) c.Vector {
    var matrix = matrix_;
    var right = right_;
    for (0..size) |k| for (k + 1..size) |i| {
        const factor = matrix[i][k] / matrix[k][k];
        for (k..size) |j| matrix[i][j] = matrix[i][j] - factor * matrix[k][j];
        right[i] = right[i] - factor * right[k];
    };
    var out = std.mem.zeroes(c.Vector);
    var remaining = size;
    while (remaining > 0) {
        remaining -= 1;
        const i = remaining;
        var value = right[i];
        for (i + 1..size) |j| value = value - matrix[i][j] * out[j];
        out[i] = value / matrix[i][i];
    }
    return out;
}
pub fn inverse(matrix: c.Matrix, size: usize) c.Matrix {
    var out = std.mem.zeroes(c.Matrix);
    for (0..size) |column| {
        var unit = std.mem.zeroes(c.Vector);
        unit[column] = 1;
        const solution = solve(matrix, unit, size);
        for (0..size) |row| out[row][column] = solution[row];
    }
    return out;
}
pub fn logGamma(a: f64) f64 {
    const coefficients = [_]f64{ 76.18009172947146, -86.50532032941677, 24.01409824083091, -1.231739572450155,
         0.001208650973866179, -0.000005395239384953 };
    const xi0 = a + 5.5;
    const xi1 = xi0 - (a + 0.5) * @log(xi0);
    var sum: f64 = 1.000000000190015;
    var y = a;
    for (coefficients) |coefficient| {
        y = y + 1;
        sum = sum + coefficient / y;
    }
    return -xi1 + @log(2.5066282746310005 * sum / a);
}
pub fn gammaQ(a: f64, x: f64) f64 {
    if (x == 0) return 1;
    const pref = @exp(-x + a * @log(x) - logGamma(a));
    if (x < a + 1) {
        var alpha = a;
        var xi = 1 / a;
        var sum = xi;
        for (0..1000) |_| {
            alpha = alpha + 1;
            xi = xi * (x / alpha);
            sum = sum + xi;
            if (@abs(xi) < @abs(sum) * 1e-15) break;
        }
        return 1 - sum * pref;
    }
    const epsilon: f64 = 1e-300;
    var b = x + 1 - a;
    var value_c = 1 / epsilon;
    var d = 1 / b;
    var h = d;
    for (1..1001) |i| {
        const an = -c.f(i) * (c.f(i) - a);
        b = b + 2;
        d = an * d + b;
        if (@abs(d) < epsilon) d = epsilon;
        value_c = b + an / value_c;
        if (@abs(value_c) < epsilon) value_c = epsilon;
        d = 1 / d;
        const delta = d * value_c;
        h = h * delta;
        if (@abs(delta - 1) < 1e-15) break;
    }
    return pref * h;
}
pub fn pValue(statistic: f64, degrees: usize) f64 {
    return gammaQ(c.f(degrees) / 2, statistic / 2);
}
