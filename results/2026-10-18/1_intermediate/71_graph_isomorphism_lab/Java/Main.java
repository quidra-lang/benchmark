import java.io.*;
import java.util.*;

public class Main {
    static class Problem extends RuntimeException {
        Problem(String message) {
            super(message);
        }
    }

    static class Graph {
        final int n;
        final int[] adjacent;
        Graph(int n) {
            this.n = n;
            adjacent = new int[n];
        }
        Graph(Graph graph) {
            n = graph.n;
            adjacent = graph.adjacent.clone();
        }
        boolean edge(int u, int v) {
            return (adjacent[u] & 1 << v) != 0;
        }
        void join(int u, int v) {
            adjacent[u] |= 1 << v;
            adjacent[v] |= 1 << u;
        }
        int degree(int v) {
            return Integer.bitCount(adjacent[v]);
        }
        List<int[]> edges() {
            List<int[]> result = new ArrayList<>();
            for (int u = 0; u < n; u++) for (int v = u + 1; v < n; v++) if (edge(u, v)) result.add(new int[]{u, v});
            return result;
        }
    }

    record Refined(int[] colors, int rounds) {}

    record Invariants(int[] degrees, int edges, int triangles, List<Integer> sizes, String girth, String diameter, String radius, String bipartite) {}

    static class Canonical {
        long nodes, leaves;
        String string;
        int[] labels;
        final List<int[]> maxima = new ArrayList<>();
    }

    record Embedding(int[] map, boolean induced) {}

    static final TreeMap<String, Graph> graphs = new TreeMap<>();
    static final Set<String> DEFINITIONS = Set.of("GRAPH", "CYCLE", "PATH", "COMPLETE", "BIPARTITE", "STAR", "WHEEL", "PETERSEN", "HYPERCUBE", "CIRCULANT", "GRID", "COMPLEMENT", "LINE", "PRODUCT", "UNION", "RELABEL", "INDUCED", "CANONIZE");
    static final Set<String> OTHER = Set.of("DELETE", "LIST", "SHOW", "INVARIANTS", "REFINE", "CANON", "ISO", "AUT", "SUBISO", "CLASSIFY");

    static void require(boolean valid, String reason) {
        if (!valid) throw new Problem("error: " + reason);
    }

    static boolean name(String word) {
        return word.matches("[a-z][a-z0-9]{0,7}");
    }

    static boolean number(String word) {
        return word.matches("0|[1-9][0-9]{0,2}");
    }

    static int integer(String word) {
        return Integer.parseInt(word);
    }

    static String numbers(int[] values) {
        return String.join(" ", Arrays.stream(values).mapToObj(Integer::toString).toList());
    }

    static String numbers(List<Integer> values) {
        return String.join(" ", values.stream().map(Object::toString).toList());
    }

    static int cells(int[] colors) {
        return Arrays.stream(colors).max().orElse(-1) + 1;
    }

    static int compare(int[] a, int[] b) {
        return Arrays.compare(a, b);
    }

    static int[] degreeColors(Graph graph) {
        int[] degrees = new int[graph.n];
        for (int i = 0; i < graph.n; i++) degrees[i] = graph.degree(i);
        int[] distinct = Arrays.stream(degrees).distinct().sorted().toArray(), colors = new int[graph.n];
        for (int i = 0; i < graph.n; i++) colors[i] = Arrays.binarySearch(distinct, degrees[i]);
        return colors;
    }

    static Refined refine(Graph graph, int[] initial) {
        int[] colors = initial.clone();
        int rounds = 0;
        while (true) {
            int[][] signatures = new int[graph.n][];
            for (int v = 0; v < graph.n; v++) {
                int[] neighbors = new int[graph.degree(v)];
                int at = 0;
                for (int w = 0; w < graph.n; w++) if (graph.edge(v, w)) neighbors[at++] = colors[w];
                Arrays.sort(neighbors);
                signatures[v] = new int[neighbors.length + 1];
                signatures[v][0] = colors[v];
                System.arraycopy(neighbors, 0, signatures[v], 1, neighbors.length);
            }
            Integer[] order = new Integer[graph.n];
            for (int i = 0; i < graph.n; i++) order[i] = i;
            Arrays.sort(order, (a, b) -> compare(signatures[a], signatures[b]));
            int[] next = new int[graph.n];
            int color = 0;
            for (int i = 0; i < graph.n; i++) {
                if (i > 0 && compare(signatures[order[i - 1]], signatures[order[i]]) != 0) color++;
                next[order[i]] = color;
            }
            if (cells(next) == cells(colors)) return new Refined(colors, rounds);
            colors = next;
            rounds++;
        }
    }

