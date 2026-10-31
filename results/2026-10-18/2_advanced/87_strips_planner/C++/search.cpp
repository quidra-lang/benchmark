#include "planner.hpp"
bool applicable(const GroundAction &action, State state) {
    return state.contains(action.pre) && !state.intersects(action.neg);
}
State apply(const GroundAction &action, State state) {
    return state.without(action.del).united(action.add);
}
struct SearchNode {
    State state;
    Value g, h, f;
    int depth, serial, parent, action;
};
static SearchResult bestFirst(GroundProblem &problem, State start, const SearchSettings &settings,
                              int budget, int weight) {
    SearchResult out;
    Value initialH = problem.heuristics(start).value(settings.heuristic);
    if (initialH == infinity) {
        out.status = "dead end";
        return out;
    }
    const auto fValue = [&](Value cost, int depth, Value h) {
        if (settings.algorithm == "bfs")
            return static_cast<Value>(depth);
        if (settings.algorithm == "ucs")
            return cost;
        if (settings.algorithm == "gbfs")
            return h;
        return cost + (settings.algorithm == "wastar" ? weight : 1) * h;
    };
    std::vector<SearchNode> nodes;
    nodes.push_back({start, 0, initialH, fValue(0, 0, initialH), 0, 0, -1, -1});
    using Entry = std::tuple<Value, Value, int, int>;
    std::priority_queue<Entry, std::vector<Entry>, std::greater<Entry>> open;
    open.emplace(nodes[0].f, initialH, 0, 0);
    std::map<State, Value> table{{start, 0}};
    bool costBased = settings.algorithm == "ucs" || settings.algorithm == "astar" ||
                     settings.algorithm == "wastar";
    while (!open.empty()) {
        int index = std::get<3>(open.top());
        open.pop();
        SearchNode node = nodes[index];
        if (costBased && node.g > table.at(node.state))
            continue;
        if (node.state.contains(problem.goal)) {
            out.status = "solved";
            for (int at = index; nodes[at].parent >= 0; at = nodes[at].parent)
                out.plan.push_back(nodes[at].action);
            std::reverse(out.plan.begin(), out.plan.end());
            return out;
        }
        if (out.expanded == budget) {
            out.status = "budget";
            return out;
        }
        ++out.expanded;
        for (std::size_t i = 0; i < problem.actions.size(); ++i) {
            const GroundAction &action = problem.actions[i];
            if (!applicable(action, node.state))
                continue;
            ++out.generated;
            State next = apply(action, node.state);
            Value cost = node.g + action.cost;
            auto found = table.find(next);
            if (found != table.end() && (!costBased || found->second <= cost))
                continue;
            table[next] = cost;
            Value h = problem.heuristics(next).value(settings.heuristic);
            if (h == infinity)
                continue;
            int serial = static_cast<int>(nodes.size());
            Value f = fValue(cost, node.depth + 1, h);
            nodes.push_back({next, cost, h, f, node.depth + 1, serial, index, static_cast<int>(i)});
            open.emplace(f, h, serial, serial);
        }
    }
    out.status = "exhausted";
    return out;
}
static SearchResult hillClimbing(GroundProblem &problem, State start,
                                 const SearchSettings &settings, int budget) {
    SearchResult out;
    State current = start;
    Value currentH = problem.heuristics(current).value(settings.heuristic);
    if (currentH == infinity) {
        out.status = "dead end";
        return out;
    }
    for (;;) {
        if (current.contains(problem.goal)) {
            out.status = "solved";
            return out;
        }
        struct Local {
            State state;
            Plan path;
        };
        std::vector<Local> queue{{current, {}}};
        std::set<State> visited{current};
        bool improved = false;
        for (std::size_t head = 0; head < queue.size() && !improved; ++head) {
            Local node = queue[head];
            if (out.expanded == budget) {
                out.status = "budget";
                return out;
            }
            ++out.expanded;
            const Plan &helpful = problem.heuristics(node.state).helpful;
            for (int action : helpful) {
                ++out.generated;
                State next = apply(problem.actions[action], node.state);
                if (!visited.insert(next).second)
                    continue;
                Value h = problem.heuristics(next).value(settings.heuristic);
                if (h == infinity)
                    continue;
                Plan path = node.path;
                path.push_back(action);
                if (h < currentH) {
                    out.plan.insert(out.plan.end(), path.begin(), path.end());
                    current = next;
                    currentH = h;
                    improved = true;
                    break;
                }
                queue.push_back({next, std::move(path)});
            }
        }
        if (!improved) {
            out.status = "stuck";
            return out;
        }
    }
}
SearchResult search(GroundProblem &problem, State start, const SearchSettings &settings, int budget,
                    int weight) {
    if (settings.algorithm == "ehc")
        return hillClimbing(problem, start, settings, budget);
    return bestFirst(problem, start, settings, budget, weight);
}
