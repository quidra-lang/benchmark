#include <algorithm>
#include <cstddef>
#include <functional>
#include <iostream>
#include <limits>
#include <numeric>
#include <optional>
#include <queue>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

struct Edge {
    int from;
    int to;
    int capacity;
    int cost = 0;
    int lower = 0;
    int flow = 0;
};

struct Arc {
    int edge;
    bool forward;
};

using Path = std::vector<Arc>;

struct Search {
    std::vector<int> levels;
    std::vector<std::optional<Arc>> parents;
};

struct Augmentation {
    Path path;
    int amount;
    int phase = 0;
    int threshold = 1;
    int unitCost = 0;
};

struct Component {
    bool cycle;
    int amount;
    Path path;
};

class Network {
public:
    std::vector<std::string> names;
    std::vector<int> demands;
    std::vector<Edge> edges;

    int addNode(const std::string& name) {
        names.push_back(name);
        demands.push_back(0);
        return static_cast<int>(names.size()) - 1;
    }

    int from(Arc arc) const {
        return arc.forward ? edges[arc.edge].from : edges[arc.edge].to;
    }

    int to(Arc arc) const {
        return arc.forward ? edges[arc.edge].to : edges[arc.edge].from;
    }

    int residual(Arc arc) const {
        const Edge& edge = edges[arc.edge];
        return arc.forward ? edge.capacity - edge.flow : edge.flow;
    }

    int cost(Arc arc) const {
        return arc.forward ? edges[arc.edge].cost : -edges[arc.edge].cost;
    }

    Path arcList(int vertex) const {
        Path arcs;
        for (std::size_t i = 0; i < edges.size(); ++i) {
            if (edges[i].from == vertex) arcs.push_back({static_cast<int>(i), true});
        }
        for (std::size_t i = 0; i < edges.size(); ++i) {
            if (edges[i].to == vertex) arcs.push_back({static_cast<int>(i), false});
        }
        return arcs;
    }

    Path globalArcs() const {
        Path arcs;
        for (bool forward : {true, false}) {
            for (std::size_t i = 0; i < edges.size(); ++i) arcs.push_back({static_cast<int>(i), forward});
        }
        return arcs;
    }

    void zero() {
        for (Edge& edge : edges) edge.flow = 0;
    }

    std::vector<int> netOut() const {
        std::vector<int> result(names.size(), 0);
        for (const Edge& edge : edges) {
            result[edge.from] += edge.flow;
            result[edge.to] -= edge.flow;
        }
        return result;
    }

    int totalCost() const {
        int result = 0;
        for (const Edge& edge : edges) result += edge.flow * edge.cost;
        return result;
    }

    Search breadthFirst(int source, int threshold = 1) const {
        Search search{std::vector<int>(names.size(), -1), std::vector<std::optional<Arc>>(names.size())};
        std::queue<int> queue;
        search.levels[source] = 0;
        queue.push(source);
        while (!queue.empty()) {
            int vertex = queue.front();
            queue.pop();
            for (Arc arc : arcList(vertex)) {
                int target = to(arc);
                if (residual(arc) >= threshold && search.levels[target] < 0) {
                    search.levels[target] = search.levels[vertex] + 1;
                    search.parents[target] = arc;
                    queue.push(target);
                }
            }
        }
        return search;
    }

    Path trace(const std::vector<std::optional<Arc>>& parents, int source, int target) const {
        Path path;
        while (target != source) {
            Arc arc = *parents[target];
            path.push_back(arc);
            target = from(arc);
        }
        std::reverse(path.begin(), path.end());
        return path;
    }

    int bottleneck(const Path& path) const {
        int amount = std::numeric_limits<int>::max();
        for (Arc arc : path) amount = std::min(amount, residual(arc));
        return amount;
    }

    void push(const Path& path, int amount) {
        for (Arc arc : path) edges[arc.edge].flow += arc.forward ? amount : -amount;
    }

    std::optional<Augmentation> augment(int source, int target, int threshold = 1) {
        Search search = breadthFirst(source, threshold);
        if (search.levels[target] < 0) return std::nullopt;
        Path path = trace(search.parents, source, target);
        int amount = bottleneck(path);
        push(path, amount);
        return Augmentation{path, amount, 0, threshold};
    }

