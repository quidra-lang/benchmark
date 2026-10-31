const std = @import("std");
const c = @import("ratings.zig");
pub const OptionalMatrix = [][]?f64;
fn optionalMatrix(rows: usize, columns: usize) OptionalMatrix {
    const out = c.alloc([]?f64, rows);
    for (out) |*row| {
        row.* = c.alloc(?f64, columns);
        @memset(row.*, null);
    }
    return out;
}
pub const Similarities = struct { user: OptionalMatrix, item: OptionalMatrix, user_common: c.IntMatrix,
     common: c.IntMatrix, difference: c.IntMatrix };
pub fn similarities(d: c.Data) Similarities {
    const nu = d.users.len;
    const ni = d.items.len;
    const out: Similarities = .{ .user = optionalMatrix(nu, nu), .item = optionalMatrix(ni, ni), .user_common = c.intMatrix(nu,
         nu), .common = c.intMatrix(ni, ni), .difference = c.intMatrix(ni, ni) };
    for (0..nu - 1) |u| for (u + 1..nu) |v| {
        var n: i64 = 0;
        var sx: i64 = 0;
        var sy: i64 = 0;
        var sxx: i64 = 0;
        var syy: i64 = 0;
        var sxy: i64 = 0;
        for (0..ni) |i| if (d.ratings[u][i] != 0 and d.ratings[v][i] != 0) {
            const x = d.ratings[u][i];
            const y = d.ratings[v][i];
            n += 1;
            sx += x;
            sy += y;
            sxx += x * x;
            syy += y * y;
            sxy += x * y;
        };
        out.user_common[u][v] = n;
        out.user_common[v][u] = n;
        if (n < 2) continue;
        const num = n * sxy - sx * sy;
        const dx = n * sxx - sx * sx;
        const dy = n * syy - sy * sy;
        if (dx == 0 or dy == 0) continue;
        const a = (num * n) * (num * n);
        const b = dx * dy * (n + d.params.shrinkage) * (n + d.params.shrinkage);
        const value = (if (num > 0) @as(f64, 1) else if (num < 0) @as(f64, -1) else @as(f64, 0)) * @sqrt(c.f(a) / c.f(b));
        out.user[u][v] = value;
        out.user[v][u] = value;
    };
    for (0..ni - 1) |i| for (i + 1..ni) |j| {
        var n: i64 = 0;
        var difference: i64 = 0;
        var num: f64 = 0;
        var left: f64 = 0;
        var right: f64 = 0;
        for (0..nu) |u| if (d.ratings[u][i] != 0 and d.ratings[u][j] != 0) {
            n += 1;
            difference += d.ratings[u][i] - d.ratings[u][j];
            const x = c.f(d.ratings[u][i]) - d.user_mean[u];
            const y = c.f(d.ratings[u][j]) - d.user_mean[u];
            num += x * y;
            left += x * x;
            right += y * y;
        };
        out.common[i][j] = n;
        out.common[j][i] = n;
        out.difference[i][j] = difference;
        out.difference[j][i] = -difference;
        if (n >= 2 and left != 0 and right != 0) {
            const value = num / @sqrt(left * right) * c.f(n) / c.f(n + d.params.shrinkage);
            out.item[i][j] = value;
            out.item[j][i] = value;
        }
    };
    return out;
}
pub const Neighbor = struct { index: usize, similarity: f64 };
pub fn less(_: void, a: Neighbor, b: Neighbor) bool {
    return if (a.similarity != b.similarity) a.similarity > b.similarity else a.index < b.index;
}
pub fn select(candidates: []Neighbor, count: usize) []const Neighbor {
    std.mem.sort(Neighbor, candidates, {}, less);
    return candidates[0..@min(count, candidates.len)];
}
