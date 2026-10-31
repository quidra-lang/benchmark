const std = @import("std");
const c = @import("pgm_io.zig");
const filters = @import("filters.zig");
pub const Corner = struct { point: c.Point, response: i64 };
pub const Result = struct { values: []const Corner, candidates: usize };
fn less(_: void, a: Corner, b: Corner) bool {
    if (a.response != b.response) return a.response > b.response;
    if (a.point.y != b.point.y) return a.point.y < b.point.y;
    return a.point.x < b.point.x;
}
pub fn detect(g: filters.Gradient, p: c.Params) Result {
    const response = c.Image.init(g.gx.width, g.gx.height);
    const half = @divTrunc(p.harris_window - 1, 2);
    for (0..response.height) |y| for (0..response.width) |x| {
        var xx: i64 = 0;
        var yy: i64 = 0;
        var xy: i64 = 0;
        var j = -half;
        while (j <= half) : (j += 1) {
            var i = -half;
            while (i <= half) : (i += 1) {
                const gx = filters.clamped(g.gx, c.n(x) + i, c.n(y) + j);
                const gy = filters.clamped(g.gy, c.n(x) + i, c.n(y) + j);
                xx += gx * gx;
                yy += gy * gy;
                xy += gx * gy;
            }
        }
        response.set(.{ .x = c.n(x), .y = c.n(y) }, xx * yy - xy * xy - @divFloor((xx + yy) * (xx + yy), 25));
    };
    var values: std.ArrayList(Corner) = .empty;
    for (0..response.height) |y| for (0..response.width) |x| {
        const point: c.Point = .{ .x = c.n(x), .y = c.n(y) };
        const value = response.at(point);
        if (value < p.harris_threshold) continue;
        var peak = true;
        for (c.offsets) |dy| {
            for (c.offsets) |dx| {
                const other: c.Point = .{ .x = point.x + dx, .y = point.y + dy };
                if ((dx == 0 and dy == 0) or !response.inside(other)) continue;
                const comparison = response.at(other);
                const earlier = other.y < point.y or (other.y == point.y and other.x < point.x);
                if (value < comparison or (value == comparison and earlier)) {
                    peak = false;
                    break;
                }
            }
            if (!peak) break;
        }
        if (peak) c.append(Corner, &values, .{ .point = point, .response = value });
    };
    const candidates = values.items.len;
    std.mem.sort(Corner, values.items, {}, less);
    return .{ .values = values.items[0..@min(values.items.len, c.u(p.corner_count))], .candidates = candidates };
}
