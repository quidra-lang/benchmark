const std = @import("std");
const c = @import("dataset.zig");
pub const Fraction = struct {
    numerator: i64 = 0,
    denominator: i64 = 1,
    pub fn init(a_: i64, b_: i64) Fraction {
        var a = a_;
        var b = b_;
        if (b < 0) {
            a = -a;
            b = -b;
        }
        var x: @TypeOf(@abs(a)) = @abs(a);
        var y: @TypeOf(x) = @intCast(b);
        while (y != 0) {
            const remainder = x % y;
            x = y;
            y = remainder;
        }
        const divisor: @TypeOf(a) = @intCast(x);
        return .{ .numerator = @divTrunc(a, divisor), .denominator = @divTrunc(b, divisor) };
    }
    pub fn add(a: Fraction, b: Fraction) Fraction {
        return init(a.numerator * b.denominator + b.numerator * a.denominator, a.denominator * b.denominator);
    }
    pub fn divide(value: Fraction, divisor: i64) Fraction {
        return init(value.numerator, value.denominator * divisor);
    }
};
pub const Measures = struct { confusion: [5][5]usize = std.mem.zeroes([5][5]usize), support: [5]usize = std.mem.zeroes([5]usize),
     predicted: [5]usize = std.mem.zeroes([5]usize), correct: usize = 0, total: usize, classes: usize,
     accuracy: Fraction = .{}, balanced: Fraction = .{}, kappa: Fraction = .{}, recall: [5]Fraction = @splat(.{}),
     precision: [5]Fraction = @splat(.{}), f1: [5]Fraction = @splat(.{}), macro_f1: f64 = 0 };
pub fn evaluate(rows: c.Rows, prediction: []const usize, classes: usize) Measures {
    var out: Measures = .{ .total = rows.len, .classes = classes };
    for (rows, prediction) |row, predicted| out.confusion[row.label][predicted] += 1;
    for (0..classes) |k| {
        for (0..classes) |j| {
            out.support[k] += out.confusion[k][j];
            out.predicted[k] += out.confusion[j][k];
        }
        out.correct += out.confusion[k][k];
        out.recall[k] = Fraction.init(c.n(out.confusion[k][k]), c.n(out.support[k]));
        if (out.predicted[k] > 0) out.precision[k] = Fraction.init(c.n(out.confusion[k][k]), c.n(out.predicted[k]));
        out.f1[k] = Fraction.init(c.n(2 * out.confusion[k][k]), c.n(out.support[k] + out.predicted[k]));
        out.balanced = out.balanced.add(out.recall[k]);
        out.macro_f1 += c.f(2 * out.confusion[k][k]) / c.f(out.support[k] + out.predicted[k]);
    }
    out.accuracy = Fraction.init(c.n(out.correct), c.n(rows.len));
    out.balanced = out.balanced.divide(c.n(classes));
    out.macro_f1 /= c.f(classes);
    var expected: i64 = 0;
    for (0..classes) |k| expected += c.n(out.support[k] * out.predicted[k]);
    out.kappa = Fraction.init(c.n(rows.len * out.correct) - expected, c.n(rows.len * rows.len) - expected);
    return out;
}
pub const McNemar = struct { b01: usize = 0, b10: usize = 0, chi2: f64 = 0 };
pub fn mcnemar(rows: c.Rows, a: []const usize, b: []const usize) McNemar {
    var out: McNemar = .{};
    for (rows, a, b) |row, first, second| {
        const ac = first == row.label;
        const bc = second == row.label;
        out.b01 += @intFromBool(ac and !bc);
        out.b10 += @intFromBool(!ac and bc);
    }
    if (out.b01 != out.b10) {
        const difference = @as(i64, @intCast(@abs(c.n(out.b01) - c.n(out.b10)))) - 1;
        out.chi2 = c.f(difference * difference) / c.f(out.b01 + out.b10);
    }
    return out;
}
pub const Generator = struct {
    state: i64,
    pub fn draw(self: *Generator) i64 {
        self.state = @mod(48271 * self.state, 2147483647);
        return self.state;
    }
};
