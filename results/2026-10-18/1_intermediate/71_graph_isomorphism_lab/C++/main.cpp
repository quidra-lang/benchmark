#include <algorithm>
#include <functional>
#include <iostream>
#include <map>
#include <numeric>
#include <queue>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

struct Graph {
    int n;
    std::vector<std::vector<bool>> adjacent;

    explicit Graph(int vertices) : n(vertices), adjacent(n, std::vector<bool>(n, false)) {}

    void add(int u, int v) {
        adjacent[u][v] = adjacent[v][u] = true;
    }

    std::vector<std::pair<int, int>> edges() const {
        std::vector<std::pair<int, int>> result;
        for (int u = 0; u < n; ++u) {
            for (int v = u + 1; v < n; ++v) {
                if (adjacent[u][v]) result.emplace_back(u, v);
            }
        }
        return result;
    }

    std::vector<int> degrees() const {
        std::vector<int> result(n);
        for (int v = 0; v < n; ++v) {
            result[v] = static_cast<int>(std::count(adjacent[v].begin(), adjacent[v].end(), true));
        }
        return result;
    }
};

[[noreturn]] static void fail(const std::string& message) {
    throw std::runtime_error(message);
}

static void range(int value, int minimum, int maximum) {
    if (value < minimum) fail("bad value");
    if (value > maximum) fail("too large");
}

static std::string yesNo(bool value) {
    return value ? "yes" : "no";
}

static void sequence(const std::vector<int>& values) {
    for (int value : values) std::cout << ' ' << value;
}

static std::vector<int> inverse(const std::vector<int>& labels) {
    std::vector<int> result(labels.size());
    for (std::size_t v = 0; v < labels.size(); ++v) result[labels[v]] = static_cast<int>(v);
    return result;
}

static int cellCount(const std::vector<int>& colors) {
    return *std::max_element(colors.begin(), colors.end()) + 1;
}

static std::vector<int> degreeColors(const Graph& graph) {
    std::vector<int> degrees = graph.degrees();
    std::vector<int> unique = degrees;
    std::sort(unique.begin(), unique.end());
    unique.erase(std::unique(unique.begin(), unique.end()), unique.end());
    for (int& degree : degrees) degree = static_cast<int>(std::lower_bound(unique.begin(), unique.end(), degree) - unique.begin());
    return degrees;
}

struct Refinement {
    std::vector<int> colors;
    int rounds;
};

static Refinement refine(const Graph& graph, std::vector<int> colors) {
    int rounds = 0;
    using Signature = std::pair<int, std::vector<int>>;
    while (true) {
        std::vector<Signature> signatures;
        for (int v = 0; v < graph.n; ++v) {
            std::vector<int> neighbors;
            for (int w = 0; w < graph.n; ++w) {
                if (graph.adjacent[v][w]) neighbors.push_back(colors[w]);
            }
            std::sort(neighbors.begin(), neighbors.end());
            signatures.emplace_back(colors[v], neighbors);
        }
        std::vector<Signature> unique = signatures;
        std::sort(unique.begin(), unique.end());
        unique.erase(std::unique(unique.begin(), unique.end()), unique.end());
        if (static_cast<int>(unique.size()) == cellCount(colors)) return {colors, rounds};
        for (int v = 0; v < graph.n; ++v) {
            colors[v] = static_cast<int>(std::lower_bound(unique.begin(), unique.end(), signatures[v]) - unique.begin());
        }
        ++rounds;
    }
}

static std::vector<int> individualize(std::vector<int> colors, int vertex) {
    int chosen = colors[vertex];
    for (std::size_t v = 0; v < colors.size(); ++v) {
        if (static_cast<int>(v) != vertex && colors[v] >= chosen) ++colors[v];
    }
    return colors;
}

struct CanonicalForm {
    long long nodes = 0;
    long long leaves = 0;
    std::string bits;
    std::vector<int> labels;
    std::vector<std::vector<int>> bestLeaves;

