const c = @import("ratings.zig");
pub fn clip(value: f64) f64 {
    return if (value < 1) 1 else if (value > 5) 5 else value;
}
pub fn rmse(errors: []const f64) f64 {
    var sum: f64 = 0;
    for (errors) |value| sum += value * value;
    return @sqrt(sum / c.f(errors.len));
}
pub fn mae(errors: []const f64) f64 {
    var sum: f64 = 0;
    for (errors) |value| sum += @abs(value);
    return sum / c.f(errors.len);
}
pub fn rankWeight(rank: usize) f64 {
    return 1 / @log2(c.f(rank + 1));
}
pub const RankingMetrics = struct { hits: usize = 0, recall: f64 = 0, ndcg: f64 = 0, ap: f64 = 0, rr: f64 = 0 };
pub fn rankingMetrics(list: []const usize, relevant: []const bool, nrelevant: usize, length: usize) RankingMetrics {
    var out: RankingMetrics = .{};
    var dcg: f64 = 0;
    var idcg: f64 = 0;
    var ap: f64 = 0;
    for (1..length + 1) |rank| if (relevant[list[rank - 1]]) {
        out.hits += 1;
        dcg += rankWeight(rank);
        ap += c.f(out.hits) / c.f(rank);
        if (out.rr == 0) out.rr = 1 / c.f(rank);
    };
    for (1..@min(length, nrelevant) + 1) |rank| idcg += rankWeight(rank);
    out.recall = c.f(out.hits) / c.f(nrelevant);
    out.ndcg = dcg / idcg;
    out.ap = ap / c.f(@min(length, nrelevant));
    return out;
}
