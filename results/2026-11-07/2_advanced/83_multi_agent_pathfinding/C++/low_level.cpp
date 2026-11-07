#include "mapf.hpp"
#include <algorithm>
#include <array>
#include <functional>
#include <queue>
bool Prohibitions::allowed(int u, int v, int time) const {
    if (states.count({v, time}))
        return false;
    auto fixed = permanent.find(v);
    if (fixed != permanent.end() && fixed->second <= time)
        return false;
    return u == v || !moves.count({u, v, time});
}
int Prohibitions::arrival(int goal) const {
    int result = 0;
    for (const std::pair<int, int> &state : states)
        if (state.first == goal)
            result = std::max(result, state.second + 1);
    return result;
}
void Prohibitions::reserve(const Path &path, int start, bool forever) {
    for (std::size_t i = 0; i < path.size(); ++i) {
        int time = start + static_cast<int>(i);
        states.insert({path[i], time});
        if (i && path[i] != path[i - 1])
            moves.insert({path[i], path[i - 1], time});
    }
    if (forever) {
        int goal = path.back(), time = start + static_cast<int>(path.size()) - 1;
        auto old = permanent.find(goal);
        if (old == permanent.end() || time < old->second)
            permanent[goal] = time;
    }
}
Prohibitions prohibitions(const std::vector<Constraint> &constraints) {
    Prohibitions result;
    for (const Constraint &constraint : constraints)
        if (constraint.edge)
            result.moves.insert({constraint.u, constraint.v, constraint.time});
        else
            result.states.insert({constraint.v, constraint.time});
    return result;
}
Path lowLevel(const Grid &grid, int agent, int start, int t0, int tmax, const Prohibitions &bans,
              bool window, Counters &counter) {
    ++counter.searches;
    struct State {
        int cell, time, parent;
    };
    std::vector<State> states = {{start, t0, -1}};
    std::priority_queue<std::array<int, 3>, std::vector<std::array<int, 3>>,
                        std::greater<std::array<int, 3>>>
        open;
    open.push({grid.distance[agent][start], 0, 0});
    int cells = grid.width * grid.height, arrival = bans.arrival(grid.agents[agent].goal);
    std::vector<bool> generated(static_cast<std::size_t>(tmax - t0 + 1) * cells);
    generated[start] = true;
    while (!open.empty()) {
        int index = open.top()[2];
        open.pop();
        State state = states[index];
        if (++counter.expansions > counter.limit) {
            counter.aborted = true;
            return {};
        }
        if ((state.cell == grid.agents[agent].goal && state.time >= arrival) ||
            (window && state.time == tmax)) {
            Path path;
            while (index >= 0) {
                path.push_back(states[index].cell);
                index = states[index].parent;
            }
            std::reverse(path.begin(), path.end());
            return path;
        }
        if (state.time == tmax)
            continue;
        for (int next : grid.destinations(state.cell)) {
            int g = state.time + 1 - t0;
            std::size_t key = static_cast<std::size_t>(g) * cells + next;
            if (grid.distance[agent][next] < 0 || generated[key] ||
                !bans.allowed(state.cell, next, state.time + 1))
                continue;
            generated[key] = true;
            int serial = static_cast<int>(states.size());
            states.push_back({next, state.time + 1, index});
            open.push({g + grid.distance[agent][next], -g, serial});
        }
    }
    return {};
}
