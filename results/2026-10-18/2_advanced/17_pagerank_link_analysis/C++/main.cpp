#include "analysis.hpp"
#include <filesystem>
#include <optional>

static const Lines regions{"CORE", "IN", "OUT", "TUBE", "IN_TENDRIL", "OUT_TENDRIL", "OTHER"};
static const Lines quantities{"in_degree", "pagerank", "cheirank", "authority", "hub", "trustrank", "harmonic"};
static Nodes everyone(int count) { Nodes nodes(count); std::iota(nodes.begin(), nodes.end(), 0); return nodes; }
static void extend(Lines& target, const Lines& source) { target.insert(target.end(), source.begin(), source.end()); }
static Nodes rankOrder(const Values& values) {
    Nodes order = everyone(static_cast<int>(values.size()));
    std::sort(order.begin(), order.end(), [&](int first, int second) { Integer a = scaled(values[first]), b = scaled(values[second]); return a != b ? a > b : first < second; });
    return order;
}
static Nodes positions(const Nodes& order) { Nodes rank(order.size()); for (std::size_t i = 0; i < order.size(); ++i) rank[order[i]] = static_cast<int>(i + 1); return rank; }
static Nodes prefix(Nodes nodes, int limit) { if (nodes.size() > static_cast<std::size_t>(limit)) nodes.resize(limit); return nodes; }
static Nodes topList(const Values& values, int limit) { Nodes result; for (int node : rankOrder(values)) if (scaled(values[node]) > 0 && result.size() < static_cast<std::size_t>(limit)) result.push_back(node); return result; }
static Nodes rankedCounts(const Nodes& values, int limit) {
    Nodes result;
    for (int node = 0; node < static_cast<int>(values.size()); ++node) if (values[node] > 0) result.push_back(node);
    std::sort(result.begin(), result.end(), [&](int a, int b) { return values[a] != values[b] ? values[a] > values[b] : a < b; });
    return prefix(result, limit);
}
static Lines distribution(const Nodes& values) { std::map<int, int> counts; for (int value : values) ++counts[value]; Lines lines; for (const std::pair<const int, int>& entry : counts) add(lines, entry.first, ' ', entry.second); return lines; }
static Lines joinedBlocks(const std::vector<Lines>& blocks) { Lines lines; for (const Lines& block : blocks) { if (!lines.empty()) lines.push_back(""); extend(lines, block); } return lines; }
static std::string kendall(const Integers& first, const Integers& second) {
    Integer numerator = 0, count = static_cast<Integer>(first.size());
    for (std::size_t i = 0; i < first.size(); ++i) for (std::size_t j = i + 1; j < first.size(); ++j) {
        Integer dx = first[i] - first[j], dy = second[i] - second[j];
        if (dx && dy) numerator += (dx > 0) == (dy > 0) ? 1 : -1;
    }
    return fraction(numerator, count * (count - 1) / 2);
}
static Integers scaledValues(const Values& values) { Integers result; for (double value : values) result.push_back(scaled(value)); return result; }
static double total(const Values& values, const Nodes& nodes) { double result = 0; for (int node : nodes) result += values[node]; return result; }
static int overlap(const Nodes& first, const Nodes& second) { int result = 0; for (int node : first) result += std::find(second.begin(), second.end(), node) != second.end(); return result; }
struct Ignored { LinkRecord record; std::string reason; };
struct Graph {
    std::vector<Page> pages;
    int count;
    std::map<int, int> indexOf;
    Links links, inter;
    std::set<Link> linkSet;
    std::vector<Ignored> ignored;
    Adjacency successors, predecessors;
    WeightedEdges forward, reverse;
    Graph(const std::vector<Page>& pages, const std::vector<LinkRecord>& records) : pages(pages), count(static_cast<int>(pages.size())), successors(count), predecessors(count), forward(count), reverse(count) {
        for (int node = 0; node < count; ++node) indexOf[this->pages[node].id] = node;
        for (const LinkRecord& record : records) {
            if (!indexOf.count(record.source) || !indexOf.count(record.target)) ignored.push_back({record, "unknown"});
            else if (record.source == record.target) ignored.push_back({record, "self"});
            else if (!linkSet.insert({indexOf.at(record.source), indexOf.at(record.target)}).second) ignored.push_back({record, "duplicate"});
        }
        links.assign(linkSet.begin(), linkSet.end());
        for (const Link& edge : links) {
            int u = edge.first, v = edge.second;
            successors[u].push_back(v); predecessors[v].push_back(u);
            forward[v].emplace_back(u, 1); reverse[u].emplace_back(v, 1);
            if (this->pages[u].host != this->pages[v].host) inter.push_back(edge);
        }
    }
    Nodes ids(const Nodes& nodes) const { Nodes result; for (int node : nodes) result.push_back(pages[node].id); return result; }
    std::string describe(int position, int node, const std::string& value) const { const Page& page = pages[node]; return text(position, ' ', page.id, ' ', value, ' ', page.host, ' ', page.title); }
    Lines rankLines(const Nodes& nodes, const Values& values) const { Lines result; for (std::size_t i = 0; i < nodes.size(); ++i) result.push_back(describe(static_cast<int>(i + 1), nodes[i], fixed(values[nodes[i]]))); return result; }
};
struct Undirected {
    Adjacency neighbors;
    Nodes core;
    int edges = 0, closed = 0, possible = 0, eligible = 0, degeneracy = 0, weakCount = 0, weakLargest = 0;
    double clustering = 0;
    explicit Undirected(const Graph& graph) : neighbors(graph.count), core(graph.count) {
        std::vector<std::set<int>> adjacent(graph.count);
        for (const Link& edge : graph.links) { adjacent[edge.first].insert(edge.second); adjacent[edge.second].insert(edge.first); }
        for (int node = 0; node < graph.count; ++node) {
            neighbors[node].assign(adjacent[node].begin(), adjacent[node].end());
            int degree = static_cast<int>(neighbors[node].size());
            edges += degree;
            if (degree < 2) continue;
            int own = 0, choices = degree * (degree - 1) / 2;
            for (std::size_t i = 0; i < neighbors[node].size(); ++i) for (std::size_t j = i + 1; j < neighbors[node].size(); ++j) own += adjacent[neighbors[node][i]].count(neighbors[node][j]) != 0;
            closed += own; possible += choices; ++eligible;
            clustering += static_cast<double>(own) / choices;
        }
        edges /= 2; clustering /= eligible;
        Nodes remaining;
        for (const Nodes& group : neighbors) remaining.push_back(static_cast<int>(group.size()));
        std::vector<bool> removed(graph.count);
        int level = 0, left = graph.count;
        while (left) {
            int chosen = -1;
            for (int node = 0; node < graph.count; ++node) if (!removed[node] && remaining[node] <= level) { chosen = node; break; }
            if (chosen < 0) { ++level; continue; }
            removed[chosen] = true; core[chosen] = level; --left;
            for (int child : neighbors[chosen]) if (!removed[child]) --remaining[child];
        }
        degeneracy = *std::max_element(core.begin(), core.end());
        Nodes labels = weakComponents(neighbors), sizes(graph.count);
        for (int label : labels) ++sizes[label];
        weakCount = *std::max_element(labels.begin(), labels.end()) + 1;
        weakLargest = *std::max_element(sizes.begin(), sizes.end());
    }
};
struct ComponentTable {
    Adjacency groups;
    Nodes labels, incoming, outgoing;
    int edgeCount = 0, depth = 0, core = 0, singletons = 0;
    explicit ComponentTable(const Graph& graph) : groups(strongComponents(graph.successors)), labels(graph.count), incoming(groups.size()), outgoing(groups.size()) {
        for (Nodes& group : groups) std::sort(group.begin(), group.end());
        std::sort(groups.begin(), groups.end(), [](const Nodes& a, const Nodes& b) { return a.front() < b.front(); });
        for (int number = 0; number < static_cast<int>(groups.size()); ++number) {
            for (int node : groups[number]) labels[node] = number;
            if (groups[number].size() > groups[core].size()) core = number;
            singletons += groups[number].size() == 1;
        }
        std::set<Link> edges;
        for (const Link& edge : graph.links) if (labels[edge.first] != labels[edge.second]) { int a = labels[edge.first], b = labels[edge.second]; ++outgoing[a]; ++incoming[b]; edges.emplace(a, b); }
        edgeCount = static_cast<int>(edges.size());
        Adjacency successors(groups.size());
        Nodes pending(groups.size()), lengths(groups.size()), ready;
        for (const Link& edge : edges) { successors[edge.first].push_back(edge.second); ++pending[edge.second]; }
        for (int number = 0; number < static_cast<int>(groups.size()); ++number) if (!pending[number]) ready.push_back(number);
        while (!ready.empty()) {
            int node = ready.back(); ready.pop_back();
            for (int child : successors[node]) { lengths[child] = std::max(lengths[child], lengths[node] + 1); if (!--pending[child]) ready.push_back(child); }
        }
        depth = *std::max_element(lengths.begin(), lengths.end());
    }
};
static Nodes bowtie(const Graph& graph, const ComponentTable& table) {
    const Nodes& core = table.groups[table.core];
    std::vector<bool> forward = reachable(graph.successors, core), backward = reachable(graph.predecessors, core);
    Nodes labels(graph.count, 6), in, out;
    for (int node = 0; node < graph.count; ++node) {
        if (table.labels[node] == table.core) labels[node] = 0;
        else if (backward[node]) { labels[node] = 1; in.push_back(node); }
        else if (forward[node]) { labels[node] = 2; out.push_back(node); }
    }
    std::vector<bool> fromIn = reachable(graph.successors, in), toOut = reachable(graph.predecessors, out);
    for (int node = 0; node < graph.count; ++node) if (labels[node] == 6) labels[node] = fromIn[node] ? (toOut[node] ? 3 : 4) : (toOut[node] ? 5 : 6);
    return labels;
}
struct Distances {
    int pairs = 0, sum = 0, diameter = 0, source = 0, target = 0, effective = 0;
    Nodes histogram;
    Values harmonic;
    explicit Distances(const Graph& graph) : histogram(graph.count), harmonic(graph.count) {
        for (int u = 0; u < graph.count; ++u) {
            Nodes distance = bfsDistances(graph.successors, Nodes{u});
            for (int v = 0; v < graph.count; ++v) if (u != v && distance[v] >= 0) {
                int steps = distance[v];
                ++pairs; sum += steps; ++histogram[steps]; harmonic[v] += 1.0 / steps;
                if (steps > diameter) { diameter = steps; source = u; target = v; }
            }
        }
        int cumulative = 0;
        for (int steps = 1; steps <= diameter; ++steps) { cumulative += histogram[steps]; if (10 * cumulative >= 9 * pairs) { effective = steps; break; } }
    }
};
static Values salsa(int count, const Links& links) {
    Nodes degree(count), sizes(count), mass(count);
    Adjacency targets(count), neighbors(count);
    for (const Link& edge : links) { ++degree[edge.second]; targets[edge.first].push_back(edge.second); }
    for (const Nodes& group : targets) for (std::size_t i = 1; i < group.size(); ++i) { neighbors[group[i - 1]].push_back(group[i]); neighbors[group[i]].push_back(group[i - 1]); }
    Nodes labels = weakComponents(neighbors);
    int side = 0;
    for (int node = 0; node < count; ++node) if (degree[node]) { ++side; ++sizes[labels[node]]; mass[labels[node]] += degree[node]; }
    Values values(count);
    for (int node = 0; node < count; ++node) if (degree[node]) values[node] = static_cast<double>(sizes[labels[node]] * degree[node]) / (side * mass[labels[node]]);
    return values;
}
struct SubgraphScores {
    Values authority, hub, salsaAuthority, salsaHub;
    Nodes authorityTop, hubTop, salsaAuthorityTop, salsaHubTop, cocitation, coupling, related, similar;
    int cited, citing, authorityOverlap, hubOverlap, authorityHosts;
    SubgraphScores(const Graph& graph, const Nodes& base, const Links& links, const Settings& p) : cocitation(graph.count), coupling(graph.count) {
        std::pair<Values, Values> scores = hits(graph.count, base, links, p.hitsIterations);
        authority = std::move(scores.first); hub = std::move(scores.second);
        salsaAuthority = salsa(graph.count, links);
        Links reversed; for (const Link& edge : links) reversed.emplace_back(edge.second, edge.first);
        salsaHub = salsa(graph.count, reversed);
        authorityTop = topList(authority, p.topK); hubTop = topList(hub, p.topK);
        salsaAuthorityTop = topList(salsaAuthority, p.topK); salsaHubTop = topList(salsaHub, p.topK);
        authorityOverlap = overlap(authorityTop, salsaAuthorityTop); hubOverlap = overlap(hubTop, salsaHubTop);
        std::set<std::string> hosts; for (int node : authorityTop) hosts.insert(graph.pages[node].host);
        authorityHosts = static_cast<int>(hosts.size());
        cited = authorityTop.front(); citing = hubTop.front();
        for (int source : graph.predecessors[cited]) for (int target : graph.successors[source]) if (target != cited) ++cocitation[target];
        for (int target : graph.successors[citing]) for (int source : graph.predecessors[target]) if (source != citing) ++coupling[source];
        related = rankedCounts(cocitation, p.topK); similar = rankedCounts(coupling, p.topK);
    }
};
struct QueryResult {
    Query query;
    Nodes matches, root, base, top;
    Links links;
    int dropped = 0, reach = 0, globalOverlap = 0;
    double seedMass;
    PageRankResult personalized;
    std::optional<SubgraphScores> sub;
    QueryResult(const Query& query, const Graph& graph, const Nodes& order, const Nodes& rank, const Settings& p) : query(query) {
        for (int node : order) {
            bool accepted = true;
            for (const std::string& word : query.words) {
                bool exclude = word.front() == '-';
                std::string term = exclude ? word.substr(1) : word;
                bool found = std::find(graph.pages[node].words.begin(), graph.pages[node].words.end(), term) != graph.pages[node].words.end();
                if (found == exclude) accepted = false;
            }
            if (accepted) matches.push_back(node);
        }
        root = prefix(matches, p.rootLimit);
        std::vector<bool> inBase(graph.count);
        for (int node : root) {
            inBase[node] = true;
            for (int child : prefix(graph.successors[node], p.neighborLimit)) inBase[child] = true;
            for (int child : prefix(graph.predecessors[node], p.neighborLimit)) inBase[child] = true;
        }
        for (int node = 0; node < graph.count; ++node) if (inBase[node]) base.push_back(node);
        for (const Link& edge : graph.links) if (inBase[edge.first] && inBase[edge.second]) {
            if (graph.pages[edge.first].host == graph.pages[edge.second].host) ++dropped;
            else links.push_back(edge);
        }
        Nodes seeds; for (int id : query.seeds) seeds.push_back(graph.indexOf.at(id)); std::sort(seeds.begin(), seeds.end());
        personalized = powerIteration(graph.forward, seeds, p.damping, p.iterations, p.tolerance);
        std::vector<bool> seen = reachable(graph.successors, seeds);
        reach = static_cast<int>(std::count(seen.begin(), seen.end(), true));
        seedMass = total(personalized.values, seeds);
        top = topList(personalized.values, p.topK);
        for (int node : top) globalOverlap += rank[node] <= p.topK;
        if (!links.empty()) sub.emplace(graph, base, links, p);
    }
};
struct HostGraph {
    Lines names;
    Adjacency members, weight;
    Nodes internal, outgoing, incoming, rank;
    Links edges, heavy;
    int reciprocal = 0, componentCount, largest = 0;
    PageRankResult run;
    HostGraph(const Graph& graph, const Settings& p) {
        std::set<std::string> hosts;
        for (const Page& page : graph.pages) hosts.insert(page.host);
        names.assign(hosts.begin(), hosts.end());
        int count = static_cast<int>(names.size());
        std::map<std::string, int> index;
        for (int i = 0; i < count; ++i) index[names[i]] = i;
        Nodes ofPage;
        members.resize(count); weight.assign(count, Nodes(count)); internal.resize(count); outgoing.resize(count); incoming.resize(count);
        for (int node = 0; node < graph.count; ++node) { int own = index.at(graph.pages[node].host); ofPage.push_back(own); members[own].push_back(node); }
        for (const Link& edge : graph.links) {
            int first = ofPage[edge.first], second = ofPage[edge.second];
            if (first == second) ++internal[first];
            else { ++weight[first][second]; ++outgoing[first]; ++incoming[second]; }
        }
        Adjacency adjacency(count);
        WeightedEdges inEdges(count);
        for (int first = 0; first < count; ++first) for (int second = 0; second < count; ++second) if (weight[first][second]) { edges.emplace_back(first, second); adjacency[first].push_back(second); inEdges[second].emplace_back(first, weight[first][second]); reciprocal += weight[second][first] > 0; }
        Adjacency components = strongComponents(adjacency);
        componentCount = static_cast<int>(components.size());
        for (const Nodes& group : components) largest = std::max(largest, static_cast<int>(group.size()));
        run = powerIteration(inEdges, everyone(count), p.damping, p.iterations, p.tolerance);
        rank = positions(rankOrder(run.values));
        heavy = edges;
        std::sort(heavy.begin(), heavy.end(), [&](const Link& a, const Link& b) { return weight[a.first][a.second] != weight[b.first][b.second] ? weight[a.first][a.second] > weight[b.first][b.second] : a < b; });
        if (heavy.size() > static_cast<std::size_t>(p.topK)) heavy.resize(p.topK);
    }
};
class Analysis {
    Input input;
    Graph graph;
    Undirected undirected;
    ComponentTable table;
    Nodes region;
    Distances distances;
    PageRankResult pr, cr, tr;
    Values authority, hub, trustRatio;
    Nodes order, rank, cheirankRank, trustDistance, suspects;
    Lines suspectHosts;
    std::optional<PageRankResult> demoted;
    int removed = 0;
    std::vector<std::pair<double, PageRankResult>> sweeps;
    std::vector<QueryResult> results;
    HostGraph hosts;
    int representative(const Nodes& members) const { return *std::min_element(members.begin(), members.end(), [&](int a, int b) { return rank[a] < rank[b]; }); }
    Lines graphStats() const {
        int intra = static_cast<int>(graph.links.size() - graph.inter.size()), reciprocal = 0;
        Nodes inDegree, outDegree, dangling, noIn;
        for (int node = 0; node < graph.count; ++node) { inDegree.push_back(static_cast<int>(graph.predecessors[node].size())); outDegree.push_back(static_cast<int>(graph.successors[node].size())); if (!inDegree.back()) noIn.push_back(node); if (!outDegree.back()) dangling.push_back(node); }
        for (const Link& edge : graph.links) reciprocal += graph.linkSet.count({edge.second, edge.first}) != 0;
        Lines lines{text("pages ", graph.count), text("hosts ", hosts.names.size()), text("link_rows ", input.records.size()), text("links ", graph.links.size())};
        for (const std::string& reason : Lines{"unknown", "self", "duplicate"}) { int count = 0; for (const Ignored& ignored : graph.ignored) count += ignored.reason == reason; add(lines, "ignored_", reason, ' ', count); }
        for (const Ignored& ignored : graph.ignored) add(lines, "ignored line ", ignored.record.line, ' ', ignored.record.source, ',', ignored.record.target, ' ', ignored.reason);
        add(lines, "intra_host_links ", intra); add(lines, "inter_host_links ", graph.inter.size());
        add(lines, "mean_degree ", fixed(static_cast<double>(graph.links.size()) / graph.count, 4)); add(lines, "reciprocity ", fraction(reciprocal, static_cast<Integer>(graph.links.size())));
        add(lines, "dangling ", dangling.size(), dangling.empty() ? "" : " " + join(graph.ids(dangling))); add(lines, "no_in_links ", noIn.size(), noIn.empty() ? "" : " " + join(graph.ids(noIn)));
        for (const std::pair<std::string, Nodes>& entry : std::vector<std::pair<std::string, Nodes>>{{"in", inDegree}, {"out", outDegree}}) {
            int largest = *std::max_element(entry.second.begin(), entry.second.end()); Nodes nodes;
            for (int node = 0; node < graph.count; ++node) if (entry.second[node] == largest) nodes.push_back(node);
            add(lines, "max_", entry.first, "_degree ", largest, " pages ", join(graph.ids(nodes)));
        }
        extend(lines, Lines{"", "in_degree_distribution"}); extend(lines, distribution(inDegree));
        extend(lines, Lines{"", "out_degree_distribution"}); extend(lines, distribution(outDegree));
        lines.push_back(""); add(lines, "undirected_links ", undirected.edges); add(lines, "transitivity ", fraction(undirected.closed, undirected.possible));
        add(lines, "average_clustering ", fixed(undirected.clustering, 4), " pages ", undirected.eligible);
        add(lines, "degeneracy ", undirected.degeneracy, " pages ", std::count(undirected.core.begin(), undirected.core.end(), undirected.degeneracy));
        lines.push_back("core_distribution"); extend(lines, distribution(undirected.core)); lines.push_back("");
        add(lines, "strong_components ", table.groups.size(), " largest ", table.groups[table.core].size(), " singletons ", table.singletons, " condensation_links ", table.edgeCount);
        add(lines, "weak_components ", undirected.weakCount, " largest ", undirected.weakLargest); add(lines, "condensation_depth ", table.depth);
        for (int number = 0; number < static_cast<int>(table.groups.size()); ++number) if (table.groups[number].size() >= 2) add(lines, "scc ", number + 1, " size ", table.groups[number].size(), " min ", graph.pages[table.groups[number].front()].id, " incoming ", table.incoming[number], " outgoing ", table.outgoing[number], " pagerank ", fixed(total(pr.values, table.groups[number])), table.outgoing[number] == 0 ? " sink" : "");
        lines.push_back(""); add(lines, "bowtie core_scc ", table.core + 1);
        for (int number = 0; number < 7; ++number) {
            Nodes members; for (int node = 0; node < graph.count; ++node) if (region[node] == number) members.push_back(node);
            std::string own = text(regions[number], ' ', members.size(), " pagerank ", fixed(total(pr.values, members)));
            if (!members.empty()) own += text(" top ", graph.pages[representative(members)].id);
            if (!members.empty() && members.size() <= 10) own += " pages " + join(graph.ids(members));
            lines.push_back(own);
        }
        Adjacency counts(7, Nodes(7)); for (const Link& edge : graph.links) ++counts[region[edge.first]][region[edge.second]];
        lines.push_back("region_links");
        for (int a = 0; a < 7; ++a) for (int b = 0; b < 7; ++b) if (counts[a][b]) add(lines, regions[a], ' ', regions[b], ' ', counts[a][b]);
        extend(lines, Lines{"", "distances"}); add(lines, "reachable_pairs ", distances.pairs); add(lines, "average ", fraction(distances.sum, distances.pairs));
        add(lines, "diameter ", distances.diameter, " from ", graph.pages[distances.source].id, " to ", graph.pages[distances.target].id); add(lines, "effective_diameter ", distances.effective);
        for (int steps = 1; steps <= distances.diameter; ++steps) add(lines, steps, ' ', distances.histogram[steps]);
        return lines;
    }
    Lines pagerankCsv() const {
        Lines lines{"id,in_degree,out_degree,scc,region,kcore,harmonic,pagerank,pagerank_rank,cheirank,cheirank_rank,authority,hub,trustrank,trust_ratio,trust_distance"};
        for (int node = 0; node < graph.count; ++node) add(lines, graph.pages[node].id, ',', graph.predecessors[node].size(), ',', graph.successors[node].size(), ',', table.labels[node] + 1, ',', regions[region[node]], ',', undirected.core[node], ',', fixed(distances.harmonic[node]), ',', fixed(pr.values[node]), ',', rank[node], ',', fixed(cr.values[node]), ',', cheirankRank[node], ',', fixed(authority[node]), ',', fixed(hub[node]), ',', fixed(tr.values[node]), ',', fixed(trustRatio[node], 4), ',', trustDistance[node]);
        return lines;
    }
    Lines rankings() const {
        const Settings& p = input.settings;
        std::vector<const Values*> values{&pr.values, &cr.values, &authority, &hub, &tr.values, &distances.harmonic};
        std::vector<Lines> blocks;
        for (std::size_t number = 0; number < values.size(); ++number) {
            Lines lines{text(quantities[number + 1], " top ", p.topK)};
            Nodes top = topList(*values[number], p.topK); extend(lines, graph.rankLines(top, *values[number]));
            if (number == 0) {
                Nodes dangling; for (int node = 0; node < graph.count; ++node) if (graph.successors[node].empty()) dangling.push_back(node);
                add(lines, "dangling_mass ", fixed(total(pr.values, dangling)));
                for (int node : top) {
                    Nodes contributors = graph.predecessors[node];
                    const std::function<double(int)> contribution = [&](int source) { return (p.damping * pr.values[source]) / graph.successors[source].size(); };
                    std::sort(contributors.begin(), contributors.end(), [&](int a, int b) { Integer first = scaled(contribution(a)), second = scaled(contribution(b)); return first != second ? first > second : a < b; });
                    std::string own = text("contributors ", graph.pages[node].id);
                    for (int source : prefix(contributors, 3)) own += text(' ', graph.pages[source].id, ' ', fixed(contribution(source)));
                    lines.push_back(own);
                }
            }
            blocks.push_back(std::move(lines));
        }
        std::vector<Integers> series(1);
        for (const Nodes& sources : graph.predecessors) series.front().push_back(static_cast<Integer>(sources.size()));
        for (const Values* scores : values) series.push_back(scaledValues(*scores));
        Lines correlation{"correlation"};
        for (int a = 0; a < 7; ++a) for (int b = a + 1; b < 7; ++b) add(correlation, quantities[a], ' ', quantities[b], ' ', kendall(series[a], series[b]));
        blocks.push_back(correlation);
        Lines sweepLines{"damping_sweep"};
        for (const std::pair<double, PageRankResult>& sweep : sweeps) {
            Nodes sweepOrder = rankOrder(sweep.second.values), ranks = positions(sweepOrder);
            int shared = 0, footrule = 0, shift = 0;
            for (int node = 0; node < graph.count; ++node) { shared += rank[node] <= p.topK && ranks[node] <= p.topK; footrule += std::abs(rank[node] - ranks[node]); if (std::abs(rank[node] - ranks[node]) > std::abs(rank[shift] - ranks[shift])) shift = node; }
            add(sweepLines, "damping ", fixed(sweep.first, 4), " overlap ", shared, " footrule ", footrule, " kendall ", kendall(scaledValues(pr.values), scaledValues(sweep.second.values)), " largest_shift ", graph.pages[shift].id, ' ', rank[shift], ' ', ranks[shift]);
            add(sweepLines, "top ", join(graph.ids(prefix(sweepOrder, p.topK))));
        }
        blocks.push_back(sweepLines);
        Lines spam{text("spam top ", p.spamTop, " threshold ", fixed(p.spamThreshold, 4))};
        for (int node : suspects) add(spam, "suspect ", graph.pages[node].id, " rank ", rank[node], " pagerank ", fixed(pr.values[node]), " trustrank ", fixed(tr.values[node]), " trust_ratio ", fixed(trustRatio[node], 4), " trust_distance ", trustDistance[node], " kcore ", undirected.core[node], ' ', graph.pages[node].host);
        add(spam, "count ", suspects.size()); spam.push_back("trust_by_distance");
        std::set<int> seenDistances; for (int distance : trustDistance) if (distance >= 0) seenDistances.insert(distance);
        Nodes sortedDistances(seenDistances.begin(), seenDistances.end()); if (std::find(trustDistance.begin(), trustDistance.end(), -1) != trustDistance.end()) sortedDistances.push_back(-1);
        for (int distance : sortedDistances) { Nodes members; for (int node = 0; node < graph.count; ++node) if (trustDistance[node] == distance) members.push_back(node); add(spam, distance < 0 ? "unreachable" : text(distance), " pages ", members.size(), " trustrank ", fixed(total(tr.values, members)), " pagerank ", fixed(total(pr.values, members))); }
        blocks.push_back(spam);
        Lines demotion{"demotion none"};
        if (demoted) {
            demotion = {text("demotion hosts ", join(suspectHosts), " removed_links ", removed)};
            Nodes ranks = positions(rankOrder(demoted->values)), top = topList(demoted->values, p.topK);
            for (std::size_t i = 0; i < top.size(); ++i) { int node = top[i]; demotion.push_back(graph.describe(static_cast<int>(i + 1), node, text(fixed(demoted->values[node]), " was ", rank[node]))); }
            for (int node : suspects) add(demotion, "suspect ", graph.pages[node].id, " before ", rank[node], " after ", ranks[node]);
        }
        blocks.push_back(demotion);
        Lines host{text("host_graph hosts ", hosts.names.size(), " links ", hosts.edges.size(), " reciprocal ", hosts.reciprocal, " strong_components ", hosts.componentCount, " largest ", hosts.largest), text("host_links top ", p.topK)};
        for (const Link& edge : hosts.heavy) add(host, hosts.names[edge.first], ' ', hosts.names[edge.second], ' ', hosts.weight[edge.first][edge.second]);
        blocks.push_back(host);
        return joinedBlocks(blocks);
    }
    static Lines convergenceBlock(const std::string& heading, const PageRankResult& run) {
        Lines lines{"", heading};
        for (std::size_t step = 10; step <= run.changes.size(); step += 10) add(lines, "iteration ", step, " l1 ", fixed(run.changes[step - 1], 10));
        add(lines, "converged_at ", run.converged ? text(run.converged) : "none");
        return lines;
    }
    Lines convergence() const {
        const Settings& p = input.settings;
        std::string damping = fixed(p.damping, 4);
        Lines lines{text("iterations ", p.iterations, " tolerance ", fixed(p.tolerance, 10))};
        extend(lines, convergenceBlock("pagerank damping " + damping, pr));
        extend(lines, convergenceBlock("cheirank damping " + damping, cr));
        extend(lines, convergenceBlock(text("trustrank damping ", damping, " seeds ", p.trusted.size()), tr));
        for (const std::pair<double, PageRankResult>& sweep : sweeps) extend(lines, convergenceBlock("sweep damping " + fixed(sweep.first, 4), sweep.second));
        if (demoted) extend(lines, convergenceBlock("demoted damping " + damping, *demoted));
        for (const QueryResult& result : results) extend(lines, convergenceBlock(text("personalized query ", result.query.number, " damping ", damping), result.personalized));
        extend(lines, convergenceBlock(text("host_pagerank damping ", damping, " hosts ", hosts.names.size()), hosts.run));
        return lines;
    }
    Lines queryLines(const QueryResult& result) const {
        const Settings& p = input.settings;
        Lines lines{text("query ", result.query.number, " words ", join(result.query.words), " seeds ", join(result.query.seeds)), text("matched ", result.matches.size(), " root ", result.root.size(), " base ", result.base.size(), " links ", result.links.size(), " dropped_intra_host ", result.dropped), "results"};
        extend(lines, graph.rankLines(prefix(result.matches, p.topK), pr.values));
        add(lines, "personalized reach ", result.reach, " seed_mass ", fixed(result.seedMass)); extend(lines, graph.rankLines(result.top, result.personalized.values)); add(lines, "overlap_with_global ", result.globalOverlap);
        if (!result.sub) { lines.push_back("hits none"); return lines; }
        const SubgraphScores& s = *result.sub;
        lines.push_back("hits authorities"); extend(lines, graph.rankLines(s.authorityTop, s.authority));
        lines.push_back("hits hubs"); extend(lines, graph.rankLines(s.hubTop, s.hub));
        lines.push_back("salsa authorities"); extend(lines, graph.rankLines(s.salsaAuthorityTop, s.salsaAuthority));
        lines.push_back("salsa hubs"); extend(lines, graph.rankLines(s.salsaHubTop, s.salsaHub));
        add(lines, "hits_salsa_overlap authorities ", s.authorityOverlap, " hubs ", s.hubOverlap, " authority_hosts ", s.authorityHosts);
        add(lines, "related_to ", graph.pages[s.cited].id, " citing ", graph.predecessors[s.cited].size());
        for (std::size_t i = 0; i < s.related.size(); ++i) { int node = s.related[i]; lines.push_back(graph.describe(static_cast<int>(i + 1), node, text(s.cocitation[node]))); }
        add(lines, "coupled_to ", graph.pages[s.citing].id, " cited ", graph.successors[s.citing].size());
        for (std::size_t i = 0; i < s.similar.size(); ++i) { int node = s.similar[i]; lines.push_back(graph.describe(static_cast<int>(i + 1), node, text(s.coupling[node]))); }
        return lines;
    }
    Lines hostsCsv() const {
        Lines lines{"host,pages,core_pages,internal_links,internal_density,outgoing_links,incoming_links,dangling_pages,page_score_sum,top_page,score,rank"};
        for (int number = 0; number < static_cast<int>(hosts.names.size()); ++number) {
            const Nodes& members = hosts.members[number];
            int size = static_cast<int>(members.size()), core = 0, dangling = 0;
            for (int node : members) { core += region[node] == 0; dangling += graph.successors[node].empty(); }
            double density = size >= 2 ? static_cast<double>(hosts.internal[number]) / (size * (size - 1)) : 0;
            add(lines, hosts.names[number], ',', size, ',', core, ',', hosts.internal[number], ',', fixed(density, 4), ',', hosts.outgoing[number], ',', hosts.incoming[number], ',', dangling, ',', fixed(total(pr.values, members)), ',', graph.pages[representative(members)].id, ',', fixed(hosts.run.values[number]), ',', hosts.rank[number]);
        }
        return lines;
    }
public:
    explicit Analysis(Input input) : input(std::move(input)), graph(this->input.pages, this->input.records), undirected(graph), table(graph), region(bowtie(graph, table)), distances(graph), hosts(graph, this->input.settings) {
        const Settings& p = this->input.settings;
        Nodes trusted; for (int id : p.trusted) trusted.push_back(graph.indexOf.at(id)); std::sort(trusted.begin(), trusted.end());
        pr = powerIteration(graph.forward, everyone(graph.count), p.damping, p.iterations, p.tolerance);
        cr = powerIteration(graph.reverse, everyone(graph.count), p.damping, p.iterations, p.tolerance);
        tr = powerIteration(graph.forward, trusted, p.damping, p.iterations, p.tolerance);
        std::pair<Values, Values> scores = hits(graph.count, everyone(graph.count), graph.inter, p.hitsIterations);
        authority = std::move(scores.first); hub = std::move(scores.second);
        order = rankOrder(pr.values); rank = positions(order); cheirankRank = positions(rankOrder(cr.values));
        for (int node = 0; node < graph.count; ++node) trustRatio.push_back(tr.values[node] / pr.values[node]);
        trustDistance = bfsDistances(graph.successors, trusted);
        std::set<std::string> hostSet;
        for (int node : prefix(order, p.spamTop)) if (static_cast<double>(scaled(trustRatio[node], 4)) / 10000 < p.spamThreshold) { suspects.push_back(node); hostSet.insert(graph.pages[node].host); }
        suspectHosts.assign(hostSet.begin(), hostSet.end());
        if (!suspects.empty()) {
            WeightedEdges kept(graph.count);
            for (const Link& edge : graph.links) {
                if (graph.pages[edge.first].host == graph.pages[edge.second].host && hostSet.count(graph.pages[edge.first].host)) ++removed;
                else kept[edge.second].emplace_back(edge.first, 1);
            }
            demoted = powerIteration(kept, everyone(graph.count), p.damping, p.iterations, p.tolerance);
        }
        for (double damping : p.sweep) sweeps.emplace_back(damping, powerIteration(graph.forward, everyone(graph.count), damping, p.iterations, p.tolerance));
        for (const Query& query : this->input.queries) results.emplace_back(query, graph, order, rank, p);
    }
    void run() const {
        std::filesystem::create_directories("output");
        writeLines("graph_stats.txt", graphStats()); writeLines("pagerank.csv", pagerankCsv()); writeLines("rankings.txt", rankings()); writeLines("convergence.txt", convergence());
        std::vector<Lines> blocks; for (const QueryResult& result : results) blocks.push_back(queryLines(result));
        writeLines("queries.txt", joinedBlocks(blocks)); writeLines("hosts.csv", hostsCsv());
    }
};
int main() { Analysis analysis(readInput()); analysis.run(); }