    explicit CanonicalForm(const Graph& graph) {
        visit(graph, refine(graph, degreeColors(graph)).colors);
    }

private:
    void visit(const Graph& graph, const std::vector<int>& colors) {
        ++nodes;
        int count = cellCount(colors);
        if (count == graph.n) {
            ++leaves;
            std::vector<int> vertex = inverse(colors);
            std::string candidate;
            for (int i = 0; i < graph.n; ++i) {
                for (int j = i + 1; j < graph.n; ++j) candidate += graph.adjacent[vertex[i]][vertex[j]] ? '1' : '0';
            }
            if (labels.empty() || candidate > bits) {
                bits = candidate;
                labels = colors;
                bestLeaves.clear();
            }
            if (candidate == bits) bestLeaves.push_back(colors);
            return;
        }
        std::vector<std::vector<int>> cells(count);
        for (int v = 0; v < graph.n; ++v) cells[colors[v]].push_back(v);
        int chosen = -1;
        for (int color = 0; color < count; ++color) {
            if (cells[color].size() > 1 && (chosen < 0 || cells[color].size() < cells[chosen].size())) chosen = color;
        }
        for (int v : cells[chosen]) visit(graph, refine(graph, individualize(colors, v)).colors);
    }
};

static Graph relabel(const Graph& graph, const std::vector<int>& labels) {
    Graph result(graph.n);
    for (const auto& [u, v] : graph.edges()) result.add(labels[u], labels[v]);
    return result;
}

struct Invariants {
    std::vector<int> degrees;
    int edges = 0;
    int triangles = 0;
    std::vector<int> componentSizes;
    int girth = 0;
    int diameter = 0;
    int radius = 0;
    bool bipartite = true;
};

static Invariants invariants(const Graph& graph) {
    Invariants result;
    result.degrees = graph.degrees();
    std::sort(result.degrees.rbegin(), result.degrees.rend());
    result.edges = static_cast<int>(graph.edges().size());
    for (int u = 0; u < graph.n; ++u) {
        for (int v = u + 1; v < graph.n; ++v) {
            for (int w = v + 1; w < graph.n; ++w) {
                if (graph.adjacent[u][v] && graph.adjacent[v][w] && graph.adjacent[w][u]) ++result.triangles;
            }
        }
    }
    std::vector<int> colors(graph.n, -1);
    for (int root = 0; root < graph.n; ++root) {
        if (colors[root] >= 0) continue;
        int size = 0;
        std::queue<int> pending;
        colors[root] = 0;
        pending.push(root);
        while (!pending.empty()) {
            int u = pending.front();
            pending.pop();
            ++size;
            for (int v = 0; v < graph.n; ++v) {
                if (!graph.adjacent[u][v]) continue;
                if (colors[v] < 0) {
                    colors[v] = 1 - colors[u];
                    pending.push(v);
                } else if (colors[v] == colors[u]) result.bipartite = false;
            }
        }
        result.componentSizes.push_back(size);
    }
    std::sort(result.componentSizes.rbegin(), result.componentSizes.rend());
    result.radius = graph.n;
    for (int root = 0; root < graph.n; ++root) {
        std::vector<int> distance(graph.n, -1);
        std::vector<int> parent(graph.n, -1);
        std::queue<int> pending;
        distance[root] = 0;
        pending.push(root);
        while (!pending.empty()) {
            int u = pending.front();
            pending.pop();
            for (int v = 0; v < graph.n; ++v) {
                if (!graph.adjacent[u][v]) continue;
                if (distance[v] < 0) {
                    distance[v] = distance[u] + 1;
                    parent[v] = u;
                    pending.push(v);
                } else if (parent[u] != v && parent[v] != u) {
                    int cycle = distance[u] + distance[v] + 1;
                    if (result.girth == 0 || cycle < result.girth) result.girth = cycle;
                }
            }
        }
        int eccentricity = *std::max_element(distance.begin(), distance.end());
        result.radius = std::min(result.radius, eccentricity);
        result.diameter = std::max(result.diameter, eccentricity);
    }
    if (result.componentSizes.size() > 1) result.diameter = result.radius = -1;
    return result;
}

