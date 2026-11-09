#include "railway.hpp"
#include <algorithm>

Interlocking readInterlocking(Layout &layout) {
    Interlocking interlocking;
    interlocking.layout = &layout;
    const auto requirements = [&](const std::string &text) {
        std::vector<Requirement> result;
        for (const std::string &part : list(text)) {
            std::size_t colon = part.find(':');
            result.push_back({layout.pointNames.at(part.substr(0, colon)), part[colon + 1]});
        }
        return result;
    };
    for (const std::string &line : readLines("input/routes.txt")) {
        std::vector<std::string> a = words(line);
        std::unique_ptr<Route> value = std::make_unique<Route>();
        Route *r = value.get();
        r->name = a[1];
        r->start = layout.signalNames.at(a[2]);
        r->finish = a[3];
        r->direction = r->start->direction;
        r->points = requirements(a[4]);
        r->flank = requirements(a[7]);
        r->conflictNames = list(a[8]);
        r->approach = std::stoi(a[9]);
        for (const std::string &name : list(a[5]))
            r->sections.push_back(layout.sectionNames.at(name));
        for (const std::string &name : list(a[6]))
            r->overlap.push_back(layout.sectionNames.at(name));
        interlocking.names[r->name] = r;
        interlocking.routes.push_back(std::move(value));
    }
    for (const std::unique_ptr<Route> &r : interlocking.routes)
        for (const std::string &name : r->conflictNames)
            r->conflicts.push_back(interlocking.names.at(name));
    return interlocking;
}
std::vector<Requirement> Route::requirements() const {
    std::vector<Requirement> result = points;
    result.insert(result.end(), flank.begin(), flank.end());
    return result;
}
static void removePointLocks(Point *point, Route *route) {
    point->locks.erase(std::remove_if(point->locks.begin(), point->locks.end(),
                                      [&](const PointLock &lock) { return lock.route == route; }),
                       point->locks.end());
}
void Interlocking::lock(Route *route) {
    route->state = RouteState::Locked;
    route->passed.clear();
    for (Section *section : route->sections)
        section->route = route;
    for (Section *section : route->overlap)
        section->overlaps.insert(route);
    for (const Requirement &requirement : route->requirements())
        requirement.point->locks.push_back({route, requirement.position});
    route->overlapLocked = true;
    route->overlapCounter = 0;
    route->releaseTime = -1;
}
void Interlocking::unlockSection(Route *route, Section *section) {
    if (section->route == route)
        section->route = nullptr;
    for (const std::unique_ptr<Point> &point : layout->points)
        if (point->common == section)
            removePointLocks(point.get(), route);
}
void Interlocking::unlockOverlap(Route *route) {
    for (Section *section : route->overlap) {
        section->overlaps.erase(route);
        for (const std::unique_ptr<Point> &point : layout->points)
            if (point->common == section)
                removePointLocks(point.get(), route);
    }
    route->overlapLocked = false;
}
void Interlocking::release(Route *route) {
    for (Section *section : route->sections)
        if (section->route == route)
            section->route = nullptr;
    if (route->overlapLocked)
        unlockOverlap(route);
    for (const std::unique_ptr<Point> &point : layout->points)
        removePointLocks(point.get(), route);
    route->state = RouteState::None;
}
