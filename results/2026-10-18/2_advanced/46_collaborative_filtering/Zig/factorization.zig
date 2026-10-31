const std = @import("std");
const c = @import("ratings.zig");
pub fn dot(a: []const f64, b: []const f64) f64 {
    var out: f64 = 0;
    for (a, b) |x, y| out += x * y;
    return out;
}
pub fn solve(a: c.Matrix, w: []const f64) c.Vector {
    const n = w.len;
    const l = c.matrix(n, n);
    const z = c.vector(n);
    const x = c.vector(n);
    for (0..n) |row| for (0..row + 1) |column| {
        var sum: f64 = 0;
        for (0..column) |t| sum += l[row][t] * l[column][t];
        const s = a[row][column] - sum;
        l[row][column] = if (row == column) @sqrt(s) else s / l[column][column];
    };
    for (0..n) |row| {
        var sum: f64 = 0;
        for (0..row) |t| sum += l[row][t] * z[t];
        z[row] = (w[row] - sum) / l[row][row];
    }
    var remaining = n;
    while (remaining > 0) {
        remaining -= 1;
        const row = remaining;
        var sum: f64 = 0;
        for (row + 1..n) |t| sum += l[t][row] * x[t];
        x[row] = (z[row] - sum) / l[row][row];
    }
    return x;
}
pub const Training = struct { method: []const u8, epoch: usize, rmse: f64 };
pub const Factors = struct { p: c.Matrix, q: c.Matrix, x: c.Matrix, y: c.Matrix, user_bias: c.Vector,
     item_bias: c.Vector, log: []const Training };
fn draw(state: *i64) i64 {
    state.* = @mod(48271 * state.*, 2147483647);
    return state.*;
}
fn initial(state: *i64) f64 {
    return c.f(@mod(draw(state), 2001) - 1000) / 10000;
}
pub fn train(d: c.Data, bu: []const f64, bi: []const f64) Factors {
    const p = d.params;
    const nu = d.users.len;
    const ni = d.items.len;
    const nf = p.factors;
    var out: Factors = .{ .p = c.matrix(nu, nf), .q = c.matrix(ni, nf), .x = c.matrix(nu, nf), .y = c.matrix(ni,
         nf), .user_bias = c.vector(nu), .item_bias = c.vector(ni), .log = &.{} };
    var log: std.ArrayList(Training) = .empty;
    var state = p.seed;
    for (out.p) |row| for (row) |*value| {
        value.* = initial(&state);
    };
    for (out.q) |row| for (row) |*value| {
        value.* = initial(&state);
    };
    const order = c.alloc(usize, d.train.len);
    for (order, 0..) |*index, i| index.* = i;
    for (1..p.epochs + 1) |epoch| {
        var remaining = order.len;
        while (remaining > 1) {
            remaining -= 1;
            const t = remaining;
            const y = c.u(@mod(draw(&state), c.n(t + 1)));
            std.mem.swap(usize, &order[t], &order[y]);
        }
        for (order) |index| {
            const record = d.train[index];
            const u = record.user;
            const i = record.item;
            const e = c.f(record.rating) - (((d.mean + out.user_bias[u]) + out.item_bias[i]) + dot(out.p[u], out.q[i]));
            out.user_bias[u] = out.user_bias[u] + p.rate * (e - p.regularization * out.user_bias[u]);
            out.item_bias[i] = out.item_bias[i] + p.rate * (e - p.regularization * out.item_bias[i]);
            for (0..nf) |f| {
                const a = out.p[u][f];
                const b = out.q[i][f];
                out.p[u][f] = a + p.rate * (e * b - p.regularization * a);
                out.q[i][f] = b + p.rate * (e * a - p.regularization * b);
            }
        }
        var sum: f64 = 0;
        for (d.train) |record| {
            const e = c.f(record.rating) - (((d.mean + out.user_bias[record.user]) + out.item_bias[record.item]) + dot(out.p[record.user],
                 out.q[record.item]));
            sum += e * e;
        }
        c.append(Training, &log, .{ .method = "SVD", .epoch = epoch, .rmse = @sqrt(sum / c.f(d.train.len)) });
    }
    state = p.seed;
    for (out.y) |row| for (row) |*value| {
        value.* = initial(&state);
    };
    for (1..p.iterations + 1) |iteration| {
        for (0..nu) |u| {
            const a = c.matrix(nf, nf);
            const w = c.vector(nf);
            for (0..nf) |row| {
                for (0..nf) |column| for (0..ni) |i| {
                    if (d.ratings[u][i] != 0) a[row][column] += out.y[i][row] * out.y[i][column];
                };
                a[row][row] += p.als_reg * c.f(d.user_count[u]);
                for (0..ni) |i| if (d.ratings[u][i] != 0) {
                    const z = c.f(d.ratings[u][i]) - ((d.mean + bu[u]) + bi[i]);
                    w[row] += z * out.y[i][row];
                };
            }
            out.x[u] = solve(a, w);
        }
        for (0..ni) |i| {
            const a = c.matrix(nf, nf);
            const w = c.vector(nf);
            for (0..nf) |row| {
                for (0..nf) |column| for (0..nu) |u| {
                    if (d.ratings[u][i] != 0) a[row][column] += out.x[u][row] * out.x[u][column];
                };
                a[row][row] += p.als_reg * c.f(d.item_count[i]);
                for (0..nu) |u| if (d.ratings[u][i] != 0) {
                    const z = c.f(d.ratings[u][i]) - ((d.mean + bu[u]) + bi[i]);
                    w[row] += z * out.x[u][row];
                };
            }
            out.y[i] = solve(a, w);
        }
        var sum: f64 = 0;
        for (d.train) |record| {
            const e = c.f(record.rating) - (((d.mean + bu[record.user]) + bi[record.item]) + dot(out.x[record.user],
                 out.y[record.item]));
            sum += e * e;
        }
        c.append(Training, &log, .{ .method = "ALS", .epoch = iteration, .rmse = @sqrt(sum / c.f(d.train.len)) });
    }
    out.log = log.items;
    return out;
}