static std::vector<int> largestClique(const Graph& graph) {
    std::vector<int> best;
    for (int mask = 1; mask < (1 << graph.n); ++mask) {
        std::vector<int> vertices;
        bool valid = true;
        for (int v = 0; v < graph.n && valid; ++v) {
            if ((mask & (1 << v)) == 0) continue;
            for (int u : vertices) {
                if (!graph.adjacent[u][v]) valid = false;
            }
            vertices.push_back(v);
        }
        if (valid && (vertices.size() > best.size() || (vertices.size() == best.size() && vertices < best))) best = vertices;
    }
    return best;
}

static std::pair<int, std::vector<int>> coloring(const Graph& graph) {
    std::vector<int> colors(graph.n, -1);
    for (int limit = 1; limit <= graph.n; ++limit) {
        std::function<bool(int, int)> assign = [&](int vertex, int highest) {
            if (vertex == graph.n) return true;
            for (int color = 0; color < limit && color <= highest + 1; ++color) {
                bool valid = true;
                for (int u = 0; u < vertex; ++u) {
                    if (graph.adjacent[u][vertex] && colors[u] == color) valid = false;
                }
                if (!valid) continue;
                colors[vertex] = color;
                if (assign(vertex + 1, std::max(highest, color))) return true;
                colors[vertex] = -1;
            }
            return false;
        };
        if (assign(0, -1)) return {limit, colors};
    }
    return {graph.n, colors};
}

static std::string girthText(int girth) {
    return girth == 0 ? "none" : std::to_string(girth);
}

static std::string distanceText(int distance) {
    return distance < 0 ? "INF" : std::to_string(distance);
}

static void printInvariants(const std::string& name, const Graph& graph) {
    Invariants value = invariants(graph);
    std::cout << "invariants " << name << "\ndegrees";
    sequence(value.degrees);
    std::cout << "\nedges " << value.edges << " triangles " << value.triangles << "\ncomponents " << value.componentSizes.size() << " sizes";
    sequence(value.componentSizes);
    std::cout << "\ngirth " << girthText(value.girth) << " diameter " << distanceText(value.diameter)
              << " radius " << distanceText(value.radius) << "\nbipartite " << yesNo(value.bipartite) << '\n';
    if (graph.n >= 13) std::cout << "clique -\nchromatic -\n";
    else {
        std::vector<int> clique = largestClique(graph);
        std::cout << "clique " << clique.size();
        sequence(clique);
        auto [count, colors] = coloring(graph);
        std::cout << "\nchromatic " << count;
        sequence(colors);
        std::cout << '\n';
    }
}

static std::vector<int> cellSizes(const std::vector<int>& colors) {
    std::vector<int> sizes(cellCount(colors));
    for (int color : colors) ++sizes[color];
    return sizes;
}

