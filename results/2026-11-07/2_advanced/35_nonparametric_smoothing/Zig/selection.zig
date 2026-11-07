pub fn looScore(observed: []const f64, predictions: []const ?f64) ?f64 {
    var total: f64 = 0;
    for (observed, predictions) |value, prediction| {
        const fit = prediction orelse return null;
        const difference = value - fit;
        total += difference * difference;
    }
    return total / @as(f64, @floatFromInt(observed.len));
}
pub fn gcvScore(observed: []const f64, fitted: []const f64, edf: f64) f64 {
    var rss: f64 = 0;
    for (observed, fitted) |value, fit| {
        const difference = value - fit;
        rss += difference * difference;
    }
    const count: f64 = @floatFromInt(observed.len);
    const tau = 1 - edf / count;
    return rss / count / (tau * tau);
}
pub fn selected(scores: []const ?f64) usize {
    var best: ?usize = null;
    for (scores, 0..) |score, i| if (score != null and (best == null or score.? < scores[best.?].?)) {
        best = i;
    };
    return best.?;
}
