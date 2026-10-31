import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.Deque;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.stream.IntStream;

public class Main {
    static final String[] REGIONS = {"CORE", "IN", "OUT", "TUBE", "IN_TENDRIL", "OUT_TENDRIL", "OTHER"};
    static final String[] QUANTITIES = {"in_degree", "pagerank", "cheirank", "authority", "hub", "trustrank", "harmonic"};
    static final String PAGERANK_HEADER = "id,in_degree,out_degree,scc,region,kcore,harmonic,pagerank,pagerank_rank,cheirank,cheirank_rank,authority,hub,trustrank,trust_ratio,trust_distance";
    static final String HOSTS_HEADER = "host,pages,core_pages,internal_links,internal_density,outgoing_links,incoming_links,dangling_pages,page_score_sum,top_page,score,rank";
    record Ignored(LinkRecord record, String reason) {}
    static List<Integer> range(int count) { return IntStream.range(0, count).boxed().toList(); }
    static List<List<Integer>> lists(int count) {
        List<List<Integer>> result = new ArrayList<>();
        for (int i = 0; i < count; i++) result.add(new ArrayList<>());
        return result;
    }
    static List<List<WeightedEdge>> weightedLists(int count) {
        List<List<WeightedEdge>> result = new ArrayList<>();
        for (int i = 0; i < count; i++) result.add(new ArrayList<>());
        return result;
    }
    static String line(Object... parts) {
        return String.join(" ", Arrays.stream(parts).map(Object::toString).toList());
    }
    static List<String> blocks(List<List<String>> groups) {
        List<String> lines = new ArrayList<>();
        for (List<String> group : groups) { if (!lines.isEmpty()) lines.add(""); lines.addAll(group); }
        return lines;
    }
    static String appendValues(String prefix, List<?> values) {
        return values.isEmpty() ? prefix : prefix + " " + String.join(" ", values.stream().map(Object::toString).toList());
    }
    static double total(double[] values, List<Integer> nodes) {
        double result = 0;
        for (int node : nodes) result += values[node];
        return result;
    }
    static List<Integer> rankOrder(double[] values) {
        return range(values.length).stream().sorted(Comparator.<Integer>comparingLong(node -> Report.scaled(values[node])).reversed().thenComparingInt(node -> node)).toList();
    }
    static int[] positions(List<Integer> order) {
        int[] rank = new int[order.size()];
        for (int position = 0; position < order.size(); position++) rank[order.get(position)] = position + 1;
        return rank;
    }
    static List<Integer> top(double[] values, int limit) {
        return rankOrder(values).stream().filter(node -> Report.scaled(values[node]) > 0).limit(limit).toList();
    }
    static List<Integer> rankedCounts(int[] counts, int limit) {
        return range(counts.length).stream().filter(node -> counts[node] > 0)
            .sorted(Comparator.<Integer>comparingInt(node -> counts[node]).reversed().thenComparingInt(node -> node)).limit(limit).toList();
    }
    static Map<Integer, Integer> distribution(int[] values) {
        Map<Integer, Integer> counts = new TreeMap<>();
        for (int value : values) counts.merge(value, 1, Integer::sum);
        return counts;
    }
    static long[] scaled(double[] values) {
        long[] result = new long[values.length];
        for (int i = 0; i < values.length; i++) result[i] = Report.scaled(values[i]);
        return result;
    }
    static String kendall(long[] first, long[] second) {
        int concordant = 0, discordant = 0;
        for (int i = 0; i < first.length; i++) for (int j = i + 1; j < first.length; j++) {
            long dx = first[i] - first[j], dy = second[i] - second[j];
            if (dx == 0 || dy == 0) continue;
            if ((dx > 0) == (dy > 0)) concordant++; else discordant++;
        }
        return Report.fraction(concordant - discordant, (long) first.length * (first.length - 1) / 2);
    }
    static PageRankResult pageRank(List<List<WeightedEdge>> edges, List<Integer> teleport, double damping, Settings settings) {
        return PageRank.compute(edges, teleport, damping, settings.iterations(), settings.tolerance());
    }
    static final class Graph {
        final List<Page> pages;
        final int count;
        final List<Edge> links;
        final Set<Edge> linkSet;
        final List<List<Integer>> successors, predecessors;
        Graph(List<Page> pages, List<Edge> links) {
            this.pages = pages; count = pages.size();
            this.links = links.stream().sorted(Comparator.comparingInt(Edge::source).thenComparingInt(Edge::target)).toList();
            linkSet = new HashSet<>(links); successors = lists(count); predecessors = lists(count);
            for (Edge edge : this.links) { successors.get(edge.source()).add(edge.target()); predecessors.get(edge.target()).add(edge.source()); }
        }
        String host(int node) { return pages.get(node).host(); }
        int id(int node) { return pages.get(node).id(); }
        boolean intra(Edge edge) { return host(edge.source()).equals(host(edge.target())); }
        List<Edge> inter(List<Edge> edges) { return edges.stream().filter(edge -> !intra(edge)).toList(); }
        List<Integer> dangling() { return range(count).stream().filter(node -> successors.get(node).isEmpty()).toList(); }
        List<Integer> ids(List<Integer> nodes) { return nodes.stream().map(this::id).toList(); }
        List<List<WeightedEdge>> forward() {
            List<List<WeightedEdge>> edges = weightedLists(count);
            for (int node = 0; node < count; node++) for (int source : predecessors.get(node)) edges.get(node).add(new WeightedEdge(source, 1));
            return edges;
        }
        List<List<WeightedEdge>> reverse() {
            List<List<WeightedEdge>> edges = weightedLists(count);
            for (int node = 0; node < count; node++) for (int target : successors.get(node)) edges.get(node).add(new WeightedEdge(target, 1));
            return edges;
        }
        String describe(int position, int node, Object... values) {
            List<Object> parts = new ArrayList<>(List.of(position, id(node)));
            parts.addAll(List.of(values)); parts.add(host(node)); parts.add(pages.get(node).title());
            return line(parts.toArray());
        }
    }
    static int[] kcores(List<List<Integer>> neighbors) {
        int count = neighbors.size(), level = 0, left = count;
        int[] degree = neighbors.stream().mapToInt(List::size).toArray(), core = new int[count];
        boolean[] removed = new boolean[count];
        while (left > 0) {
            int candidate = -1;
            for (int node = 0; node < count; node++) if (!removed[node] && degree[node] <= level) { candidate = node; break; }
            if (candidate < 0) { level++; continue; }
            removed[candidate] = true; core[candidate] = level; left--;
            for (int neighbor : neighbors.get(candidate)) if (!removed[neighbor]) degree[neighbor]--;
        }
        return core;
    }
    static final class Undirected {
        final List<List<Integer>> neighbors;
        final boolean[][] adjacent;
        final int edgeCount, closed, possible, eligible, degeneracy, weakCount, weakLargest;
        final double clustering;
        final int[] kcore;
        Undirected(Graph graph) {
            adjacent = new boolean[graph.count][graph.count]; neighbors = lists(graph.count);
            for (Edge edge : graph.links) { adjacent[edge.source()][edge.target()] = true; adjacent[edge.target()][edge.source()] = true; }
            int degreeSum = 0, closedSum = 0, possibleSum = 0, eligibleCount = 0; double localSum = 0;
            for (int node = 0; node < graph.count; node++) {
                List<Integer> group = neighbors.get(node);
                for (int other = 0; other < graph.count; other++) if (adjacent[node][other]) group.add(other);
                degreeSum += group.size();
                if (group.size() < 2) continue;
                int closedHere = 0, possibleHere = group.size() * (group.size() - 1) / 2;
                for (int a = 0; a < group.size(); a++) for (int b = a + 1; b < group.size(); b++) if (adjacent[group.get(a)][group.get(b)]) closedHere++;
                closedSum += closedHere; possibleSum += possibleHere; eligibleCount++; localSum += (double) closedHere / possibleHere;
            }
            edgeCount = degreeSum / 2; closed = closedSum; possible = possibleSum; eligible = eligibleCount; clustering = localSum / eligible;
            kcore = kcores(neighbors); degeneracy = Arrays.stream(kcore).max().orElseThrow();
            int[] labels = Components.weak(neighbors), sizes = new int[graph.count];
            for (int label : labels) sizes[label]++;
            weakCount = Arrays.stream(labels).max().orElseThrow() + 1; weakLargest = Arrays.stream(sizes).max().orElseThrow();
        }
    }
    static int longestPath(int count, Set<Edge> edges) {
        List<List<Integer>> successors = lists(count); int[] pending = new int[count], length = new int[count];
        for (Edge edge : edges) { successors.get(edge.source()).add(edge.target()); pending[edge.target()]++; }
        Deque<Integer> ready = new ArrayDeque<>();
        for (int node = 0; node < count; node++) if (pending[node] == 0) ready.push(node);
        while (!ready.isEmpty()) {
            int node = ready.pop();
            for (int target : successors.get(node)) { length[target] = Math.max(length[target], length[node] + 1); if (--pending[target] == 0) ready.push(target); }
        }
        return Arrays.stream(length).max().orElseThrow();
    }
    static final class ComponentTable {
        final List<List<Integer>> groups;
        final int[] labels, incoming, outgoing;
        final int edgeCount, depth, core, singletons;
        ComponentTable(Graph graph) {
            groups = new ArrayList<>();
            for (List<Integer> group : Components.strong(graph.successors)) groups.add(group.stream().sorted().toList());
            groups.sort(Comparator.<List<Integer>>comparingInt(group -> group.getFirst())); labels = new int[graph.count];
            for (int j = 0; j < groups.size(); j++) for (int node : groups.get(j)) labels[node] = j;
            incoming = new int[groups.size()]; outgoing = new int[groups.size()]; Set<Edge> edges = new HashSet<>();
            for (Edge edge : graph.links) {
                int a = labels[edge.source()], b = labels[edge.target()];
                if (a != b) { outgoing[a]++; incoming[b]++; edges.add(new Edge(a, b)); }
            }
            edgeCount = edges.size(); depth = longestPath(groups.size(), edges);
            int largest = 0, singles = 0;
            for (int j = 0; j < groups.size(); j++) { if (groups.get(j).size() > groups.get(largest).size()) largest = j; if (groups.get(j).size() == 1) singles++; }
            core = largest; singletons = singles;
        }
    }
    static int[] bowtie(Graph graph, List<Integer> core) {
        boolean[] forward = Components.reachable(graph.successors, core), backward = Components.reachable(graph.predecessors, core), inCore = new boolean[graph.count];
        for (int node : core) inCore[node] = true;
        int[] regions = new int[graph.count]; Arrays.fill(regions, 6);
        for (int node = 0; node < graph.count; node++) {
            if (inCore[node]) regions[node] = 0; else if (backward[node]) regions[node] = 1; else if (forward[node]) regions[node] = 2;
        }
        List<Integer> in = range(graph.count).stream().filter(node -> regions[node] == 1).toList(), out = range(graph.count).stream().filter(node -> regions[node] == 2).toList();
        boolean[] fromIn = Components.reachable(graph.successors, in), toOut = Components.reachable(graph.predecessors, out);
        for (int node = 0; node < graph.count; node++) {
            if (inCore[node] || backward[node] || forward[node]) continue;
            if (fromIn[node] && toOut[node]) regions[node] = 3; else if (fromIn[node]) regions[node] = 4; else if (toOut[node]) regions[node] = 5;
        }
        return regions;
    }
    static final class DistanceStats {
        int pairs, total, diameter, source, target;
        final int[] histogram;
        final double[] harmonic;
        DistanceStats(Graph graph) {
            histogram = new int[graph.count]; harmonic = new double[graph.count];
            for (int from = 0; from < graph.count; from++) {
                int[] distance = Components.distances(graph.successors, List.of(from));
                for (int to = 0; to < graph.count; to++) {
                    int steps = distance[to]; if (to == from || steps < 0) continue;
                    pairs++; total += steps; histogram[steps]++; harmonic[to] += 1.0 / steps;
                    if (steps > diameter) { diameter = steps; source = from; target = to; }
                }
            }
        }
        int effective() {
            int reached = 0;
            for (int steps = 1; steps <= diameter; steps++) { reached += histogram[steps]; if (10 * reached >= 9 * pairs) return steps; }
            return diameter;
        }
    }
    static final class Scores {
        final PageRankResult pagerankRun, cheirankRun, trustrankRun;
        final double[] pagerank, cheirank, trustrank, authority, hub, harmonic, ratio;
        final int[] rank, cheirankRank, trustDistance;
        final List<Integer> order;
        final double damping;
        Scores(Graph graph, Settings settings, List<Integer> trusted, double[] harmonic) {
            damping = settings.damping();
            pagerankRun = pageRank(graph.forward(), range(graph.count), damping, settings);
            cheirankRun = pageRank(graph.reverse(), range(graph.count), damping, settings);
            trustrankRun = pageRank(graph.forward(), trusted, damping, settings);
            pagerank = pagerankRun.values(); cheirank = cheirankRun.values(); trustrank = trustrankRun.values(); this.harmonic = harmonic;
            order = rankOrder(pagerank); rank = positions(order); cheirankRank = positions(rankOrder(cheirank));
            ratio = new double[graph.count]; for (int i = 0; i < graph.count; i++) ratio[i] = trustrank[i] / pagerank[i];
            trustDistance = Components.distances(graph.successors, trusted);
            HitsResult hits = Hits.compute(graph.count, range(graph.count), graph.inter(graph.links), settings.hitsIterations()); authority = hits.authority(); hub = hits.hub();
        }
        double contribution(Graph graph, int source) { return (damping * pagerank[source]) / graph.successors.get(source).size(); }
        int representative(List<Integer> nodes) { return nodes.stream().min(Comparator.comparingInt(node -> rank[node])).orElseThrow(); }
    }
    static final class Sweep {
        final double damping;
        final PageRankResult run;
        final int overlap, footrule, shift, shiftRank;
        final String correlation;
        final List<Integer> top;
        Sweep(double damping, Graph graph, Scores scores, Settings settings) {
            this.damping = damping; run = pageRank(graph.forward(), range(graph.count), damping, settings);
            List<Integer> order = rankOrder(run.values()); int[] rank = positions(order);
            int overlapCount = 0, footruleSum = 0, largest = 0;
            for (int node = 0; node < graph.count; node++) {
                if (rank[node] <= settings.topK() && scores.rank[node] <= settings.topK()) overlapCount++;
                footruleSum += Math.abs(rank[node] - scores.rank[node]);
                if (Math.abs(rank[node] - scores.rank[node]) > Math.abs(rank[largest] - scores.rank[largest])) largest = node;
            }
            overlap = overlapCount; footrule = footruleSum; shift = largest; shiftRank = rank[shift];
            correlation = kendall(scaled(scores.pagerank), scaled(run.values())); top = order.stream().limit(settings.topK()).toList();
        }
    }
    static final class Spam {
        final List<Integer> suspects;
        final List<String> hosts;
        final int removed;
        final PageRankResult run;
        final int[] rank;
        Spam(Graph graph, Scores scores, Settings settings) {
            suspects = scores.order.stream().limit(settings.spamTop()).filter(node -> Report.scaled(scores.ratio[node], 4) / 10000.0 < settings.spamThreshold()).toList();
            hosts = suspects.stream().map(graph::host).distinct().sorted().toList();
            if (suspects.isEmpty()) { removed = 0; run = null; rank = null; }
            else {
                List<Edge> kept = graph.links.stream().filter(edge -> !(graph.intra(edge) && hosts.contains(graph.host(edge.source())))).toList();
                removed = graph.links.size() - kept.size(); Graph demoted = new Graph(graph.pages, kept);
                run = pageRank(demoted.forward(), range(graph.count), settings.damping(), settings); rank = positions(rankOrder(run.values()));
            }
        }
    }
    static double[] salsa(int count, List<Edge> links) {
        int[] degree = new int[count]; List<List<Integer>> targets = lists(count), neighbors = lists(count);
        for (Edge edge : links) { degree[edge.target()]++; targets.get(edge.source()).add(edge.target()); }
        for (List<Integer> group : targets) for (int i = 1; i < group.size(); i++) { int a = group.get(i - 1), b = group.get(i); neighbors.get(a).add(b); neighbors.get(b).add(a); }
        int[] labels = Components.weak(neighbors), size = new int[count], mass = new int[count]; int side = 0;
        for (int node = 0; node < count; node++) if (degree[node] > 0) { side++; size[labels[node]]++; mass[labels[node]] += degree[node]; }
        double[] values = new double[count];
        for (int node = 0; node < count; node++) if (degree[node] > 0) values[node] = (double) (size[labels[node]] * degree[node]) / (side * mass[labels[node]]);
        return values;
    }
    static int[] cocitation(Graph graph, int page) {
        int[] counts = new int[graph.count];
        for (int citing : graph.predecessors.get(page)) for (int cited : graph.successors.get(citing)) if (cited != page) counts[cited]++;
        return counts;
    }
    static int[] coupling(Graph graph, int page) {
        int[] counts = new int[graph.count];
        for (int cited : graph.successors.get(page)) for (int citing : graph.predecessors.get(cited)) if (citing != page) counts[citing]++;
        return counts;
    }
    static final class SubgraphScores {
        final double[] authority, hub, salsaAuthority, salsaHub;
        final List<Integer> authorityTop, hubTop, salsaAuthorityTop, salsaHubTop, related, similar;
        final int authorityOverlap, hubOverlap, authorityHosts, cited, citing;
        final int[] cocitation, coupling;
        SubgraphScores(Graph graph, List<Integer> base, List<Edge> links, Settings settings) {
            int limit = settings.topK(); HitsResult hits = Hits.compute(graph.count, base, links, settings.hitsIterations());
            authority = hits.authority(); hub = hits.hub(); salsaAuthority = salsa(graph.count, links);
            salsaHub = salsa(graph.count, links.stream().map(edge -> new Edge(edge.target(), edge.source())).toList());
            authorityTop = top(authority, limit); hubTop = top(hub, limit); salsaAuthorityTop = top(salsaAuthority, limit); salsaHubTop = top(salsaHub, limit);
            authorityOverlap = (int) authorityTop.stream().filter(salsaAuthorityTop::contains).count(); hubOverlap = (int) hubTop.stream().filter(salsaHubTop::contains).count();
            authorityHosts = (int) authorityTop.stream().map(graph::host).distinct().count(); cited = authorityTop.getFirst(); citing = hubTop.getFirst();
            cocitation = Main.cocitation(graph, cited); coupling = Main.coupling(graph, citing); related = rankedCounts(cocitation, limit); similar = rankedCounts(coupling, limit);
        }
    }
    static final class QueryResult {
        final Query query;
        final List<Integer> matches, personalizedTop;
        final int rootSize, baseSize, dropped, reach, overlap;
        final List<Edge> subgraph;
        final PageRankResult personalized;
        final double seedMass;
        final SubgraphScores subScores;
        QueryResult(Query query, Graph graph, Scores scores, Settings settings, Map<Integer, Integer> index) {
            this.query = query;
            List<String> include = query.words().stream().filter(word -> !word.startsWith("-")).toList();
            List<String> exclude = query.words().stream().filter(word -> word.startsWith("-")).map(word -> word.substring(1)).toList();
            matches = scores.order.stream().filter(node -> graph.pages.get(node).words().containsAll(include) && exclude.stream().noneMatch(graph.pages.get(node).words()::contains)).toList();
            List<Integer> root = matches.stream().limit(settings.rootLimit()).toList(); rootSize = root.size(); boolean[] inBase = new boolean[graph.count];
            for (int node : root) {
                inBase[node] = true;
                for (int neighbor : graph.successors.get(node).stream().limit(settings.neighborLimit()).toList()) inBase[neighbor] = true;
                for (int neighbor : graph.predecessors.get(node).stream().limit(settings.neighborLimit()).toList()) inBase[neighbor] = true;
            }
            List<Integer> base = range(graph.count).stream().filter(node -> inBase[node]).toList(); baseSize = base.size();
            List<Edge> inside = graph.links.stream().filter(edge -> inBase[edge.source()] && inBase[edge.target()]).toList(); subgraph = graph.inter(inside); dropped = inside.size() - subgraph.size();
            List<Integer> seeds = Arrays.stream(query.seeds()).mapToObj(index::get).sorted().toList();
            personalized = pageRank(graph.forward(), seeds, settings.damping(), settings); personalizedTop = top(personalized.values(), settings.topK());
            int reached = 0; for (boolean seen : Components.reachable(graph.successors, seeds)) if (seen) reached++;
            reach = reached; seedMass = total(personalized.values(), seeds); overlap = (int) personalizedTop.stream().filter(node -> scores.rank[node] <= settings.topK()).count();
            subScores = subgraph.isEmpty() ? null : new SubgraphScores(graph, base, subgraph, settings);
        }
    }
    static final class HostGraph {
        final List<String> names;
        final List<List<Integer>> members;
        final int[] ofPage, internal, outgoing, incoming, rank;
        final int[][] weight;
        final List<Edge> edges, heavy;
        final int reciprocal, componentCount, largest;
        final PageRankResult run;
        HostGraph(Graph graph, Settings settings) {
            names = graph.pages.stream().map(Page::host).distinct().sorted().toList(); int count = names.size();
            Map<String, Integer> index = new HashMap<>(); for (int i = 0; i < count; i++) index.put(names.get(i), i);
            ofPage = new int[graph.count]; members = lists(count);
            for (int node = 0; node < graph.count; node++) { ofPage[node] = index.get(graph.host(node)); members.get(ofPage[node]).add(node); }
            weight = new int[count][count]; internal = new int[count]; outgoing = new int[count]; incoming = new int[count];
            for (Edge edge : graph.links) {
                int a = ofPage[edge.source()], b = ofPage[edge.target()];
                if (a == b) internal[a]++; else { weight[a][b]++; outgoing[a]++; incoming[b]++; }
            }
            edges = new ArrayList<>(); int reciprocalCount = 0; List<List<Integer>> adjacency = lists(count); List<List<WeightedEdge>> incomingEdges = weightedLists(count);
            for (int a = 0; a < count; a++) for (int b = 0; b < count; b++) if (weight[a][b] > 0) {
                edges.add(new Edge(a, b)); adjacency.get(a).add(b); incomingEdges.get(b).add(new WeightedEdge(a, weight[a][b])); if (weight[b][a] > 0) reciprocalCount++;
            }
            reciprocal = reciprocalCount; List<List<Integer>> components = Components.strong(adjacency); componentCount = components.size(); largest = components.stream().mapToInt(List::size).max().orElseThrow();
            run = pageRank(incomingEdges, range(count), settings.damping(), settings); rank = positions(rankOrder(run.values()));
            heavy = edges.stream().sorted(Comparator.<Edge>comparingInt(edge -> weight[edge.source()][edge.target()]).reversed().thenComparingInt(Edge::source).thenComparingInt(Edge::target)).limit(settings.topK()).toList();
        }
    }
    static List<String> rankLines(Graph graph, List<Integer> nodes, double[] values) {
        List<String> lines = new ArrayList<>();
        for (int i = 0; i < nodes.size(); i++) { int node = nodes.get(i); lines.add(graph.describe(i + 1, node, Report.fixed(values[node]))); }
        return lines;
    }
    static List<String> scoreBlock(String name, Graph graph, double[] values, int limit) {
        List<String> lines = new ArrayList<>(List.of(line(name, "top", limit))); lines.addAll(rankLines(graph, top(values, limit), values)); return lines;
    }
    static List<String> graphStats(Graph graph, List<LinkRecord> records, List<Ignored> ignored, Undirected undirected, ComponentTable table, int[] regions, DistanceStats distances, Scores scores) {
        int intra = (int) graph.links.stream().filter(graph::intra).count(), reciprocal = 0;
        for (Edge edge : graph.links) if (graph.linkSet.contains(new Edge(edge.target(), edge.source()))) reciprocal++;
        int[] in = graph.predecessors.stream().mapToInt(List::size).toArray(), out = graph.successors.stream().mapToInt(List::size).toArray();
        int maxIn = Arrays.stream(in).max().orElseThrow(), maxOut = Arrays.stream(out).max().orElseThrow();
        List<String> lines = new ArrayList<>(List.of(line("pages", graph.count), line("hosts", graph.pages.stream().map(Page::host).distinct().count()), line("link_rows", records.size()), line("links", graph.links.size())));
        for (String reason : List.of("unknown", "self", "duplicate")) lines.add(line("ignored_" + reason, ignored.stream().filter(item -> item.reason().equals(reason)).count()));
        for (Ignored item : ignored) { LinkRecord r = item.record(); lines.add(line("ignored", "line", r.line(), r.source() + "," + r.target(), item.reason())); }
        lines.addAll(List.of(line("intra_host_links", intra), line("inter_host_links", graph.links.size() - intra), line("mean_degree", Report.fixed((double) graph.links.size() / graph.count, 4)), line("reciprocity", Report.fraction(reciprocal, graph.links.size()))));
        List<Integer> dangling = graph.dangling(), noIn = range(graph.count).stream().filter(node -> in[node] == 0).toList();
        lines.add(appendValues(line("dangling", dangling.size()), graph.ids(dangling))); lines.add(appendValues(line("no_in_links", noIn.size()), graph.ids(noIn)));
        lines.add(appendValues(line("max_in_degree", maxIn, "pages"), graph.ids(range(graph.count).stream().filter(node -> in[node] == maxIn).toList())));
        lines.add(appendValues(line("max_out_degree", maxOut, "pages"), graph.ids(range(graph.count).stream().filter(node -> out[node] == maxOut).toList())));
        String[] names = {"in_degree_distribution", "out_degree_distribution"};
        for (int i = 0; i < 2; i++) { lines.add(""); lines.add(names[i]); for (var entry : distribution(i == 0 ? in : out).entrySet()) lines.add(line(entry.getKey(), entry.getValue())); }
        lines.addAll(List.of("", line("undirected_links", undirected.edgeCount), line("transitivity", Report.fraction(undirected.closed, undirected.possible)),
            line("average_clustering", Report.fixed(undirected.clustering, 4), "pages", undirected.eligible), line("degeneracy", undirected.degeneracy, "pages", Arrays.stream(undirected.kcore).filter(value -> value == undirected.degeneracy).count()), "core_distribution"));
        for (var entry : distribution(undirected.kcore).entrySet()) lines.add(line(entry.getKey(), entry.getValue()));
        lines.addAll(List.of("", line("strong_components", table.groups.size(), "largest", table.groups.get(table.core).size(), "singletons", table.singletons, "condensation_links", table.edgeCount),
            line("weak_components", undirected.weakCount, "largest", undirected.weakLargest), line("condensation_depth", table.depth)));
        for (int j = 0; j < table.groups.size(); j++) {
            List<Integer> group = table.groups.get(j); if (group.size() < 2) continue;
            String text = line("scc", j + 1, "size", group.size(), "min", graph.id(group.getFirst()), "incoming", table.incoming[j], "outgoing", table.outgoing[j], "pagerank", Report.fixed(total(scores.pagerank, group)));
            lines.add(text + (table.outgoing[j] == 0 ? " sink" : ""));
        }
        lines.add(""); lines.add(line("bowtie", "core_scc", table.core + 1));
        for (int region = 0; region < REGIONS.length; region++) {
            List<Integer> members = new ArrayList<>(); for (int node = 0; node < graph.count; node++) if (regions[node] == region) members.add(node);
            String text = line(REGIONS[region], members.size(), "pagerank", Report.fixed(total(scores.pagerank, members)));
            if (!members.isEmpty()) text += line("", "top", graph.id(scores.representative(members)));
            if (members.size() >= 1 && members.size() <= 10) text = appendValues(text + " pages", graph.ids(members)); lines.add(text);
        }
        int[][] counts = new int[REGIONS.length][REGIONS.length]; for (Edge edge : graph.links) counts[regions[edge.source()]][regions[edge.target()]]++;
        lines.add("region_links");
        for (int a = 0; a < REGIONS.length; a++) for (int b = 0; b < REGIONS.length; b++) if (counts[a][b] > 0) lines.add(line(REGIONS[a], REGIONS[b], counts[a][b]));
        lines.addAll(List.of("", "distances", line("reachable_pairs", distances.pairs), line("average", Report.fraction(distances.total, distances.pairs)),
            line("diameter", distances.diameter, "from", graph.id(distances.source), "to", graph.id(distances.target)), line("effective_diameter", distances.effective())));
        for (int steps = 1; steps <= distances.diameter; steps++) lines.add(line(steps, distances.histogram[steps])); return lines;
    }
    static List<String> pagerankCsv(Graph graph, ComponentTable table, int[] regions, Undirected undirected, Scores scores) {
        List<String> lines = new ArrayList<>(List.of(PAGERANK_HEADER));
        for (int node = 0; node < graph.count; node++) lines.add(String.join(",", "" + graph.id(node), "" + graph.predecessors.get(node).size(), "" + graph.successors.get(node).size(),
            "" + (table.labels[node] + 1), REGIONS[regions[node]], "" + undirected.kcore[node], Report.fixed(scores.harmonic[node]), Report.fixed(scores.pagerank[node]), "" + scores.rank[node],
            Report.fixed(scores.cheirank[node]), "" + scores.cheirankRank[node], Report.fixed(scores.authority[node]), Report.fixed(scores.hub[node]), Report.fixed(scores.trustrank[node]), Report.fixed(scores.ratio[node], 4), "" + scores.trustDistance[node]));
        return lines;
    }
    static List<String> rankings(Graph graph, Scores scores, Undirected undirected, List<Sweep> sweeps, Spam spam, HostGraph hosts, Settings settings) {
        int limit = settings.topK(); List<List<String>> groups = new ArrayList<>();
        List<String> pagerank = scoreBlock("pagerank", graph, scores.pagerank, limit); pagerank.add(line("dangling_mass", Report.fixed(total(scores.pagerank, graph.dangling()))));
        for (int node : top(scores.pagerank, limit)) {
            List<Integer> contributors = graph.predecessors.get(node).stream().sorted(Comparator.<Integer>comparingLong(source -> Report.scaled(scores.contribution(graph, source))).reversed().thenComparingInt(source -> source)).limit(3).toList();
            List<Object> parts = new ArrayList<>(List.of("contributors", graph.id(node))); for (int source : contributors) { parts.add(graph.id(source)); parts.add(Report.fixed(scores.contribution(graph, source))); } pagerank.add(line(parts.toArray()));
        }
        groups.add(pagerank); groups.add(scoreBlock("cheirank", graph, scores.cheirank, limit)); groups.add(scoreBlock("authority", graph, scores.authority, limit));
        groups.add(scoreBlock("hub", graph, scores.hub, limit)); groups.add(scoreBlock("trustrank", graph, scores.trustrank, limit)); groups.add(scoreBlock("harmonic", graph, scores.harmonic, limit));
        long[][] series = new long[7][]; series[0] = graph.predecessors.stream().mapToLong(List::size).toArray();
        series[1] = scaled(scores.pagerank); series[2] = scaled(scores.cheirank); series[3] = scaled(scores.authority); series[4] = scaled(scores.hub); series[5] = scaled(scores.trustrank); series[6] = scaled(scores.harmonic);
        List<String> correlation = new ArrayList<>(List.of("correlation")); for (int a = 0; a < 7; a++) for (int b = a + 1; b < 7; b++) correlation.add(line(QUANTITIES[a], QUANTITIES[b], kendall(series[a], series[b]))); groups.add(correlation);
        List<String> sweepLines = new ArrayList<>(List.of("damping_sweep"));
        for (Sweep sweep : sweeps) {
            sweepLines.add(line("damping", Report.fixed(sweep.damping, 4), "overlap", sweep.overlap, "footrule", sweep.footrule, "kendall", sweep.correlation, "largest_shift", graph.id(sweep.shift), scores.rank[sweep.shift], sweep.shiftRank));
            sweepLines.add(appendValues("top", graph.ids(sweep.top)));
        }
        groups.add(sweepLines); List<String> spamLines = new ArrayList<>(List.of(line("spam", "top", settings.spamTop(), "threshold", Report.fixed(settings.spamThreshold(), 4))));
        for (int node : spam.suspects) spamLines.add(line("suspect", graph.id(node), "rank", scores.rank[node], "pagerank", Report.fixed(scores.pagerank[node]), "trustrank", Report.fixed(scores.trustrank[node]),
            "trust_ratio", Report.fixed(scores.ratio[node], 4), "trust_distance", scores.trustDistance[node], "kcore", undirected.kcore[node], graph.host(node)));
        spamLines.add(line("count", spam.suspects.size())); spamLines.add("trust_by_distance");
        List<Integer> distances = Arrays.stream(scores.trustDistance).filter(value -> value >= 0).distinct().sorted().boxed().collect(java.util.stream.Collectors.toCollection(ArrayList::new));
        if (Arrays.stream(scores.trustDistance).anyMatch(value -> value == -1)) distances.add(-1);
        for (int distance : distances) {
            List<Integer> members = range(graph.count).stream().filter(node -> scores.trustDistance[node] == distance).toList();
            spamLines.add(line(distance == -1 ? "unreachable" : distance, "pages", members.size(), "trustrank", Report.fixed(total(scores.trustrank, members)), "pagerank", Report.fixed(total(scores.pagerank, members))));
        }
        groups.add(spamLines); List<String> demotion = new ArrayList<>();
        if (spam.run == null) demotion.add("demotion none");
        else {
            demotion.add(appendValues("demotion hosts", spam.hosts) + " removed_links " + spam.removed);
            List<Integer> nodes = top(spam.run.values(), limit);
            for (int i = 0; i < nodes.size(); i++) { int node = nodes.get(i); demotion.add(graph.describe(i + 1, node, Report.fixed(spam.run.values()[node]), "was", scores.rank[node])); }
            for (int node : spam.suspects) demotion.add(line("suspect", graph.id(node), "before", scores.rank[node], "after", spam.rank[node]));
        }
        groups.add(demotion); List<String> hostLines = new ArrayList<>(List.of(line("host_graph", "hosts", hosts.names.size(), "links", hosts.edges.size(), "reciprocal", hosts.reciprocal,
            "strong_components", hosts.componentCount, "largest", hosts.largest), line("host_links", "top", limit)));
        for (Edge edge : hosts.heavy) hostLines.add(line(hosts.names.get(edge.source()), hosts.names.get(edge.target()), hosts.weight[edge.source()][edge.target()])); groups.add(hostLines); return blocks(groups);
    }
    static List<String> convergenceBlock(String heading, PageRankResult run) {
        List<String> lines = new ArrayList<>(List.of("", heading));
        for (int step = 10; step <= run.changes().length; step += 10) lines.add(line("iteration", step, "l1", Report.fixed(run.changes()[step - 1], 10)));
        lines.add(line("converged_at", run.convergedAt() == null ? "none" : run.convergedAt())); return lines;
    }
    static List<String> convergence(Scores scores, List<Sweep> sweeps, Spam spam, List<QueryResult> queries, HostGraph hosts, Settings settings) {
        String damping = Report.fixed(settings.damping(), 4); List<String> lines = new ArrayList<>(List.of(line("iterations", settings.iterations(), "tolerance", Report.fixed(settings.tolerance(), 10))));
        lines.addAll(convergenceBlock(line("pagerank", "damping", damping), scores.pagerankRun)); lines.addAll(convergenceBlock(line("cheirank", "damping", damping), scores.cheirankRun));
        lines.addAll(convergenceBlock(line("trustrank", "damping", damping, "seeds", settings.trusted().length), scores.trustrankRun));
        for (Sweep sweep : sweeps) lines.addAll(convergenceBlock(line("sweep", "damping", Report.fixed(sweep.damping, 4)), sweep.run));
        if (spam.run != null) lines.addAll(convergenceBlock(line("demoted", "damping", damping), spam.run));
        for (QueryResult query : queries) lines.addAll(convergenceBlock(line("personalized", "query", query.query.number(), "damping", damping), query.personalized));
        lines.addAll(convergenceBlock(line("host_pagerank", "damping", damping, "hosts", hosts.names.size()), hosts.run)); return lines;
    }
    static List<String> queryLines(Graph graph, Scores scores, QueryResult result, int limit) {
        Query query = result.query; String heading = appendValues(line("query", query.number(), "words"), query.words());
        heading = appendValues(heading + " seeds", Arrays.stream(query.seeds()).boxed().toList());
        List<String> lines = new ArrayList<>(List.of(heading, line("matched", result.matches.size(), "root", result.rootSize, "base", result.baseSize, "links", result.subgraph.size(), "dropped_intra_host", result.dropped), "results"));
        lines.addAll(rankLines(graph, result.matches.stream().limit(limit).toList(), scores.pagerank)); lines.add(line("personalized", "reach", result.reach, "seed_mass", Report.fixed(result.seedMass)));
        lines.addAll(rankLines(graph, result.personalizedTop, result.personalized.values())); lines.add(line("overlap_with_global", result.overlap));
        SubgraphScores sub = result.subScores;
        if (sub == null) { lines.add("hits none"); return lines; }
        lines.add("hits authorities"); lines.addAll(rankLines(graph, sub.authorityTop, sub.authority)); lines.add("hits hubs"); lines.addAll(rankLines(graph, sub.hubTop, sub.hub));
        lines.add("salsa authorities"); lines.addAll(rankLines(graph, sub.salsaAuthorityTop, sub.salsaAuthority)); lines.add("salsa hubs"); lines.addAll(rankLines(graph, sub.salsaHubTop, sub.salsaHub));
        lines.add(line("hits_salsa_overlap", "authorities", sub.authorityOverlap, "hubs", sub.hubOverlap, "authority_hosts", sub.authorityHosts));
        lines.add(line("related_to", graph.id(sub.cited), "citing", graph.predecessors.get(sub.cited).size()));
        for (int i = 0; i < sub.related.size(); i++) { int node = sub.related.get(i); lines.add(graph.describe(i + 1, node, sub.cocitation[node])); }
        lines.add(line("coupled_to", graph.id(sub.citing), "cited", graph.successors.get(sub.citing).size()));
        for (int i = 0; i < sub.similar.size(); i++) { int node = sub.similar.get(i); lines.add(graph.describe(i + 1, node, sub.coupling[node])); }
        return lines;
    }
    static List<String> hostsCsv(Graph graph, int[] regions, Scores scores, HostGraph hosts) {
        List<String> lines = new ArrayList<>(List.of(HOSTS_HEADER));
        for (int number = 0; number < hosts.names.size(); number++) {
            List<Integer> members = hosts.members.get(number); int size = members.size();
            double density = size >= 2 ? (double) hosts.internal[number] / (size * (size - 1)) : 0;
            lines.add(String.join(",", hosts.names.get(number), "" + size, "" + members.stream().filter(node -> regions[node] == 0).count(), "" + hosts.internal[number], Report.fixed(density, 4),
                "" + hosts.outgoing[number], "" + hosts.incoming[number], "" + members.stream().filter(node -> graph.successors.get(node).isEmpty()).count(), Report.fixed(total(scores.pagerank, members)),
                "" + graph.id(scores.representative(members)), Report.fixed(hosts.run.values()[number]), "" + hosts.rank[number]));
        }
        return lines;
    }
    public static void main(String[] args) throws Exception {
        InputData input = GraphIO.read("input"); List<Page> pages = input.pages().stream().sorted(Comparator.comparingInt(Page::id)).toList(); Settings settings = input.settings();
        Map<Integer, Integer> index = new HashMap<>(); for (int node = 0; node < pages.size(); node++) index.put(pages.get(node).id(), node);
        Set<Edge> accepted = new HashSet<>(); List<Ignored> ignored = new ArrayList<>();
        for (LinkRecord record : input.records()) {
            if (!index.containsKey(record.source()) || !index.containsKey(record.target())) { ignored.add(new Ignored(record, "unknown")); continue; }
            Edge edge = new Edge(index.get(record.source()), index.get(record.target()));
            if (edge.source() == edge.target()) ignored.add(new Ignored(record, "self"));
            else if (!accepted.add(edge)) ignored.add(new Ignored(record, "duplicate"));
        }
        Graph graph = new Graph(pages, new ArrayList<>(accepted)); Undirected undirected = new Undirected(graph); ComponentTable table = new ComponentTable(graph);
        int[] regions = bowtie(graph, table.groups.get(table.core)); DistanceStats distances = new DistanceStats(graph);
        List<Integer> trusted = Arrays.stream(settings.trusted()).mapToObj(index::get).sorted().toList(); Scores scores = new Scores(graph, settings, trusted, distances.harmonic);
        List<Sweep> sweeps = new ArrayList<>(); for (double damping : settings.sweep()) sweeps.add(new Sweep(damping, graph, scores, settings)); Spam spam = new Spam(graph, scores, settings);
        List<QueryResult> results = new ArrayList<>(); for (Query query : input.queries()) results.add(new QueryResult(query, graph, scores, settings, index)); HostGraph hosts = new HostGraph(graph, settings);
        List<List<String>> queryBlocks = new ArrayList<>(); for (QueryResult result : results) queryBlocks.add(queryLines(graph, scores, result, settings.topK()));
        Map<String, List<String>> files = new LinkedHashMap<>();
        files.put("graph_stats.txt", graphStats(graph, input.records(), ignored, undirected, table, regions, distances, scores)); files.put("pagerank.csv", pagerankCsv(graph, table, regions, undirected, scores));
        files.put("rankings.txt", rankings(graph, scores, undirected, sweeps, spam, hosts, settings)); files.put("convergence.txt", convergence(scores, sweeps, spam, results, hosts, settings));
        files.put("queries.txt", blocks(queryBlocks)); files.put("hosts.csv", hostsCsv(graph, regions, scores, hosts)); Report.write(files);
    }
}