static void isomorphism(const Graph& a, const Graph& b) {
    std::string difference;
    if (a.n != b.n) difference = "vertices " + std::to_string(a.n) + ' ' + std::to_string(b.n);
    else {
        Invariants x = invariants(a);
        Invariants y = invariants(b);
        if (x.edges != y.edges) difference = "edges " + std::to_string(x.edges) + ' ' + std::to_string(y.edges);
        else if (x.degrees != y.degrees) difference = "degrees";
        else if (x.triangles != y.triangles) difference = "triangles " + std::to_string(x.triangles) + ' ' + std::to_string(y.triangles);
        else if (x.componentSizes.size() != y.componentSizes.size()) difference = "components " + std::to_string(x.componentSizes.size()) + ' ' + std::to_string(y.componentSizes.size());
        else if (x.girth != y.girth) difference = "girth " + girthText(x.girth) + ' ' + girthText(y.girth);
        else if (x.diameter != y.diameter) difference = "diameter " + distanceText(x.diameter) + ' ' + distanceText(y.diameter);
        else if (x.bipartite != y.bipartite) difference = "bipartite " + yesNo(x.bipartite) + ' ' + yesNo(y.bipartite);
        else {
            Refinement ra = refine(a, degreeColors(a));
            Refinement rb = refine(b, degreeColors(b));
            if (ra.rounds != rb.rounds || cellSizes(ra.colors) != cellSizes(rb.colors)) difference = "refinement";
            else {
                CanonicalForm ca(a);
                CanonicalForm cb(b);
                if (ca.bits != cb.bits) difference = "canonical";
                else {
                    std::vector<int> vertex = inverse(cb.labels);
                    std::cout << "isomorphic\nmapping";
                    for (int label : ca.labels) std::cout << ' ' << vertex[label];
                    std::cout << '\n';
                    return;
                }
            }
        }
    }
    std::cout << "not isomorphic " << difference << '\n';
}

class DisjointSet {
    std::vector<int> parent;
public:
    explicit DisjointSet(int size) : parent(size) {
        std::iota(parent.begin(), parent.end(), 0);
    }
    int find(int value) {
        return parent[value] == value ? value : parent[value] = find(parent[value]);
    }
    void join(int a, int b) {
        parent[find(b)] = find(a);
    }
    std::vector<std::vector<int>> groups() {
        std::map<int, std::vector<int>> cells;
        for (std::size_t i = 0; i < parent.size(); ++i) cells[find(static_cast<int>(i))].push_back(static_cast<int>(i));
        std::vector<std::vector<int>> result;
        for (const auto& [root, cell] : cells) result.push_back(cell);
        std::sort(result.begin(), result.end());
        return result;
    }
};

static void automorphisms(const std::string& name, const Graph& graph) {
    CanonicalForm canonical(graph);
    std::vector<int> vertex = inverse(canonical.labels);
    std::vector<std::pair<int, int>> edges = graph.edges();
    std::map<std::pair<int, int>, int> edgeIds;
    for (std::size_t i = 0; i < edges.size(); ++i) edgeIds[edges[i]] = static_cast<int>(i);
    DisjointSet vertexSets(graph.n);
    DisjointSet edgeSets(static_cast<int>(edges.size()));
    for (const std::vector<int>& labels : canonical.bestLeaves) {
        std::vector<int> permutation(graph.n);
        for (int v = 0; v < graph.n; ++v) {
            permutation[v] = vertex[labels[v]];
            vertexSets.join(v, permutation[v]);
        }
        for (std::size_t i = 0; i < edges.size(); ++i) {
            int a = permutation[edges[i].first];
            int b = permutation[edges[i].second];
            if (a > b) std::swap(a, b);
            edgeSets.join(static_cast<int>(i), edgeIds.at({a, b}));
        }
    }
    std::vector<std::vector<int>> vertices = vertexSets.groups();
    std::vector<std::vector<int>> edgeGroups = edgeSets.groups();
    std::cout << "aut " << name << " order " << canonical.bestLeaves.size() << "\nvertex orbits " << vertices.size() << '\n';
    for (const std::vector<int>& group : vertices) {
        std::cout << "orbit";
        sequence(group);
        std::cout << '\n';
    }
    std::cout << "edge orbits " << edgeGroups.size() << '\n';
    for (const std::vector<int>& group : edgeGroups) {
        std::cout << "orbit";
        for (int edge : group) std::cout << ' ' << edges[edge].first << '-' << edges[edge].second;
        std::cout << '\n';
    }
    std::cout << "transitive vertex " << yesNo(vertices.size() == 1) << " edge " << yesNo(edgeGroups.size() == 1) << '\n';
}