    static int[] individualize(int[] colors, int vertex) {
        int[] result = colors.clone();
        for (int i = 0; i < colors.length; i++) if (i != vertex && colors[i] >= colors[vertex]) result[i]++;
        return result;
    }

    static String leafString(Graph graph, int[] labels) {
        int[] inverse = new int[graph.n];
        for (int i = 0; i < graph.n; i++) inverse[labels[i]] = i;
        StringBuilder text = new StringBuilder();
        for (int i = 0; i < graph.n; i++) for (int j = i + 1; j < graph.n; j++) text.append(graph.edge(inverse[i], inverse[j]) ? '1' : '0');
        return text.toString();
    }

    static void canonicalSearch(Graph graph, int[] colors, Canonical result) {
        result.nodes++;
        if (cells(colors) == graph.n) {
            result.leaves++;
            String text = leafString(graph, colors);
            int order = result.string == null ? 1 : text.compareTo(result.string);
            if (order > 0) {
                result.string = text;
                result.labels = colors.clone();
                result.maxima.clear();
            }
            if (order >= 0) result.maxima.add(colors.clone());
            return;
        }
        int chosen = -1, smallest = graph.n + 1;
        int[] sizes = new int[cells(colors)];
        for (int color : colors) sizes[color]++;
        for (int color = 0; color < sizes.length; color++) if (sizes[color] >= 2 && sizes[color] < smallest) {
            chosen = color;
            smallest = sizes[color];
        }
        for (int vertex = 0; vertex < graph.n; vertex++) if (colors[vertex] == chosen) canonicalSearch(graph, refine(graph, individualize(colors, vertex)).colors(), result);
    }

    static Canonical canonical(Graph graph) {
        Canonical result = new Canonical();
        canonicalSearch(graph, refine(graph, degreeColors(graph)).colors(), result);
        return result;
    }

    static Invariants invariants(Graph graph) {
        int[] degrees = new int[graph.n];
        for (int i = 0; i < graph.n; i++) degrees[i] = graph.degree(i);
        Arrays.sort(degrees);
        for (int i = 0; i < graph.n / 2; i++) {
            int x = degrees[i];
            degrees[i] = degrees[graph.n - 1 - i];
            degrees[graph.n - 1 - i] = x;
        }
        int triangles = 0;
        for (int a = 0; a < graph.n; a++) for (int b = a + 1; b < graph.n; b++) for (int c = b + 1; c < graph.n; c++) if (graph.edge(a, b) && graph.edge(a, c) && graph.edge(b, c)) triangles++;
        int[][] distances = new int[graph.n][graph.n];
        boolean[] visited = new boolean[graph.n];
        List<Integer> sizes = new ArrayList<>();
        int girth = Integer.MAX_VALUE;
        boolean bipartite = true;
        for (int source = 0; source < graph.n; source++) {
            Arrays.fill(distances[source], -1);
            int[] parents = new int[graph.n];
            Arrays.fill(parents, -1);
            ArrayDeque<Integer> queue = new ArrayDeque<>();
            queue.add(source);
            distances[source][source] = 0;
            int size = 0;
            while (!queue.isEmpty()) {
                int u = queue.remove();
                size++;
                for (int v = 0; v < graph.n; v++) if (graph.edge(u, v)) {
                    if (distances[source][v] < 0) {
                        distances[source][v] = distances[source][u] + 1;
                        parents[v] = u;
                        queue.add(v);
                    } else if (parents[u] != v && parents[v] != u) girth = Math.min(girth, distances[source][u] + distances[source][v] + 1);
                    if (distances[source][v] % 2 == distances[source][u] % 2) bipartite = false;
                }
            }
            if (!visited[source]) {
                sizes.add(size);
                for (int i = 0; i < graph.n; i++) if (distances[source][i] >= 0) visited[i] = true;
            }
        }
        sizes.sort(Comparator.reverseOrder());
        int diameter = 0, radius = graph.n;
        if (sizes.size() == 1) for (int[] row : distances) {
            int eccentricity = Arrays.stream(row).max().orElse(0);
            diameter = Math.max(diameter, eccentricity);
            radius = Math.min(radius, eccentricity);
        }
        return new Invariants(degrees, graph.edges().size(), triangles, sizes, girth == Integer.MAX_VALUE ? "none" : "" + girth, sizes.size() == 1 ? "" + diameter : "INF", sizes.size() == 1 ? "" + radius : "INF", bipartite ? "yes" : "no");
    }

