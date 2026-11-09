using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;


class Program {
    public static readonly string[] REGIONS = {"CORE", "IN", "OUT", "TUBE", "IN_TENDRIL", "OUT_TENDRIL", "OTHER"};
    public static readonly string[] QUANTITIES = {"in_degree", "pagerank", "cheirank", "authority", "hub", "trustrank", "harmonic"};
    public static readonly string PAGERANK_HEADER = "id,in_degree,out_degree,scc,region,kcore,harmonic,pagerank,pagerank_rank,cheirank,cheirank_rank,authority,hub,trustrank,trust_ratio,trust_distance";
    public static readonly string HOSTS_HEADER = "host,pages,core_pages,internal_links,internal_density,outgoing_links,incoming_links,dangling_pages,page_score_sum,top_page,score,rank";
    public sealed record Ignored(LinkRecord record, string reason);
    public static List<int> range(int count) { return Enumerable.Range(0, count).ToList(); }
    public static List<List<int>> lists(int count) {
        List<List<int>> result = new();
        for (int i = 0; i < count; i++) result.Add(new());
        return result;
    }
    public static List<List<WeightedEdge>> weightedLists(int count) {
        List<List<WeightedEdge>> result = new();
        for (int i = 0; i < count; i++) result.Add(new());
        return result;
    }
    public static string line(params object[] parts) {
        return string.Join(" ", parts.Select(part => Convert.ToString(part, CultureInfo.InvariantCulture)));
    }
    public static List<string> blocks(List<List<string>> groups) {
        List<string> lines = new();
        foreach (List<string> group in groups) { if (lines.Count != 0) lines.Add(""); lines.AddRange(group); }
        return lines;
    }
    public static string appendValues<T>(string prefix, IEnumerable<T> values) {
        return !values.Any() ? prefix : prefix + " " + string.Join(" ", values.Select(value => Convert.ToString(value, CultureInfo.InvariantCulture)));
    }
    public static double total(double[] values, List<int> nodes) {
        double result = 0;
        foreach (int node in nodes) result += values[node];
        return result;
    }
    public static List<int> rankOrder(double[] values) {
        return range(values.Length).OrderByDescending(node => Report.scaled(values[node])).ThenBy(node => node).ToList();
    }
    public static int[] positions(List<int> order) {
        int[] rank = new int[order.Count];
        for (int position = 0; position < order.Count; position++) rank[order[position]] = position + 1;
        return rank;
    }
    public static List<int> top(double[] values, int limit) {
        return rankOrder(values).Where(node => Report.scaled(values[node]) > 0).Take(limit).ToList();
    }
    public static List<int> rankedCounts(int[] counts, int limit) {
        return range(counts.Length).Where(node => counts[node] > 0).OrderByDescending(node => counts[node]).ThenBy(node => node).Take(limit).ToList();
    }
    public static SortedDictionary<int, int> distribution(int[] values) {
        SortedDictionary<int, int> counts = new();
        foreach (int value in values) counts[value] = counts.GetValueOrDefault(value) + 1;
        return counts;
    }
    public static long[] scaled(double[] values) {
        long[] result = new long[values.Length];
        for (int i = 0; i < values.Length; i++) result[i] = Report.scaled(values[i]);
        return result;
    }
    public static string kendall(long[] first, long[] second) {
        int concordant = 0, discordant = 0;
        for (int i = 0; i < first.Length; i++) for (int j = i + 1; j < first.Length; j++) {
            long dx = first[i] - first[j], dy = second[i] - second[j];
            if (dx == 0 || dy == 0) continue;
            if ((dx > 0) == (dy > 0)) concordant++; else discordant++;
        }
        return Report.fraction(concordant - discordant, (long) first.Length * (first.Length - 1) / 2);
    }
    public static PageRankResult pageRank(List<List<WeightedEdge>> edges, List<int> teleport, double damping, Settings settings) {
        return PageRank.compute(edges, teleport, damping, settings.iterations, settings.tolerance);
    }
    public sealed class Graph {
        public readonly List<Page> pages;
        public readonly int count;
        public readonly List<Edge> links;
        public readonly HashSet<Edge> linkSet;
        public readonly List<List<int>> successors, predecessors;
        public Graph(List<Page> pages, List<Edge> links) {
            this.pages = pages; count = pages.Count;
            this.links = links.OrderBy(edge => edge.source).ThenBy(edge => edge.target).ToList();
            linkSet = new HashSet<Edge>(links); successors = lists(count); predecessors = lists(count);
            foreach (Edge edge in this.links) { successors[edge.source].Add(edge.target); predecessors[edge.target].Add(edge.source); }
        }
        public string host(int node) { return pages[node].host; }
        public int id(int node) { return pages[node].id; }
        public bool intra(Edge edge) { return host(edge.source).Equals(host(edge.target)); }
        public List<Edge> inter(List<Edge> edges) { return edges.Where(edge => !intra(edge)).ToList(); }
        public List<int> dangling() { return range(count).Where(node => successors[node].Count == 0).ToList(); }
        public List<int> ids(List<int> nodes) { return nodes.Select(id).ToList(); }
        public List<List<WeightedEdge>> forward() {
            List<List<WeightedEdge>> edges = weightedLists(count);
            for (int node = 0; node < count; node++) foreach (int source in predecessors[node]) edges[node].Add(new WeightedEdge(source, 1));
            return edges;
        }
        public List<List<WeightedEdge>> reverse() {
            List<List<WeightedEdge>> edges = weightedLists(count);
            for (int node = 0; node < count; node++) foreach (int target in successors[node]) edges[node].Add(new WeightedEdge(target, 1));
            return edges;
        }
        public string describe(int position, int node, params object[] values) {
            List<object> parts = [position, id(node)];
            parts.AddRange(values); parts.Add(host(node)); parts.Add(pages[node].title);
            return line(parts.ToArray());
        }
    }
    public static int[] kcores(List<List<int>> neighbors) {
        int count = neighbors.Count, level = 0, left = count;
        int[] degree = neighbors.Select(group => group.Count).ToArray(), core = new int[count];
        bool[] removed = new bool[count];
        while (left > 0) {
            int candidate = -1;
            for (int node = 0; node < count; node++) if (!removed[node] && degree[node] <= level) { candidate = node; break; }
            if (candidate < 0) { level++; continue; }
            removed[candidate] = true; core[candidate] = level; left--;
            foreach (int neighbor in neighbors[candidate]) if (!removed[neighbor]) degree[neighbor]--;
        }
        return core;
    }
    public sealed class Undirected {
        public readonly List<List<int>> neighbors;
        public readonly bool[][] adjacent;
        public readonly int edgeCount, closed, possible, eligible, degeneracy, weakCount, weakLargest;
        public readonly double clustering;
        public readonly int[] kcore;
        public Undirected(Graph graph) {
            adjacent = Enumerable.Range(0, graph.count).Select(_ => new bool[graph.count]).ToArray(); neighbors = lists(graph.count);
            foreach (Edge edge in graph.links) { adjacent[edge.source][edge.target] = true; adjacent[edge.target][edge.source] = true; }
            int degreeSum = 0, closedSum = 0, possibleSum = 0, eligibleCount = 0; double localSum = 0;
            for (int node = 0; node < graph.count; node++) {
                List<int> group = neighbors[node];
                for (int other = 0; other < graph.count; other++) if (adjacent[node][other]) group.Add(other);
                degreeSum += group.Count;
                if (group.Count < 2) continue;
                int closedHere = 0, possibleHere = group.Count * (group.Count - 1) / 2;
                for (int a = 0; a < group.Count; a++) for (int b = a + 1; b < group.Count; b++) if (adjacent[group[a]][group[b]]) closedHere++;
                closedSum += closedHere; possibleSum += possibleHere; eligibleCount++; localSum += (double) closedHere / possibleHere;
            }
            edgeCount = degreeSum / 2; closed = closedSum; possible = possibleSum; eligible = eligibleCount; clustering = localSum / eligible;
            kcore = kcores(neighbors); degeneracy = kcore.Max();
            int[] labels = Components.weak(neighbors), sizes = new int[graph.count];
            foreach (int label in labels) sizes[label]++;
            weakCount = labels.Max() + 1; weakLargest = sizes.Max();
        }
    }
    public static int longestPath(int count, HashSet<Edge> edges) {
        List<List<int>> successors = lists(count); int[] pending = new int[count], length = new int[count];
        foreach (Edge edge in edges) { successors[edge.source].Add(edge.target); pending[edge.target]++; }
        Stack<int> ready = new();
        for (int node = 0; node < count; node++) if (pending[node] == 0) ready.Push(node);
        while (ready.Count != 0) {
            int node = ready.Pop();
            foreach (int target in successors[node]) { length[target] = Math.Max(length[target], length[node] + 1); if (--pending[target] == 0) ready.Push(target); }
        }
        return length.Max();
    }
    public sealed class ComponentTable {
        public readonly List<List<int>> groups;
        public readonly int[] labels, incoming, outgoing;
        public readonly int edgeCount, depth, core, singletons;
        public ComponentTable(Graph graph) {
            groups = new();
            foreach (List<int> group in Components.strong(graph.successors)) groups.Add(group.OrderBy(node => node).ToList());
            groups.Sort((a, b) => a[0].CompareTo(b[0])); labels = new int[graph.count];
            for (int j = 0; j < groups.Count; j++) foreach (int node in groups[j]) labels[node] = j;
            incoming = new int[groups.Count]; outgoing = new int[groups.Count]; HashSet<Edge> edges = new();
            foreach (Edge edge in graph.links) {
                int a = labels[edge.source], b = labels[edge.target];
                if (a != b) { outgoing[a]++; incoming[b]++; edges.Add(new Edge(a, b)); }
            }
            edgeCount = edges.Count; depth = longestPath(groups.Count, edges);
            int largest = 0, singles = 0;
            for (int j = 0; j < groups.Count; j++) { if (groups[j].Count > groups[largest].Count) largest = j; if (groups[j].Count == 1) singles++; }
            core = largest; singletons = singles;
        }
    }
    public static int[] bowtie(Graph graph, List<int> core) {
        bool[] forward = Components.reachable(graph.successors, core), backward = Components.reachable(graph.predecessors, core), inCore = new bool[graph.count];
        foreach (int node in core) inCore[node] = true;
        int[] regions = new int[graph.count]; Array.Fill(regions, 6);
        for (int node = 0; node < graph.count; node++) {
            if (inCore[node]) regions[node] = 0; else if (backward[node]) regions[node] = 1; else if (forward[node]) regions[node] = 2;
        }
        List<int> incomingNodes = range(graph.count).Where(node => regions[node] == 1).ToList(), outgoingNodes = range(graph.count).Where(node => regions[node] == 2).ToList();
        bool[] fromIn = Components.reachable(graph.successors, incomingNodes), toOut = Components.reachable(graph.predecessors, outgoingNodes);
        for (int node = 0; node < graph.count; node++) {
            if (inCore[node] || backward[node] || forward[node]) continue;
            if (fromIn[node] && toOut[node]) regions[node] = 3; else if (fromIn[node]) regions[node] = 4; else if (toOut[node]) regions[node] = 5;
        }
        return regions;
    }
    public sealed class DistanceStats {
        public int pairs, total, diameter, source, target;
        public readonly int[] histogram;
        public readonly double[] harmonic;
        public DistanceStats(Graph graph) {
            histogram = new int[graph.count]; harmonic = new double[graph.count];
            for (int from = 0; from < graph.count; from++) {
                int[] distance = Components.distances(graph.successors, [from]);
                for (int to = 0; to < graph.count; to++) {
                    int steps = distance[to]; if (to == from || steps < 0) continue;
                    pairs++; total += steps; histogram[steps]++; harmonic[to] += 1.0 / steps;
                    if (steps > diameter) { diameter = steps; source = from; target = to; }
                }
            }
        }
        public int effective() {
            int reached = 0;
            for (int steps = 1; steps <= diameter; steps++) { reached += histogram[steps]; if (10 * reached >= 9 * pairs) return steps; }
            return diameter;
        }
    }
    public sealed class Scores {
        public readonly PageRankResult pagerankRun, cheirankRun, trustrankRun;
        public readonly double[] pagerank, cheirank, trustrank, authority, hub, harmonic, ratio;
        public readonly int[] rank, cheirankRank, trustDistance;
        public readonly List<int> order;
        public readonly double damping;
        public Scores(Graph graph, Settings settings, List<int> trusted, double[] harmonic) {
            damping = settings.damping;
            pagerankRun = pageRank(graph.forward(), range(graph.count), damping, settings);
            cheirankRun = pageRank(graph.reverse(), range(graph.count), damping, settings);
            trustrankRun = pageRank(graph.forward(), trusted, damping, settings);
            pagerank = pagerankRun.values; cheirank = cheirankRun.values; trustrank = trustrankRun.values; this.harmonic = harmonic;
            order = rankOrder(pagerank); rank = positions(order); cheirankRank = positions(rankOrder(cheirank));
            ratio = new double[graph.count]; for (int i = 0; i < graph.count; i++) ratio[i] = trustrank[i] / pagerank[i];
            trustDistance = Components.distances(graph.successors, trusted);
            HitsResult hits = Hits.compute(graph.count, range(graph.count), graph.inter(graph.links), settings.hitsIterations); authority = hits.authority; hub = hits.hub;
        }
        public double contribution(Graph graph, int source) { return (damping * pagerank[source]) / graph.successors[source].Count; }
        public int representative(List<int> nodes) { return nodes.OrderBy(node => rank[node]).First(); }
    }
    public sealed class Sweep {
        public readonly double damping;
        public readonly PageRankResult run;
        public readonly int overlap, footrule, shift, shiftRank;
        public readonly string correlation;
        public readonly List<int> top;
        public Sweep(double damping, Graph graph, Scores scores, Settings settings) {
            this.damping = damping; run = pageRank(graph.forward(), range(graph.count), damping, settings);
            List<int> order = rankOrder(run.values); int[] rank = positions(order);
            int overlapCount = 0, footruleSum = 0, largest = 0;
            for (int node = 0; node < graph.count; node++) {
                if (rank[node] <= settings.topK && scores.rank[node] <= settings.topK) overlapCount++;
                footruleSum += Math.Abs(rank[node] - scores.rank[node]);
                if (Math.Abs(rank[node] - scores.rank[node]) > Math.Abs(rank[largest] - scores.rank[largest])) largest = node;
            }
            overlap = overlapCount; footrule = footruleSum; shift = largest; shiftRank = rank[shift];
            correlation = kendall(scaled(scores.pagerank), scaled(run.values)); top = order.Take(settings.topK).ToList();
        }
    }
    public sealed class Spam {
        public readonly List<int> suspects;
        public readonly List<string> hosts;
        public readonly int removed;
        public readonly PageRankResult run;
        public readonly int[] rank;
        public Spam(Graph graph, Scores scores, Settings settings) {
            suspects = scores.order.Take(settings.spamTop).Where(node => Report.scaled(scores.ratio[node], 4) / 10000.0 < settings.spamThreshold).ToList();
            hosts = suspects.Select(graph.host).Distinct(StringComparer.Ordinal).OrderBy(host => host, StringComparer.Ordinal).ToList();
            if (suspects.Count == 0) { removed = 0; run = null; rank = null; }
            else {
                List<Edge> kept = graph.links.Where(edge => !(graph.intra(edge) && hosts.Contains(graph.host(edge.source)))).ToList();
                removed = graph.links.Count - kept.Count; Graph demoted = new Graph(graph.pages, kept);
                run = pageRank(demoted.forward(), range(graph.count), settings.damping, settings); rank = positions(rankOrder(run.values));
            }
        }
    }
    public static double[] salsa(int count, List<Edge> links) {
        int[] degree = new int[count]; List<List<int>> targets = lists(count), neighbors = lists(count);
        foreach (Edge edge in links) { degree[edge.target]++; targets[edge.source].Add(edge.target); }
        foreach (List<int> group in targets) for (int i = 1; i < group.Count; i++) { int a = group[i - 1], b = group[i]; neighbors[a].Add(b); neighbors[b].Add(a); }
        int[] labels = Components.weak(neighbors), size = new int[count], mass = new int[count]; int side = 0;
        for (int node = 0; node < count; node++) if (degree[node] > 0) { side++; size[labels[node]]++; mass[labels[node]] += degree[node]; }
        double[] values = new double[count];
        for (int node = 0; node < count; node++) if (degree[node] > 0) values[node] = (double) (size[labels[node]] * degree[node]) / (side * mass[labels[node]]);
        return values;
    }
    public static int[] cocitation(Graph graph, int page) {
        int[] counts = new int[graph.count];
        foreach (int citing in graph.predecessors[page]) foreach (int cited in graph.successors[citing]) if (cited != page) counts[cited]++;
        return counts;
    }
    public static int[] coupling(Graph graph, int page) {
        int[] counts = new int[graph.count];
        foreach (int cited in graph.successors[page]) foreach (int citing in graph.predecessors[cited]) if (citing != page) counts[citing]++;
        return counts;
    }
    public sealed class SubgraphScores {
        public readonly double[] authority, hub, salsaAuthority, salsaHub;
        public readonly List<int> authorityTop, hubTop, salsaAuthorityTop, salsaHubTop, related, similar;
        public readonly int authorityOverlap, hubOverlap, authorityHosts, cited, citing;
        public readonly int[] cocitation, coupling;
        public SubgraphScores(Graph graph, List<int> baseNodes, List<Edge> links, Settings settings) {
            int limit = settings.topK; HitsResult hits = Hits.compute(graph.count, baseNodes, links, settings.hitsIterations);
            authority = hits.authority; hub = hits.hub; salsaAuthority = salsa(graph.count, links);
            salsaHub = salsa(graph.count, links.Select(edge => new Edge(edge.target, edge.source)).ToList());
            authorityTop = top(authority, limit); hubTop = top(hub, limit); salsaAuthorityTop = top(salsaAuthority, limit); salsaHubTop = top(salsaHub, limit);
            authorityOverlap = (int) authorityTop.Count(salsaAuthorityTop.Contains); hubOverlap = (int) hubTop.Count(salsaHubTop.Contains);
            authorityHosts = (int) authorityTop.Select(graph.host).Distinct(StringComparer.Ordinal).Count(); cited = authorityTop[0]; citing = hubTop[0];
            cocitation = Program.cocitation(graph, cited); coupling = Program.coupling(graph, citing); related = rankedCounts(cocitation, limit); similar = rankedCounts(coupling, limit);
        }
    }
    public sealed class QueryResult {
        public readonly Query query;
        public readonly List<int> matches, personalizedTop;
        public readonly int rootSize, baseSize, dropped, reach, overlap;
        public readonly List<Edge> subgraph;
        public readonly PageRankResult personalized;
        public readonly double seedMass;
        public readonly SubgraphScores subScores;
        public QueryResult(Query query, Graph graph, Scores scores, Settings settings, Dictionary<int, int> index) {
            this.query = query;
            List<string> include = query.words.Where(word => !word.StartsWith("-", StringComparison.Ordinal)).ToList();
            List<string> exclude = query.words.Where(word => word.StartsWith("-", StringComparison.Ordinal)).Select(word => word[1..]).ToList();
            matches = scores.order.Where(node => include.All(graph.pages[node].words.Contains) && !exclude.Any(graph.pages[node].words.Contains)).ToList();
            List<int> root = matches.Take(settings.rootLimit).ToList(); rootSize = root.Count; bool[] inBase = new bool[graph.count];
            foreach (int node in root) {
                inBase[node] = true;
                foreach (int neighbor in graph.successors[node].Take(settings.neighborLimit)) inBase[neighbor] = true;
                foreach (int neighbor in graph.predecessors[node].Take(settings.neighborLimit)) inBase[neighbor] = true;
            }
            List<int> baseNodes = range(graph.count).Where(node => inBase[node]).ToList(); baseSize = baseNodes.Count;
            List<Edge> inside = graph.links.Where(edge => inBase[edge.source] && inBase[edge.target]).ToList(); subgraph = graph.inter(inside); dropped = inside.Count - subgraph.Count;
            List<int> seeds = query.seeds.Select(id => index[id]).OrderBy(node => node).ToList();
            personalized = pageRank(graph.forward(), seeds, settings.damping, settings); personalizedTop = top(personalized.values, settings.topK);
            int reached = 0; foreach (bool seen in Components.reachable(graph.successors, seeds)) if (seen) reached++;
            reach = reached; seedMass = total(personalized.values, seeds); overlap = (int) personalizedTop.Count(node => scores.rank[node] <= settings.topK);
            subScores = subgraph.Count == 0 ? null : new SubgraphScores(graph, baseNodes, subgraph, settings);
        }
    }
    public sealed class HostGraph {
        public readonly List<string> names;
        public readonly List<List<int>> members;
        public readonly int[] ofPage, internalLinks, outgoing, incoming, rank;
        public readonly int[][] weight;
        public readonly List<Edge> edges, heavy;
        public readonly int reciprocal, componentCount, largest;
        public readonly PageRankResult run;
        public HostGraph(Graph graph, Settings settings) {
            names = graph.pages.Select(page => page.host).Distinct(StringComparer.Ordinal).OrderBy(host => host, StringComparer.Ordinal).ToList(); int count = names.Count;
            Dictionary<string, int> index = new(); for (int i = 0; i < count; i++) index.Add(names[i], i);
            ofPage = new int[graph.count]; members = lists(count);
            for (int node = 0; node < graph.count; node++) { ofPage[node] = index[graph.host(node)]; members[ofPage[node]].Add(node); }
            weight = Enumerable.Range(0, count).Select(_ => new int[count]).ToArray(); internalLinks = new int[count]; outgoing = new int[count]; incoming = new int[count];
            foreach (Edge edge in graph.links) {
                int a = ofPage[edge.source], b = ofPage[edge.target];
                if (a == b) internalLinks[a]++; else { weight[a][b]++; outgoing[a]++; incoming[b]++; }
            }
            edges = new(); int reciprocalCount = 0; List<List<int>> adjacency = lists(count); List<List<WeightedEdge>> incomingEdges = weightedLists(count);
            for (int a = 0; a < count; a++) for (int b = 0; b < count; b++) if (weight[a][b] > 0) {
                edges.Add(new Edge(a, b)); adjacency[a].Add(b); incomingEdges[b].Add(new WeightedEdge(a, weight[a][b])); if (weight[b][a] > 0) reciprocalCount++;
            }
            reciprocal = reciprocalCount; List<List<int>> components = Components.strong(adjacency); componentCount = components.Count; largest = components.Max(group => group.Count);
            run = pageRank(incomingEdges, range(count), settings.damping, settings); rank = positions(rankOrder(run.values));
            heavy = edges.OrderByDescending(edge => weight[edge.source][edge.target]).ThenBy(edge => edge.source).ThenBy(edge => edge.target).Take(settings.topK).ToList();
        }
    }
    public static List<string> rankLines(Graph graph, List<int> nodes, double[] values) {
        List<string> lines = new();
        for (int i = 0; i < nodes.Count; i++) { int node = nodes[i]; lines.Add(graph.describe(i + 1, node, Report.fixedValue(values[node]))); }
        return lines;
    }
    public static List<string> scoreBlock(string name, Graph graph, double[] values, int limit) {
        List<string> lines = [line(name, "top", limit)]; lines.AddRange(rankLines(graph, top(values, limit), values)); return lines;
    }
    public static List<string> graphStats(Graph graph, List<LinkRecord> records, List<Ignored> ignored, Undirected undirected, ComponentTable table, int[] regions, DistanceStats distances, Scores scores) {
        int intra = (int) graph.links.Count(graph.intra), reciprocal = 0;
        foreach (Edge edge in graph.links) if (graph.linkSet.Contains(new Edge(edge.target, edge.source))) reciprocal++;
        int[] incomingNodes = graph.predecessors.Select(group => group.Count).ToArray(), outgoingNodes = graph.successors.Select(group => group.Count).ToArray();
        int maxIn = incomingNodes.Max(), maxOut = outgoingNodes.Max();
        List<string> lines = [line("pages", graph.count), line("hosts", graph.pages.Select(page => page.host).Distinct(StringComparer.Ordinal).Count()), line("link_rows", records.Count), line("links", graph.links.Count)];
        foreach (string reason in new[] { "unknown", "self", "duplicate" }) lines.Add(line("ignored_" + reason, ignored.Count(item => item.reason == reason)));
        foreach (Ignored item in ignored) { LinkRecord r = item.record; lines.Add(line("ignored", "line", r.line, r.source + "," + r.target, item.reason)); }
        lines.AddRange([line("intra_host_links", intra), line("inter_host_links", graph.links.Count - intra), line("mean_degree", Report.fixedValue((double) graph.links.Count / graph.count, 4)), line("reciprocity", Report.fraction(reciprocal, graph.links.Count))]);
        List<int> dangling = graph.dangling(), noIn = range(graph.count).Where(node => incomingNodes[node] == 0).ToList();
        lines.Add(appendValues(line("dangling", dangling.Count), graph.ids(dangling))); lines.Add(appendValues(line("no_in_links", noIn.Count), graph.ids(noIn)));
        lines.Add(appendValues(line("max_in_degree", maxIn, "pages"), graph.ids(range(graph.count).Where(node => incomingNodes[node] == maxIn).ToList())));
        lines.Add(appendValues(line("max_out_degree", maxOut, "pages"), graph.ids(range(graph.count).Where(node => outgoingNodes[node] == maxOut).ToList())));
        string[] names = {"in_degree_distribution", "out_degree_distribution"};
        for (int i = 0; i < 2; i++) { lines.Add(""); lines.Add(names[i]); foreach (var entry in distribution(i == 0 ? incomingNodes : outgoingNodes)) lines.Add(line(entry.Key, entry.Value)); }
        lines.AddRange(["", line("undirected_links", undirected.edgeCount), line("transitivity", Report.fraction(undirected.closed, undirected.possible)),
            line("average_clustering", Report.fixedValue(undirected.clustering, 4), "pages", undirected.eligible), line("degeneracy", undirected.degeneracy, "pages", undirected.kcore.Count(value => value == undirected.degeneracy)), "core_distribution"]);
        foreach (var entry in distribution(undirected.kcore)) lines.Add(line(entry.Key, entry.Value));
        lines.AddRange(["", line("strong_components", table.groups.Count, "largest", table.groups[table.core].Count, "singletons", table.singletons, "condensation_links", table.edgeCount),
            line("weak_components", undirected.weakCount, "largest", undirected.weakLargest), line("condensation_depth", table.depth)]);
        for (int j = 0; j < table.groups.Count; j++) {
            List<int> group = table.groups[j]; if (group.Count < 2) continue;
            string text = line("scc", j + 1, "size", group.Count, "min", graph.id(group[0]), "incoming", table.incoming[j], "outgoing", table.outgoing[j], "pagerank", Report.fixedValue(total(scores.pagerank, group)));
            lines.Add(text + (table.outgoing[j] == 0 ? " sink" : ""));
        }
        lines.Add(""); lines.Add(line("bowtie", "core_scc", table.core + 1));
        for (int region = 0; region < REGIONS.Length; region++) {
            List<int> members = new(); for (int node = 0; node < graph.count; node++) if (regions[node] == region) members.Add(node);
            string text = line(REGIONS[region], members.Count, "pagerank", Report.fixedValue(total(scores.pagerank, members)));
            if (members.Count != 0) text += line("", "top", graph.id(scores.representative(members)));
            if (members.Count >= 1 && members.Count <= 10) text = appendValues(text + " pages", graph.ids(members)); lines.Add(text);
        }
        int[][] counts = Enumerable.Range(0, REGIONS.Length).Select(_ => new int[REGIONS.Length]).ToArray(); foreach (Edge edge in graph.links) counts[regions[edge.source]][regions[edge.target]]++;
        lines.Add("region_links");
        for (int a = 0; a < REGIONS.Length; a++) for (int b = 0; b < REGIONS.Length; b++) if (counts[a][b] > 0) lines.Add(line(REGIONS[a], REGIONS[b], counts[a][b]));
        lines.AddRange(["", "distances", line("reachable_pairs", distances.pairs), line("average", Report.fraction(distances.total, distances.pairs)),
            line("diameter", distances.diameter, "from", graph.id(distances.source), "to", graph.id(distances.target)), line("effective_diameter", distances.effective())]);
        for (int steps = 1; steps <= distances.diameter; steps++) lines.Add(line(steps, distances.histogram[steps])); return lines;
    }
    public static List<string> pagerankCsv(Graph graph, ComponentTable table, int[] regions, Undirected undirected, Scores scores) {
        List<string> lines = [PAGERANK_HEADER];
        for (int node = 0; node < graph.count; node++) lines.Add(string.Join(",", "" + graph.id(node), "" + graph.predecessors[node].Count, "" + graph.successors[node].Count,
            "" + (table.labels[node] + 1), REGIONS[regions[node]], "" + undirected.kcore[node], Report.fixedValue(scores.harmonic[node]), Report.fixedValue(scores.pagerank[node]), "" + scores.rank[node],
            Report.fixedValue(scores.cheirank[node]), "" + scores.cheirankRank[node], Report.fixedValue(scores.authority[node]), Report.fixedValue(scores.hub[node]), Report.fixedValue(scores.trustrank[node]), Report.fixedValue(scores.ratio[node], 4), "" + scores.trustDistance[node]));
        return lines;
    }
    public static List<string> rankings(Graph graph, Scores scores, Undirected undirected, List<Sweep> sweeps, Spam spam, HostGraph hosts, Settings settings) {
        int limit = settings.topK; List<List<string>> groups = new();
        List<string> pagerank = scoreBlock("pagerank", graph, scores.pagerank, limit); pagerank.Add(line("dangling_mass", Report.fixedValue(total(scores.pagerank, graph.dangling()))));
        foreach (int node in top(scores.pagerank, limit)) {
            List<int> contributors = graph.predecessors[node].OrderByDescending(source => Report.scaled(scores.contribution(graph, source))).ThenBy(source => source).Take(3).ToList();
            List<object> parts = ["contributors", graph.id(node)]; foreach (int source in contributors) { parts.Add(graph.id(source)); parts.Add(Report.fixedValue(scores.contribution(graph, source))); } pagerank.Add(line(parts.ToArray()));
        }
        groups.Add(pagerank); groups.Add(scoreBlock("cheirank", graph, scores.cheirank, limit)); groups.Add(scoreBlock("authority", graph, scores.authority, limit));
        groups.Add(scoreBlock("hub", graph, scores.hub, limit)); groups.Add(scoreBlock("trustrank", graph, scores.trustrank, limit)); groups.Add(scoreBlock("harmonic", graph, scores.harmonic, limit));
        long[][] series = new long[7][]; series[0] = graph.predecessors.Select(group => (long) group.Count).ToArray();
        series[1] = scaled(scores.pagerank); series[2] = scaled(scores.cheirank); series[3] = scaled(scores.authority); series[4] = scaled(scores.hub); series[5] = scaled(scores.trustrank); series[6] = scaled(scores.harmonic);
        List<string> correlation = ["correlation"]; for (int a = 0; a < 7; a++) for (int b = a + 1; b < 7; b++) correlation.Add(line(QUANTITIES[a], QUANTITIES[b], kendall(series[a], series[b]))); groups.Add(correlation);
        List<string> sweepLines = ["damping_sweep"];
        foreach (Sweep sweep in sweeps) {
            sweepLines.Add(line("damping", Report.fixedValue(sweep.damping, 4), "overlap", sweep.overlap, "footrule", sweep.footrule, "kendall", sweep.correlation, "largest_shift", graph.id(sweep.shift), scores.rank[sweep.shift], sweep.shiftRank));
            sweepLines.Add(appendValues("top", graph.ids(sweep.top)));
        }
        groups.Add(sweepLines); List<string> spamLines = [line("spam", "top", settings.spamTop, "threshold", Report.fixedValue(settings.spamThreshold, 4))];
        foreach (int node in spam.suspects) spamLines.Add(line("suspect", graph.id(node), "rank", scores.rank[node], "pagerank", Report.fixedValue(scores.pagerank[node]), "trustrank", Report.fixedValue(scores.trustrank[node]),
            "trust_ratio", Report.fixedValue(scores.ratio[node], 4), "trust_distance", scores.trustDistance[node], "kcore", undirected.kcore[node], graph.host(node)));
        spamLines.Add(line("count", spam.suspects.Count)); spamLines.Add("trust_by_distance");
        List<int> distances = scores.trustDistance.Where(value => value >= 0).Distinct().OrderBy(value => value).ToList();
        if (scores.trustDistance.Contains(-1)) distances.Add(-1);
        foreach (int distance in distances) {
            List<int> members = range(graph.count).Where(node => scores.trustDistance[node] == distance).ToList();
            spamLines.Add(line(distance == -1 ? "unreachable" : distance.ToString(CultureInfo.InvariantCulture), "pages", members.Count, "trustrank", Report.fixedValue(total(scores.trustrank, members)), "pagerank", Report.fixedValue(total(scores.pagerank, members))));
        }
        groups.Add(spamLines); List<string> demotion = new();
        if (spam.run == null) demotion.Add("demotion none");
        else {
            demotion.Add(appendValues("demotion hosts", spam.hosts) + " removed_links " + spam.removed);
            List<int> nodes = top(spam.run.values, limit);
            for (int i = 0; i < nodes.Count; i++) { int node = nodes[i]; demotion.Add(graph.describe(i + 1, node, Report.fixedValue(spam.run.values[node]), "was", scores.rank[node])); }
            foreach (int node in spam.suspects) demotion.Add(line("suspect", graph.id(node), "before", scores.rank[node], "after", spam.rank[node]));
        }
        groups.Add(demotion); List<string> hostLines = new List<string>([line("host_graph", "hosts", hosts.names.Count, "links", hosts.edges.Count, "reciprocal", hosts.reciprocal,
            "strong_components", hosts.componentCount, "largest", hosts.largest), line("host_links", "top", limit)]);
        foreach (Edge edge in hosts.heavy) hostLines.Add(line(hosts.names[edge.source], hosts.names[edge.target], hosts.weight[edge.source][edge.target])); groups.Add(hostLines); return blocks(groups);
    }
    public static List<string> convergenceBlock(string heading, PageRankResult run) {
        List<string> lines = ["", heading];
        for (int step = 10; step <= run.changes.Length; step += 10) lines.Add(line("iteration", step, "l1", Report.fixedValue(run.changes[step - 1], 10)));
        lines.Add(line("converged_at", run.convergedAt?.ToString(CultureInfo.InvariantCulture) ?? "none")); return lines;
    }
    public static List<string> convergence(Scores scores, List<Sweep> sweeps, Spam spam, List<QueryResult> queries, HostGraph hosts, Settings settings) {
        string damping = Report.fixedValue(settings.damping, 4); List<string> lines = [line("iterations", settings.iterations, "tolerance", Report.fixedValue(settings.tolerance, 10))];
        lines.AddRange(convergenceBlock(line("pagerank", "damping", damping), scores.pagerankRun)); lines.AddRange(convergenceBlock(line("cheirank", "damping", damping), scores.cheirankRun));
        lines.AddRange(convergenceBlock(line("trustrank", "damping", damping, "seeds", settings.trusted.Length), scores.trustrankRun));
        foreach (Sweep sweep in sweeps) lines.AddRange(convergenceBlock(line("sweep", "damping", Report.fixedValue(sweep.damping, 4)), sweep.run));
        if (spam.run != null) lines.AddRange(convergenceBlock(line("demoted", "damping", damping), spam.run));
        foreach (QueryResult query in queries) lines.AddRange(convergenceBlock(line("personalized", "query", query.query.number, "damping", damping), query.personalized));
        lines.AddRange(convergenceBlock(line("host_pagerank", "damping", damping, "hosts", hosts.names.Count), hosts.run)); return lines;
    }
    public static List<string> queryLines(Graph graph, Scores scores, QueryResult result, int limit) {
        Query query = result.query; string heading = appendValues(line("query", query.number, "words"), query.words);
        heading = appendValues(heading + " seeds", query.seeds.ToList());
        List<string> lines = [heading, line("matched", result.matches.Count, "root", result.rootSize, "base", result.baseSize, "links", result.subgraph.Count, "dropped_intra_host", result.dropped), "results"];
        lines.AddRange(rankLines(graph, result.matches.Take(limit).ToList(), scores.pagerank)); lines.Add(line("personalized", "reach", result.reach, "seed_mass", Report.fixedValue(result.seedMass)));
        lines.AddRange(rankLines(graph, result.personalizedTop, result.personalized.values)); lines.Add(line("overlap_with_global", result.overlap));
        SubgraphScores sub = result.subScores;
        if (sub == null) { lines.Add("hits none"); return lines; }
        lines.Add("hits authorities"); lines.AddRange(rankLines(graph, sub.authorityTop, sub.authority)); lines.Add("hits hubs"); lines.AddRange(rankLines(graph, sub.hubTop, sub.hub));
        lines.Add("salsa authorities"); lines.AddRange(rankLines(graph, sub.salsaAuthorityTop, sub.salsaAuthority)); lines.Add("salsa hubs"); lines.AddRange(rankLines(graph, sub.salsaHubTop, sub.salsaHub));
        lines.Add(line("hits_salsa_overlap", "authorities", sub.authorityOverlap, "hubs", sub.hubOverlap, "authority_hosts", sub.authorityHosts));
        lines.Add(line("related_to", graph.id(sub.cited), "citing", graph.predecessors[sub.cited].Count));
        for (int i = 0; i < sub.related.Count; i++) { int node = sub.related[i]; lines.Add(graph.describe(i + 1, node, sub.cocitation[node])); }
        lines.Add(line("coupled_to", graph.id(sub.citing), "cited", graph.successors[sub.citing].Count));
        for (int i = 0; i < sub.similar.Count; i++) { int node = sub.similar[i]; lines.Add(graph.describe(i + 1, node, sub.coupling[node])); }
        return lines;
    }
    public static List<string> hostsCsv(Graph graph, int[] regions, Scores scores, HostGraph hosts) {
        List<string> lines = [HOSTS_HEADER];
        for (int number = 0; number < hosts.names.Count; number++) {
            List<int> members = hosts.members[number]; int size = members.Count;
            double density = size >= 2 ? (double) hosts.internalLinks[number] / (size * (size - 1)) : 0;
            lines.Add(string.Join(",", hosts.names[number], "" + size, "" + members.Count(node => regions[node] == 0), "" + hosts.internalLinks[number], Report.fixedValue(density, 4),
                "" + hosts.outgoing[number], "" + hosts.incoming[number], "" + members.Count(node => graph.successors[node].Count == 0), Report.fixedValue(total(scores.pagerank, members)),
                "" + graph.id(scores.representative(members)), Report.fixedValue(hosts.run.values[number]), "" + hosts.rank[number]));
        }
        return lines;
    }
    public static void Main(string[] args)  {
        InputData input = GraphIO.read("input"); List<Page> pages = input.pages.OrderBy(page => page.id).ToList(); Settings settings = input.settings;
        Dictionary<int, int> index = new(); for (int node = 0; node < pages.Count; node++) index.Add(pages[node].id, node);
        HashSet<Edge> accepted = new(); List<Ignored> ignored = new();
        foreach (LinkRecord record in input.records) {
            if (!index.ContainsKey(record.source) || !index.ContainsKey(record.target)) { ignored.Add(new Ignored(record, "unknown")); continue; }
            Edge edge = new Edge(index[record.source], index[record.target]);
            if (edge.source == edge.target) ignored.Add(new Ignored(record, "self"));
            else if (!accepted.Add(edge)) ignored.Add(new Ignored(record, "duplicate"));
        }
        Graph graph = new Graph(pages, accepted.ToList()); Undirected undirected = new Undirected(graph); ComponentTable table = new ComponentTable(graph);
        int[] regions = bowtie(graph, table.groups[table.core]); DistanceStats distances = new DistanceStats(graph);
        List<int> trusted = settings.trusted.Select(id => index[id]).OrderBy(node => node).ToList(); Scores scores = new Scores(graph, settings, trusted, distances.harmonic);
        List<Sweep> sweeps = new(); foreach (double damping in settings.sweep) sweeps.Add(new Sweep(damping, graph, scores, settings)); Spam spam = new Spam(graph, scores, settings);
        List<QueryResult> results = new(); foreach (Query query in input.queries) results.Add(new QueryResult(query, graph, scores, settings, index)); HostGraph hosts = new HostGraph(graph, settings);
        List<List<string>> queryBlocks = new(); foreach (QueryResult result in results) queryBlocks.Add(queryLines(graph, scores, result, settings.topK));
        Dictionary<string, List<string>> files = new();
        files.Add("graph_stats.txt", graphStats(graph, input.records, ignored, undirected, table, regions, distances, scores)); files.Add("pagerank.csv", pagerankCsv(graph, table, regions, undirected, scores));
        files.Add("rankings.txt", rankings(graph, scores, undirected, sweeps, spam, hosts, settings)); files.Add("convergence.txt", convergence(scores, sweeps, spam, results, hosts, settings));
        files.Add("queries.txt", blocks(queryBlocks)); files.Add("hosts.csv", hostsCsv(graph, regions, scores, hosts)); Report.write(files);
    }
}
