readonly record struct VertexPair(int A, int B)
{
    public static VertexPair Unordered(int a, int b) => new(Math.Min(a, b), Math.Max(a, b));
}
sealed record Coordinates(int[] X, List<int[]> Aligned, List<int> Blocks, List<int> Widths, int Smallest, int Conflicts, int[] Left, int[] Right)
{
    public static int FloorHalf(int value) => value / 2 - (value % 2 < 0 ? 1 : 0);
    public static Coordinates Assign(int n, Order order, List<int> layer, Order upper, Order lower, List<int> width, bool vertical, int nodeSep, int dummySep)
    {
        int vertices = layer.Count;
        int[] positions = Crossing.Positions(order, vertices);
        int[] left = width.Select(w => vertical ? (w - 1) / 2 : 0).ToArray(), right = width.Select((w, i) => vertical ? w - 1 - left[i] : 0).ToArray();
        int Separation(int a, int b) => right[a] + left[b] + 1 + (a < n && b < n ? nodeSep : dummySep);
        HashSet<VertexPair> marked = new();
        for (int i = 0; i < order.Count - 1; i++)
        {
            List<int> a = order[i], b = order[i + 1];
            int k0 = 0, t = 0;
            for (int l1 = 0; l1 < b.Count; l1++)
            {
                int v = b[l1];
                bool inner = v >= n && upper[v][0] >= n;
                if (inner || l1 + 1 == b.Count)
                {
                    int k1 = inner ? positions[upper[v][0]] : a.Count - 1;
                    for (int l = t; l <= l1; l++) foreach (int u in upper[b[l]]) if (positions[u] < k0 || positions[u] > k1) marked.Add(VertexPair.Unordered(u, b[l]));
                    t = l1 + 1;
                    k0 = k1;
                }
            }
        }
        List<int[]> layouts = new();
        List<int> blocks = new(), widths = new(), lows = new(), highs = new();
        for (int variant = 0; variant < 4; variant++)
        {
            bool down = variant >= 2, rightScan = variant % 2 == 1;
            int Q(int v) => rightScan ? order[layer[v]].Count - 1 - positions[v] : positions[v];
            int[] root = Enumerable.Range(0, vertices).ToArray(), align = (int[])root.Clone();
            List<int> layers = (down ? Enumerable.Range(0, order.Count).Reverse() : Enumerable.Range(0, order.Count)).ToList();
            foreach (int i in layers.Skip(1))
            {
                IEnumerable<int> scan = rightScan ? order[i].AsEnumerable().Reverse() : order[i];
                int rho = -1;
                foreach (int v in scan)
                {
                    List<int> reference = (down ? lower[v] : upper[v]).OrderBy(Q).ToList();
                    if (reference.Count == 0) continue;
                    foreach (int m in new[] {
                        (reference.Count - 1) / 2, reference.Count / 2
                    })
                    {
                        int u = reference[m];
                        if (align[v] == v && !marked.Contains(VertexPair.Unordered(u, v)) && rho < Q(u)) {
                            align[u] = v;
                            root[v] = root[u];
                            align[v] = root[v];
                            rho = Q(u);
                        }
                    }
                }
            }
            HashSet<int> roots = root.ToHashSet();
            blocks.Add(roots.Count);
            Dictionary<VertexPair, int> edges = new();
            foreach (List<int> row in order)
            {
                List<int> scan = (rightScan ? row.AsEnumerable().Reverse() : row).ToList();
                for (int i = 1; i < scan.Count; i++)
                {
                    int a = scan[i - 1], b = scan[i], delta = rightScan ? Separation(b, a) : Separation(a, b);
                    VertexPair pair = new(root[a], root[b]);
                    edges[pair] = Math.Max(edges.GetValueOrDefault(pair), delta);
                }
            }
            List<List<(int Vertex, int Delta)>> incoming = Enumerable.Range(0, vertices).Select(_ => new List<(int, int)>()).ToList(), outgoing = Enumerable.Range(0, vertices).Select(_ => new List<(int, int)>()).ToList();
            int[] degree = new int[vertices];
            foreach (var (pair, delta) in edges) {
                incoming[pair.B].Add((pair.A, delta));
                outgoing[pair.A].Add((pair.B, delta));
                degree[pair.B]++;
            }
            SortedSet<int> ready = new(roots.Where(v => degree[v] == 0));
            List<int> topology = new();
            while (ready.Count > 0)
            {
                int v = ready.Min;
                ready.Remove(v);
                topology.Add(v);
                foreach (var (u, _) in outgoing[v]) {
                    degree[u]--;
                    if (degree[u] == 0) ready.Add(u);
                }
            }
            int[] y1 = new int[vertices];
            foreach (int v in topology) y1[v] = incoming[v].Select(e => y1[e.Vertex] + e.Delta).DefaultIfEmpty(0).Max();
            int[] y2 = (int[])y1.Clone();
            foreach (int v in topology.AsEnumerable().Reverse()) if (outgoing[v].Count > 0) y2[v] = Math.Max(y1[v], outgoing[v].Min(e => y2[e.Vertex] - e.Delta));
            int[] x = root.Select(r => rightScan ? -y2[r] : y2[r]).ToArray();
            int lo = Enumerable.Range(0, vertices).Min(v => x[v] - left[v]), hi = Enumerable.Range(0, vertices).Max(v => x[v] + right[v]);
            lows.Add(lo);
            highs.Add(hi);
            widths.Add(hi - lo + 1);
            layouts.Add(x);
        }
        int smallest = Enumerable.Range(0, 4).OrderBy(i => widths[i]).ThenBy(i => i).First();
        for (int i = 0; i < 4; i++)
        {
            int delta = i % 2 == 0 ? lows[smallest] - lows[i] : highs[smallest] - highs[i];
            for (int v = 0; v < vertices; v++) layouts[i][v] += delta;
        }
        int[] final = Enumerable.Range(0, vertices).Select(v => {
            int[] sorted = layouts.Select(a => a[v]).Order().ToArray();
            return FloorHalf(sorted[1] + sorted[2]);
        }).ToArray();
        int minimum = Enumerable.Range(0, vertices).Min(v => final[v] - left[v]);
        for (int v = 0; v < vertices; v++) final[v] -= minimum;
        return new Coordinates(final, layouts, blocks, widths, smallest, marked.Count, left, right);
    }
}