    static boolean colorSearch(Graph graph, int count, int vertex, int largest, int[] colors) {
        if (vertex == graph.n) return true;
        for (int color = 0; color < count && color <= largest + 1; color++) {
            boolean good = true;
            for (int other = 0; other < vertex; other++) if (graph.edge(vertex, other) && colors[other] == color) good = false;
            if (good) {
                colors[vertex] = color;
                if (colorSearch(graph, count, vertex + 1, Math.max(largest, color), colors)) return true;
            }
        }
        return false;
    }

    static void printInvariants(String name, Graph graph) {
        Invariants data = invariants(graph);
        System.out.println("invariants " + name);
        System.out.println("degrees " + numbers(data.degrees()));
        System.out.println("edges " + data.edges() + " triangles " + data.triangles());
        System.out.println("components " + data.sizes().size() + " sizes " + numbers(data.sizes()));
        System.out.println("girth " + data.girth() + " diameter " + data.diameter() + " radius " + data.radius());
        System.out.println("bipartite " + data.bipartite());
        if (graph.n >= 13) {
            System.out.println("clique -\nchromatic -");
            return;
        }
        int[] best = new int[0];
        for (int mask = 1; mask < 1 << graph.n; mask++) {
            if (Integer.bitCount(mask) < best.length) continue;
            boolean good = true;
            List<Integer> selected = new ArrayList<>();
            for (int u = 0; u < graph.n; u++) if ((mask & 1 << u) != 0) {
                selected.add(u);
                for (int v = u + 1; v < graph.n; v++) if ((mask & 1 << v) != 0 && !graph.edge(u, v)) good = false;
            }
            int[] candidate = selected.stream().mapToInt(Integer::intValue).toArray();
            if (good && (candidate.length > best.length || compare(candidate, best) < 0)) best = candidate;
        }
        System.out.println("clique " + best.length + " " + numbers(best));
        int[] colors = new int[graph.n];
        int count = 1;
        while (!colorSearch(graph, count, 0, -1, colors)) count++;
        System.out.println("chromatic " + count + " " + numbers(colors));
    }

    static class DisjointSet {
        final int[] parent;
        DisjointSet(int n) {
            parent = new int[n];
            for (int i = 0; i < n; i++) parent[i] = i;
        }
        int find(int v) {
            return parent[v] == v ? v : (parent[v] = find(parent[v]));
        }
        void join(int a, int b) {
            a = find(a);
            b = find(b);
            if (a != b) parent[Math.max(a, b)] = Math.min(a, b);
        }
        List<List<Integer>> groups() {
            TreeMap<Integer, List<Integer>> groups = new TreeMap<>();
            for (int i = 0; i < parent.length; i++) groups.computeIfAbsent(find(i), key -> new ArrayList<>()).add(i);
            return new ArrayList<>(groups.values());
        }
    }

    static void automorphisms(String name, Graph graph) {
        Canonical data = canonical(graph);
        List<int[]> edges = graph.edges();
        DisjointSet vertices = new DisjointSet(graph.n), edgeSets = new DisjointSet(edges.size());
        int[] inverse = new int[graph.n];
        for (int i = 0; i < graph.n; i++) inverse[data.labels[i]] = i;
        int[][] edgeIndex = new int[graph.n][graph.n];
        for (int i = 0; i < edges.size(); i++) {
            int[] edge = edges.get(i);
            edgeIndex[edge[0]][edge[1]] = edgeIndex[edge[1]][edge[0]] = i;
        }
        for (int[] leaf : data.maxima) {
            int[] permutation = new int[graph.n];
            for (int i = 0; i < graph.n; i++) {
                permutation[i] = inverse[leaf[i]];
                vertices.join(i, permutation[i]);
            }
            for (int i = 0; i < edges.size(); i++) edgeSets.join(i, edgeIndex[permutation[edges.get(i)[0]]][permutation[edges.get(i)[1]]]);
        }
        var vertexGroups = vertices.groups();
        var edgeGroups = edgeSets.groups();
        System.out.println("aut " + name + " order " + data.maxima.size());
        System.out.println("vertex orbits " + vertexGroups.size());
        for (var group : vertexGroups) System.out.println("orbit " + numbers(group));
        System.out.println("edge orbits " + edgeGroups.size());
        for (var group : edgeGroups) System.out.println("orbit " + String.join(" ", group.stream().map(i -> edges.get(i)[0] + "-" + edges.get(i)[1]).toList()));
        System.out.println("transitive vertex " + (vertexGroups.size() == 1 ? "yes" : "no") + " edge " + (edgeGroups.size() == 1 ? "yes" : "no"));
    }