static void subisomorphism(const std::string& patternName, const std::string& targetName,
                          const Graph& pattern, const Graph& target) {
    long long embeddings = 0;
    long long induced = 0;
    std::vector<std::pair<std::vector<int>, bool>> first;
    std::vector<int> mapping(pattern.n, -1);
    std::vector<bool> used(target.n, false);
    std::function<void(int, bool)> search = [&](int vertex, bool exact) {
        if (vertex == pattern.n) {
            ++embeddings;
            if (exact) ++induced;
            if (first.size() < 5) first.emplace_back(mapping, exact);
            return;
        }
        for (int v = 0; v < target.n; ++v) {
            if (used[v]) continue;
            bool valid = true;
            bool nextExact = exact;
            for (int u = 0; u < vertex; ++u) {
                bool edge = target.adjacent[mapping[u]][v];
                if (pattern.adjacent[u][vertex] && !edge) valid = false;
                if (pattern.adjacent[u][vertex] != edge) nextExact = false;
            }
            if (!valid) continue;
            mapping[vertex] = v;
            used[v] = true;
            search(vertex + 1, nextExact);
            used[v] = false;
        }
    };
    if (pattern.n <= target.n) search(0, true);
    long long order = static_cast<long long>(CanonicalForm(pattern).bestLeaves.size());
    std::cout << "subiso " << patternName << ' ' << targetName << " embeddings " << embeddings << " induced " << induced
              << "\ncopies " << embeddings / order << " induced " << induced / order << '\n';
    for (const auto& [values, exact] : first) {
        std::cout << "embedding";
        sequence(values);
        if (exact) std::cout << " induced";
        std::cout << '\n';
    }
}

static void classify(int n) {
    range(n, 1, 5);
    int possible = n * (n - 1) / 2;
    std::vector<std::set<std::string>> classes(possible + 1);
    for (int mask = 0; mask < (1 << possible); ++mask) {
        Graph graph(n);
        int bit = 0;
        int count = 0;
        for (int u = 0; u < n; ++u) {
            for (int v = u + 1; v < n; ++v, ++bit) {
                if (mask & (1 << bit)) {
                    graph.add(u, v);
                    ++count;
                }
            }
        }
        classes[count].insert(CanonicalForm(graph).bits);
    }
    std::size_t total = 0;
    for (const auto& group : classes) total += group.size();
    std::cout << "classify " << n << " total " << total << '\n';
    for (int m = 0; m <= possible; ++m) {
        std::cout << "edges " << m << " count " << classes[m].size();
        for (const std::string& bits : classes[m]) std::cout << ' ' << (bits.empty() ? "-" : bits);
        std::cout << '\n';
    }
}

struct Format {
    int minimum;
    int maximum;
    std::string fixed;
    char tail = 0;
};

static bool nameWord(const std::string& text) {
    return !text.empty() && text.size() <= 8 && text[0] >= 'a' && text[0] <= 'z' &&
           text.find_first_not_of("abcdefghijklmnopqrstuvwxyz0123456789") == std::string::npos;
}

static bool numberWord(const std::string& text) {
    return !text.empty() && text.size() <= 3 && (text.size() == 1 || text[0] != '0') &&
           text.find_first_not_of("0123456789") == std::string::npos;
}

static std::pair<int, int> edgeWord(const std::string& text) {
    std::size_t dash = text.find('-');
    if (dash == std::string::npos || !numberWord(text.substr(0, dash)) || !numberWord(text.substr(dash + 1))) fail("bad arguments");
    return {std::stoi(text.substr(0, dash)), std::stoi(text.substr(dash + 1))};
}

