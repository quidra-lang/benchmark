const std = @import("std");
const s = @import("season.zig");
const r = @import("report.zig");

pub const Run = struct {
    ratings: [30]f64 = @splat(0),
    expected: [600]f64 = @splat(0),
    changes: [600]f64 = @splat(0),
    round_ratings: [40][30]f64 = @splat(@splat(0)),
};
pub fn expectedScore(home: f64, away: f64, advantage: f64) f64 {
    return 1 / (1 + std.math.pow(f64, 10, (away - home - advantage) / 400));
}
fn multiplier(match: s.Match, home: f64, away: f64, advantage: f64) f64 {
    const goals = @abs(match.margin);
    if (goals == 0) return 1;
    const difference = if (match.margin > 0) home + advantage - away else away - home - advantage;
    return @log(r.f(goals + 1)) * 2.2 / (0.001 * difference + 2.2);
}
pub fn run(n: usize, matches: []const s.Match, k: i64, home: i64, initial: i64) Run {
    var result: Run = .{};
    @memset(result.ratings[0..n], r.f(initial));
    for (matches, 0..) |match, i| {
        const first = result.ratings[match.home];
        const second = result.ratings[match.away];
        const expected = expectedScore(first, second, r.f(home));
        const weight = multiplier(match, first, second, r.f(home));
        const change = r.f(k) * weight * (match.result() - expected);
        result.ratings[match.home] = first + change;
        result.ratings[match.away] = second - change;
        result.expected[i] = expected;
        result.changes[i] = change;
        if (i + 1 == matches.len or matches[i + 1].round != match.round) result.round_ratings[match.round - 1] = result.ratings;
    }
    return result;
}
