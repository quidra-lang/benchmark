const std = @import("std");
const d = @import("pgm_io.zig");
const refinement = @import("refinement.zig");
pub const Regions = struct { region: [3][]const usize, occluded: []const usize };
pub const Evaluation = struct { pixels: i64 = 0, valid: i64 = 0, bad1: i64 = 0, bad2: i64 = 0,
     error_sum: i64 = 0, exact: i64 = 0 };
pub fn truthRegions(truth: d.PGM) Regions {
    const width = truth.width;
    const height = truth.height;
    var regions: [3]std.ArrayList(usize) = .{ .empty, .empty, .empty };
    var occluded: std.ArrayList(usize) = .empty;
    for (truth.pixels, 0..) |g, index| {
        if (g == 0) continue;
        d.append(usize, &regions[1], index);
        const x = index % width;
        const y = index / width;
        const target = d.n(x) - g;
        var hidden = target < 0;
        for (0..width) |x2| {
            if (truth.pixels[y * width + x2] > g and d.n(x2) - truth.pixels[y * width + x2] == target) hidden = true;
        }
        if (hidden) d.append(usize, &occluded, index) else d.append(usize, &regions[0], index);
    }
    for (regions[0].items) |index| {
        const x = index % width;
        const y = index / width;
        var discontinuity = false;
        var dy: i64 = -1;
        while (dy <= 1) : (dy += 1) {
            var dx: i64 = -1;
            while (dx <= 1) : (dx += 1) {
                const xx = d.n(x) + dx;
                const yy = d.n(y) + dy;
                if (xx < 0 or xx >= d.n(width) or yy < 0 or yy >= d.n(height)) continue;
                const other = truth.pixels[d.u(yy) * width + d.u(xx)];
                if (other != 0 and @abs(other - truth.pixels[index]) >= 2) discontinuity = true;
            }
        }
        if (discontinuity) d.append(usize, &regions[2], index);
    }
    return .{ .region = .{ regions[0].items, regions[1].items, regions[2].items }, .occluded = occluded.items };
}
pub fn evaluate(image: []const i64, truth: []const i64, region: []const usize) Evaluation {
    var out: Evaluation = .{ .pixels = d.n(region.len) };
    for (region) |index| {
        if (image[index] == 0) {
            out.bad1 += 1;
            out.bad2 += 1;
            continue;
        }
        out.valid += 1;
        const difference: i64 = @intCast(@abs(image[index] - truth[index]));
        out.bad1 += @intFromBool(difference > 1);
        out.bad2 += @intFromBool(difference > 2);
        out.error_sum += difference;
        out.exact += @intFromBool(difference == 0);
    }
    return out;
}
pub fn ratio(numerator: i64, denominator: i64) []const u8 {
    if (denominator == 0) return "0/1 0.00";
    var a = numerator;
    var b = denominator;
    while (b != 0) {
        const next = @mod(a, b);
        a = b;
        b = next;
    }
    return d.fmt("{d}/{d} {s}", .{ @divTrunc(numerator, a), @divTrunc(denominator, a), refinement.twoDecimals(100 * numerator,
         denominator) });
}