    static class Embeddings {
        long count, induced;
        final List<Embedding> first = new ArrayList<>();
        void search(Graph pattern, Graph target, int vertex, int used, int[] map, boolean stillInduced) {
            if (vertex == pattern.n) {
                count++;
                if (stillInduced) induced++;
                if (first.size() < 5) first.add(new Embedding(map.clone(), stillInduced));
                return;
            }
            for (int candidate = 0; candidate < target.n; candidate++) if ((used & 1 << candidate) == 0) {
                boolean good = true, induced = stillInduced;
                for (int before = 0; before < vertex; before++) {
                    boolean a = pattern.edge(vertex, before), b = target.edge(candidate, map[before]);
                    if (a && !b) good = false;
                    if (a != b) induced = false;
                }
                if (good) {
                    map[vertex] = candidate;
                    search(pattern, target, vertex + 1, used | 1 << candidate, map, induced);
                }
            }
        }
    }

    static void isomorphism(String leftName, Graph left, String rightName, Graph right) {
        if (left.n != right.n) {
            System.out.println("not isomorphic vertices " + left.n + " " + right.n);
            return;
        }
        Invariants a = invariants(left), b = invariants(right);
        String reason = null;
        if (a.edges() != b.edges()) reason = "edges " + a.edges() + " " + b.edges();
        else if (!Arrays.equals(a.degrees(), b.degrees())) reason = "degrees";
        else if (a.triangles() != b.triangles()) reason = "triangles " + a.triangles() + " " + b.triangles();
        else if (a.sizes().size() != b.sizes().size()) reason = "components " + a.sizes().size() + " " + b.sizes().size();
        else if (!a.girth().equals(b.girth())) reason = "girth " + a.girth() + " " + b.girth();
        else if (!a.diameter().equals(b.diameter())) reason = "diameter " + a.diameter() + " " + b.diameter();
        else if (!a.bipartite().equals(b.bipartite())) reason = "bipartite " + a.bipartite() + " " + b.bipartite();
        if (reason != null) {
            System.out.println("not isomorphic " + reason);
            return;
        }
        Refined x = refine(left, degreeColors(left)), y = refine(right, degreeColors(right));
        int[] xs = new int[cells(x.colors())], ys = new int[cells(y.colors())];
        for (int color : x.colors()) xs[color]++;
        for (int color : y.colors()) ys[color]++;
        if (x.rounds() != y.rounds() || !Arrays.equals(xs, ys)) {
            System.out.println("not isomorphic refinement");
            return;
        }
        Canonical c = canonical(left), d = canonical(right);
        if (!c.string.equals(d.string)) {
            System.out.println("not isomorphic canonical");
            return;
        }
        int[] inverse = new int[right.n], mapping = new int[left.n];
        for (int i = 0; i < right.n; i++) inverse[d.labels[i]] = i;
        for (int i = 0; i < left.n; i++) mapping[i] = inverse[c.labels[i]];
        System.out.println("isomorphic\nmapping " + numbers(mapping));
    }

    static Graph fromString(int n, String text) {
        Graph graph = new Graph(n);
        int at = 0;
        for (int u = 0; u < n; u++) for (int v = u + 1; v < n; v++) if (text.charAt(at++) == '1') graph.join(u, v);
        return graph;
    }