class Laboratory {
    std::map<std::string, Graph> graphs;
    const std::map<std::string, Format> formats = {
        {"GRAPH", {2, -1, "ni", 'e'}}, {"CYCLE", {2, 2, "ni"}}, {"PATH", {2, 2, "ni"}},
        {"COMPLETE", {2, 2, "ni"}}, {"BIPARTITE", {3, 3, "nii"}}, {"STAR", {2, 2, "ni"}},
        {"WHEEL", {2, 2, "ni"}}, {"PETERSEN", {1, 1, "n"}}, {"HYPERCUBE", {2, 2, "ni"}},
        {"CIRCULANT", {3, -1, "ni", 'i'}}, {"GRID", {3, 3, "nii"}},
        {"COMPLEMENT", {2, 2, "ng"}}, {"LINE", {2, 2, "ng"}}, {"PRODUCT", {3, 3, "ngg"}},
        {"UNION", {3, 3, "ngg"}}, {"RELABEL", {2, -1, "ng", 'i'}},
        {"INDUCED", {3, -1, "ng", 'i'}}, {"CANONIZE", {2, 2, "ng"}},
        {"DELETE", {1, 1, "g"}}, {"LIST", {0, 0, ""}}, {"SHOW", {1, 1, "g"}},
        {"INVARIANTS", {1, 1, "g"}}, {"REFINE", {1, -1, "g", 'i'}}, {"CANON", {1, 1, "g"}},
        {"ISO", {2, 2, "gg"}}, {"AUT", {1, 1, "g"}}, {"SUBISO", {2, 2, "gg"}}, {"CLASSIFY", {1, 1, "i"}}
    };

