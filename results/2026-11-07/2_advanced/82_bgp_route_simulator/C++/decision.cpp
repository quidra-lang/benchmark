#include "bgp.hpp"
#include <algorithm>
#include <limits>
bool Attribute::operator==(const Attribute &a) const {
    return path == a.path && origin == a.origin && med == a.med && communities == a.communities;
}
bool Route::operator==(const Route &r) const {
    return local == r.local && preference == r.preference && link == r.link &&
           attribute == r.attribute;
}
int originRank(const std::string &name) { return name == "IGP" ? 0 : name == "EGP" ? 1 : 2; }
const char *originName(int rank) {
    static const char *names[] = {"IGP", "EGP", "INCOMPLETE"};
    return names[rank];
}
std::pair<Route, std::string> bestRoute(std::vector<Route> routes, const Topology &topology) {
    if (routes.size() == 1)
        return {routes.front(), "ONLY"};
    static const char *stages[] = {"LOCALPREF", "ASPATH", "ORIGIN", "MED", "ROUTERID", "LINK"};
    for (int stage = 0; stage < 6; ++stage) {
        std::vector<Route> keep;
        if (stage == 3) {
            std::map<int, int> minimum;
            for (const Route &route : routes) {
                int neighbor = route.attribute.path.front();
                auto found = minimum.find(neighbor);
                if (found == minimum.end() || route.attribute.med < found->second)
                    minimum[neighbor] = route.attribute.med;
            }
            for (const Route &route : routes)
                if (route.attribute.med == minimum.at(route.attribute.path.front()))
                    keep.push_back(route);
        } else {
            const auto value = [&](const Route &route) -> std::int64_t {
                if (stage == 0)
                    return -route.preference;
                if (stage == 1)
                    return static_cast<std::int64_t>(route.attribute.path.size());
                if (stage == 2)
                    return route.attribute.origin;
                if (stage == 4)
                    return static_cast<std::int64_t>(
                        topology.nodes.at(route.attribute.path.front()).router);
                return route.link->number;
            };
            std::int64_t minimum = std::numeric_limits<std::int64_t>::max();
            for (const Route &route : routes)
                minimum = std::min(minimum, value(route));
            for (const Route &route : routes)
                if (value(route) == minimum)
                    keep.push_back(route);
        }
        routes = std::move(keep);
        if (routes.size() == 1)
            return {routes.front(), stages[stage]};
    }
    return {routes.front(), "LINK"};
}