    std::vector<Augmentation> maximumFlow(int source, int target, int threshold = 1) {
        std::vector<Augmentation> result;
        while (true) {
            std::optional<Augmentation> next = augment(source, target, threshold);
            if (!next) return result;
            result.push_back(*next);
        }
    }

    std::pair<int, std::vector<Augmentation>> dinic(int source, int target) {
        int phases = 0;
        std::vector<Augmentation> result;
        std::vector<Path> arcs;
        for (std::size_t v = 0; v < names.size(); ++v) arcs.push_back(arcList(static_cast<int>(v)));
        while (true) {
            Search search = breadthFirst(source);
            if (search.levels[target] < 0) return {phases, result};
            ++phases;
            std::vector<std::size_t> pointers(names.size(), 0);
            Path path;
            int vertex = source;
            while (true) {
                if (vertex == target) {
                    int amount = bottleneck(path);
                    push(path, amount);
                    result.push_back({path, amount, phases});
                    path.clear();
                    vertex = source;
                } else if (pointers[vertex] == arcs[vertex].size()) {
                    if (vertex == source) break;
                    Arc last = path.back();
                    path.pop_back();
                    vertex = from(last);
                    ++pointers[vertex];
                } else {
                    Arc arc = arcs[vertex][pointers[vertex]];
                    int destination = to(arc);
                    if (residual(arc) > 0 && search.levels[destination] == search.levels[vertex] + 1) {
                        path.push_back(arc);
                        vertex = destination;
                    } else ++pointers[vertex];
                }
            }
        }
    }

    bool negativeCycle(bool subtractLower = false) const {
        std::vector<int> distance(names.size(), 0);
        for (std::size_t pass = 0; pass < names.size(); ++pass) {
            bool updated = false;
            for (const Edge& edge : edges) {
                if (edge.capacity - (subtractLower ? edge.lower : 0) < 1) continue;
                if (distance[edge.to] > distance[edge.from] + edge.cost) {
                    distance[edge.to] = distance[edge.from] + edge.cost;
                    updated = true;
                }
            }
            if (!updated) return false;
            if (pass + 1 == names.size()) return true;
        }
        return false;
    }

    std::optional<Augmentation> cheapest(int source, int target, std::optional<int> limit) {
        Path usable;
        for (Arc arc : globalArcs()) {
            if (residual(arc) > 0) usable.push_back(arc);
        }
        std::vector<std::optional<int>> distances(names.size());
        std::vector<std::optional<Arc>> parents(names.size());
        distances[source] = 0;
        while (true) {
            bool updated = false;
            for (Arc arc : usable) {
                int start = from(arc);
                int end = to(arc);
                if (!distances[start]) continue;
                int candidate = *distances[start] + cost(arc);
                if (!distances[end] || candidate < *distances[end]) {
                    distances[end] = candidate;
                    parents[end] = arc;
                    updated = true;
                }
            }
            if (!updated) break;
        }
        if (!distances[target]) return std::nullopt;
        Path path = trace(parents, source, target);
        int amount = bottleneck(path);
        if (limit) amount = std::min(amount, *limit);
        push(path, amount);
        return Augmentation{path, amount, 0, 1, *distances[target]};
    }

    std::vector<Augmentation> minimumCost(int source, int target, std::optional<int> limit) {
        int pushed = 0;
        std::vector<Augmentation> result;
        while (!limit || pushed < *limit) {
            std::optional<Augmentation> next = cheapest(source, target, limit ? std::optional<int>(*limit - pushed) : std::nullopt);
            if (!next) break;
            result.push_back(*next);
            pushed += next->amount;
        }
        return result;
    }

    std::string pathText(const Path& path, int originalEdges = -1, const Network* original = nullptr) const {
        std::ostringstream text;
        text << names[from(path[0])];
        for (Arc arc : path) {
            if (originalEdges >= 0 && arc.edge >= originalEdges) continue;
            text << ' ' << (arc.forward ? '+' : '-') << arc.edge + 1 << ' ';
            if (original) text << original->names[original->edges[arc.edge].to];
            else text << names[to(arc)];
        }
        return text.str();
    }

