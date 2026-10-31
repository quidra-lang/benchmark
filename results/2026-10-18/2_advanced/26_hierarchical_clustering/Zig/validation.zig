const d = @import("dataset.zig");
const distances = @import("distances.zig");
pub fn correlation(first: []const f64, second: []const f64) f64 {
    const mean_first = distances.sum(first) / d.f(first.len);
    const mean_second = distances.sum(second) / d.f(second.len);
    var cross: f64 = 0;
    var spread_first: f64 = 0;
    var spread_second: f64 = 0;
    for (first, second) |a, b| {
        const x = a - mean_first;
        const y = b - mean_second;
        cross += x * y;
        spread_first += x * x;
        spread_second += y * y;
    }
    return cross / @sqrt(spread_first * spread_second);
}
pub const Table = [][]i64;
pub fn contingency(first: []const usize, second: []const usize, rows: usize, columns: usize) Table {
    const table = d.alloc([]i64, rows);
    const values = d.alloc(i64, rows * columns);
    @memset(values, 0);
    for (table, 0..) |*row, index| row.* = values[index * columns .. (index + 1) * columns];
    for (first, second) |a, b| table[a][b] += 1;
    return table;
}
fn pairCount(value: i64) i64 { return @divTrunc(value * (value - 1), 2); }
pub const Fraction = struct {
    numerator: i64,
    denominator: i64,
    pub fn value(self: Fraction) f64 { return d.f(self.numerator) / d.f(self.denominator); }
    pub fn greater(self: Fraction, other: Fraction) bool { return self.numerator * other.denominator > other.numerator * self.denominator; }
};
pub fn adjustedRand(table: Table) Fraction {
    var count: i64 = 0;
    var same: i64 = 0;
    var row_pairs: i64 = 0;
    var columns: [120]i64 = @splat(0);
    for (table) |row| {
        var row_sum: i64 = 0;
        for (row, 0..) |cell, column| {
            count += cell;
            row_sum += cell;
            same += pairCount(cell);
            columns[column] += cell;
        }
        row_pairs += pairCount(row_sum);
    }
    var column_pairs: i64 = 0;
    for (columns[0..table[0].len]) |value| column_pairs += pairCount(value);
    const total = pairCount(count);
    const numerator = 2 * (total * same - row_pairs * column_pairs);
    const denominator = total * (row_pairs + column_pairs) - 2 * row_pairs * column_pairs;
    if (denominator == 0) return .{ .numerator = 1, .denominator = 1 };
    var first = @abs(numerator);
    var second = @abs(denominator);
    while (second != 0) {
        const remainder = first % second;
        first = second;
        second = remainder;
    }
    const divisor: i64 = @intCast(first);
    const sign: i64 = if (denominator < 0) -1 else 1;
    return .{ .numerator = @divTrunc(numerator, divisor) * sign, .denominator = @divTrunc(denominator, divisor) * sign };
}
pub fn silhouetteValues(partition: []const usize, groups: usize, delta: d.Matrix) []f64 {
    var sizes: [121]usize = @splat(0);
    for (partition) |number| sizes[number] += 1;
    const values = d.alloc(f64, partition.len);
    for (partition, 0..) |own, i| {
        if (sizes[own] == 1) { values[i] = 0; continue; }
        var sums: [121]f64 = @splat(0);
        for (partition, 0..) |other, j| if (j != i) { sums[other] += delta[i][j]; };
        const inner = sums[own] / d.f(sizes[own] - 1);
        var outer: ?f64 = null;
        for (1..groups + 1) |group| {
            if (group == own) continue;
            const value = sums[group] / d.f(sizes[group]);
            if (outer == null or value < outer.?) outer = value;
        }
        values[i] = (outer.? - inner) / @max(inner, outer.?);
    }
    return values;
}
