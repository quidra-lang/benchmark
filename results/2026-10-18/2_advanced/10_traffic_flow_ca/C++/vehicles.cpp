#include "traffic.hpp"
#include <algorithm>

int Vehicle::maxSpeed() const { return std::min(kind->vmax,segment->limit); }
void Vehicle::place(Segment* target, int targetLane, int targetCell) {
    if (segment) segment->put(lane,cell,0);
    target->put(targetLane,targetCell,number); segment = target; lane = targetLane; cell = targetCell;
}
void Vehicle::leave() { segment->put(lane,cell,0); segment = nullptr; }
bool Vehicle::headingForStop() const {
    return segment && kind->stops && segment->stop && !completedStops.count(segment->id) && cell <= segment->stop->cell;
}
int Vehicle::travelTime() const { return exited - inserted + 1; }
int randomSlowdown(int speed, int previous, Integer value, int dawdle, int stopped) { return speed > 0 && value % 1000 < (previous == 0 ? stopped : dawdle) ? speed - 1 : speed; }
