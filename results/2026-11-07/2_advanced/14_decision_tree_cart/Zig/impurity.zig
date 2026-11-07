const D = @import("dataset.zig");
pub const Fraction = struct { numerator: i64, denominator: i64 };
pub const Statistics = struct { counts: [6]i64 = [_]i64{0} ** 6, size: i64, squares: i64 = 0, errors: i64 = 0, prediction: usize = 0 };
pub fn majority(counts: []const i64) usize {
    var selected: usize = 0;
    for (counts, 0..) |count, i| { if (count > counts[selected]) selected = i; }
    return selected;
}
pub fn statistics(rows: D.Rows, classes: usize) Statistics {
    var result: Statistics = .{ .size = D.n(rows.len) };
    for (rows.slice()) |row| result.counts[row.label] += 1;
    for (result.counts[0..classes]) |count| result.squares += count * count;
    result.prediction = majority(result.counts[0..classes]);
    result.errors = result.size - result.counts[result.prediction];
    return result;
}
pub fn compare(first: Fraction, second: Fraction) i8 {
    const a = first.numerator * second.denominator;
    const b = second.numerator * first.denominator;
    return if (a < b) -1 else if (a > b) 1 else 0;
}
pub fn evaluationValue(left: Statistics, right: Statistics) Fraction { return .{ .numerator = left.squares * right.size + right.squares * left.size, .denominator = left.size * right.size }; }
pub fn improves(value: Fraction, parent: Statistics) bool { return value.numerator * parent.size > parent.squares * value.denominator; }
pub fn decrease(parent: Statistics, left: Statistics, right: Statistics) f64 {
    const first = D.real(left.squares) / D.real(left.size);
    const second = D.real(right.squares) / D.real(right.size);
    const whole = D.real(parent.squares) / D.real(parent.size);
    return (first + second) - whole;
}
