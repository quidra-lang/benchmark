const s = @import("season.zig");
const r = @import("report.zig");

pub const BradleyTerry = struct { strengths: [30]f64, theta: f64 };
pub fn bradleyTerry(n: usize, matches: []const s.Match, iterations: usize) BradleyTerry {
    var wins: [30]i64 = @splat(0);
    var home_wins: i64 = 0;
    for (matches) |match| {
        wins[match.home] += match.y2;
        wins[match.away] += 2 - match.y2;
        home_wins += match.y2;
    }
    var strengths: [30]f64 = @splat(1);
    var theta: f64 = 1;
    for (0..iterations) |_| {
        var zeta: [30]f64 = @splat(0);
        for (matches) |match| {
            const denominator = theta * strengths[match.home] + strengths[match.away];
            zeta[match.home] += theta / denominator;
            zeta[match.away] += 1 / denominator;
        }
        for (0..n) |i| strengths[i] = (r.f(wins[i]) / 2) / zeta[i];
        var total: f64 = 0;
        for (strengths[0..n]) |strength| total += strength;
        for (0..n) |i| strengths[i] = strengths[i] * r.f(n) / total;
        var denominator: f64 = 0;
        for (matches) |match| denominator += strengths[match.home] / (theta * strengths[match.home] + strengths[match.away]);
        theta = (r.f(home_wins) / 2) / denominator;
    }
    return .{ .strengths = strengths, .theta = theta };
}

pub const OffenseDefense = struct { offense: [30]f64, defense: [30]f64, ratings: [30]f64 };
pub fn offenseDefense(n: usize, matches: []const s.Match, iterations: usize) OffenseDefense {
    var points: [30][30]i64 = @splat(@splat(0));
    for (matches) |match| {
        points[match.home][match.away] += match.away_score;
        points[match.away][match.home] += match.home_score;
    }
    var offense: [30]f64 = @splat(0);
    var defense: [30]f64 = @splat(1);
    for (0..iterations) |_| {
        for (0..n) |j| {
            var total: f64 = 0;
            for (0..n) |i| total += r.f(points[i][j]) / defense[i];
            offense[j] = total;
        }
        for (0..n) |i| {
            var total: f64 = 0;
            for (0..n) |j| total += r.f(points[i][j]) / offense[j];
            defense[i] = total;
        }
    }
    var ratings: [30]f64 = @splat(0);
    for (0..n) |i| ratings[i] = offense[i] / defense[i];
    return .{ .offense = offense, .defense = defense, .ratings = ratings };
}