    Graph build(const std::string& command, const std::vector<std::string>& a) const {
        if (command == "GRAPH") {
            int n = std::stoi(a[1]);
            range(n, 1, 16);
            Graph graph(n);
            for (std::size_t i = 2; i < a.size(); ++i) {
                auto [u, v] = edgeWord(a[i]);
                if (u >= n || v >= n || u == v) fail("bad edge " + a[i]);
                if (graph.adjacent[u][v]) fail("duplicate edge " + a[i]);
                graph.add(u, v);
            }
            return graph;
        }
        if (command == "CYCLE" || command == "PATH" || command == "COMPLETE" || command == "CIRCULANT") {
            int n = std::stoi(a[1]);
            range(n, command == "CYCLE" || command == "CIRCULANT" ? 3 : 1, 16);
            Graph graph(n);
            if (command == "COMPLETE") {
                for (int u = 0; u < n; ++u) {
                    for (int v = u + 1; v < n; ++v) graph.add(u, v);
                }
            } else if (command == "CIRCULANT") {
                int previous = 0;
                for (std::size_t i = 2; i < a.size(); ++i) {
                    int jump = std::stoi(a[i]);
                    if (jump <= previous || 2 * jump > n) fail("bad value");
                    previous = jump;
                    for (int v = 0; v < n; ++v) graph.add(v, (v + jump) % n);
                }
            } else {
                for (int v = 1; v < n; ++v) graph.add(v - 1, v);
                if (command == "CYCLE") graph.add(n - 1, 0);
            }
            return graph;
        }
        if (command == "BIPARTITE" || command == "GRID") {
            int first = std::stoi(a[1]);
            int second = std::stoi(a[2]);
            if (first == 0 || second == 0) fail("bad value");
            int n = command == "GRID" ? first * second : first + second;
            range(n, 1, 16);
            Graph graph(n);
            for (int x = 0; x < first; ++x) {
                for (int y = 0; y < second; ++y) {
                    if (command == "BIPARTITE") graph.add(x, first + y);
                    else {
                        if (x + 1 < first) graph.add(x * second + y, (x + 1) * second + y);
                        if (y + 1 < second) graph.add(x * second + y, x * second + y + 1);
                    }
                }
            }
            return graph;
        }
        if (command == "STAR" || command == "WHEEL") {
            int k = std::stoi(a[1]);
            range(k, command == "STAR" ? 1 : 3, 15);
            Graph graph(k + 1);
            for (int v = 1; v <= k; ++v) graph.add(0, v);
            if (command == "WHEEL") {
                for (int v = 1; v <= k; ++v) graph.add(v, v % k + 1);
            }
            return graph;
        }
        if (command == "PETERSEN") {
            Graph graph(10);
            for (int v = 0; v < 5; ++v) {
                graph.add(v, (v + 1) % 5);
                graph.add(v, v + 5);
                graph.add(v + 5, (v + 2) % 5 + 5);
            }
            return graph;
        }
        if (command == "HYPERCUBE") {
            int d = std::stoi(a[1]);
            range(d, 1, 4);
            Graph graph(1 << d);
            for (int v = 0; v < graph.n; ++v) {
                for (int bit = 0; bit < d; ++bit) graph.add(v, v ^ (1 << bit));
            }
            return graph;
        }
        const Graph& source = graphs.at(a[1]);
        if (command == "COMPLEMENT") {
            Graph graph(source.n);
            for (int u = 0; u < source.n; ++u) {
                for (int v = u + 1; v < source.n; ++v) {
                    if (!source.adjacent[u][v]) graph.add(u, v);
                }
            }
            return graph;
        }
        if (command == "LINE") {
            std::vector<std::pair<int, int>> edges = source.edges();
            if (edges.empty()) fail("no edges");
            range(static_cast<int>(edges.size()), 1, 16);
            Graph graph(static_cast<int>(edges.size()));
            for (int u = 0; u < graph.n; ++u) {
                for (int v = u + 1; v < graph.n; ++v) {
                    if (edges[u].first == edges[v].first || edges[u].first == edges[v].second ||
                        edges[u].second == edges[v].first || edges[u].second == edges[v].second) graph.add(u, v);
                }
            }
            return graph;
        }
        if (command == "PRODUCT" || command == "UNION") {
            const Graph& second = graphs.at(a[2]);
            int n = command == "PRODUCT" ? source.n * second.n : source.n + second.n;
            range(n, 1, 16);
            Graph graph(n);
            if (command == "UNION") {
                for (const auto& [u, v] : source.edges()) graph.add(u, v);
                for (const auto& [u, v] : second.edges()) graph.add(u + source.n, v + source.n);
            } else {
                for (const auto& [u, v] : source.edges()) {
                    for (int y = 0; y < second.n; ++y) graph.add(u * second.n + y, v * second.n + y);
                }
                for (const auto& [u, v] : second.edges()) {
                    for (int x = 0; x < source.n; ++x) graph.add(x * second.n + u, x * second.n + v);
                }
            }
            return graph;
        }
        if (command == "CANONIZE") return relabel(source, CanonicalForm(source).labels);
        std::vector<int> values;
        for (std::size_t i = 2; i < a.size(); ++i) values.push_back(std::stoi(a[i]));
        if (command == "RELABEL") {
            std::vector<int> sorted = values;
            std::sort(sorted.begin(), sorted.end());
            std::vector<int> expected(source.n);
            std::iota(expected.begin(), expected.end(), 0);
            if (sorted != expected) fail("bad permutation");
            return relabel(source, values);
        }
        std::set<int> unique(values.begin(), values.end());
        if (unique.size() != values.size() || *unique.rbegin() >= source.n) fail("bad vertices");
        Graph graph(static_cast<int>(values.size()));
        for (int u = 0; u < graph.n; ++u) {
            for (int v = u + 1; v < graph.n; ++v) {
                if (source.adjacent[values[u]][values[v]]) graph.add(u, v);
            }
        }
        return graph;
    }

public:
    void execute(const std::string& line) {
        std::istringstream input(line);
        std::string command;
        input >> command;
        if (!formats.count(command)) fail("unknown command " + command);
        std::vector<std::string> arguments;
        for (std::string word; input >> word;) arguments.push_back(word);
        const Format& format = formats.at(command);
        int count = static_cast<int>(arguments.size());
        if (count < format.minimum || (format.maximum >= 0 && count > format.maximum)) fail("bad arguments");
        for (std::size_t i = 0; i < arguments.size(); ++i) {
            char kind = i < format.fixed.size() ? format.fixed[i] : format.tail;
            if ((kind == 'n' || kind == 'g') && !nameWord(arguments[i])) fail("bad arguments");
            if (kind == 'i' && !numberWord(arguments[i])) fail("bad arguments");
            if (kind == 'e') edgeWord(arguments[i]);
        }
        for (std::size_t i = 0; i < format.fixed.size(); ++i) {
            if (format.fixed[i] == 'g' && !graphs.count(arguments[i])) fail("no graph " + arguments[i]);
        }
        if (!format.fixed.empty() && format.fixed[0] == 'n') {
            Graph graph = build(command, arguments);
            bool existed = graphs.count(arguments[0]) != 0;
            graphs.insert_or_assign(arguments[0], graph);
            std::cout << (existed ? "redefined " : "defined ") << arguments[0] << " n " << graph.n << " m " << graph.edges().size() << '\n';
            return;
        }
        if (command == "LIST") {
            std::cout << "graphs " << graphs.size() << '\n';
            for (const auto& [name, graph] : graphs) std::cout << name << " n " << graph.n << " m " << graph.edges().size() << '\n';
            return;
        }
        if (command == "CLASSIFY") {
            classify(std::stoi(arguments[0]));
            return;
        }
        const std::string& name = arguments[0];
        const Graph& graph = graphs.at(name);
        if (command == "DELETE") {
            graphs.erase(name);
            std::cout << "deleted " << name << '\n';
        } else if (command == "SHOW") {
            std::cout << "graph " << name << " n " << graph.n << " m " << graph.edges().size() << '\n';
            for (int v = 0; v < graph.n; ++v) {
                std::cout << v << ':';
                for (int w = 0; w < graph.n; ++w) {
                    if (graph.adjacent[v][w]) std::cout << ' ' << w;
                }
                std::cout << '\n';
            }
        } else if (command == "INVARIANTS") printInvariants(name, graph);
        else if (command == "REFINE") {
            for (std::size_t i = 1; i < arguments.size(); ++i) {
                if (std::stoi(arguments[i]) >= graph.n) fail("bad vertices");
            }
            Refinement result = refine(graph, degreeColors(graph));
            for (std::size_t i = 1; i < arguments.size(); ++i) {
                int vertex = std::stoi(arguments[i]);
                if (std::count(result.colors.begin(), result.colors.end(), result.colors[vertex]) == 1) fail("singleton " + arguments[i]);
                Refinement next = refine(graph, individualize(result.colors, vertex));
                result.colors = std::move(next.colors);
                result.rounds += next.rounds;
            }
            std::cout << "refine " << name << " rounds " << result.rounds << " cells " << cellCount(result.colors) << '\n';
            for (int color = 0; color < cellCount(result.colors); ++color) {
                std::cout << color << ':';
                for (int v = 0; v < graph.n; ++v) {
                    if (result.colors[v] == color) std::cout << ' ' << v;
                }
                std::cout << '\n';
            }
        } else if (command == "CANON") {
            CanonicalForm result(graph);
            std::cout << "canon " << name << " nodes " << result.nodes << " leaves " << result.leaves << "\nlabels";
            sequence(result.labels);
            std::cout << "\nstring " << (result.bits.empty() ? "-" : result.bits) << '\n';
        } else if (command == "ISO") isomorphism(graph, graphs.at(arguments[1]));
        else if (command == "AUT") automorphisms(name, graph);
        else if (command == "SUBISO") subisomorphism(name, arguments[1], graph, graphs.at(arguments[1]));
    }
};

int main() {
    int count;
    std::cin >> count;
    std::string line;
    std::getline(std::cin, line);
    Laboratory laboratory;
    while (count-- > 0 && std::getline(std::cin, line)) {
        try {
            laboratory.execute(line);
        } catch (const std::runtime_error& error) {
            std::cout << "error: " << error.what() << '\n';
        }
    }
}