    std::vector<Component> decompose() const {
        std::vector<int> remaining;
        for (const Edge& edge : edges) remaining.push_back(edge.flow);
        std::vector<int> balance = netOut();
        std::vector<Component> result;
        while (true) {
            int firstEdge = -1;
            for (std::size_t i = 0; i < edges.size(); ++i) {
                if (remaining[i] > 0) {
                    firstEdge = static_cast<int>(i);
                    break;
                }
            }
            if (firstEdge < 0) return result;
            int start = edges[firstEdge].from;
            for (std::size_t v = 0; v < balance.size(); ++v) {
                if (balance[v] > 0) {
                    start = static_cast<int>(v);
                    break;
                }
            }
            std::vector<int> vertices = {start};
            Path path;
            while (true) {
                int next = 0;
                while (edges[next].from != vertices.back() || remaining[next] == 0) ++next;
                path.push_back({next, true});
                int destination = edges[next].to;
                auto repeated = std::find(vertices.begin(), vertices.end(), destination);
                if (repeated != vertices.end()) {
                    std::size_t offset = static_cast<std::size_t>(repeated - vertices.begin());
                    Path cycle(path.begin() + static_cast<std::ptrdiff_t>(offset), path.end());
                    int amount = std::numeric_limits<int>::max();
                    for (Arc arc : cycle) amount = std::min(amount, remaining[arc.edge]);
                    for (Arc arc : cycle) remaining[arc.edge] -= amount;
                    result.push_back({true, amount, cycle});
                    break;
                }
                vertices.push_back(destination);
                if (balance[destination] < 0) {
                    int amount = std::min(balance[start], -balance[destination]);
                    for (Arc arc : path) amount = std::min(amount, remaining[arc.edge]);
                    for (Arc arc : path) remaining[arc.edge] -= amount;
                    balance[start] -= amount;
                    balance[destination] += amount;
                    result.push_back({false, amount, path});
                    break;
                }
            }
        }
    }
};

[[noreturn]] static void fail(const std::string& message) {
    throw std::runtime_error(message);
}

static std::vector<std::string> split(const std::string& text, char separator) {
    std::vector<std::string> result;
    std::istringstream input(text);
    for (std::string part; std::getline(input, part, separator);) result.push_back(part);
    return result;
}

static std::string commaList(const std::vector<std::string>& names) {
    if (names.empty()) return "-";
    std::string result;
    for (const std::string& name : names) {
        if (!result.empty()) result += ',';
        result += name;
    }
    return result;
}

class Solver {
    Network network;
    enum class Owner { None, Flow, Circulation } owner = Owner::None;
    int source = -1;
    int target = -1;

    int node(const std::string& name) const {
        auto found = std::find(network.names.begin(), network.names.end(), name);
        if (found == network.names.end()) fail("UNKNOWN NODE " + name);
        return static_cast<int>(found - network.names.begin());
    }

    int edge(const std::string& number) const {
        int index = std::stoi(number) - 1;
        if (index < 0 || index >= static_cast<int>(network.edges.size())) fail("UNKNOWN EDGE " + number);
        return index;
    }

    std::pair<int, int> endpoints(const std::vector<std::string>& words) const {
        int start = node(words[1]);
        int end = node(words[2]);
        if (start == end) fail("SAME NODE");
        return {start, end};
    }

    int startFlow(int start, int end) {
        if (owner != Owner::Flow || start != source || end != target) network.zero();
        owner = Owner::Flow;
        source = start;
        target = end;
        return network.netOut()[start];
    }

    void flowList() const {
        for (std::size_t i = 0; i < network.edges.size(); ++i) {
            const Edge& item = network.edges[i];
            std::cout << "FLOW " << i + 1 << ' ' << network.names[item.from] << ' '
                      << network.names[item.to] << ' ' << item.flow << '/' << item.capacity << '\n';
        }
    }

