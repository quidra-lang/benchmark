using System;
using System.Collections.Generic;
using System.Linq;
using System.Numerics;
using System.Text;
using System.Text.RegularExpressions;

class Program
{
    class Problem(string message) : Exception("error: " + message) { }

    class Graph
    {
        public readonly int N;
        public readonly int[] Adjacent;
        public Graph(int n)
        {
            N = n;
            Adjacent = new int[n];
        }
        public Graph(Graph graph)
        {
            N = graph.N;
            Adjacent = (int[])graph.Adjacent.Clone();
        }
        public bool Edge(int u, int v) => (Adjacent[u] & 1 << v) != 0;
        public void Join(int u, int v)
        {
            Adjacent[u] |= 1 << v;
            Adjacent[v] |= 1 << u;
        }
        public int Degree(int vertex) => BitOperations.PopCount((uint)Adjacent[vertex]);
        public List<(int U, int V)> Edges()
        {
            List<(int, int)> result = [];
            for (int u = 0; u < N; u++) for (int v = u + 1; v < N; v++) if (Edge(u, v)) result.Add((u, v));
            return result;
        }
    }

    record Refined(int[] Colors, int Rounds);

    record Invariant(int[] Degrees, int Edges, int Triangles, List<int> Sizes, string Girth, string Diameter, string Radius, string Bipartite);

    class Canonical
    {
        public long Nodes, Leaves;
        public string? Text;
        public int[] Labels = [];
        public List<int[]> Maxima = [];
    }

    record Embedding(int[] Map, bool Induced);
    static readonly SortedDictionary<string, Graph> Graphs = new(StringComparer.Ordinal);
    static readonly HashSet<string> Definitions = ["GRAPH", "CYCLE", "PATH", "COMPLETE", "BIPARTITE", "STAR", "WHEEL", "PETERSEN", "HYPERCUBE", "CIRCULANT", "GRID", "COMPLEMENT", "LINE", "PRODUCT", "UNION", "RELABEL", "INDUCED", "CANONIZE"];
    static readonly HashSet<string> Other = ["DELETE", "LIST", "SHOW", "INVARIANTS", "REFINE", "CANON", "ISO", "AUT", "SUBISO", "CLASSIFY"];

    static void Require(bool valid, string reason)
    {
        if (!valid) throw new Problem(reason);
    }

    static bool Matches(string word, string pattern) => Regex.IsMatch(word, @"\A(?:" + pattern + @")\z");

    static bool Name(string word) => Matches(word, "[a-z][a-z0-9]{0,7}");

    static bool Number(string word) => Matches(word, "0|[1-9][0-9]{0,2}");

    static int Integer(string word) => int.Parse(word);

    static string Numbers(IEnumerable<int> values) => string.Join(" ", values);

    static int Cells(int[] colors) => colors.Max() + 1;

    static int Compare(int[] left, int[] right)
    {
        for (int i = 0; i < Math.Min(left.Length, right.Length); i++)
        {
            int order = left[i].CompareTo(right[i]);
            if (order != 0) return order;
        }
        return left.Length.CompareTo(right.Length);
    }

    static int[] DegreeColors(Graph graph)
    {
        int[] degrees = Enumerable.Range(0, graph.N).Select(graph.Degree).ToArray(), distinct = degrees.Distinct().Order().ToArray();
        return degrees.Select(degree => Array.IndexOf(distinct, degree)).ToArray();
    }

    static Refined Refine(Graph graph, int[] initial)
    {
        int[] colors = (int[])initial.Clone();
        int rounds = 0;
        while (true)
        {
            int[][] signatures = new int[graph.N][];
            for (int v = 0; v < graph.N; v++)
            {
                List<int> neighbors = [];
                for (int w = 0; w < graph.N; w++) if (graph.Edge(v, w)) neighbors.Add(colors[w]);
                neighbors.Sort();
                signatures[v] = [colors[v], .. neighbors];
            }
            int[] order = Enumerable.Range(0, graph.N).OrderBy(vertex => signatures[vertex], Comparer<int[]>.Create(Compare)).ToArray(), next = new int[graph.N];
            int color = 0;
            for (int i = 0; i < graph.N; i++)
            {
                if (i > 0 && Compare(signatures[order[i - 1]], signatures[order[i]]) != 0) color++;
                next[order[i]] = color;
            }
            if (Cells(next) == Cells(colors)) return new(colors, rounds);
            colors = next;
            rounds++;
        }
    }

