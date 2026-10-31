#include "railway.hpp"
#include <algorithm>

static const std::array<std::string, 4> properties = {"OCCUPANCY", "POINT_MOTION", "CONFLICT",
                                                      "SIGNAL_PASSING"};
void Safety::violation(int time, int property, const std::string &details) {
    ++violations[property];
    records.push_back("VIOLATION " + std::to_string(time) + " " + properties[property] + " " +
                      details);
}
void Safety::signalPassing(int time, Train *train, Signal *signal) {
    ++checks[3];
    if (signal->aspect == Aspect::Red)
        violation(time, 3, train->name + " " + signal->name);
}
void Safety::check(int time, const Layout &layout, const Interlocking &interlocking) {
    for (const std::unique_ptr<Section> &section : layout.sections) {
        ++checks[0];
        if (section->occupants.size() >= 2) {
            std::vector<std::string> names;
            for (const Train *train : section->occupants)
                names.push_back(train->name);
            violation(time, 0, section->name + " " + join(names, ","));
        }
    }
    for (const std::unique_ptr<Point> &point : layout.points) {
        if (!point->moving)
            continue;
        ++checks[1];
        if (!point->common->occupants.empty())
            violation(time, 1, point->name + " occupied");
        else
            for (const PointLock &lock : point->locks)
                if (lock.route->state == RouteState::Used ||
                    lock.route->state == RouteState::Approach) {
                    violation(time, 1, point->name + " locked");
                    break;
                }
    }
    const auto active = [](const Route &route) {
        return route.state == RouteState::Locked || route.state == RouteState::Approach;
    };
    for (std::size_t i = 0; i < interlocking.routes.size(); ++i) {
        Route *a = interlocking.routes[i].get();
        if (!active(*a))
            continue;
        for (std::size_t j = i + 1; j < interlocking.routes.size(); ++j) {
            Route *b = interlocking.routes[j].get();
            if (!active(*b))
                continue;
            ++checks[2];
            if (std::find(a->conflicts.begin(), a->conflicts.end(), b) != a->conflicts.end() ||
                std::find(b->conflicts.begin(), b->conflicts.end(), a) != b->conflicts.end())
                violation(time, 2, a->name + " " + b->name);
        }
    }
}
std::vector<std::string> Safety::lines() const {
    std::vector<std::string> result;
    bool safe = true;
    for (int i = 0; i < 4; ++i) {
        safe = safe && violations[i] == 0;
        result.push_back(properties[i] + (violations[i] == 0 ? " OK" : " FAIL") + " checks " +
                         std::to_string(checks[i]) + " violations " +
                         std::to_string(violations[i]));
    }
    result.insert(result.end(), records.begin(), records.end());
    result.push_back(safe ? "RESULT SAFE" : "RESULT UNSAFE");
    return result;
}
