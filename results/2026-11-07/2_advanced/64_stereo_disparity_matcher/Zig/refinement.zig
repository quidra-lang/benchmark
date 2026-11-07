const d = @import("pgm_io.zig");
pub fn hundredths(value: i64) []const u8 {
    return d.fmt("{d}.{d:0>2}", .{ @divTrunc(value, 100), @mod(value, 100) });
}
pub fn twoDecimals(numerator: i64, denominator: i64) []const u8 {
    return hundredths(@divTrunc(200 * numerator + denominator, 2 * denominator));
}
pub fn depthHundredths(disparity: i64, focal: i64, baseline: i64) i64 {
    return @divTrunc(200 * focal * baseline + disparity, 2 * disparity);
}
pub const Refined = struct { disparity: []const u8, depth: []const u8 };
pub fn subpixel(disparity: i64, costs: []const i64, p: d.Params) Refined {
    const index = d.u(disparity) - p.minimum;
    var a: i64 = 0;
    var b: i64 = 1;
    if (d.n(p.minimum) < disparity and disparity < d.n(p.maximum) and costs[index - 1] > costs[index] and costs[index + 1] >= costs[index]) {
        a = costs[index - 1] - costs[index + 1];
        b = 2 * (costs[index - 1] - 2 * costs[index] + costs[index + 1]);
    }
    const rounded = @divTrunc(200 * (disparity * b + a) + b, 2 * b);
    return .{ .disparity = hundredths(rounded), .depth = twoDecimals(100 * p.focal * p.baseline, rounded) };
}