    static int[] Individualize(int[] colors, int vertex)
    {
        int[] result = (int[])colors.Clone();
        for (int i = 0; i < colors.Length; i++) if (i != vertex && colors[i] >= colors[vertex]) result[i]++;
        return result;
    }

    static string LeafString(Graph graph, int[] labels)
    {
        int[] inverse = new int[graph.N];
        for (int i = 0; i < graph.N; i++) inverse[labels[i]] = i;
        StringBuilder text = new();
        for (int u = 0; u < graph.N; u++) for (int v = u + 1; v < graph.N; v++) text.Append(graph.Edge(inverse[u], inverse[v]) ? '1' : '0');
        return text.ToString();
    }

    static void CanonicalSearch(Graph graph, int[] colors, Canonical result)
    {
        result.Nodes++;
        if (Cells(colors) == graph.N)
        {
            result.Leaves++;
            string text = LeafString(graph, colors);
            int order = result.Text is null ? 1 : StringComparer.Ordinal.Compare(text, result.Text);
            if (order > 0)
            {
                result.Text = text;
                result.Labels = (int[])colors.Clone();
                result.Maxima.Clear();
            }
            if (order >= 0) result.Maxima.Add((int[])colors.Clone());
            return;
        }
        int chosen = -1, smallest = graph.N + 1;
        int[] sizes = new int[Cells(colors)];
        foreach (int color in colors) sizes[color]++;
        for (int color = 0; color < sizes.Length; color++) if (sizes[color] >= 2 && sizes[color] < smallest)
        {
            chosen = color;
            smallest = sizes[color];
        }
        for (int vertex = 0; vertex < graph.N; vertex++) if (colors[vertex] == chosen) CanonicalSearch(graph, Refine(graph, Individualize(colors, vertex)).Colors, result);
    }

    static Canonical Canon(Graph graph)
    {
        Canonical result = new();
        CanonicalSearch(graph, Refine(graph, DegreeColors(graph)).Colors, result);
        return result;
    }

    static Invariant Invariants(Graph graph)
    {
        int[] degrees = Enumerable.Range(0, graph.N).Select(graph.Degree).OrderDescending().ToArray();
        int triangles = 0;
        for (int a = 0; a < graph.N; a++) for (int b = a + 1; b < graph.N; b++) for (int c = b + 1; c < graph.N; c++) if (graph.Edge(a, b) && graph.Edge(a, c) && graph.Edge(b, c)) triangles++;
        int[][] distances = new int[graph.N][];
        bool[] visited = new bool[graph.N];
        List<int> sizes = [];
        int girth = int.MaxValue;
        bool bipartite = true;
        for (int source = 0; source < graph.N; source++)
        {
            int[] d = Enumerable.Repeat(-1, graph.N).ToArray(), parents = Enumerable.Repeat(-1, graph.N).ToArray();
            distances[source] = d;
            Queue<int> queue = new();
            queue.Enqueue(source);
            d[source] = 0;
            int size = 0;
            while (queue.Count > 0)
            {
                int u = queue.Dequeue();
                size++;
                for (int v = 0; v < graph.N; v++) if (graph.Edge(u, v))
                {
                    if (d[v] < 0)
                    {
                        d[v] = d[u] + 1;
                        parents[v] = u;
                        queue.Enqueue(v);
                    }
                    else if (parents[u] != v && parents[v] != u) girth = Math.Min(girth, d[u] + d[v] + 1);
                    if (d[u] % 2 == d[v] % 2) bipartite = false;
                }
            }
            if (!visited[source])
            {
                sizes.Add(size);
                for (int i = 0; i < graph.N; i++) if (d[i] >= 0) visited[i] = true;
            }
        }
        sizes.Sort((a, b) => b.CompareTo(a));
        int diameter = 0, radius = graph.N;
        if (sizes.Count == 1) foreach (int[] row in distances)
        {
            int eccentricity = row.Max();
            diameter = Math.Max(diameter, eccentricity);
            radius = Math.Min(radius, eccentricity);
        }
        return new(degrees, graph.Edges().Count, triangles, sizes, girth == int.MaxValue ? "none" : girth.ToString(), sizes.Count == 1 ? diameter.ToString() : "INF", sizes.Count == 1 ? radius.ToString() : "INF", bipartite ? "yes" : "no");
    }

