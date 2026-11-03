const s = @import("season.zig");
const r = @import("report.zig");

pub fn colley(n: usize, matches: []const s.Match) [30]f64 {
    var matrix: [30][30]f64 = @splat(@splat(0));
    var lower: [30][30]f64 = @splat(@splat(0));
    var balance: [30]i64 = @splat(0);
    for (0..n) |i| matrix[i][i] = 2;
    for (matches) |match| {
        const home = match.home;
        const away = match.away;
        matrix[home][home] += 1;
        matrix[away][away] += 1;
        matrix[home][away] -= 1;
        matrix[away][home] -= 1;
        const result: i64 = if (match.margin > 0) 1 else if (match.margin < 0) -1 else 0;
        balance[home] += result;
        balance[away] -= result;
    }
    var vector: [30]f64 = undefined;
    for (0..n) |i| vector[i] = 1 + r.f(balance[i]) / 2;
    for (0..n) |i| {
        for (0..i + 1) |j| {
            var total: f64 = 0;
            for (0..j) |k| total += lower[i][k] * lower[j][k];
            lower[i][j] = if (j < i) (matrix[i][j] - total) / lower[j][j] else @sqrt(matrix[i][i] - total);
        }
    }
    var forward: [30]f64 = undefined;
    for (0..n) |i| {
        var total: f64 = 0;
        for (0..i) |k| total += lower[i][k] * forward[k];
        forward[i] = (vector[i] - total) / lower[i][i];
    }
    var ratings: [30]f64 = @splat(0);
    var i = n;
    while (i > 0) {
        i -= 1;
        var total: f64 = 0;
        for (i + 1..n) |k| total += lower[k][i] * ratings[k];
        ratings[i] = (forward[i] - total) / lower[i][i];
    }
    return ratings;
}

pub const Massey = struct { ratings: [30]f64, advantage: f64 };
pub fn massey(n: usize, matches: []const s.Match) Massey {
    const size = n + 1;
    var matrix: [31][31]f64 = @splat(@splat(0));
    var vector: [31]f64 = @splat(0);
    for (matches) |match| {
        const home = match.home;
        const away = match.away;
        matrix[home][home] += 1;
        matrix[away][away] += 1;
        matrix[home][away] -= 1;
        matrix[away][home] -= 1;
        matrix[home][n] += 1;
        matrix[n][home] += 1;
        matrix[away][n] -= 1;
        matrix[n][away] -= 1;
        matrix[n][n] += 1;
        vector[home] += r.f(match.margin);
        vector[away] -= r.f(match.margin);
        vector[n] += r.f(match.margin);
    }
    for (0..size) |j| matrix[n - 1][j] = if (j < n) 1 else 0;
    vector[n - 1] = 0;
    for (0..size) |k| {
        var pivot = k;
        for (k + 1..size) |row| if (@abs(matrix[row][k]) > @abs(matrix[pivot][k])) { pivot = row; };
        const row = matrix[k];
        matrix[k] = matrix[pivot];
        matrix[pivot] = row;
        const value = vector[k];
        vector[k] = vector[pivot];
        vector[pivot] = value;
        for (k + 1..size) |i| {
            const factor = matrix[i][k] / matrix[k][k];
            for (k..size) |j| matrix[i][j] -= factor * matrix[k][j];
            vector[i] -= factor * vector[k];
        }
    }
    var solution: [31]f64 = @splat(0);
    var i = size;
    while (i > 0) {
        i -= 1;
        var total: f64 = 0;
        for (i + 1..size) |j| total += matrix[i][j] * solution[j];
        solution[i] = (vector[i] - total) / matrix[i][i];
    }
    var ratings: [30]f64 = @splat(0);
    @memcpy(ratings[0..n], solution[0..n]);
    return .{ .ratings = ratings, .advantage = solution[n] };
}
