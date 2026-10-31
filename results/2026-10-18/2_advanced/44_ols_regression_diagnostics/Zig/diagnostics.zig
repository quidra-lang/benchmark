const std = @import("std");
const c = @import("dataframe.zig");
const qr = @import("qr_solver.zig");
const inference = @import("inference.zig");
pub const Diagnostics = struct { standardized: c.Vector, studentized: c.Vector, cooks: c.Vector, dffits: c.Vector,
     flags: []const []const u8, dfbetas: c.Matrix, flag_counts: [4]usize = std.mem.zeroes([4]usize),
     any: usize = 0, durbin: f64 = 0, bp: f64 = 0, bp_p: f64 = 0, jb: f64 = 0, jb_p: f64 = 0, skewness: f64 = 0,
     kurtosis: f64 = 0, bp_df: usize = 0 };
pub fn diagnostics(x: c.Matrix, model: qr.Fit, params: c.Params) Diagnostics {
    const n = x.len;
    const r = model.rank;
    const df = n - r;
    const sigma = @sqrt(model.rss / c.f(df));
    const flags = c.alloc([]const u8, n);
    var out: Diagnostics = .{ .standardized = c.vector(n), .studentized = c.vector(n), .cooks = c.vector(n),
         .dffits = c.vector(n), .flags = flags, .dfbetas = c.matrix(n, r) };
    for (0..n) |i| {
        const h = model.leverage[i];
        const eps = model.weighted_residuals[i];
        const z = eps / (sigma * @sqrt(1 - h));
        const student = z * @sqrt(c.f(df - 1) / (c.f(df) - z * z));
        out.standardized[i] = z;
        out.studentized[i] = student;
        out.cooks[i] = z * z * h / (c.f(r) * (1 - h));
        out.dffits[i] = student * @sqrt(h / (1 - h));
        const decisions = [_]bool{ h > params.leverage * c.f(r) / c.f(n), @abs(student) > params.studentized,
             out.cooks[i] > params.cook / c.f(n), @abs(out.dffits[i]) > params.dffits * @sqrt(c.f(r) / c.f(n)) };
        var flag_text: c.Text = .{};
        for (decisions, 0..) |marked, j| if (marked) {
            out.flag_counts[j] += 1;
            flag_text.add("{c}", .{"HOCF"[j]});
        };
        if (flag_text.value().len == 0) flags[i] = "-" else {
            flags[i] = flag_text.value();
            out.any += 1;
        }
        const deleted_sigma = sigma * @sqrt((c.f(df) - z * z) / c.f(df - 1));
        for (0..r) |k| out.dfbetas[i][k] = model.g[i][k] * eps / (1 - h) / (deleted_sigma * @sqrt(model.variance[k]));
    }
    var difference_sum: f64 = 0;
    for (1..n) |i| {
        const difference = model.weighted_residuals[i] - model.weighted_residuals[i - 1];
        difference_sum += difference * difference;
    }
    out.durbin = difference_sum / model.rss;
    const accepted = c.matrix(n, r);
    const square = c.vector(n);
    const ones = c.vector(n);
    @memset(ones, 1);
    var square_sum: f64 = 0;
    for (0..n) |i| {
        square[i] = model.weighted_residuals[i] * model.weighted_residuals[i];
        square_sum += square[i];
        for (model.accepted, 0..) |column, k| accepted[i][k] = x[i][column];
    }
    const auxiliary = qr.fit(accepted, square, ones, params.rank_tol);
    const mean = square_sum / c.f(n);
    var tss: f64 = 0;
    for (square) |value| tss += (value - mean) * (value - mean);
    out.bp = c.f(n) * (1 - auxiliary.rss / tss);
    out.bp_df = auxiliary.rank - 1;
    out.bp_p = inference.pChi(out.bp, c.f(out.bp_df));
    var eps_sum: f64 = 0;
    for (model.weighted_residuals) |value| eps_sum += value;
    const eps_mean = eps_sum / c.f(n);
    var second: f64 = 0;
    var third: f64 = 0;
    var fourth: f64 = 0;
    for (model.weighted_residuals) |value| {
        const delta = value - eps_mean;
        second += delta * delta;
        third += delta * delta * delta;
        fourth += delta * delta * delta * delta;
    }
    second /= c.f(n);
    third /= c.f(n);
    fourth /= c.f(n);
    out.skewness = third / (second * @sqrt(second));
    out.kurtosis = fourth / (second * second);
    out.jb = c.f(n) / 6 * (out.skewness * out.skewness + (out.kurtosis - 3) * (out.kurtosis - 3) / 4);
    out.jb_p = inference.pChi(out.jb, 2);
    return out;
}
