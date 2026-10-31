#include "mapf.hpp"
#include <algorithm>
int position(const Path &path, int time) {
    return path[std::min(time, static_cast<int>(path.size()) - 1)];
}
std::pair<int, int> costs(const Plan &plan) {
    int soc = 0, makespan = 0;
    for (const std::shared_ptr<const Path> &path : plan) {
        int cost = static_cast<int>(path->size()) - 1;
        soc += cost;
        makespan = std::max(makespan, cost);
    }
    return {soc, makespan};
}
std::vector<Conflict> conflicts(const Plan &paths) {
    std::vector<Conflict> result;
    int last = costs(paths).second;
    for (int time = 1; time <= last; ++time)
        for (int a = 0; a < static_cast<int>(paths.size()); ++a)
            for (int b = a + 1; b < static_cast<int>(paths.size()); ++b) {
                int u = position(*paths[a], time - 1), v = position(*paths[a], time),
                    bu = position(*paths[b], time - 1), bv = position(*paths[b], time);
                if (v == bv)
                    result.push_back({time, a, b, v, v, false});
                else if (v == bu && bv == u)
                    result.push_back({time, a, b, u, v, true});
            }
    return result;
}
Constraint Conflict::constraint(int agent) const {
    return edge && agent == b ? Constraint{agent, time, v, u, true}
                              : Constraint{agent, time, u, v, edge};
}
bool nodeLess(const std::shared_ptr<TreeNode> &a, const std::shared_ptr<TreeNode> &b) {
    return std::make_tuple(a->cost, a->conflicts.size(), a->number) <
           std::make_tuple(b->cost, b->conflicts.size(), b->number);
}
