const std = @import("std");
const d = @import("alignment.zig");
pub const Matrix = [16][16]f64;
pub const Pair = struct { first: usize, second: usize, sites: i64 = 0, transitions: i64 = 0, transversions: i64 = 0 };
pub fn allPairs(sequences: []const []const u8, weights: []const i64) []const Pair {
    const out = d.alloc(Pair, sequences.len * (sequences.len - 1) / 2);
    var index: usize = 0;
    for (0..sequences.len) |a| for (a + 1..sequences.len) |b| {
        var pair: Pair = .{ .first = a, .second = b };
        for (sequences[a], sequences[b], weights) |x_character, y_character, weight| {
            const x = d.baseIndex(x_character) orelse continue;
            const y = d.baseIndex(y_character) orelse continue;
            pair.sites += weight;
            if (x != y) {
                if ((x == 0 and y == 2) or (x == 2 and y == 0) or (x == 1 and y == 3) or (x == 3 and y == 1)) pair.transitions += weight else pair.transversions += weight;
            }
        }
        out[index] = pair;
        index += 1;
    };
    return out;
}
pub const Distance = struct { value: f64, saturated: bool };
pub fn corrected(model: usize, pair: Pair, replacement: f64) Distance {
    const count = pair.sites;
    const transitions = pair.transitions;
    const transversions = pair.transversions;
    var saturated = count == 0;
    if (model == 1) saturated = saturated or 4 * (transitions + transversions) >= 3 * count else if (model == 2) saturated = saturated or 2 * transitions + transversions >= count or 2 * transversions >= count;
    if (saturated) return .{ .value = replacement, .saturated = true };
    const value = if (model == 0) d.f(transitions + transversions) / d.f(count) else if (model == 1) -0.75 * @log(1 - d.f(4 * (transitions + transversions)) / d.f(3 * count)) else -0.5 * @log(1 - d.f(2 * transitions) / d.f(count) - d.f(transversions) / d.f(count)) - 0.25 * @log(1 - d.f(2 * transversions) / d.f(count));
    return .{ .value = value, .saturated = false };
}
pub const Built = struct { matrix: Matrix = [_][16]f64{[_]f64{0} ** 16} ** 16, saturated: []const Pair };
pub fn buildMatrix(pairs: []const Pair, model: usize, replacement: f64) Built {
    var out: Built = .{ .saturated = &.{} };
    var saturated: std.ArrayList(Pair) = .empty;
    for (pairs) |pair| {
        const value = corrected(model, pair, replacement);
        out.matrix[pair.first][pair.second] = value.value;
        out.matrix[pair.second][pair.first] = value.value;
        if (value.saturated) d.append(Pair, &saturated, pair);
    }
    out.saturated = saturated.items;
    return out;
}
