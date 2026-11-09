#include "mapf.hpp"
#include <algorithm>
#include <filesystem>
#include <limits>
#include <numeric>
#include <queue>

static const char *classNames[] = {"cardinal", "semi_cardinal", "non_cardinal"};
static Parameters readParameters(int count) {
    Parameters p;
    std::vector<int> order(count);
    std::iota(order.begin(), order.end(), 0);
    p.orders.push_back(order);
    for (const std::string &line : readLines("input/params.txt")) {
        std::vector<std::string> a = words(line);
        if (a[0] == "HORIZON")
            p.horizon = std::stoi(a[1]);
        else if (a[0] == "HL_BUDGET")
            p.highBudget = std::stoi(a[1]);
        else if (a[0] == "LL_BUDGET")
            p.lowBudget = std::stoi(a[1]);
        else if (a[0] == "WINDOW") {
            p.window = std::stoi(a[1]);
            p.step = std::stoi(a[2]);
        } else if (a[0] == "ORDER") {
            order.clear();
            for (std::size_t i = 1; i < a.size(); ++i)
                order.push_back(std::stoi(a[i]));
            p.orders.push_back(order);
        } else if (a[0] == "RUN")
            p.runs.push_back({a[1], a[2], a[1] + "-" + a[2]});
        else if (a[0] == "ANIMATE") {
            p.animate = a[1];
            p.frames = std::stoi(a[2]);
        } else
            p.delays.push_back({std::stoi(a[1]), std::stoi(a[2]), std::stoi(a[3])});
    }
    return p;
}
static ConstraintSet emptyConstraints(std::size_t count) {
    return ConstraintSet(count, std::make_shared<const std::vector<Constraint>>());
}
static std::vector<int> mdd(const Grid &g, int agent, int length, const Prohibitions &bans) {
    int cells = g.width * g.height;
    std::vector<std::vector<bool>> forward(length + 1, std::vector<bool>(cells)),
        valid(length + 1, std::vector<bool>(cells));
    forward[0][g.agents[agent].start] = true;
    for (int t = 1; t <= length; ++t)
        for (int c = 0; c < cells; ++c)
            if (forward[t - 1][c])
                for (int v : g.destinations(c))
                    if (g.distance[agent][v] >= 0 && t + g.distance[agent][v] <= length &&
                        bans.allowed(c, v, t))
                        forward[t][v] = true;
    valid[length][g.agents[agent].goal] = true;
    for (int t = length - 1; t >= 0; --t)
        for (int c = 0; c < cells; ++c)
            if (forward[t][c])
                for (int v : g.destinations(c))
                    if (valid[t + 1][v] && bans.allowed(c, v, t + 1)) {
                        valid[t][c] = true;
                        break;
                    }
    std::vector<int> widths(length + 1);
    for (int t = 0; t <= length; ++t)
        widths[t] = static_cast<int>(std::count(valid[t].begin(), valid[t].end(), true));
    return widths;
}
static int classify(const Grid &g, const Conflict &conflict, const Plan &paths,
                    const ConstraintSet &constraints, std::map<int, std::vector<int>> &cache) {
    int fixed = 0;
    for (int agent : {conflict.a, conflict.b}) {
        int length = static_cast<int>(paths[agent]->size()) - 1;
        if (conflict.time > length) {
            ++fixed;
            continue;
        }
        auto found = cache.find(agent);
        if (found == cache.end())
            found = cache.emplace(agent, mdd(g, agent, length, prohibitions(*constraints[agent])))
                        .first;
        const std::vector<int> &widths = found->second;
        if (widths[conflict.time] == 1 && (!conflict.edge || widths[conflict.time - 1] == 1))
            ++fixed;
    }
    return 2 - fixed;
}
static std::vector<std::string> overview(const Grid &g, const Plan &independent) {
    int free = 0, components = 0, degrees[4] = {0, 0, 0, 0}, cells = g.width * g.height;
    std::vector<bool> seen(cells);
    for (int c = 0; c < cells; ++c)
        if (g.free(c)) {
            ++free;
            ++degrees[std::min(3, static_cast<int>(g.destinations(c).size()) - 1)];
            if (seen[c])
                continue;
            ++components;
            std::vector<int> queue = {c};
            seen[c] = true;
            for (std::size_t i = 0; i < queue.size(); ++i)
                for (int v : g.destinations(queue[i]))
                    if (!seen[v]) {
                        seen[v] = true;
                        queue.push_back(v);
                    }
        }
    std::vector<std::string> result = {
        "instance width " + std::to_string(g.width) + " height " + std::to_string(g.height) +
            " free " + std::to_string(free) + " agents " + std::to_string(g.agents.size()),
        "map isolated " + std::to_string(degrees[0]) + " dead_ends " + std::to_string(degrees[1]) +
            " corridors " + std::to_string(degrees[2]) + " junctions " +
            std::to_string(degrees[3]) + " components " + std::to_string(components)};
    int lowerSoc = 0, lowerMax = 0;
    for (int i = 0; i < static_cast<int>(g.agents.size()); ++i) {
        int distance = g.distance[i][g.agents[i].start];
        std::vector<int> widths = mdd(g, i, distance, Prohibitions{});
        lowerSoc += distance;
        lowerMax = std::max(lowerMax, distance);
        result.push_back("agent " + std::string(1, static_cast<char>('A' + i)) + " start " +
                         cell(g, g.agents[i].start) + " goal " + cell(g, g.agents[i].goal) +
                         " distance " + std::to_string(distance) + " mdd " +
                         std::to_string(std::accumulate(widths.begin(), widths.end(), 0)) +
                         " width " +
                         std::to_string(*std::max_element(widths.begin(), widths.end())));
    }
    result.push_back("lower_bound soc " + std::to_string(lowerSoc) + " makespan " +
                     std::to_string(lowerMax));
    std::vector<Conflict> sequence = conflicts(independent);
    int counts[3] = {0, 0, 0}, vertex = 0, edge = 0;
    ConstraintSet constraints = emptyConstraints(g.agents.size());
    std::map<int, std::vector<int>> cache;
    std::vector<std::set<int>> adjacency(g.agents.size());
    for (const Conflict &c : sequence) {
        ++counts[classify(g, c, independent, constraints, cache)];
        if (c.edge)
            ++edge;
        else
            ++vertex;
        adjacency[c.a].insert(c.b);
        adjacency[c.b].insert(c.a);
    }
    result.push_back("independent conflicts " + std::to_string(sequence.size()) + " vertex " +
                     std::to_string(vertex) + " edge " + std::to_string(edge) + " cardinal " +
                     std::to_string(counts[0]) + " semi_cardinal " + std::to_string(counts[1]) +
                     " non_cardinal " + std::to_string(counts[2]));
    std::vector<bool> visited(g.agents.size());
    std::vector<std::string> groups;
    for (int i = 0; i < static_cast<int>(g.agents.size()); ++i)
        if (!visited[i] && !adjacency[i].empty()) {
            std::vector<int> queue = {i};
            visited[i] = true;
            for (std::size_t j = 0; j < queue.size(); ++j)
                for (int v : adjacency[queue[j]])
                    if (!visited[v]) {
                        visited[v] = true;
                        queue.push_back(v);
                    }
            std::sort(queue.begin(), queue.end());
            std::string group;
            for (int agent : queue)
                group += static_cast<char>('A' + agent);
            groups.push_back(group);
        }
    result.push_back("groups " + (groups.empty() ? "-" : join(groups, " ")));
    return result;
}
static void solvePP(const Grid &g, const Parameters &p, Run &r) {
    for (std::size_t i = 0; i < p.orders.size(); ++i) {
        ++r.high;
        int before = r.counter.expansions;
        PriorityResult result = prioritized(g, p, p.orders[i], static_cast<int>(i) + 1, r);
        if (r.counter.aborted) {
            r.reason = "ll_budget";
            return;
        }
        std::string order;
        for (int agent : p.orders[i])
            order += static_cast<char>('A' + agent);
        std::string text = "order " + std::to_string(i + 1) + " " + order + " planned " +
                           std::to_string(result.planned) + " expansions " +
                           std::to_string(r.counter.expansions - before);
        if (!result.paths.empty()) {
            r.paths = std::move(result.paths);
            r.specific.push_back(text + " ok");
            r.end = "end OK order " + std::to_string(i + 1);
            return;
        }
        r.specific.push_back(text + " failed " + static_cast<char>('A' + result.failed));
    }
    r.reason = "orders";
}
static std::shared_ptr<TreeNode> nodeFor(Plan paths, ConstraintSet constraints, int number,
                                         int parent, int depth, const std::string &function) {
    std::pair<int, int> cost = costs(paths);
    std::vector<Conflict> sequence = conflicts(paths);
    return std::make_shared<TreeNode>(
        TreeNode{number, parent, depth, function == "SOC" ? cost.first : cost.second,
                 std::move(paths), std::move(constraints), std::move(sequence)});
}
static void solveCBS(const Grid &g, const Parameters &p, Run &r) {
    const auto later = [](const std::shared_ptr<TreeNode> &a, const std::shared_ptr<TreeNode> &b) {
        return nodeLess(b, a);
    };
    std::priority_queue<std::shared_ptr<TreeNode>, std::vector<std::shared_ptr<TreeNode>>,
                        decltype(later)>
        open(later);
    Plan paths(g.agents.size());
    ConstraintSet constraints = emptyConstraints(g.agents.size());
    bool root = true;
    for (int i = 0; i < static_cast<int>(g.agents.size()); ++i) {
        Path path =
            lowLevel(g, i, g.agents[i].start, 0, p.horizon, Prohibitions{}, false, r.counter);
        if (r.counter.aborted) {
            r.reason = "ll_budget";
            root = false;
            break;
        }
        paths[i] = std::make_shared<const Path>(std::move(path));
    }
    if (root) {
        open.push(
            nodeFor(std::move(paths), std::move(constraints), 0, -1, 0, r.definition.costFunction));
        r.generated = 1;
    }
    while (r.reason.empty() && !open.empty()) {
        std::shared_ptr<TreeNode> node = open.top();
        open.pop();
        if (node->conflicts.empty()) {
            r.paths = node->paths;
            r.answer = node;
            r.end = "end OK node " + std::to_string(node->number) + " cost " +
                    std::to_string(node->cost);
            break;
        }
        if (r.high == p.highBudget) {
            r.reason = "hl_budget";
            break;
        }
        ++r.high;
        Conflict split = node->conflicts.front();
        int selectedClass = 2;
        if (r.definition.solver == "ICBS") {
            selectedClass = 3;
            std::map<int, std::vector<int>> cache;
            for (const Conflict &c : node->conflicts) {
                int kind = classify(g, c, node->paths, node->constraints, cache);
                if (kind < selectedClass) {
                    split = c;
                    selectedClass = kind;
                }
            }
            ++r.classes[selectedClass];
        }
        std::string children[2] = {"-", "-"};
        int agents[2] = {split.a, split.b};
        for (int side = 0; side < 2; ++side) {
            int agent = agents[side];
            ConstraintSet childConstraints = node->constraints;
            std::vector<Constraint> list = *childConstraints[agent];
            list.push_back(split.constraint(agent));
            childConstraints[agent] =
                std::make_shared<const std::vector<Constraint>>(std::move(list));
            Path path = lowLevel(g, agent, g.agents[agent].start, 0, p.horizon,
                                 prohibitions(*childConstraints[agent]), false, r.counter);
            if (r.counter.aborted) {
                r.reason = "ll_budget";
                break;
            }
            if (path.empty()) {
                ++r.pruned;
                continue;
            }
            Plan childPaths = node->paths;
            childPaths[agent] = std::make_shared<const Path>(std::move(path));
            int number = r.generated++;
            open.push(nodeFor(std::move(childPaths), std::move(childConstraints), number,
                              node->number, node->depth + 1, r.definition.costFunction));
            children[side] = std::to_string(number);
        }
        if (r.counter.aborted)
            break;
        std::string splitText = conflictText(g, split);
        if (r.definition.solver == "ICBS")
            splitText += " class " + std::string(classNames[selectedClass]);
        r.trace.push_back("expand " + std::to_string(r.high) + " node " +
                          std::to_string(node->number) + " parent " +
                          (node->parent < 0 ? "-" : std::to_string(node->parent)) + " depth " +
                          std::to_string(node->depth) + " cost " + std::to_string(node->cost) +
                          " conflicts " + std::to_string(node->conflicts.size()) + " split " +
                          splitText + " children " + children[0] + " " + children[1]);
    }
    if (r.reason.empty() && r.paths.empty())
        r.reason = "exhausted";
    r.open = static_cast<int>(open.size());
    r.specific.push_back("search expanded " + std::to_string(r.high) + " generated " +
                         std::to_string(r.generated) + " pruned " + std::to_string(r.pruned) +
                         " open " + std::to_string(r.open));
    if (r.definition.solver == "ICBS")
        r.specific.push_back("classes cardinal " + std::to_string(r.classes[0]) +
                             " semi_cardinal " + std::to_string(r.classes[1]) + " non_cardinal " +
                             std::to_string(r.classes[2]));
    if (r.answer) {
        r.specific.push_back("solution node " + std::to_string(r.answer->number) + " depth " +
                             std::to_string(r.answer->depth));
        std::vector<Constraint> all;
        for (const std::shared_ptr<const std::vector<Constraint>> &list : r.answer->constraints)
            all.insert(all.end(), list->begin(), list->end());
        std::sort(all.begin(), all.end(), [&](const Constraint &a, const Constraint &b) {
            return std::make_tuple(a.agent, a.time, a.edge, a.u % g.width, a.u / g.width,
                                   a.v % g.width, a.v / g.width) <
                   std::make_tuple(b.agent, b.time, b.edge, b.u % g.width, b.u / g.width,
                                   b.v % g.width, b.v / g.width);
        });
        for (const Constraint &c : all)
            r.specific.push_back("constraint " + std::string(1, static_cast<char>('A' + c.agent)) +
                                 (c.edge ? " edge " + cell(g, c.u) + " " + cell(g, c.v)
                                         : " vertex " + cell(g, c.v)) +
                                 " t " + std::to_string(c.time));
    }
}
static void solveWHCA(const Grid &g, const Parameters &p, Run &r) {
    std::vector<Path> executed(g.agents.size());
    std::vector<int> current;
    for (std::size_t i = 0; i < g.agents.size(); ++i) {
        executed[i].push_back(g.agents[i].start);
        current.push_back(g.agents[i].start);
    }
    for (int time = 0;; time += p.step) {
        bool done = true;
        for (std::size_t i = 0; i < g.agents.size(); ++i)
            done = done && current[i] == g.agents[i].goal;
        if (done) {
            for (std::size_t i = 0; i < g.agents.size(); ++i) {
                Path &path = executed[i];
                while (path.size() > 1 && path[path.size() - 2] == g.agents[i].goal)
                    path.pop_back();
                r.paths.push_back(std::make_shared<const Path>(std::move(path)));
            }
            r.end = "end OK rounds " + std::to_string(r.high);
            break;
        }
        if (time >= p.horizon) {
            r.reason = "timeout";
            break;
        }
        ++r.high;
        std::vector<int> order;
        for (bool atGoal : {false, true})
            for (int i = 0; i < static_cast<int>(g.agents.size()); ++i)
                if ((current[i] == g.agents[i].goal) == atGoal)
                    order.push_back(i);
        Prohibitions bans;
        std::vector<Path> window(g.agents.size());
        for (int agent : order) {
            int before = r.counter.expansions;
            Path path =
                lowLevel(g, agent, current[agent], time, time + p.window, bans, true, r.counter);
            if (r.counter.aborted) {
                r.reason = "ll_budget";
                break;
            }
            std::string base = "round " + std::to_string(r.high) + " time " + std::to_string(time) +
                               " agent " + static_cast<char>('A' + agent);
            if (path.empty()) {
                r.trace.push_back(base + " blocked expansions " +
                                  std::to_string(r.counter.expansions - before));
                r.reason = "blocked";
                break;
            }
            path.resize(p.window + 1, path.back());
            r.trace.push_back(base + " moves " + actions(g, path) + " expansions " +
                              std::to_string(r.counter.expansions - before));
            bans.reserve(path, time, false);
            window[agent] = std::move(path);
        }
        if (!r.reason.empty())
            break;
        for (std::size_t i = 0; i < g.agents.size(); ++i) {
            executed[i].insert(executed[i].end(), window[i].begin() + 1,
                               window[i].begin() + p.step + 1);
            current[i] = window[i][p.step];
        }
    }
    r.specific.push_back("window " + std::to_string(p.window) + " step " + std::to_string(p.step) +
                         " rounds " + std::to_string(r.high));
}
static PlanMetrics metrics(const Grid &g, const Plan &paths) {
    PlanMetrics m;
    std::pair<int, int> cost = costs(paths);
    m.soc = cost.first;
    m.makespan = cost.second;
    m.traffic.resize(g.width * g.height);
    m.cellWaits.resize(g.width * g.height);
    m.arrivals.resize(m.makespan + 1);
    for (std::size_t i = 0; i < paths.size(); ++i) {
        const Path &path = *paths[i];
        AgentMetrics a;
        a.cost = static_cast<int>(path.size()) - 1;
        a.extra = a.cost - g.distance[i][g.agents[i].start];
        a.actions = actions(g, path);
        std::set<int> seen;
        char last = 0;
        for (int t = 0; t < static_cast<int>(path.size()); ++t) {
            int c = path[t];
            seen.insert(c);
            if (c == g.agents[i].goal && a.arrival < 0)
                a.arrival = t;
            if (t == 0)
                continue;
            if (c == path[t - 1]) {
                ++a.waits;
                ++m.cellWaits[c];
            } else {
                char direction = action(g, path[t - 1], c);
                if (last && last != direction)
                    ++a.turns;
                last = direction;
            }
            if (path[t - 1] == g.agents[i].goal && c != g.agents[i].goal)
                ++a.leave;
        }
        for (int c : seen)
            ++m.traffic[c];
        for (int t = a.cost; t <= m.makespan; ++t)
            ++m.arrivals[t];
        m.sumExtra += a.extra;
        m.maxExtra = std::max(m.maxExtra, a.extra);
        m.waits += a.waits;
        m.turns += a.turns;
        m.agents.push_back(std::move(a));
    }
    for (int c = 0; c < g.width * g.height; ++c)
        if (m.traffic[c])
            m.hotspots.push_back(c);
    std::sort(m.hotspots.begin(), m.hotspots.end(), [&](int a, int b) {
        return m.traffic[a] != m.traffic[b] ? m.traffic[a] > m.traffic[b] : a < b;
    });
    if (m.hotspots.size() > 5)
        m.hotspots.resize(5);
    return m;
}
static std::vector<std::string> validation(const Grid &g, const std::string &name,
                                           const Plan &paths, bool independent) {
    int start = 0, goal = 0, moves = 0, follows = 0, vertex = 0, edge = 0;
    for (std::size_t i = 0; i < paths.size(); ++i) {
        const Path &path = *paths[i];
        start += path.front() != g.agents[i].start;
        goal += path.back() != g.agents[i].goal;
        for (std::size_t t = 1; t < path.size(); ++t) {
            std::vector<int> destinations = g.destinations(path[t - 1]);
            moves +=
                std::find(destinations.begin(), destinations.end(), path[t]) == destinations.end();
        }
    }
    std::vector<Conflict> sequence = conflicts(paths);
    for (const Conflict &c : sequence)
        if (c.edge)
            ++edge;
        else
            ++vertex;
    int last = costs(paths).second;
    for (int t = 1; t <= last; ++t)
        for (std::size_t a = 0; a < paths.size(); ++a)
            for (std::size_t b = 0; b < paths.size(); ++b)
                if (a != b && position(*paths[a], t) != position(*paths[a], t - 1) &&
                    position(*paths[a], t) == position(*paths[b], t - 1) &&
                    position(*paths[b], t) != position(*paths[a], t - 1))
                    ++follows;
    std::vector<std::string> result = {
        "plan " + name + " verdict " +
        (start + goal + moves + vertex + edge ? "INVALID" : "VALID") + " start " +
        std::to_string(start) + " goal " + std::to_string(goal) + " moves " +
        std::to_string(moves) + " vertex " + std::to_string(vertex) + " edge " +
        std::to_string(edge) + " follows " + std::to_string(follows)};
    std::map<int, std::vector<int>> cache;
    ConstraintSet constraints = emptyConstraints(paths.size());
    for (const Conflict &c : sequence)
        result.push_back(
            "  " + conflictText(g, c) +
            (independent ? " " + std::string(classNames[classify(g, c, paths, constraints, cache)])
                         : ""));
    return result;
}
static Execution delayed(const Plan &paths, const std::vector<Delay> &delays) {
    struct Step {
        int time, cell;
    };
    int n = static_cast<int>(paths.size());
    std::vector<std::vector<Step>> steps(n);
    for (int i = 0; i < n; ++i) {
        steps[i].push_back({0, paths[i]->front()});
        for (int t = 1; t < static_cast<int>(paths[i]->size()); ++t)
            if ((*paths[i])[t] != (*paths[i])[t - 1])
                steps[i].push_back({t, (*paths[i])[t]});
    }
    std::vector<std::vector<std::vector<int>>> needs(n);
    for (int i = 0; i < n; ++i) {
        needs[i].assign(steps[i].size(), std::vector<int>(n, -1));
        for (std::size_t k = 1; k < steps[i].size(); ++k)
            for (int j = 0; j < n; ++j)
                if (i != j)
                    for (int l = 0; l < static_cast<int>(steps[j].size()); ++l)
                        if (steps[j][l].cell == steps[i][k].cell &&
                            steps[j][l].time < steps[i][k].time)
                            needs[i][k][j] = l;
    }
    Execution result;
    result.finish.resize(n);
    std::vector<int> progress(n);
    for (int time = 0;; ++time) {
        bool done = true;
        for (int i = 0; i < n; ++i)
            done = done && progress[i] == static_cast<int>(steps[i].size()) - 1;
        if (done) {
            result.soc = std::accumulate(result.finish.begin(), result.finish.end(), 0);
            result.makespan = *std::max_element(result.finish.begin(), result.finish.end());
            return result;
        }
        std::vector<int> advance;
        bool stopped = false;
        for (int i = 0; i < n; ++i) {
            if (progress[i] == static_cast<int>(steps[i].size()) - 1)
                continue;
            bool stop = false;
            for (const Delay &delay : delays)
                if (delay.agent == i && delay.start <= time && time < delay.start + delay.length)
                    stop = true;
            if (stop) {
                stopped = true;
                continue;
            }
            bool held = false;
            for (int j = 0; j < n; ++j)
                if (progress[j] <= needs[i][progress[i] + 1][j])
                    held = true;
            if (held)
                ++result.blocked;
            else
                advance.push_back(i);
        }
        if (advance.empty() && !stopped) {
            result.deadlock = true;
            result.time = time;
            return result;
        }
        for (int i : advance) {
            ++progress[i];
            result.finish[i] = time + 1;
        }
    }
}
static void append(std::vector<std::string> &destination, const std::vector<std::string> &source) {
    destination.insert(destination.end(), source.begin(), source.end());
}
static std::vector<std::string> countPicture(const Grid &g, const std::vector<int> &counts) {
    std::vector<std::string> result = g.rows;
    for (int c = 0; c < g.width * g.height; ++c)
        if (g.free(c))
            result[c / g.width][c % g.width] = counts[c] == 0   ? '.'
                                               : counts[c] < 10 ? static_cast<char>('0' + counts[c])
                                                                : '+';
    return result;
}
static std::vector<std::string> frames(const Grid &g, const Parameters &p, const Run &r) {
    if (r.paths.empty())
        return {"run " + p.animate + " FAIL"};
    std::vector<std::string> result = {"run " + p.animate + " frames " + std::to_string(p.frames)};
    for (int t = 0; t < p.frames; ++t) {
        std::vector<std::string> picture = g.rows;
        for (std::size_t i = 0; i < g.agents.size(); ++i) {
            int goal = g.agents[i].goal;
            picture[goal / g.width][goal % g.width] = static_cast<char>('a' + i);
        }
        int done = 0, moving = 0, waiting = 0;
        for (std::size_t i = 0; i < r.paths.size(); ++i) {
            int c = position(*r.paths[i], t);
            picture[c / g.width][c % g.width] = static_cast<char>('A' + i);
            if (t >= static_cast<int>(r.paths[i]->size()) - 1)
                ++done;
            else if (t >= 1 && position(*r.paths[i], t) != position(*r.paths[i], t - 1))
                ++moving;
            else
                ++waiting;
        }
        result.push_back("");
        result.push_back("frame " + std::to_string(t) + " done " + std::to_string(done) +
                         " moving " + std::to_string(moving) + " waiting " +
                         std::to_string(waiting));
        append(result, picture);
    }
    result.push_back("");
    result.push_back("traffic");
    append(result, countPicture(g, r.metrics.traffic));
    result.push_back("");
    result.push_back("waits");
    append(result, countPicture(g, r.metrics.cellWaits));
    return result;
}
static std::vector<std::string> runBlock(const Grid &g, const Run &r) {
    const RunDefinition &d = r.definition;
    std::string base =
        "run " + d.name + " solver " + d.solver + " cost_function " + d.costFunction + " result";
    std::vector<std::string> result;
    if (r.paths.empty()) {
        result.push_back(base + " FAIL reason " + r.reason);
        append(result, r.specific);
        return result;
    }
    const PlanMetrics &m = r.metrics;
    int lower = 0, cost = d.costFunction == "SOC" ? m.soc : m.makespan;
    for (std::size_t i = 0; i < g.agents.size(); ++i) {
        int distance = g.distance[i][g.agents[i].start];
        lower = d.costFunction == "SOC" ? lower + distance : std::max(lower, distance);
    }
    result.push_back(base + " OK cost " + std::to_string(cost) + " soc " + std::to_string(m.soc) +
                     " makespan " + std::to_string(m.makespan) + " ratio " + fraction(cost, lower));
    append(result, r.specific);
    for (std::size_t i = 0; i < m.agents.size(); ++i) {
        const AgentMetrics &a = m.agents[i];
        result.push_back("agent " + std::string(1, static_cast<char>('A' + i)) + " cost " +
                         std::to_string(a.cost) + " extra " + std::to_string(a.extra) + " waits " +
                         std::to_string(a.waits) + " turns " + std::to_string(a.turns) +
                         " arrive " + std::to_string(a.arrival) + " leave " +
                         std::to_string(a.leave) + " moves " + a.actions);
    }
    result.push_back("arrivals " + integers(m.arrivals));
    std::vector<std::string> hotspots;
    for (int c : m.hotspots)
        hotspots.push_back(cell(g, c) + ":" + std::to_string(m.traffic[c]));
    result.push_back("hotspots " + join(hotspots, " "));
    const Execution &e = r.execution;
    result.push_back(e.deadlock ? "execution deadlock time " + std::to_string(e.time)
                                : "execution soc " + std::to_string(e.soc) + " makespan " +
                                      std::to_string(e.makespan) + " blocked " +
                                      std::to_string(e.blocked) + " finish " + integers(e.finish));
    return result;
}
static std::string statsLine(const Run &r) {
    const RunDefinition &d = r.definition;
    std::vector<std::string> fields = {d.name, d.solver, d.costFunction};
    if (r.paths.empty()) {
        fields.push_back("FAIL");
        fields.push_back(r.reason);
        fields.insert(fields.end(), 9, "-");
    } else {
        const PlanMetrics &m = r.metrics;
        fields.push_back("OK");
        fields.push_back("-");
        for (int value : {d.costFunction == "SOC" ? m.soc : m.makespan, m.soc, m.makespan,
                          m.sumExtra, m.maxExtra, m.waits, m.turns})
            fields.push_back(std::to_string(value));
        fields.push_back(r.execution.deadlock ? "-" : std::to_string(r.execution.soc));
        fields.push_back(r.execution.deadlock ? "-" : std::to_string(r.execution.makespan));
    }
    fields.push_back(std::to_string(r.high));
    fields.push_back(d.solver == "CBS" || d.solver == "ICBS" ? std::to_string(r.generated) : "-");
    fields.push_back(std::to_string(r.counter.searches));
    fields.push_back(std::to_string(r.counter.expansions));
    return join(fields, ",");
}
int main() {
    Grid g = readGrid();
    Parameters p = readParameters(static_cast<int>(g.agents.size()));
    Plan independent;
    Counters counter;
    counter.limit = std::numeric_limits<int>::max();
    for (int i = 0; i < static_cast<int>(g.agents.size()); ++i)
        independent.push_back(std::make_shared<const Path>(
            lowLevel(g, i, g.agents[i].start, 0, p.horizon, Prohibitions{}, false, counter)));
    std::vector<std::string>
        solutions = overview(g, independent),
        validations = validation(g, "INDEPENDENT", independent, true),
        stats =
            {"run,solver,cost_function,result,reason,cost,soc,makespan,sum_extra,max_extra,waits,turns,exec_soc,exec_makespan,high_level,generated,searches,expansions"},
        trace;
    std::vector<Run> runs;
    std::vector<int> successful;
    int animated = -1;
    for (const RunDefinition &definition : p.runs) {
        Run r;
        r.definition = definition;
        r.counter.limit = p.lowBudget;
        if (definition.solver == "PP")
            solvePP(g, p, r);
        else if (definition.solver == "WHCA")
            solveWHCA(g, p, r);
        else
            solveCBS(g, p, r);
        if (!r.paths.empty()) {
            r.metrics = metrics(g, r.paths);
            r.execution = delayed(r.paths, p.delays);
            successful.push_back(static_cast<int>(runs.size()));
            append(validations, validation(g, definition.name, r.paths, false));
        } else {
            validations.push_back("plan " + definition.name + " verdict NONE");
            r.end = "end FAIL " + r.reason;
        }
        solutions.push_back("");
        append(solutions, runBlock(g, r));
        stats.push_back(statsLine(r));
        if (!trace.empty())
            trace.push_back("");
        trace.push_back("run " + definition.name);
        append(trace, r.trace);
        trace.push_back(r.end);
        if (definition.name == p.animate)
            animated = static_cast<int>(runs.size());
        runs.push_back(std::move(r));
    }
    solutions.push_back("");
    solutions.push_back("summary ok " + std::to_string(successful.size()) + " failed " +
                        std::to_string(runs.size() - successful.size()));
    if (!successful.empty()) {
        int bestSoc = runs[successful.front()].metrics.soc,
            bestMax = runs[successful.front()].metrics.makespan;
        for (int i : successful) {
            bestSoc = std::min(bestSoc, runs[i].metrics.soc);
            bestMax = std::min(bestMax, runs[i].metrics.makespan);
        }
        std::vector<std::string> socNames, maxNames;
        for (int i : successful) {
            if (runs[i].metrics.soc == bestSoc)
                socNames.push_back(runs[i].definition.name);
            if (runs[i].metrics.makespan == bestMax)
                maxNames.push_back(runs[i].definition.name);
        }
        solutions.push_back("best_soc " + std::to_string(bestSoc) + " " + join(socNames, " "));
        solutions.push_back("best_makespan " + std::to_string(bestMax) + " " + join(maxNames, " "));
        std::sort(successful.begin(), successful.end(), [&](int a, int b) {
            return std::tie(runs[a].metrics.soc, runs[a].metrics.makespan, a) <
                   std::tie(runs[b].metrics.soc, runs[b].metrics.makespan, b);
        });
        std::vector<std::string> ranking;
        for (int i : successful)
            ranking.push_back(runs[i].definition.name);
        solutions.push_back("ranking " + join(ranking, " "));
    }
    std::filesystem::create_directories("output");
    writeLines("solutions.txt", solutions);
    writeLines("stats.csv", stats);
    writeLines("validation.txt", validations);
    writeLines("trace.txt", trace);
    writeLines("frames.txt", frames(g, p, runs[animated]));
}
