#include "airspace.hpp"
std::string phase_name(Phase phase) {
    return phase == Phase::Climb ? "CLB" : phase == Phase::Descent ? "DES" : "LVL";
}
Trajectory build_trajectory(const Plan &plan, const std::vector<AircraftType> &types) {
    Trajectory out;
    double current = double(plan.departure + plan.delay);
    Integer level = plan.level + plan.offset;
    out.length = 0;
    out.passing.push_back({current, level});
    for (int leg = 1; leg < int(plan.waypoints.size()); ++leg) {
        const Waypoint &p = plan.waypoints[leg - 1], &q = plan.waypoints[leg];
        int dx = q.x - p.x, dy = q.y - p.y;
        double length = std::sqrt(double(dx * dx + dy * dy)) / 10,
               duration = length * 3600 / plan.speed, vx = (double(dx) / 10) / duration,
               vy = (double(dy) / 10) / duration;
        out.length += length;
        Integer target = q.level ? *q.level + plan.offset : level;
        Point first = {double(p.x) / 10, double(p.y) / 10, double(level * 100)},
              last = {double(q.x) / 10, double(q.y) / 10, double(target * 100)};
        if (target == level)
            out.segments.push_back({int(out.segments.size()) + 1,
                                    leg,
                                    Phase::Level,
                                    current,
                                    current + duration,
                                    first,
                                    {vx, vy, 0},
                                    last});
        else {
            bool climbing = target > level;
            int rate = climbing ? types[plan.type].climb : types[plan.type].descent;
            double vz = climbing ? double(rate) / 60 : -(double(rate) / 60),
                   change = double(std::abs(target - level) * 6000) / rate;
            Point middle = {first[0] + vx * change, first[1] + vy * change, double(target * 100)};
            out.segments.push_back({int(out.segments.size()) + 1,
                                    leg,
                                    climbing ? Phase::Climb : Phase::Descent,
                                    current,
                                    current + change,
                                    first,
                                    {vx, vy, vz},
                                    middle});
            out.segments.push_back({int(out.segments.size()) + 1,
                                    leg,
                                    Phase::Level,
                                    current + change,
                                    current + duration,
                                    middle,
                                    {vx, vy, 0},
                                    last});
        }
        current = current + duration;
        level = target;
        out.passing.push_back({current, level});
    }
    out.arrival = current;
    return out;
}
Point position(const Segment &segment, double time) {
    Point out;
    for (int i = 0; i < 3; ++i)
        out[i] = segment.start[i] + segment.velocity[i] * (time - segment.start_time);
    return out;
}
const Segment *active_segment(const Trajectory &trajectory, double time) {
    if (!(trajectory.segments.front().start_time <= time &&
          time < trajectory.segments.back().end_time))
        return nullptr;
    for (const Segment &segment : trajectory.segments)
        if (segment.start_time <= time && time < segment.end_time)
            return &segment;
    return nullptr;
}
