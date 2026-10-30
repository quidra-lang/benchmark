import java.util.*;
final class Trajectory {
    record Vec(double x, double y, double z) {
        Vec minus(Vec other) { return new Vec(x - other.x, y - other.y, z - other.z); }
        double component(int axis) { return axis == 0 ? x : axis == 1 ? y : z; }
    }
    record Segment(int number, int leg, String phase, double ts, double te, Vec start, Vec velocity,
                   Vec end) {}
    record Passing(double time, int level) {}
    record
        Built(List<Segment> segments, double arrival, double length, List<Passing> waypointTimes) {}
    record Observed(Vec position, Segment segment) {}
    static Built build(FlightPlans.Plan plan, Map<String, FlightPlans.AircraftType> types) {
        List<Segment> segments = new ArrayList<>();
        List<Passing> times = new ArrayList<>();
        double current = plan.departure + plan.delay, length = 0;
        int level = plan.level + plan.offset;
        times.add(new Passing(current, level));
        FlightPlans.AircraftType type = types.get(plan.type);
        for (int leg = 1; leg < plan.waypoints.size(); leg++) {
            FlightPlans.Waypoint a = plan.waypoints.get(leg - 1), b = plan.waypoints.get(leg);
            int dx = b.x() - a.x(), dy = b.y() - a.y();
            double distance = Math.sqrt(dx * dx + dy * dy) / 10,
                   duration = distance * 3600 / plan.speed, vx = (dx / 10.0) / duration,
                   vy = (dy / 10.0) / duration, x = a.x() / 10.0, y = a.y() / 10.0;
            length += distance;
            int target = b.level() < 0 ? level : b.level() + plan.offset;
            Vec velocity = new Vec(vx, vy, 0),
                end = new Vec(b.x() / 10.0, b.y() / 10.0, target * 100.0);
            if (target == level)
                segments.add(new Segment(segments.size() + 1, leg, "LVL", current,
                                         current + duration, new Vec(x, y, level * 100.0), velocity,
                                         end));
            else {
                boolean climbing = target > level;
                int rate = climbing ? type.climb() : type.descent();
                double vz = climbing ? rate / 60.0 : -(rate / 60.0),
                       change = Math.abs((long)target - level) * 6000 / (double)rate;
                Vec corner = new Vec(x + vx * change, y + vy * change, target * 100.0);
                segments.add(new Segment(segments.size() + 1, leg, climbing ? "CLB" : "DES",
                                         current, current + change, new Vec(x, y, level * 100.0),
                                         new Vec(vx, vy, vz), corner));
                segments.add(new Segment(segments.size() + 1, leg, "LVL", current + change,
                                         current + duration, corner, velocity, end));
            }
            current = current + duration;
            level = target;
            times.add(new Passing(current, level));
        }
        return new Built(segments, current, length, times);
    }
    static Vec position(Segment segment, double time) {
        double elapsed = time - segment.ts();
        return new Vec(segment.start().x() + segment.velocity().x() * elapsed,
                       segment.start().y() + segment.velocity().y() * elapsed,
                       segment.start().z() + segment.velocity().z() * elapsed);
    }
    static Segment active(Built trajectory, double time) {
        List<Segment> segments = trajectory.segments();
        if (!(segments.getFirst().ts() <= time && time < segments.getLast().te()))
            return null;
        for (Segment segment : segments)
            if (segment.ts() <= time && time < segment.te())
                return segment;
        return null;
    }
    static Observed current(Built trajectory, double time) {
        Segment segment = active(trajectory, time);
        return segment == null ? null : new Observed(position(segment, time), segment);
    }
}