    void show() const {
        std::cout << "NETWORK nodes=" << network.names.size() << " edges=" << network.edges.size() << '\n';
        if (owner == Owner::None) std::cout << "STATE none\n";
        else if (owner == Owner::Circulation) std::cout << "STATE circulation cost=" << network.totalCost() << '\n';
        else std::cout << "STATE flow " << network.names[source] << ' ' << network.names[target]
                       << " value=" << network.netOut()[source] << " cost=" << network.totalCost() << '\n';
        std::vector<int> outgoing(network.names.size(), 0), incoming(network.names.size(), 0);
        for (const Edge& item : network.edges) {
            outgoing[item.from] += item.flow;
            incoming[item.to] += item.flow;
        }
        for (std::size_t i = 0; i < network.names.size(); ++i) {
            std::cout << "NODE " << network.names[i] << " demand=" << network.demands[i]
                      << " out=" << outgoing[i] << " in=" << incoming[i] << '\n';
        }
        for (std::size_t i = 0; i < network.edges.size(); ++i) {
            const Edge& item = network.edges[i];
            std::cout << "EDGE " << i + 1 << ' ' << network.names[item.from] << ' ' << network.names[item.to]
                      << " cap=" << item.capacity << " cost=" << item.cost << " low=" << item.lower
                      << " flow=" << item.flow << '\n';
        }
    }

    void maximum(const std::vector<std::string>& words) {
        auto [start, end] = endpoints(words);
        int initial = startFlow(start, end);
        const std::string& command = words[0];
        if (command == "AUGMENT") {
            std::optional<Augmentation> pushed = network.augment(start, end);
            std::cout << "AUGMENT " << words[1] << ' ' << words[2] << " value=" << network.netOut()[start];
            if (pushed) std::cout << " amount=" << pushed->amount << ' ' << network.pathText(pushed->path) << '\n';
            else std::cout << " none\n";
            return;
        }
        std::vector<Augmentation> paths;
        int phases = 0;
        if (command == "DINIC") {
            auto result = network.dinic(start, end);
            phases = result.first;
            paths = std::move(result.second);
        } else if (command == "SCALING") {
            int maximumCapacity = 0;
            for (const Edge& item : network.edges) maximumCapacity = std::max(maximumCapacity, item.capacity);
            int threshold = 1;
            while (threshold <= maximumCapacity / 2) threshold *= 2;
            for (; threshold >= 1; threshold /= 2) {
                std::vector<Augmentation> next = network.maximumFlow(start, end, threshold);
                paths.insert(paths.end(), next.begin(), next.end());
            }
        } else paths = network.maximumFlow(start, end);
        if (command == "MINCUT") {
            Search reachable = network.breadthFirst(start);
            std::vector<int> cut;
            for (std::size_t i = 0; i < network.edges.size(); ++i) {
                const Edge& item = network.edges[i];
                if (reachable.levels[item.from] >= 0 && reachable.levels[item.to] < 0) cut.push_back(static_cast<int>(i));
            }
            std::cout << "MINCUT " << words[1] << ' ' << words[2] << " value=" << network.netOut()[start]
                      << " edges=" << cut.size() << '\n';
            for (bool inside : {true, false}) {
                std::cout << (inside ? "SOURCE" : "SINK");
                for (std::size_t i = 0; i < network.names.size(); ++i) {
                    if ((reachable.levels[i] >= 0) == inside) std::cout << ' ' << network.names[i];
                }
                std::cout << '\n';
            }
            for (int index : cut) {
                const Edge& item = network.edges[index];
                std::cout << "CUT " << index + 1 << ' ' << network.names[item.from] << ' '
                          << network.names[item.to] << ' ' << item.capacity << '\n';
            }
            return;
        }
        std::cout << command << ' ' << words[1] << ' ' << words[2] << " value=" << network.netOut()[start]
                  << " start=" << initial;
        if (command == "DINIC") std::cout << " phases=" << phases;
        std::cout << " paths=" << paths.size() << '\n';
        for (std::size_t i = 0; i < paths.size(); ++i) {
            const Augmentation& item = paths[i];
            std::cout << "AUG " << i + 1;
            if (command == "DINIC") std::cout << " phase=" << item.phase;
            if (command == "SCALING") std::cout << " delta=" << item.threshold;
            std::cout << " amount=" << item.amount << ' ' << network.pathText(item.path) << '\n';
        }
        flowList();
    }

