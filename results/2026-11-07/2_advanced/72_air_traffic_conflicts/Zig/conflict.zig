const std = @import("std");
const d = @import("flight_plans.zig");
const t = @import("trajectory.zig");
pub const Pair = [2]usize;
pub const Loss = struct { low: f64, high: f64, time: f64, distance: f64, vertical: f64 };
pub fn lossInterval(p: t.Point, w: t.Point, first: f64, last: f64, horizontal: f64, vertical: f64) ?Loss {
    const qa = w[0] * w[0] + w[1] * w[1];
    const qb = 2 * (p[0] * w[0] + p[1] * w[1]);
    const qc = (p[0] * p[0] + p[1] * p[1]) - horizontal * horizontal;
    var low = first;
    var high = last;
    if (qa < 1e-12) {
        if (qc >= 0) return null;
    } else {
        const discriminant = qb * qb - 4 * qa * qc;
        if (discriminant <= 0) return null;
        const root = @sqrt(discriminant);
        low = @max(low, first + (-qb - root) / (2 * qa));
        high = @min(high, first + (-qb + root) / (2 * qa));
    }
    if (w[2] == 0) {
        if (@abs(p[2]) >= vertical) return null;
    } else {
        const r1 = (-vertical - p[2]) / w[2];
        const r2 = (vertical - p[2]) / w[2];
        low = @max(low, first + @min(r1, r2));
        high = @min(high, first + @max(r1, r2));
    }
    if (high - low <= 1e-6) return null;
    var time = if (qa >= 1e-12) first + (-qb / (2 * qa)) else first;
    time = @min(@max(time, low), high);
    const tau = time - first;
    const ex = p[0] + w[0] * tau;
    const ey = p[1] + w[1] * tau;
    return .{ .low = low, .high = high, .time = time, .distance = @sqrt(ex * ex + ey * ey),
         .vertical = @abs(p[2] + w[2] * tau) };
}
pub const Piece = struct { first_segment: usize, second_segment: usize, loss: Loss };
pub const Conflict = struct { pair: Pair, start: f64, end: f64, pieces: []const Piece, closest: Piece,
     first_level: f64 = 0, second_level: f64 = 0, first_track: f64 = 0, second_track: f64 = 0,
     angle: f64 = 0, geometry: usize = 0, severity: usize = 0, sector: ?usize = null, outcome: usize = 0 };
fn append(comptime T: type, allocator: std.mem.Allocator, list: *std.ArrayList(T), value: T) void {
    list.append(allocator, value) catch @panic("allocation failed");
}
pub fn before(left: Conflict, right: Conflict) bool {
    return left.start < right.start or (left.start == right.start and (left.pair[0] < right.pair[0] or (left.pair[0] == right.pair[0] and left.pair[1] < right.pair[1])));
}
pub fn pairConflicts(allocator: std.mem.Allocator, first: usize, ta: *const t.Trajectory, second: usize,
     tb: *const t.Trajectory, params: d.Params) []Conflict {
    var pieces: [196]Piece = undefined;
    var count: usize = 0;
    for (ta.segments[0..ta.count], 0..) |a, i| for (tb.segments[0..tb.count], 0..) |b, j| {
        const t1 = @max(a.start_time, b.start_time);
        const t2 = @min(a.end_time, b.end_time);
        if (t1 >= t2) continue;
        const pa = t.position(a, t1);
        const pb = t.position(b, t1);
        var relative: t.Point = undefined;
        var velocity: t.Point = undefined;
        for (0..3) |axis| {
            relative[axis] = pa[axis] - pb[axis];
            velocity[axis] = a.velocity[axis] - b.velocity[axis];
        }
        if (lossInterval(relative, velocity, t1, t2, d.f(params.horizontal), d.f(params.vertical))) |loss| {
            const piece: Piece = .{ .first_segment = i, .second_segment = j, .loss = loss };
            var k = count;
            count += 1;
            while (k > 0 and piece.loss.low < pieces[k - 1].loss.low) : (k -= 1) pieces[k] = pieces[k - 1];
            pieces[k] = piece;
        }
    };
    var out: std.ArrayList(Conflict) = .empty;
    var groups: std.ArrayList(Piece) = .empty;
    for (pieces[0..count]) |piece| {
        if (out.items.len == 0 or piece.loss.low - out.items[out.items.len - 1].end > 1e-6) {
            if (out.items.len > 0) out.items[out.items.len - 1].pieces = groups.items;
            groups = .empty;
            append(Piece, allocator, &groups, piece);
            append(Conflict, allocator, &out, .{ .pair = .{ first, second }, .start = piece.loss.low,
                 .end = piece.loss.high, .pieces = &.{}, .closest = piece });
        } else {
            append(Piece, allocator, &groups, piece);
            const item = &out.items[out.items.len - 1];
            item.end = piece.loss.high;
            if (piece.loss.distance < item.closest.loss.distance - 1e-9) item.closest = piece;
        }
    }
    if (out.items.len > 0) out.items[out.items.len - 1].pieces = groups.items;
    return out.items;
}
pub fn allConflicts(allocator: std.mem.Allocator, trajectories: []const t.Trajectory, params: d.Params) []Conflict {
    var out: std.ArrayList(Conflict) = .empty;
    for (0..trajectories.len) |a| for (a + 1..trajectories.len) |b| {
        for (pairConflicts(allocator, a, &trajectories[a], b, &trajectories[b], params)) |item| append(Conflict,
             allocator, &out, item);
    };
    const Context = struct {
        fn less(_: void, left: Conflict, right: Conflict) bool {
            return before(left, right);
        }
    };
    std.mem.sort(Conflict, out.items, {}, Context.less);
    return out.items;
}