    // A lexicographically smallest coloring introduces new colors in numerical order.
    static bool ColorSearch(Graph graph, int count, int vertex, int largest, int[] colors)
    {
        if (vertex == graph.N) return true;
        for (int color = 0; color < count && color <= largest + 1; color++)
        {
            bool good = true;
            for (int other = 0; other < vertex; other++) if (graph.Edge(vertex, other) && colors[other] == color) good = false;
            if (good)
            {
                colors[vertex] = color;
                if (ColorSearch(graph, count, vertex + 1, Math.Max(largest, color), colors)) return true;
            }
        }
        return false;
    }

    static void PrintInvariants(string name, Graph graph)
    {
        var data = Invariants(graph);
        Console.WriteLine("invariants " + name);
        Console.WriteLine("degrees " + Numbers(data.Degrees));
        Console.WriteLine($"edges {data.Edges} triangles {data.Triangles}");
        Console.WriteLine($"components {data.Sizes.Count} sizes {Numbers(data.Sizes)}");
        Console.WriteLine($"girth {data.Girth} diameter {data.Diameter} radius {data.Radius}");
        Console.WriteLine("bipartite " + data.Bipartite);
        if (graph.N >= 13)
        {
            Console.WriteLine("clique -\nchromatic -");
            return;
        }
        int[] best = [];
        for (int mask = 1; mask < 1 << graph.N; mask++)
        {
            if (BitOperations.PopCount((uint)mask) < best.Length) continue;
            bool good = true;
            List<int> selected = [];
            for (int u = 0; u < graph.N; u++) if ((mask & 1 << u) != 0)
            {
                selected.Add(u);
                for (int v = u + 1; v < graph.N; v++) if ((mask & 1 << v) != 0 && !graph.Edge(u, v)) good = false;
            }
            int[] candidate = selected.ToArray();
            if (good && (candidate.Length > best.Length || Compare(candidate, best) < 0)) best = candidate;
        }
        Console.WriteLine($"clique {best.Length} {Numbers(best)}");
        int[] colors = new int[graph.N];
        int count = 1;
        while (!ColorSearch(graph, count, 0, -1, colors)) count++;
        Console.WriteLine($"chromatic {count} {Numbers(colors)}");
    }

    class DisjointSet(int count)
    {
        readonly int[] parent = Enumerable.Range(0, count).ToArray();
        public int Find(int vertex) => parent[vertex] == vertex ? vertex : parent[vertex] = Find(parent[vertex]);
        public void Join(int left, int right)
        {
            left = Find(left);
            right = Find(right);
            if (left != right) parent[Math.Max(left, right)] = Math.Min(left, right);
        }
        public List<List<int>> Groups()
        {
            SortedDictionary<int, List<int>> groups = [];
            for (int i = 0; i < parent.Length; i++)
            {
                int root = Find(i);
                if (!groups.ContainsKey(root)) groups[root] = [];
                groups[root].Add(i);
            }
            return groups.Values.ToList();
        }
    }

    static void Automorphisms(string name, Graph graph)
    {
        Canonical data = Canon(graph);
        var edges = graph.Edges();
        DisjointSet vertices = new(graph.N), edgeSets = new(edges.Count);
        int[] inverse = new int[graph.N];
        for (int i = 0; i < graph.N; i++) inverse[data.Labels[i]] = i;
        int[,] edgeIndex = new int[graph.N, graph.N];
        for (int i = 0; i < edges.Count; i++) edgeIndex[edges[i].U, edges[i].V] = edgeIndex[edges[i].V, edges[i].U] = i;
        foreach (int[] leaf in data.Maxima)
        {
            int[] permutation = new int[graph.N];
            for (int i = 0; i < graph.N; i++)
            {
                permutation[i] = inverse[leaf[i]];
                vertices.Join(i, permutation[i]);
            }
            for (int i = 0; i < edges.Count; i++) edgeSets.Join(i, edgeIndex[permutation[edges[i].U], permutation[edges[i].V]]);
        }
        var vertexGroups = vertices.Groups();
        var edgeGroups = edgeSets.Groups();
        Console.WriteLine($"aut {name} order {data.Maxima.Count}");
        Console.WriteLine($"vertex orbits {vertexGroups.Count}");
        foreach (var group in vertexGroups) Console.WriteLine("orbit " + Numbers(group));
        Console.WriteLine($"edge orbits {edgeGroups.Count}");
        foreach (var group in edgeGroups) Console.WriteLine("orbit " + string.Join(" ", group.Select(i => $"{edges[i].U}-{edges[i].V}")));
        Console.WriteLine($"transitive vertex {(vertexGroups.Count == 1 ? "yes" : "no")} edge {(edgeGroups.Count == 1 ? "yes" : "no")}");
    }