    void sensitivity(const std::vector<std::string>& words) const {
        auto [start, end] = endpoints(words);
        auto value = [&](int changed, int delta) {
            Network copy = network;
            copy.zero();
            if (changed >= 0) copy.edges[changed].capacity += delta;
            copy.maximumFlow(start, end);
            return copy.netOut()[start];
        };
        int baseline = value(-1, 0), upCount = 0, downCount = 0;
        std::vector<std::pair<bool, bool>> flags;
        for (std::size_t i = 0; i < network.edges.size(); ++i) {
            bool up = value(static_cast<int>(i), 1) > baseline;
            bool down = network.edges[i].capacity > 0 && value(static_cast<int>(i), -1) < baseline;
            flags.emplace_back(up, down);
            upCount += up;
            downCount += down;
        }
        std::cout << "SENSITIVITY " << words[1] << ' ' << words[2] << " value=" << baseline
                  << " up=" << upCount << " down=" << downCount << '\n';
        for (std::size_t i = 0; i < flags.size(); ++i) {
            if (!flags[i].first && !flags[i].second) continue;
            const Edge& item = network.edges[i];
            std::cout << "CRITICAL " << i + 1 << ' ' << network.names[item.from] << ' ' << network.names[item.to]
                      << " up=" << (flags[i].first ? "yes" : "no") << " down=" << (flags[i].second ? "yes" : "no") << '\n';
        }
    }

    void minimumCost(const std::vector<std::string>& words) {
        auto [start, end] = endpoints(words);
        if (network.negativeCycle()) fail("NEGATIVE CYCLE");
        std::optional<int> limit;
        if (words[3] != "MAX") limit = std::stoi(words[3]);
        Network copy = network;
        copy.zero();
        std::vector<Augmentation> paths = copy.minimumCost(start, end, limit);
        int pushed = copy.netOut()[start];
        if (limit && pushed < *limit) {
            std::cout << "MINCOST " << words[1] << ' ' << words[2] << " k=" << words[3]
                      << " infeasible max=" << pushed << '\n';
            return;
        }
        for (std::size_t i = 0; i < network.edges.size(); ++i) network.edges[i].flow = copy.edges[i].flow;
        owner = Owner::Flow;
        source = start;
        target = end;
        std::cout << "MINCOST " << words[1] << ' ' << words[2] << " k=" << words[3]
                  << " flow=" << pushed << " cost=" << network.totalCost() << '\n';
        for (std::size_t i = 0; i < paths.size(); ++i) {
            std::cout << "AUG " << i + 1 << " amount=" << paths[i].amount << " cost=" << paths[i].unitCost
                      << ' ' << copy.pathText(paths[i].path) << '\n';
        }
        flowList();
    }

    void disjoint(const std::vector<std::string>& words) const {
        auto [start, end] = endpoints(words);
        Network copy;
        std::vector<int> entrance(network.names.size()), exit(network.names.size());
        for (std::size_t i = 0; i < network.names.size(); ++i) {
            entrance[i] = copy.addNode(network.names[i]);
            exit[i] = words[3] == "VERTEX" && static_cast<int>(i) != start && static_cast<int>(i) != end
                    ? copy.addNode(network.names[i]) : entrance[i];
        }
        for (const Edge& item : network.edges) copy.edges.push_back({exit[item.from], entrance[item.to], item.capacity > 0 ? 1 : 0});
        if (words[3] == "VERTEX") {
            for (std::size_t i = 0; i < entrance.size(); ++i) {
                if (entrance[i] != exit[i]) copy.edges.push_back({entrance[i], exit[i], 1});
            }
        }
        copy.maximumFlow(entrance[start], entrance[end]);
        std::vector<Component> paths;
        for (const Component& item : copy.decompose()) {
            if (!item.cycle) paths.push_back(item);
        }
        std::cout << "DISJOINT " << words[1] << ' ' << words[2] << ' ' << words[3] << " count=" << paths.size() << '\n';
        for (std::size_t i = 0; i < paths.size(); ++i) {
            std::cout << "PATH " << i + 1 << ' ' << copy.pathText(paths[i].path, static_cast<int>(network.edges.size()), &network) << '\n';
        }
    }

    void decompose() const {
        std::vector<Component> parts = network.decompose();
        int paths = 0, cycles = 0;
        for (const Component& item : parts) item.cycle ? ++cycles : ++paths;
        std::cout << "DECOMPOSE paths=" << paths << " cycles=" << cycles << '\n';
        paths = cycles = 0;
        for (const Component& item : parts) {
            std::cout << (item.cycle ? "CYCLE " : "PATH ") << (item.cycle ? ++cycles : ++paths)
                      << " amount=" << item.amount << ' ' << network.pathText(item.path) << '\n';
        }
    }

