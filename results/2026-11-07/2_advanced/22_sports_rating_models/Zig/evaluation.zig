const s = @import("season.zig");
const r = @import("report.zig");

pub const Link = struct { alpha: f64 = 0, beta: f64 = 0 };
pub fn sigma(value: f64) f64 { return 1 / (1 + @exp(-value)); }
pub fn fitLink(features: []const f64, matches: []const s.Match, iterations: usize) Link {
    var link: Link = .{};
    for (0..iterations) |_| {
        var g0: f64 = 0;
        var g1: f64 = 0;
        var h00: f64 = 0;
        var h01: f64 = 0;
        var h11: f64 = 0;
        for (features, matches) |z, match| {
            const y = match.result();
            const p = sigma(link.alpha + link.beta * z);
            const w = p * (1 - p);
            g0 += y - p;
            g1 += (y - p) * z;
            h00 += w;
            h01 += w * z;
            h11 += w * z * z;
        }
        const determinant = h00 * h11 - h01 * h01;
        link.alpha += (h11 * g0 - h01 * g1) / determinant;
        link.beta += (h00 * g1 - h01 * g0) / determinant;
    }
    return link;
}
pub fn logLoss(probability: f64, y2: i64) f64 {
    if (y2 == 2) return -@log(probability);
    if (y2 == 0) return -@log(1 - probability);
    return -(@log(probability) / 2 + @log(1 - probability) / 2);
}
pub fn brierScore(probability: f64, y2: i64) f64 {
    const difference = probability - r.f(y2) / 2;
    return difference * difference;
}
pub fn correctness(probability: f64, y2: i64) i64 {
    if (y2 == 1) return 1;
    return if ((probability > 0.5 and y2 == 2) or (probability < 0.5 and y2 == 0)) 2 else 0;
}
pub fn kendallTau(first: []const r.Comparison, second: []const r.Comparison) r.Fraction {
    var balance: i64 = 0;
    for (0..first.len) |i| {
        for (i + 1..first.len) |j| {
            const a = first[i].compare(first[j]);
            const b = second[i].compare(second[j]);
            if (a != .eq and b != .eq) balance += if (a == b) @as(i64, 1) else -1;
        }
    }
    return r.Fraction.init(balance, @divTrunc(r.n(first.len) * r.n(first.len - 1), 2));
}
fn averageRanks(values: []const r.Comparison) [30]i64 {
    var doubled: [30]i64 = @splat(0);
    for (values, 0..) |value, i| {
        var greater: i64 = 0;
        var equal: i64 = 0;
        for (values) |other| {
            const order = other.compare(value);
            greater += @intFromBool(order == .gt);
            equal += @intFromBool(order == .eq);
        }
        doubled[i] = 2 * greater + equal + 1;
    }
    return doubled;
}
pub fn spearmanRho(first: []const r.Comparison, second: []const r.Comparison) r.Fraction {
    const first_ranks = averageRanks(first);
    const second_ranks = averageRanks(second);
    const count = r.n(first.len);
    const denominator = count * (count * count - 1) * 4;
    var squares: i64 = 0;
    for (0..first.len) |i| {
        const difference = first_ranks[i] - second_ranks[i];
        squares += difference * difference;
    }
    return r.Fraction.init(denominator - 6 * squares, denominator);
}
