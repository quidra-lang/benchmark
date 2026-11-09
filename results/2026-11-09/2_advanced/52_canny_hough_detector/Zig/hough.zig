const std = @import("std");
const c = @import("pgm_io.zig");
pub fn circlePoints(radius: i64) []const c.Point {
    var points: std.ArrayList(c.Point) = .empty;
    var a = radius;
    var b: i64 = 0;
    var error_value = 1 - radius;
    while (a >= b) {
        const candidates = [_]c.Point{ .{ .x = a, .y = b }, .{ .x = b, .y = a }, .{ .x = -b, .y = a },
             .{ .x = -a, .y = b }, .{ .x = -a, .y = -b }, .{ .x = -b, .y = -a }, .{ .x = b, .y = -a },
             .{ .x = a, .y = -b } };
        for (candidates) |point| {
            var present = false;
            for (points.items) |known| if (point.x == known.x and point.y == known.y) {
                present = true;
            };
            if (!present) c.append(c.Point, &points, point);
        }
        b += 1;
        if (error_value < 0) error_value += 2 * b + 1 else {
            a -= 1;
            error_value += 2 * (b - a) + 1;
        }
    }
    return points.items;
}
pub const CirclePeak = struct { radius: i64, center: c.Point, votes: i64, points: i64 };
pub const CircleVotes = struct { offsets: []const []const c.Point, votes: []c.Image, peaks: []const CirclePeak,
     candidates: i64 = 0 };
fn circleLess(_: void, a: CirclePeak, b: CirclePeak) bool {
    const left = a.votes * b.points;
    const right = b.votes * a.points;
    if (left != right) return left > right;
    if (a.radius != b.radius) return a.radius < b.radius;
    if (a.center.y != b.center.y) return a.center.y < b.center.y;
    return a.center.x < b.center.x;
}
pub fn circleVotes(edges: c.Image, p: c.Params) CircleVotes {
    const radii = c.u(p.r_max - p.r_min + 1);
    const offsets = c.alloc([]const c.Point, radii);
    const votes = c.alloc(c.Image, radii);
    for (0..radii) |r| {
        offsets[r] = circlePoints(c.n(r) + p.r_min);
        votes[r] = c.Image.init(edges.width, edges.height);
        for (0..edges.height) |y| for (0..edges.width) |x| {
            if (edges.at(.{ .x = c.n(x), .y = c.n(y) }) == 0) continue;
            for (offsets[r]) |offset| {
                const center: c.Point = .{ .x = c.n(x) + offset.x, .y = c.n(y) + offset.y };
                if (edges.inside(center)) votes[r].set(center, votes[r].at(center) + 1);
            }
        };
    }
    var out: CircleVotes = .{ .offsets = offsets, .votes = votes, .peaks = &.{} };
    var peaks: std.ArrayList(CirclePeak) = .empty;
    for (0..radii) |r| for (0..edges.height) |y| for (0..edges.width) |x| {
        const point: c.Point = .{ .x = c.n(x), .y = c.n(y) };
        const count = c.n(offsets[r].len);
        const value = votes[r].at(point);
        if (100 * value < p.circle_percent * count) continue;
        out.candidates += 1;
        var peak = true;
        var rr = c.n(r) - 2;
        while (rr <= c.n(r) + 2 and peak) : (rr += 1) {
            if (rr < 0 or rr >= c.n(radii)) continue;
            var yy = c.n(y) - 2;
            while (yy <= c.n(y) + 2 and peak) : (yy += 1) {
                if (yy < 0 or yy >= c.n(edges.height)) continue;
                var xx = c.n(x) - 2;
                while (xx <= c.n(x) + 2) : (xx += 1) {
                    if (xx < 0 or xx >= c.n(edges.width) or (rr == c.n(r) and yy == c.n(y) and xx == c.n(x))) continue;
                    const left = value * c.n(offsets[c.u(rr)].len);
                    const right = votes[c.u(rr)].at(.{ .x = xx, .y = yy }) * count;
                    const earlier = rr < c.n(r) or (rr == c.n(r) and (yy < c.n(y) or (yy == c.n(y) and xx < c.n(x))));
                    if (left < right or (left == right and earlier)) {
                        peak = false;
                        break;
                    }
                }
            }
        }
        if (peak) c.append(CirclePeak, &peaks, .{ .radius = c.n(r) + p.r_min, .center = point, .votes = value, .points = count });
    };
    std.mem.sort(CirclePeak, peaks.items, {}, circleLess);
    out.peaks = peaks.items;
    return out;
}
pub fn rho(point: c.Point, theta: i64, trig: *const c.Trig, p: c.Params) i64 {
    return @divFloor(point.x * trig[c.u(theta)][0] + point.y * trig[c.u(theta)][1], 16384 * p.rho_step);
}
pub const LinePeak = struct { theta: i64, rho: i64, votes: i64 };
pub const LineVotes = struct { low: i64 = 0, high: i64 = 0, maximum: i64 = 0, votes: c.Image, peaks: []const LinePeak };
fn lineLess(_: void, a: LinePeak, b: LinePeak) bool {
    if (a.votes != b.votes) return a.votes > b.votes;
    if (a.theta != b.theta) return a.theta < b.theta;
    return a.rho < b.rho;
}
pub fn lineVotes(edges: c.Image, trig: *const c.Trig, p: c.Params) LineVotes {
    var low: i64 = 0;
    var high: i64 = 0;
    const corners = [_]c.Point{ .{ .x = 0, .y = 0 }, .{ .x = c.n(edges.width) - 1, .y = 0 }, .{ .x = 0,
         .y = c.n(edges.height) - 1 }, .{ .x = c.n(edges.width) - 1, .y = c.n(edges.height) - 1 } };
    for (0..180) |theta| for (corners) |point| {
        const value = rho(point, c.n(theta), trig, p);
        low = @min(low, value);
        high = @max(high, value);
    };
    const votes = c.Image.init(180, c.u(high - low + 1));
    for (0..edges.height) |y| for (0..edges.width) |x| {
        const point: c.Point = .{ .x = c.n(x), .y = c.n(y) };
        if (edges.at(point) == 0) continue;
        for (0..180) |theta| {
            const target: c.Point = .{ .x = c.n(theta), .y = rho(point, c.n(theta), trig, p) - low };
            votes.set(target, votes.at(target) + 1);
        }
    };
    var maximum: i64 = 0;
    for (votes.data) |value| maximum = @max(maximum, value);
    var peaks: std.ArrayList(LinePeak) = .empty;
    for (0..180) |theta| {
        const t = c.n(theta);
        var r = low;
        while (r <= high) : (r += 1) {
            const value = votes.at(.{ .x = t, .y = r - low });
            if (value < p.vote_threshold) continue;
            var peak = true;
            var tt = t - 2;
            while (tt <= t + 2 and peak) : (tt += 1) {
                var rr = r - 2;
                while (rr <= r + 2) : (rr += 1) {
                    if (tt == t and rr == r) continue;
                    const other = if (tt >= 0 and tt < 180 and rr >= low and rr <= high) votes.at(.{ .x = tt,
                         .y = rr - low }) else 0;
                    const earlier = tt < t or (tt == t and rr < r);
                    if (value < other or (value == other and earlier)) {
                        peak = false;
                        break;
                    }
                }
            }
            if (peak) c.append(LinePeak, &peaks, .{ .theta = t, .rho = r, .votes = value });
        }
    }
    std.mem.sort(LinePeak, peaks.items, {}, lineLess);
    return .{ .low = low, .high = high, .maximum = maximum, .votes = votes, .peaks = peaks.items };
}