    void verify() const {
        std::vector<std::string> violations;
        for (std::size_t i = 0; i < network.edges.size(); ++i) {
            const Edge& item = network.edges[i];
            if (item.flow < item.lower) violations.push_back("LOW " + std::to_string(i + 1) + " flow="
                + std::to_string(item.flow) + " low=" + std::to_string(item.lower));
        }
        std::vector<int> outgoing = network.netOut();
        for (std::size_t i = 0; i < network.names.size(); ++i) {
            if (owner == Owner::Flow && (static_cast<int>(i) == source || static_cast<int>(i) == target)) continue;
            int needed = owner == Owner::Flow ? 0 : network.demands[i];
            if (-outgoing[i] != needed) violations.push_back("BALANCE " + network.names[i]
                + " net=" + std::to_string(-outgoing[i]) + " need=" + std::to_string(needed));
        }
        if (violations.empty()) std::cout << "VERIFY ok\n";
        else {
            std::cout << "VERIFY violations=" << violations.size() << '\n';
            for (const std::string& violation : violations) std::cout << violation << '\n';
        }
    }

    void circulation(const std::string& mode) {
        if (mode == "MINCOST" && network.negativeCycle(true)) fail("NEGATIVE CYCLE");
        int sum = std::accumulate(network.demands.begin(), network.demands.end(), 0);
        if (sum != 0) {
            std::cout << "CIRCULATION infeasible unbalanced=" << sum << '\n';
            return;
        }
        Network copy = network;
        copy.zero();
        std::vector<int> remainder = network.demands;
        for (std::size_t i = 0; i < network.edges.size(); ++i) {
            const Edge& item = network.edges[i];
            remainder[item.from] += item.lower;
            remainder[item.to] -= item.lower;
            copy.edges[i].capacity -= item.lower;
        }
        int superSource = copy.addNode("source"), superSink = copy.addNode("sink");
        for (std::size_t i = 0; i < remainder.size(); ++i) {
            if (remainder[i] < 0) copy.edges.push_back({superSource, static_cast<int>(i), -remainder[i]});
        }
        int positiveStart = static_cast<int>(copy.edges.size()), required = 0;
        for (std::size_t i = 0; i < remainder.size(); ++i) {
            if (remainder[i] > 0) {
                copy.edges.push_back({static_cast<int>(i), superSink, remainder[i]});
                required += remainder[i];
            }
        }
        if (mode == "ANY") copy.maximumFlow(superSource, superSink);
        else copy.minimumCost(superSource, superSink, std::nullopt);
        int achieved = 0;
        for (std::size_t i = positiveStart; i < copy.edges.size(); ++i) achieved += copy.edges[i].flow;
        if (achieved < required) {
            std::cout << "CIRCULATION infeasible required=" << required << " achieved=" << achieved << "\nCUT";
            Search reachable = copy.breadthFirst(superSource);
            for (std::size_t i = 0; i < network.names.size(); ++i) {
                if (reachable.levels[i] >= 0) std::cout << ' ' << network.names[i];
            }
            std::cout << '\n';
            return;
        }
        for (std::size_t i = 0; i < network.edges.size(); ++i) network.edges[i].flow = network.edges[i].lower + copy.edges[i].flow;
        owner = Owner::Circulation;
        std::cout << "CIRCULATION feasible required=" << required << " cost=" << network.totalCost() << '\n';
        flowList();
    }

