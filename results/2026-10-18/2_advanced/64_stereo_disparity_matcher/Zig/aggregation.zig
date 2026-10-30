const d = @import("pgm_io.zig");
pub const directions = [8]d.Point{ .{ .x = 1, .y = 0 }, .{ .x = -1, .y = 0 }, .{ .x = 0, .y = 1 },
     .{ .x = 0, .y = -1 }, .{ .x = 1, .y = 1 }, .{ .x = -1, .y = -1 }, .{ .x = -1, .y = 1 },
     .{ .x = 1, .y = -1 } };
pub fn pathCosts(base: d.Volume, left: d.PGM, direction: d.Point, p: d.Params) d.Volume {
    const width = left.width;
    const height = left.height;
    const count = base.disparities;
    const out: d.Volume = .{ .values = d.alloc(i64, base.values.len), .pixels = base.pixels, .disparities = count };
    for (0..height) |iy| {
        const y = if (direction.y >= 0) iy else height - 1 - iy;
        for (0..width) |ix| {
            const x = if (direction.x >= 0) ix else width - 1 - ix;
            const index = y * width + x;
            const qx = d.n(x) - direction.x;
            const qy = d.n(y) - direction.y;
            if (qx < 0 or qx >= d.n(width) or qy < 0 or qy >= d.n(height)) {
                @memcpy(out.values[index * count ..][0..count], base.values[index * count ..][0..count]);
                continue;
            }
            const previous = d.u(qy) * width + d.u(qx);
            var minimum = out.values[previous * count];
            for (1..count) |disparity| minimum = @min(minimum, out.values[previous * count + disparity]);
            const difference: i64 = @intCast(@abs(left.pixels[index] - left.pixels[previous]));
            const penalty = @max(p.p1, @divTrunc(p.p2 * p.gamma, p.gamma + difference));
            for (0..count) |disparity| {
                var best = @min(out.values[previous * count + disparity], minimum + penalty);
                if (disparity > 0) best = @min(best, out.values[previous * count + disparity - 1] + p.p1);
                if (disparity + 1 < count) best = @min(best, out.values[previous * count + disparity + 1] + p.p1);
                out.values[index * count + disparity] = base.values[index * count + disparity] + best - minimum;
            }
        }
    }
    return out;
}
pub fn cumulativeCosts(base: d.Volume, left: d.PGM, p: d.Params) []const d.Volume {
    const out = d.alloc(d.Volume, p.paths);
    const total = d.alloc(i64, base.values.len);
    @memset(total, 0);
    for (0..p.paths) |i| {
        const path = pathCosts(base, left, directions[i], p);
        out[i] = .{ .values = d.alloc(i64, total.len), .pixels = base.pixels, .disparities = base.disparities };
        for (total, path.values, out[i].values) |*value, addition, *destination| {
            value.* += addition;
            destination.* = value.*;
        }
    }
    return out;
}
