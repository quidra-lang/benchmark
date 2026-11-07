const std = @import("std");
const d = @import("dataset.zig");
const l = @import("logistic.zig");
pub const Minstd = struct {
    state: i64,
    pub fn draw(self: *Minstd) i64 {
        self.state = @mod(48271 * self.state, 2147483647);
        return self.state;
    }
    pub fn shuffle(self: *Minstd, values: []usize) void {
        var size = values.len;
        while (size > 1) : (size -= 1) {
            const index: usize = @intCast(@mod(self.draw(), d.n(size)));
            std.mem.swap(usize, &values[size - 1], &values[index]);
        }
    }
};
pub fn cholesky(matrix: d.Matrix) d.Matrix {
    const lower = d.matrix(matrix.len, matrix.len);
    for (0..matrix.len) |j| for (j..matrix.len) |i| {
        var total: f64 = 0;
        for (0..j) |k| total += lower[i][k] * lower[j][k];
        const sigma = matrix[i][j] - total;
        lower[i][j] = if (i == j) @sqrt(sigma) else sigma / lower[j][j];
    };
    return lower;
}
pub fn solve(lower: d.Matrix, right: []const f64) []f64 {
    const middle = d.alloc(f64, lower.len);
    const result = d.alloc(f64, lower.len);
    for (0..lower.len) |i| {
        var total: f64 = 0;
        for (0..i) |k| total += lower[i][k] * middle[k];
        middle[i] = (right[i] - total) / lower[i][i];
    }
    var i = lower.len;
    while (i > 0) {
        i -= 1;
        var total: f64 = 0;
        for (i + 1..lower.len) |k| total += lower[k][i] * result[k];
        result[i] = (middle[i] - total) / lower[i][i];
    }
    return result;
}
pub const Checkpoint = struct { iteration: usize, weights: []const f64 };
pub fn newton(data: d.Matrix, targets: []const usize, lambda: f64) []Checkpoint {
    const weights = d.zeros(data[0].len);
    var result: std.ArrayList(Checkpoint) = .empty;
    d.append(Checkpoint, &result, .{ .iteration = 0, .weights = d.dupe(f64, weights) });
    for (1..11) |iteration| {
        const delta = solve(cholesky(l.hessian(weights, data, lambda)), l.gradient(weights, data, targets, lambda));
        for (weights, delta) |*value, change| value.* -= change;
        d.append(Checkpoint, &result, .{ .iteration = iteration, .weights = d.dupe(f64, weights) });
    }
    return result.items;
}
pub fn gradientDescent(data: d.Matrix, targets: []const usize, lambda: f64, rate: f64, iterations: usize) []Checkpoint {
    const weights = d.zeros(data[0].len);
    var result: std.ArrayList(Checkpoint) = .empty;
    d.append(Checkpoint, &result, .{ .iteration = 0, .weights = d.dupe(f64, weights) });
    for (1..iterations + 1) |iteration| {
        const gradient = l.gradient(weights, data, targets, lambda);
        for (weights, gradient) |*value, delta| value.* -= rate * delta;
        if (iteration % 100 == 0) d.append(Checkpoint, &result, .{ .iteration = iteration, .weights = d.dupe(f64, weights) });
    }
    return result.items;
}
pub fn stochastic(data: d.Matrix, targets: []const usize, lambda: f64, params: d.Params) []Checkpoint {
    const weights = d.zeros(data[0].len);
    var result: std.ArrayList(Checkpoint) = .empty;
    d.append(Checkpoint, &result, .{ .iteration = 0, .weights = d.dupe(f64, weights) });
    var random: Minstd = .{ .state = params.sgd_seed };
    const order = d.sequence(data.len);
    for (1..params.epochs + 1) |epoch| {
        random.shuffle(order);
        var first: usize = 0;
        while (first < data.len) : (first += params.batch) {
            const indices = order[first..@min(first + params.batch, data.len)];
            const batch = d.alloc([]f64, indices.len);
            const labels_ = d.alloc(usize, indices.len);
            for (indices, batch, labels_) |id, *row, *target| {
                row.* = data[id];
                target.* = targets[id];
            }
            const gradient = l.gradient(weights, batch, labels_, lambda);
            for (weights, gradient) |*value, delta| value.* -= params.sgd_rate * delta;
        }
        d.append(Checkpoint, &result, .{ .iteration = epoch, .weights = d.dupe(f64, weights) });
    }
    return result.items;
}