    static void classify(int n) {
        require(n >= 1, "bad value");
        require(n <= 5, "too large");
        List<TreeSet<String>> classes = new ArrayList<>();
        TreeSet<String> current = new TreeSet<>();
        current.add(canonical(new Graph(n)).string);
        int total = 0;
        for (int m = 0; m <= n * (n - 1) / 2; m++) {
            classes.add(current);
            total += current.size();
            TreeSet<String> next = new TreeSet<>();
            for (String text : current) {
                Graph graph = fromString(n, text);
                for (int u = 0; u < n; u++) for (int v = u + 1; v < n; v++) if (!graph.edge(u, v)) {
                    Graph added = new Graph(graph);
                    added.join(u, v);
                    next.add(canonical(added).string);
                }
            }
            current = next;
        }
        System.out.println("classify " + n + " total " + total);
        for (int m = 0; m < classes.size(); m++) System.out.println("edges " + m + " count " + classes.get(m).size() + " " + String.join(" ", classes.get(m).stream().map(s -> s.isEmpty() ? "-" : s).toList()));
    }

    static void command(String line) {
        String[] all = line.split(" "), args = Arrays.copyOfRange(all, 1, all.length);
        String command = all[0];
        require(DEFINITIONS.contains(command) || OTHER.contains(command), "unknown command " + command);
        int minimum, maximum, names;
        switch (command) {
            case "LIST":
                minimum = maximum = names = 0;
                break;
            case "CLASSIFY":
                minimum = maximum = 1;
                names = 0;
                break;
            case "PETERSEN", "DELETE", "SHOW", "INVARIANTS", "CANON", "AUT":
                minimum = maximum = names = 1;
                break;
            case "CYCLE", "PATH", "COMPLETE", "STAR", "WHEEL", "HYPERCUBE":
                minimum = maximum = 2;
                names = 1;
                break;
            case "BIPARTITE", "GRID":
                minimum = maximum = 3;
                names = 1;
                break;
            case "COMPLEMENT", "LINE", "CANONIZE", "ISO", "SUBISO":
                minimum = maximum = names = 2;
                break;
            case "PRODUCT", "UNION":
                minimum = maximum = names = 3;
                break;
            case "GRAPH":
                minimum = 2;
                maximum = Integer.MAX_VALUE;
                names = 1;
                break;
            case "CIRCULANT":
                minimum = 3;
                maximum = Integer.MAX_VALUE;
                names = 1;
                break;
            case "RELABEL":
                minimum = names = 2;
                maximum = Integer.MAX_VALUE;
                break;
            case "INDUCED":
                minimum = 3;
                names = 2;
                maximum = Integer.MAX_VALUE;
                break;
            default:
                minimum = names = 1;
                maximum = Integer.MAX_VALUE;
        }
        require(args.length >= minimum && args.length <= maximum, "bad arguments");
        for (int i = 0; i < names; i++) require(name(args[i]), "bad arguments");
        for (int i = names; i < args.length; i++) require(command.equals("GRAPH") && i >= 2 ? args[i].matches("(?:0|[1-9][0-9]{0,2})-(?:0|[1-9][0-9]{0,2})") : number(args[i]), "bad arguments");
        int firstReference = DEFINITIONS.contains(command) ? (Set.of("COMPLEMENT", "LINE", "PRODUCT", "UNION", "RELABEL", "INDUCED", "CANONIZE").contains(command) ? 1 : names) : 0;
        if (!command.equals("LIST") && !command.equals("CLASSIFY")) for (int i = firstReference; i < names; i++) require(graphs.containsKey(args[i]), "no graph " + args[i]);
        String name = args.length == 0 ? "" : args[0];
        Graph graph = null;
        int n = args.length > names ? integer(args[names]) : 0;
        if (DEFINITIONS.contains(command)) {
            switch (command) {
                case "GRAPH", "CYCLE", "PATH", "COMPLETE", "CIRCULANT":
                    require(n >= (command.equals("CYCLE") || command.equals("CIRCULANT") ? 3 : 1), "bad value");
                    require(n <= 16, "too large");
                    graph = new Graph(n);
                    if (command.equals("GRAPH")) for (int i = 2; i < args.length; i++) {
                        String[] edge = args[i].split("-");
                        int u = integer(edge[0]), v = integer(edge[1]);
                        require(u < n && v < n && u != v, "bad edge " + args[i]);
                        require(!graph.edge(u, v), "duplicate edge " + args[i]);
                        graph.join(u, v);
                    }
                    if (command.equals("PATH") || command.equals("CYCLE")) {
                        for (int i = 1; i < n; i++) graph.join(i - 1, i);
                        if (command.equals("CYCLE")) graph.join(n - 1, 0);
                    }
                    if (command.equals("COMPLETE")) for (int u = 0; u < n; u++) for (int v = u + 1; v < n; v++) graph.join(u, v);
                    if (command.equals("CIRCULANT")) {
                        int previous = 0;
                        for (int i = 2; i < args.length; i++) {
                            int jump = integer(args[i]);
                            require(jump > previous && jump * 2 <= n, "bad value");
                            previous = jump;
                            for (int v = 0; v < n; v++) graph.join(v, (v + jump) % n);
                        }
                    }
                    break;
                case "STAR", "WHEEL":
                    require(n >= (command.equals("WHEEL") ? 3 : 1), "bad value");
                    require(n < 16, "too large");
                    graph = new Graph(n + 1);
                    for (int i = 1; i <= n; i++) graph.join(0, i);
                    if (command.equals("WHEEL")) for (int i = 1; i <= n; i++) graph.join(i, i == n ? 1 : i + 1);
                    break;
                case "BIPARTITE", "GRID":
                    {
                        int b = integer(args[2]);
                        require(n > 0 && b > 0, "bad value");
                        int size = command.equals("GRID") ? n * b : n + b;
                        require(size <= 16, "too large");
                        graph = new Graph(size);
                        if (command.equals("BIPARTITE")) for (int u = 0; u < n; u++) for (int v = 0; v < b; v++) graph.join(u, n + v);
                        else for (int x = 0; x < n; x++) for (int y = 0; y < b; y++) {
                            if (x + 1 < n) graph.join(x * b + y, (x + 1) * b + y);
                            if (y + 1 < b) graph.join(x * b + y, x * b + y + 1);
                        }
                        break;
                    }
                case "PETERSEN":
                    graph = new Graph(10);
                    for (int i = 0; i < 5; i++) {
                        graph.join(i, (i + 1) % 5);
                        graph.join(i, i + 5);
                        graph.join(i + 5, 5 + (i + 2) % 5);
                    }
                    break;
                case "HYPERCUBE":
                    require(n > 0, "bad value");
                    require(n <= 4, "too large");
                    graph = new Graph(1 << n);
                    for (int u = 0; u < graph.n; u++) for (int bit = 0; bit < n; bit++) graph.join(u, u ^ 1 << bit);
                    break;
                case "COMPLEMENT":
                    {
                        Graph source = graphs.get(args[1]);
                        graph = new Graph(source.n);
                        for (int u = 0; u < source.n; u++) for (int v = u + 1; v < source.n; v++) if (!source.edge(u, v)) graph.join(u, v);
                        break;
                    }
                case "LINE":
                    {
                        List<int[]> edges = graphs.get(args[1]).edges();
                        require(!edges.isEmpty(), "no edges");
                        require(edges.size() <= 16, "too large");
                        graph = new Graph(edges.size());
                        for (int i = 0; i < edges.size(); i++) for (int j = i + 1; j < edges.size(); j++) if (edges.get(i)[0] == edges.get(j)[0] || edges.get(i)[0] == edges.get(j)[1] || edges.get(i)[1] == edges.get(j)[0] || edges.get(i)[1] == edges.get(j)[1]) graph.join(i, j);
                        break;
                    }
                case "PRODUCT", "UNION":
                    {
                        Graph a = graphs.get(args[1]), b = graphs.get(args[2]);
                        boolean product = command.equals("PRODUCT");
                        int size = product ? a.n * b.n : a.n + b.n;
                        require(size <= 16, "too large");
                        graph = new Graph(size);
                        if (product) {
                            for (int x = 0; x < a.n; x++) for (int[] edge : b.edges()) graph.join(x * b.n + edge[0], x * b.n + edge[1]);
                            for (int y = 0; y < b.n; y++) for (int[] edge : a.edges()) graph.join(edge[0] * b.n + y, edge[1] * b.n + y);
                        } else {
                            for (int[] edge : a.edges()) graph.join(edge[0], edge[1]);
                            for (int[] edge : b.edges()) graph.join(a.n + edge[0], a.n + edge[1]);
                        }
                        break;
                    }
                case "RELABEL", "INDUCED", "CANONIZE":
                    {
                        Graph source = graphs.get(args[1]);
                        int[] vertices = command.equals("CANONIZE") ? canonical(source).labels : Arrays.stream(args).skip(2).mapToInt(Main::integer).toArray();
                        if (command.equals("RELABEL")) {
                            require(vertices.length == source.n && Arrays.stream(vertices).distinct().count() == source.n && Arrays.stream(vertices).allMatch(v -> v < source.n), "bad permutation");
                        } else if (command.equals("INDUCED")) require(Arrays.stream(vertices).distinct().count() == vertices.length && Arrays.stream(vertices).allMatch(v -> v < source.n), "bad vertices");
                        graph = new Graph(command.equals("INDUCED") ? vertices.length : source.n);
                        if (command.equals("INDUCED")) {
                            for (int u = 0; u < vertices.length; u++) for (int v = u + 1; v < vertices.length; v++) if (source.edge(vertices[u], vertices[v])) graph.join(u, v);
                        } else for (int[] edge : source.edges()) graph.join(vertices[edge[0]], vertices[edge[1]]);
                        break;
                    }
            }
            boolean existed = graphs.containsKey(name);
            graphs.put(name, graph);
            System.out.println((existed ? "redefined " : "defined ") + name + " n " + graph.n + " m " + graph.edges().size());
            return;
        }
        graph = graphs.get(name);
        switch (command) {
            case "DELETE":
                graphs.remove(name);
                System.out.println("deleted " + name);
                break;
            case "LIST":
                System.out.println("graphs " + graphs.size());
                graphs.forEach((key, value) -> System.out.println(key + " n " + value.n + " m " + value.edges().size()));
                break;
            case "SHOW":
                System.out.println("graph " + name + " n " + graph.n + " m " + graph.edges().size());
                for (int v = 0; v < graph.n; v++) {
                    StringBuilder row = new StringBuilder(v + ":");
                    for (int w = 0; w < graph.n; w++) if (graph.edge(v, w)) row.append(' ').append(w);
                    System.out.println(row);
                }
                break;
            case "INVARIANTS":
                printInvariants(name, graph);
                break;
            case "REFINE":
                {
                    int[] vertices = Arrays.stream(args).skip(1).mapToInt(Main::integer).toArray();
                    Graph source = graph;
                    require(Arrays.stream(vertices).allMatch(v -> v < source.n), "bad vertices");
                    Refined result = refine(graph, degreeColors(graph));
                    int rounds = result.rounds();
                    int[] colors = result.colors();
                    for (int vertex : vertices) {
                        int size = 0;
                        for (int color : colors) if (color == colors[vertex]) size++;
                        require(size > 1, "singleton " + vertex);
                        result = refine(graph, individualize(colors, vertex));
                        colors = result.colors();
                        rounds += result.rounds();
                    }
                    System.out.println("refine " + name + " rounds " + rounds + " cells " + cells(colors));
                    for (int color = 0; color < cells(colors); color++) {
                        StringBuilder row = new StringBuilder(color + ":");
                        for (int v = 0; v < graph.n; v++) if (colors[v] == color) row.append(' ').append(v);
                        System.out.println(row);
                    }
                    break;
                }
            case "CANON":
                {
                    Canonical result = canonical(graph);
                    System.out.println("canon " + name + " nodes " + result.nodes + " leaves " + result.leaves);
                    System.out.println("labels " + numbers(result.labels));
                    System.out.println("string " + (result.string.isEmpty() ? "-" : result.string));
                    break;
                }
            case "AUT":
                automorphisms(name, graph);
                break;
            case "ISO":
                isomorphism(name, graph, args[1], graphs.get(args[1]));
                break;
            case "SUBISO":
                {
                    Graph destination = graphs.get(args[1]);
                    Embeddings result = new Embeddings();
                    if (graph.n <= destination.n) result.search(graph, destination, 0, 0, new int[graph.n], true);
                    int order = canonical(graph).maxima.size();
                    System.out.println("subiso " + name + " " + args[1] + " embeddings " + result.count + " induced " + result.induced);
                    System.out.println("copies " + result.count / order + " induced " + result.induced / order);
                    for (Embedding embedding : result.first) System.out.println("embedding " + numbers(embedding.map()) + (embedding.induced() ? " induced" : ""));
                    break;
                }
            case "CLASSIFY":
                classify(integer(name));
                break;
        }
    }
    public static void main(String[] args) throws IOException {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in));
        int count = Integer.parseInt(input.readLine());
        for (int i = 0; i < count; i++) try {
            command(input.readLine());
        } catch (Problem problem) {
            System.out.println(problem.getMessage());
        }
    }
}
