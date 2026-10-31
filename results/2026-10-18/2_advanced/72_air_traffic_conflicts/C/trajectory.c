#include "airspace.h"
const char *phase_name(Phase phase) {
    return phase == CLIMB ? "CLB" : phase == DESCENT ? "DES" : "LVL";
}
void build_trajectory(const Plan *plan, const AircraftType *types, Trajectory *out) {
    memset(out, 0, sizeof *out);
    double current = (double)(plan->departure + plan->delay);
    Integer level = plan->level + plan->offset;
    out->passing[0] = (Passing){current, level};
    for (int leg = 1; leg < plan->waypoint_count; ++leg) {
        const Waypoint *p = &plan->waypoints[leg - 1], *q = &plan->waypoints[leg];
        int dx = q->x - p->x, dy = q->y - p->y;
        double length = sqrt((double)(dx * dx + dy * dy)) / 10,
               duration = length * 3600 / plan->speed, vx = ((double)dx / 10) / duration,
               vy = ((double)dy / 10) / duration;
        out->length += length;
        Integer target = q->has_level ? q->level + plan->offset : level;
        Point first = {{(double)p->x / 10, (double)p->y / 10, (double)(level * 100)}},
              last = {{(double)q->x / 10, (double)q->y / 10, (double)(target * 100)}};
        if (target == level) {
            out->segments[out->count] = (Segment){out->count + 1,     leg,   LEVEL,         current,
                                                  current + duration, first, {{vx, vy, 0}}, last};
            ++out->count;
        } else {
            bool climbing = target > level;
            int rate = climbing ? types[plan->type].climb : types[plan->type].descent;
            Integer difference = target - level;
            if (difference < 0)
                difference = -difference;
            double vz = climbing ? (double)rate / 60 : -((double)rate / 60),
                   change = (double)(difference * 6000) / rate;
            Point middle = {
                {first.v[0] + vx * change, first.v[1] + vy * change, (double)(target * 100)}};
            out->segments[out->count] = (Segment){
                out->count + 1, leg,   climbing ? CLIMB : DESCENT, current, current + change, first,
                {{vx, vy, vz}}, middle};
            ++out->count;
            out->segments[out->count] =
                (Segment){out->count + 1,     leg,    LEVEL,         current + change,
                          current + duration, middle, {{vx, vy, 0}}, last};
            ++out->count;
        }
        current = current + duration;
        level = target;
        out->passing[leg] = (Passing){current, level};
    }
    out->arrival = current;
}
Point position(const Segment *segment, double time) {
    Point out;
    for (int i = 0; i < 3; ++i)
        out.v[i] = segment->start.v[i] + segment->velocity.v[i] * (time - segment->start_time);
    return out;
}
const Segment *active_segment(const Trajectory *trajectory, double time) {
    if (!(trajectory->segments[0].start_time <= time &&
          time < trajectory->segments[trajectory->count - 1].end_time))
        return NULL;
    for (int i = 0; i < trajectory->count; ++i)
        if (trajectory->segments[i].start_time <= time && time < trajectory->segments[i].end_time)
            return &trajectory->segments[i];
    return NULL;
}
