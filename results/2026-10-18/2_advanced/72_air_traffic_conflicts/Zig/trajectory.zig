const d = @import("flight_plans.zig");
pub const Point = [3]f64;
pub const Phase = enum { climb, descent, level };
pub fn phaseName(phase: Phase) []const u8 {
    return switch (phase) {
        .climb => "CLB",
        .descent => "DES",
        .level => "LVL",
    };
}
pub const Segment = struct { number: usize, leg: usize, phase: Phase, start_time: f64, end_time: f64,
     start: Point, velocity: Point, end: Point };
pub const Passing = struct { time: f64, level: i64 };
pub const Trajectory = struct {
    segments: [14]Segment = undefined,
    count: usize = 0,
    arrival: f64 = 0,
    length: f64 = 0,
    passing: [8]Passing = undefined,
    fn add(self: *Trajectory, leg: usize, phase: Phase, first: f64, last: f64, start: Point,
         velocity: Point, end: Point) void {
        self.segments[self.count] = .{ .number = self.count + 1, .leg = leg, .phase = phase,
             .start_time = first, .end_time = last, .start = start, .velocity = velocity, .end = end };
        self.count += 1;
    }
};
pub fn build(plan: d.Plan, types: []const d.AircraftType) Trajectory {
    var out: Trajectory = .{};
    var current = d.f(plan.departure + plan.delay);
    var level = plan.level + plan.offset;
    out.passing[0] = .{ .time = current, .level = level };
    for (1..plan.waypoints.len) |leg| {
        const p = plan.waypoints[leg - 1];
        const q = plan.waypoints[leg];
        const dx = q.x - p.x;
        const dy = q.y - p.y;
        const length = @sqrt(d.f(dx * dx + dy * dy)) / 10;
        const duration = length * 3600 / d.f(plan.speed);
        const vx = (d.f(dx) / 10) / duration;
        const vy = (d.f(dy) / 10) / duration;
        out.length += length;
        const target = if (q.level) |value| value + plan.offset else level;
        const first: Point = .{ d.f(p.x) / 10, d.f(p.y) / 10, d.f(level * 100) };
        const last: Point = .{ d.f(q.x) / 10, d.f(q.y) / 10, d.f(target * 100) };
        if (target == level) out.add(leg, .level, current, current + duration, first, .{ vx, vy, 0 }, last) else {
            const climbing = target > level;
            const rate = if (climbing) types[plan.type_index].climb else types[plan.type_index].descent;
            const vz = if (climbing) d.f(rate) / 60 else -(d.f(rate) / 60);
            const change = d.f(d.n(@abs(target - level)) * 6000) / d.f(rate);
            const middle: Point = .{ first[0] + vx * change, first[1] + vy * change, d.f(target * 100) };
            out.add(leg, if (climbing) .climb else .descent, current, current + change, first, .{ vx, vy, vz }, middle);
            out.add(leg, .level, current + change, current + duration, middle, .{ vx, vy, 0 }, last);
        }
        current = current + duration;
        level = target;
        out.passing[leg] = .{ .time = current, .level = level };
    }
    out.arrival = current;
    return out;
}
pub fn position(segment: Segment, time: f64) Point {
    var out: Point = undefined;
    for (0..3) |i| out[i] = segment.start[i] + segment.velocity[i] * (time - segment.start_time);
    return out;
}
pub fn activeSegment(trajectory: *const Trajectory, time: f64) ?Segment {
    if (!(trajectory.segments[0].start_time <= time and time < trajectory.segments[trajectory.count - 1].end_time)) return null;
    for (trajectory.segments[0..trajectory.count]) |segment| if (segment.start_time <= time and time < segment.end_time) return segment;
    return null;
}
