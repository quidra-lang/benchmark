const std = @import("std");
const m = @import("matrix.zig");
pub const Pair = struct { row: usize, column: usize };
fn less(_: void, a: Pair, b: Pair) bool {
    return if (a.row != b.row) a.row < b.row else a.column < b.column;
}
pub fn minimumMatching(costs: []const f64, row_count: usize, column_count: usize) []const Pair {
    if (row_count == 0 or column_count == 0) return &.{};
    const flipped = row_count > column_count;
    const rows = if (flipped) column_count else row_count;
    const columns = if (flipped) row_count else column_count;
    const u = m.alloc(f64, rows + 1);
    @memset(u, 0);
    const v = m.alloc(f64, columns + 1);
    @memset(v, 0);
    const distances = m.alloc(f64, columns + 1);
    const matched = m.alloc(usize, columns + 1);
    @memset(matched, 0);
    const previous = m.alloc(usize, columns + 1);
    @memset(previous, 0);
    const used = m.alloc(bool, columns + 1);
    for (1..rows + 1) |row| {
        matched[0] = row;
        var column: usize = 0;
        @memset(distances, std.math.inf(f64));
        @memset(used, false);
        while (true) {
            used[column] = true;
            const current = matched[column];
            var following: usize = 0;
            var delta = std.math.inf(f64);
            for (1..columns + 1) |candidate| {
                if (used[candidate]) continue;
                const value = if (flipped) costs[(candidate - 1) * column_count + current - 1] else costs[(current - 1) * column_count + candidate - 1];
                const reduced = value - u[current] - v[candidate];
                if (reduced < distances[candidate]) {
                    distances[candidate] = reduced;
                    previous[candidate] = column;
                }
                if (distances[candidate] < delta) {
                    delta = distances[candidate];
                    following = candidate;
                }
            }
            for (0..columns + 1) |candidate| {
                if (used[candidate]) {
                    u[matched[candidate]] += delta;
                    v[candidate] -= delta;
                } else distances[candidate] -= delta;
            }
            column = following;
            if (matched[column] == 0) break;
        }
        while (column > 0) {
            const following = previous[column];
            matched[column] = matched[following];
            column = following;
        }
    }
    var out: std.ArrayList(Pair) = .empty;
    for (1..columns + 1) |column| {
        if (matched[column] == 0) continue;
        m.append(Pair, &out, if (flipped) .{ .row = column - 1, .column = matched[column] - 1 } else .{ .row = matched[column] - 1,
             .column = column - 1 });
    }
    std.mem.sort(Pair, out.items, {}, less);
    return out.items;
}
pub fn optimalAssignment(costs: []const f64, usable: []const bool, rows: usize, columns: usize) []const Pair {
    if (rows == 0 or columns == 0) return &.{};
    var largest: f64 = 0;
    for (costs, usable) |value, valid| {
        if (valid) largest = @max(largest, value);
    }
    const penalty = m.f(@min(rows, columns) + 1) * (@max(@as(f64, 1), largest) + 1);
    const matrix = m.alloc(f64, costs.len);
    for (costs, usable, matrix) |value, valid, *target| target.* = if (valid) value else penalty;
    var out: std.ArrayList(Pair) = .empty;
    for (minimumMatching(matrix, rows, columns)) |pair| {
        if (usable[pair.row * columns + pair.column]) m.append(Pair, &out, pair);
    }
    return out.items;
}
