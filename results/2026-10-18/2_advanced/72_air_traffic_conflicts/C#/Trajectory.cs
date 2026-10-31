using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
public static class Trajectory {
    public record Vec(double x, double y, double z) {
        public Vec Minus(Vec other) { return new Vec(x - other.x, y - other.y, z - other.z); }
        public double Component(int axis) { return axis == 0 ? x : axis == 1 ? y : z; }
    }
    public record Segment(int number, int leg, string phase, double ts, double te, Vec start,
                          Vec velocity, Vec end) {}
    public record Passing(double time, int level) {}
    public record Built(List<Segment> segments, double arrival, double length,
                        List<Passing> waypointTimes) {}
    public record Observed(Vec position, Segment segment) {}
    public static Built Build(FlightPlans.Plan plan,
                              Dictionary<string, FlightPlans.AircraftType> types) {
        List<Segment> segments = new();
        List<Passing> times = new();
        double current = plan.departure + plan.delay, length = 0;
        int level = plan.level + plan.offset;
        times.Add(new Passing(current, level));
        FlightPlans.AircraftType type = types[plan.type];
        for (int leg = 1; leg < plan.waypoints.Count; leg++) {
            FlightPlans.Waypoint a = plan.waypoints[leg - 1], b = plan.waypoints[leg];
            int dx = b.x - a.x, dy = b.y - a.y;
            double distance = Math.Sqrt(dx * dx + dy * dy) / 10,
                   duration = distance * 3600 / plan.speed, vx = (dx / 10.0) / duration,
                   vy = (dy / 10.0) / duration, x = a.x / 10.0, y = a.y / 10.0;
            length += distance;
            int target = b.level < 0 ? level : b.level + plan.offset;
            Vec velocity = new Vec(vx, vy, 0),
                end = new Vec(b.x / 10.0, b.y / 10.0, target * 100.0);
            if (target == level)
                segments.Add(new Segment(segments.Count + 1, leg, "LVL", current,
                                         current + duration, new Vec(x, y, level * 100.0), velocity,
                                         end));
            else {
                bool climbing = target > level;
                int rate = climbing ? type.climb : type.descent;
                double vz = climbing ? rate / 60.0 : -(rate / 60.0),
                       change = Math.Abs((long)target - level) * 6000 / (double)rate;
                Vec corner = new Vec(x + vx * change, y + vy * change, target * 100.0);
                segments.Add(new Segment(segments.Count + 1, leg, climbing ? "CLB" : "DES", current,
                                         current + change, new Vec(x, y, level * 100.0),
                                         new Vec(vx, vy, vz), corner));
                segments.Add(new Segment(segments.Count + 1, leg, "LVL", current + change,
                                         current + duration, corner, velocity, end));
            }
            current = current + duration;
            level = target;
            times.Add(new Passing(current, level));
        }
        return new Built(segments, current, length, times);
    }
    public static Vec Position(Segment segment, double time) {
        double elapsed = time - segment.ts;
        return new Vec(segment.start.x + segment.velocity.x * elapsed,
                       segment.start.y + segment.velocity.y * elapsed,
                       segment.start.z + segment.velocity.z * elapsed);
    }
    public static Segment Active(Built trajectory, double time) {
        List<Segment> segments = trajectory.segments;
        if (!(segments[0].ts <= time && time < segments[^1].te))
            return null;
        foreach (Segment segment in segments)
            if (segment.ts <= time && time < segment.te)
                return segment;
        return null;
    }
    public static Observed Current(Built trajectory, double time) {
        Segment segment = Active(trajectory, time);
        return segment == null ? null : new Observed(Position(segment, time), segment);
    }
}