    static void match(const std::vector<std::string>& words) {
        std::vector<std::string> left = split(words[1], ','), right = split(words[2], ',');
        std::set<std::string> seen;
        for (const std::vector<std::string>* side : {&left, &right}) {
            for (const std::string& name : *side) {
                if (!seen.insert(name).second) fail("DUPLICATE VERTEX " + name);
            }
        }
        std::vector<std::pair<int, int>> pairs;
        std::set<std::pair<int, int>> registered;
        if (words[3] != "-") {
            for (const std::string& item : split(words[3], ',')) {
                std::vector<std::string> names = split(item, '-');
                auto a = std::find(left.begin(), left.end(), names[0]);
                if (a == left.end()) fail("UNKNOWN VERTEX " + names[0]);
                auto b = std::find(right.begin(), right.end(), names[1]);
                if (b == right.end()) fail("UNKNOWN VERTEX " + names[1]);
                std::pair<int, int> pair{static_cast<int>(a - left.begin()), static_cast<int>(b - right.begin())};
                if (!registered.insert(pair).second) fail("DUPLICATE PAIR " + item);
                pairs.push_back(pair);
            }
        }
        std::vector<int> leftPartner(left.size(), -1), rightPartner(right.size(), -1);
        std::vector<bool> examined;
        std::function<bool(int)> attempt = [&](int a) {
            for (auto [from, to] : pairs) {
                if (from != a || examined[to]) continue;
                examined[to] = true;
                if (rightPartner[to] < 0 || attempt(rightPartner[to])) {
                    rightPartner[to] = a;
                    leftPartner[a] = to;
                    return true;
                }
            }
            return false;
        };
        for (std::size_t a = 0; a < left.size(); ++a) {
            examined.assign(right.size(), false);
            attempt(static_cast<int>(a));
        }
        std::vector<std::string> freeLeft, freeRight, hallLeft, hallRight, cover;
        std::vector<bool> reachedLeft(left.size(), false), reachedRight(right.size(), false);
        std::queue<int> queue;
        int count = 0;
        for (std::size_t a = 0; a < left.size(); ++a) {
            if (leftPartner[a] < 0) {
                freeLeft.push_back(left[a]);
                reachedLeft[a] = true;
                queue.push(static_cast<int>(a));
            } else ++count;
        }
        for (std::size_t b = 0; b < right.size(); ++b) {
            if (rightPartner[b] < 0) freeRight.push_back(right[b]);
        }
        while (!queue.empty()) {
            int a = queue.front();
            queue.pop();
            for (auto [from, to] : pairs) {
                if (from != a || leftPartner[a] == to || reachedRight[to]) continue;
                reachedRight[to] = true;
                int partner = rightPartner[to];
                if (partner >= 0 && !reachedLeft[partner]) {
                    reachedLeft[partner] = true;
                    queue.push(partner);
                }
            }
        }
        for (std::size_t a = 0; a < left.size(); ++a) {
            if (reachedLeft[a]) hallLeft.push_back(left[a]);
            else cover.push_back(left[a]);
        }
        for (std::size_t b = 0; b < right.size(); ++b) {
            if (reachedRight[b]) {
                hallRight.push_back(right[b]);
                cover.push_back(right[b]);
            }
        }
        std::cout << "MATCH size=" << count << " left=" << left.size() << " right=" << right.size() << '\n';
        for (std::size_t a = 0; a < left.size(); ++a) {
            if (leftPartner[a] >= 0) std::cout << "PAIR " << left[a] << ' ' << right[leftPartner[a]] << '\n';
        }
        std::cout << "FREE " << commaList(freeLeft) << ' ' << commaList(freeRight) << "\nCOVER size=" << cover.size();
        for (const std::string& name : cover) std::cout << ' ' << name;
        std::cout << '\n';
        if (!freeLeft.empty()) std::cout << "HALL " << commaList(hallLeft) << ' ' << commaList(hallRight) << '\n';
    }