    class Embeddings
    {
        public long Count, Induced;
        public List<Embedding> First = [];
        public void Search(Graph pattern, Graph target, int vertex, int used, int[] map, bool stillInduced)
        {
            if (vertex == pattern.N)
            {
                Count++;
                if (stillInduced) Induced++;
                if (First.Count < 5) First.Add(new((int[])map.Clone(), stillInduced));
                return;
            }
            for (int candidate = 0; candidate < target.N; candidate++) if ((used & 1 << candidate) == 0)
            {
                bool good = true, induced = stillInduced;
                for (int before = 0; before < vertex; before++)
                {
                    bool a = pattern.Edge(vertex, before), b = target.Edge(candidate, map[before]);
                    if (a && !b) good = false;
                    if (a != b) induced = false;
                }
                if (good)
                {
                    map[vertex] = candidate;
                    Search(pattern, target, vertex + 1, used | 1 << candidate, map, induced);
                }
            }
        }
    }

    static void Isomorphism(Graph left, Graph right)
    {
        if (left.N != right.N)
        {
            Console.WriteLine($"not isomorphic vertices {left.N} {right.N}");
            return;
        }
        var a = Invariants(left);
        var b = Invariants(right);
        string? reason = null;
        if (a.Edges != b.Edges) reason = $"edges {a.Edges} {b.Edges}";
        else if (!a.Degrees.SequenceEqual(b.Degrees)) reason = "degrees";
        else if (a.Triangles != b.Triangles) reason = $"triangles {a.Triangles} {b.Triangles}";
        else if (a.Sizes.Count != b.Sizes.Count) reason = $"components {a.Sizes.Count} {b.Sizes.Count}";
        else if (a.Girth != b.Girth) reason = $"girth {a.Girth} {b.Girth}";
        else if (a.Diameter != b.Diameter) reason = $"diameter {a.Diameter} {b.Diameter}";
        else if (a.Bipartite != b.Bipartite) reason = $"bipartite {a.Bipartite} {b.Bipartite}";
        if (reason is not null)
        {
            Console.WriteLine("not isomorphic " + reason);
            return;
        }
        var x = Refine(left, DegreeColors(left));
        var y = Refine(right, DegreeColors(right));
        int[] xs = new int[Cells(x.Colors)], ys = new int[Cells(y.Colors)];
        foreach (int color in x.Colors) xs[color]++;
        foreach (int color in y.Colors) ys[color]++;
        if (x.Rounds != y.Rounds || !xs.SequenceEqual(ys))
        {
            Console.WriteLine("not isomorphic refinement");
            return;
        }
        Canonical c = Canon(left), d = Canon(right);
        if (c.Text != d.Text)
        {
            Console.WriteLine("not isomorphic canonical");
            return;
        }
        int[] inverse = new int[right.N], mapping = new int[left.N];
        for (int i = 0; i < right.N; i++) inverse[d.Labels[i]] = i;
        for (int i = 0; i < left.N; i++) mapping[i] = inverse[c.Labels[i]];
        Console.WriteLine("isomorphic\nmapping " + Numbers(mapping));
    }

    static Graph FromString(int n, string text)
    {
        Graph graph = new(n);
        int at = 0;
        for (int u = 0; u < n; u++) for (int v = u + 1; v < n; v++) if (text[at++] == '1') graph.Join(u, v);
        return graph;
    }