    static void assign(const std::vector<std::string>& words) {
        int size = std::stoi(words[2]);
        if (size < 1 || size > 8) fail("BAD SIZE");
        if (words.size() - 3 != static_cast<std::size_t>(size * size)) fail("BAD LENGTH");
        std::vector<std::optional<int>> matrix;
        for (std::size_t i = 3; i < words.size(); ++i) matrix.push_back(words[i] == "x" ? std::nullopt : std::optional<int>(std::stoi(words[i])));
        std::vector<int> permutation(size), best;
        std::iota(permutation.begin(), permutation.end(), 0);
        int total = 0, optimal = 0;
        do {
            bool valid = true;
            int sum = 0;
            for (int row = 0; row < size; ++row) {
                const std::optional<int>& item = matrix[row * size + permutation[row]];
                if (!item) {
                    valid = false;
                    break;
                }
                sum += *item;
            }
            if (!valid) continue;
            if (best.empty() || (words[1] == "MIN" ? sum < total : sum > total)) {
                total = sum;
                optimal = 1;
                best = permutation;
            } else if (sum == total) ++optimal;
        } while (std::next_permutation(permutation.begin(), permutation.end()));
        std::cout << "ASSIGN " << words[1] << " n=" << size;
        if (best.empty()) std::cout << " infeasible\n";
        else {
            std::cout << " total=" << total << " optimal=" << optimal << '\n';
            for (int row = 0; row < size; ++row) {
                std::cout << "MATE " << row + 1 << ' ' << best[row] + 1 << ' ' << *matrix[row * size + best[row]] << '\n';
            }
        }
    }

public:
    void execute(const std::string& line) {
        std::istringstream input(line);
        std::vector<std::string> words;
        for (std::string word; input >> word;) words.push_back(word);
        const std::string& command = words[0];
        if (command == "NODE") {
            std::set<std::string> names(network.names.begin(), network.names.end());
            for (std::size_t i = 1; i < words.size(); ++i) {
                if (!names.insert(words[i]).second) fail("DUPLICATE NODE " + words[i]);
            }
            if (network.names.size() + words.size() - 1 > 20) fail("TOO MANY NODES");
            for (std::size_t i = 1; i < words.size(); ++i) network.addNode(words[i]);
            std::cout << "NODE added=" << words.size() - 1 << " total=" << network.names.size() << '\n';
        } else if (command == "EDGE") {
            int from = node(words[1]), to = node(words[2]);
            if (from == to) fail("SELF LOOP");
            if (network.edges.size() == 60) fail("TOO MANY EDGES");
            int capacity = std::stoi(words[3]), cost = words.size() == 5 ? std::stoi(words[4]) : 0;
            network.edges.push_back({from, to, capacity, cost});
            std::cout << "EDGE " << network.edges.size() << ' ' << words[1] << ' ' << words[2]
                      << " cap=" << capacity << " cost=" << cost << '\n';
        } else if (command == "LOWER" || command == "CAP" || command == "COST") {
            Edge& item = network.edges[edge(words[1])];
            int value = std::stoi(words[2]);
            if (command == "LOWER") {
                if (value > item.capacity) fail("BAD BOUND");
                item.lower = value;
                std::cout << "LOWER " << words[1] << " low=" << value << " cap=" << item.capacity << '\n';
            } else if (command == "CAP") {
                if (value < item.lower) fail("BAD BOUND");
                if (value < item.flow) fail("BELOW FLOW");
                item.capacity = value;
                std::cout << "CAP " << words[1] << " low=" << item.lower << " cap=" << value << '\n';
            } else {
                item.cost = value;
                std::cout << "COST " << words[1] << " cost=" << value << '\n';
            }
        } else if (command == "DEMAND") {
            int vertex = node(words[1]), demand = std::stoi(words[2]);
            network.demands[vertex] = demand;
            std::cout << "DEMAND " << words[1] << ' ' << demand << " total="
                      << std::accumulate(network.demands.begin(), network.demands.end(), 0) << '\n';
        } else if (command == "RESET") {
            int count = 0;
            for (const Edge& item : network.edges) count += item.flow != 0;
            network.zero();
            owner = Owner::None;
            std::cout << "RESET edges=" << count << '\n';
        } else if (command == "CLEAR") {
            std::cout << "CLEAR nodes=" << network.names.size() << " edges=" << network.edges.size() << '\n';
            network = Network{};
            owner = Owner::None;
            source = target = -1;
        } else if (command == "SHOW") show();
        else if (command == "AUGMENT" || command == "MAXFLOW" || command == "DINIC"
                 || command == "SCALING" || command == "MINCUT") maximum(words);
        else if (command == "SENSITIVITY") sensitivity(words);
        else if (command == "MINCOST") minimumCost(words);
        else if (command == "DISJOINT") disjoint(words);
        else if (command == "DECOMPOSE") decompose();
        else if (command == "VERIFY") verify();
        else if (command == "CIRCULATION") circulation(words[1]);
        else if (command == "MATCH") match(words);
        else if (command == "ASSIGN") assign(words);
    }
};

int main() {
    int count;
    std::cin >> count;
    std::string line;
    std::getline(std::cin, line);
    Solver solver;
    for (int i = 0; i < count; ++i) {
        std::getline(std::cin, line);
        try {
            solver.execute(line);
        } catch (const std::runtime_error& error) {
            std::cout << "ERROR " << error.what() << '\n';
        }
    }
}