    static void Classify(int n)
    {
        Require(n > 0, "bad value");
        Require(n <= 5, "too large");
        List<SortedSet<string>> classes = [];
        SortedSet<string> current = new(StringComparer.Ordinal) { Canon(new(n)).Text! };
        int total = 0;
        for (int m = 0; m <= n * (n - 1) / 2; m++)
        {
            classes.Add(current);
            total += current.Count;
            SortedSet<string> next = new(StringComparer.Ordinal);
            foreach (string text in current)
            {
                Graph graph = FromString(n, text);
                for (int u = 0; u < n; u++) for (int v = u + 1; v < n; v++) if (!graph.Edge(u, v))
                {
                    Graph added = new(graph);
                    added.Join(u, v);
                    next.Add(Canon(added).Text!);
                }
            }
            current = next;
        }
        Console.WriteLine($"classify {n} total {total}");
        for (int m = 0; m < classes.Count; m++) Console.WriteLine($"edges {m} count {classes[m].Count} " + string.Join(" ", classes[m].Select(text => text.Length == 0 ? "-" : text)));
    }

    static void Command(string line)
    {
        string[] all = line.Split(' '), args = all[1..];
        string command = all[0];
        Require(Definitions.Contains(command) || Other.Contains(command), "unknown command " + command);
        int minimum, maximum, names;
        switch (command)
        {
            case "LIST":
                minimum = maximum = names = 0;
                break;
            case "CLASSIFY":
                minimum = maximum = 1;
                names = 0;
                break;
            case "PETERSEN":
            case "DELETE":
            case "SHOW":
            case "INVARIANTS":
            case "CANON":
            case "AUT":
                minimum = maximum = names = 1;
                break;
            case "CYCLE":
            case "PATH":
            case "COMPLETE":
            case "STAR":
            case "WHEEL":
            case "HYPERCUBE":
                minimum = maximum = 2;
                names = 1;
                break;
            case "BIPARTITE":
            case "GRID":
                minimum = maximum = 3;
                names = 1;
                break;
            case "COMPLEMENT":
            case "LINE":
            case "CANONIZE":
            case "ISO":
            case "SUBISO":
                minimum = maximum = names = 2;
                break;
            case "PRODUCT":
            case "UNION":
                minimum = maximum = names = 3;
                break;
            case "GRAPH":
                minimum = 2;
                maximum = int.MaxValue;
                names = 1;
                break;
            case "CIRCULANT":
                minimum = 3;
                maximum = int.MaxValue;
                names = 1;
                break;
            case "RELABEL":
                minimum = names = 2;
                maximum = int.MaxValue;
                break;
            case "INDUCED":
                minimum = 3;
                names = 2;
                maximum = int.MaxValue;
                break;
            default:
                minimum = names = 1;
                maximum = int.MaxValue;
                break;
        }
        Require(args.Length >= minimum && args.Length <= maximum, "bad arguments");
        for (int i = 0; i < names; i++) Require(Name(args[i]), "bad arguments");
        for (int i = names; i < args.Length; i++) Require(command == "GRAPH" && i >= 2 ? Matches(args[i], "(?:0|[1-9][0-9]{0,2})-(?:0|[1-9][0-9]{0,2})") : Number(args[i]), "bad arguments");
        int firstReference = Definitions.Contains(command) ? (command is "COMPLEMENT" or "LINE" or "PRODUCT" or "UNION" or "RELABEL" or "INDUCED" or "CANONIZE" ? 1 : names) : 0;
        if (command is not ("LIST" or "CLASSIFY")) for (int i = firstReference; i < names; i++) Require(Graphs.ContainsKey(args[i]), "no graph " + args[i]);
        string name = args.Length == 0 ? "" : args[0];
        Graph? graph = null;
        int n = args.Length > names ? Integer(args[names]) : 0;
        if (Definitions.Contains(command))
        {
            switch (command)
            {
                case "GRAPH":
                case "CYCLE":
                case "PATH":
                case "COMPLETE":
                case "CIRCULANT":
                    Require(n >= (command is "CYCLE" or "CIRCULANT" ? 3 : 1), "bad value");
                    Require(n <= 16, "too large");
                    graph = new(n);
                    if (command == "GRAPH") for (int i = 2; i < args.Length; i++)
                    {
                        string[] edge = args[i].Split('-');
                        int u = Integer(edge[0]), v = Integer(edge[1]);
                        Require(u < n && v < n && u != v, "bad edge " + args[i]);
                        Require(!graph.Edge(u, v), "duplicate edge " + args[i]);
                        graph.Join(u, v);
                    }
                    if (command is "PATH" or "CYCLE")
                    {
                        for (int i = 1; i < n; i++) graph.Join(i - 1, i);
                        if (command == "CYCLE") graph.Join(n - 1, 0);
                    }
                    if (command == "COMPLETE") for (int u = 0; u < n; u++) for (int v = u + 1; v < n; v++) graph.Join(u, v);
                    if (command == "CIRCULANT")
                    {
                        int previous = 0;
                        for (int i = 2; i < args.Length; i++)
                        {
                            int jump = Integer(args[i]);
                            Require(jump > previous && jump * 2 <= n, "bad value");
                            previous = jump;
                            for (int v = 0; v < n; v++) graph.Join(v, (v + jump) % n);
                        }
                    }
                    break;
                case "STAR":
                case "WHEEL":
                    Require(n >= (command == "WHEEL" ? 3 : 1), "bad value");
                    Require(n < 16, "too large");
                    graph = new(n + 1);
                    for (int i = 1; i <= n; i++) graph.Join(0, i);
                    if (command == "WHEEL") for (int i = 1; i <= n; i++) graph.Join(i, i == n ? 1 : i + 1);
                    break;
                case "BIPARTITE":
                case "GRID":
                {
                    int b = Integer(args[2]);
                    Require(n > 0 && b > 0, "bad value");
                    int size = command == "GRID" ? n * b : n + b;
                    Require(size <= 16, "too large");
                    graph = new(size);
                    if (command == "BIPARTITE") for (int u = 0; u < n; u++) for (int v = 0; v < b; v++) graph.Join(u, n + v);
                    else for (int x = 0; x < n; x++) for (int y = 0; y < b; y++)
                    {
                        if (x + 1 < n) graph.Join(x * b + y, (x + 1) * b + y);
                        if (y + 1 < b) graph.Join(x * b + y, x * b + y + 1);
                    }
                    break;
                }
                case "PETERSEN":
                    graph = new(10);
                    for (int i = 0; i < 5; i++)
                    {
                        graph.Join(i, (i + 1) % 5);
                        graph.Join(i, i + 5);
                        graph.Join(i + 5, 5 + (i + 2) % 5);
                    }
                    break;
                case "HYPERCUBE":
                    Require(n > 0, "bad value");
                    Require(n <= 4, "too large");
                    graph = new(1 << n);
                    for (int u = 0; u < graph.N; u++) for (int bit = 0; bit < n; bit++) graph.Join(u, u ^ 1 << bit);
                    break;
                case "COMPLEMENT":
                {
                    Graph source = Graphs[args[1]];
                    graph = new(source.N);
                    for (int u = 0; u < source.N; u++) for (int v = u + 1; v < source.N; v++) if (!source.Edge(u, v)) graph.Join(u, v);
                    break;
                }
                case "LINE":
                {
                    var edges = Graphs[args[1]].Edges();
                    Require(edges.Count > 0, "no edges");
                    Require(edges.Count <= 16, "too large");
                    graph = new(edges.Count);
                    for (int i = 0; i < edges.Count; i++) for (int j = i + 1; j < edges.Count; j++) if (edges[i].U == edges[j].U || edges[i].U == edges[j].V || edges[i].V == edges[j].U || edges[i].V == edges[j].V) graph.Join(i, j);
                    break;
                }
                case "PRODUCT":
                case "UNION":
                {
                    Graph a = Graphs[args[1]], b = Graphs[args[2]];
                    bool product = command == "PRODUCT";
                    int size = product ? a.N * b.N : a.N + b.N;
                    Require(size <= 16, "too large");
                    graph = new(size);
                    if (product)
                    {
                        for (int x = 0; x < a.N; x++) foreach (var edge in b.Edges()) graph.Join(x * b.N + edge.U, x * b.N + edge.V);
                        for (int y = 0; y < b.N; y++) foreach (var edge in a.Edges()) graph.Join(edge.U * b.N + y, edge.V * b.N + y);
                    }
                    else
                    {
                        foreach (var edge in a.Edges()) graph.Join(edge.U, edge.V);
                        foreach (var edge in b.Edges()) graph.Join(a.N + edge.U, a.N + edge.V);
                    }
                    break;
                }
                case "RELABEL":
                case "INDUCED":
                case "CANONIZE":
                {
                    Graph source = Graphs[args[1]];
                    int[] vertices = command == "CANONIZE" ? Canon(source).Labels : args.Skip(2).Select(Integer).ToArray();
                    if (command == "RELABEL") Require(vertices.Length == source.N && vertices.Distinct().Count() == source.N && vertices.All(v => v < source.N), "bad permutation");
                    else if (command == "INDUCED") Require(vertices.Distinct().Count() == vertices.Length && vertices.All(v => v < source.N), "bad vertices");
                    graph = new(command == "INDUCED" ? vertices.Length : source.N);
                    if (command == "INDUCED")
                    {
                        for (int u = 0; u < vertices.Length; u++) for (int v = u + 1; v < vertices.Length; v++) if (source.Edge(vertices[u], vertices[v])) graph.Join(u, v);
                    }
                    else foreach (var edge in source.Edges()) graph.Join(vertices[edge.U], vertices[edge.V]);
                    break;
                }
            }
            bool existed = Graphs.ContainsKey(name);
            Graphs[name] = graph!;
            Console.WriteLine($"{(existed ? "redefined" : "defined")} {name} n {graph!.N} m {graph.Edges().Count}");
            return;
        }
        graph = Graphs.GetValueOrDefault(name);
        switch (command)
        {
            case "DELETE":
                Graphs.Remove(name);
                Console.WriteLine("deleted " + name);
                break;
            case "LIST":
                Console.WriteLine($"graphs {Graphs.Count}");
                foreach (var entry in Graphs) Console.WriteLine($"{entry.Key} n {entry.Value.N} m {entry.Value.Edges().Count}");
                break;
            case "SHOW":
                Console.WriteLine($"graph {name} n {graph!.N} m {graph.Edges().Count}");
                for (int v = 0; v < graph.N; v++)
                {
                    StringBuilder row = new(v + ":");
                    for (int w = 0; w < graph.N; w++) if (graph.Edge(v, w)) row.Append(' ').Append(w);
                    Console.WriteLine(row);
                }
                break;
            case "INVARIANTS":
                PrintInvariants(name, graph!);
                break;
            case "REFINE":
            {
                Graph source = graph!;
                int[] vertices = args.Skip(1).Select(Integer).ToArray();
                Require(vertices.All(v => v < source.N), "bad vertices");
                var result = Refine(source, DegreeColors(source));
                int rounds = result.Rounds;
                int[] colors = result.Colors;
                foreach (int vertex in vertices)
                {
                    Require(colors.Count(color => color == colors[vertex]) > 1, "singleton " + vertex);
                    result = Refine(source, Individualize(colors, vertex));
                    colors = result.Colors;
                    rounds += result.Rounds;
                }
                Console.WriteLine($"refine {name} rounds {rounds} cells {Cells(colors)}");
                for (int color = 0; color < Cells(colors); color++)
                {
                    StringBuilder row = new(color + ":");
                    for (int v = 0; v < source.N; v++) if (colors[v] == color) row.Append(' ').Append(v);
                    Console.WriteLine(row);
                }
                break;
            }
            case "CANON":
            {
                var result = Canon(graph!);
                Console.WriteLine($"canon {name} nodes {result.Nodes} leaves {result.Leaves}");
                Console.WriteLine("labels " + Numbers(result.Labels));
                Console.WriteLine("string " + (result.Text!.Length == 0 ? "-" : result.Text));
                break;
            }
            case "AUT":
                Automorphisms(name, graph!);
                break;
            case "ISO":
                Isomorphism(graph!, Graphs[args[1]]);
                break;
            case "SUBISO":
            {
                Graph destination = Graphs[args[1]];
                Embeddings result = new();
                if (graph!.N <= destination.N) result.Search(graph, destination, 0, 0, new int[graph.N], true);
                int order = Canon(graph).Maxima.Count;
                Console.WriteLine($"subiso {name} {args[1]} embeddings {result.Count} induced {result.Induced}");
                Console.WriteLine($"copies {result.Count / order} induced {result.Induced / order}");
                foreach (var embedding in result.First) Console.WriteLine("embedding " + Numbers(embedding.Map) + (embedding.Induced ? " induced" : ""));
                break;
            }
            case "CLASSIFY":
                Classify(Integer(name));
                break;
        }
    }

    static void Main()
    {
        int count = int.Parse(Console.ReadLine()!);
        for (int i = 0; i < count; i++) try
        {
            Command(Console.ReadLine()!);
        }
        catch (Problem problem)
        {
            Console.WriteLine(problem.Message);
        }
    }
}
