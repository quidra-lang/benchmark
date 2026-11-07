sealed record Model(List<int> Layer, List<int> Width, Order Chains, List<List<Segment>> Gaps, Order Upper, Order Lower, Order Initial);
sealed record Analysis(int Sources, int Sinks, int Isolated, int Components, Order Scc);
sealed record Reduction(Order Order, List<string> Records, List<string> Csv, int Initial, int Swept, int Run, int Sweep);
sealed record Bus(int Lo, int Hi, int Side, int X, List<int> Members);
sealed record Geometry(List<int> Tracks, List<int> Gaps, List<int?[]> Offsets, int[] Thickness, int[] Starts, int Main, int Secondary);
sealed record Drawing(Canvas Canvas, List<List<Cell>> Routes, int[] Lengths, int[] Bends);
sealed record Processed(List<string> Layout, List<string> Stats, List<string> Csv, List<string> Drawings, int[] Totals);
static class Program
{
    static Order CopyOrder(Order order) => order.Select(r => new List<int>(r)).ToList();
    static bool SameOrder(Order a, Order b) => a.Count == b.Count && a.Zip(b).All(p => p.First.SequenceEqual(p.Second));
    static bool[,] Reachability(int n, List<Edge> edges)
    {
        bool[,] reachable = new bool[n, n];
        for (int i = 0; i < n; i++) reachable[i, i] = true;
        foreach (var (a, b) in edges) reachable[a, b] = true;
        for (int k = 0; k < n; k++) for (int i = 0; i < n; i++) for (int j = 0; j < n; j++) reachable[i, j] |= reachable[i, k] && reachable[k, j];
        return reachable;
    }
    static Analysis Analyze(Graph graph)
    {
        int n = graph.Nodes.Count;
        int[] incoming = new int[n], outgoing = new int[n];
        foreach (var (a, b) in graph.Edges) {
            outgoing[a]++;
            incoming[b]++;
        }
        int sources = Enumerable.Range(0, n).Count(v => incoming[v] == 0 && outgoing[v] > 0), sinks = Enumerable.Range(0, n).Count(v => outgoing[v] == 0 && incoming[v] > 0), isolated = Enumerable.Range(0, n).Count(v => incoming[v] == 0 && outgoing[v] == 0);
        HashSet<int> visited = new();
        int components = 0;
        for (int v = 0; v < n; v++) if (!visited.Contains(v))
        {
            components++;
            Stack<int> stack = new();
            stack.Push(v);
            while (stack.TryPop(out int a)) if (visited.Add(a)) foreach (var (u, w) in graph.Edges) {
                if (u == a) stack.Push(w);
                if (w == a) stack.Push(u);
            }
        }
        bool[,] connected = Reachability(n, graph.Edges);
        HashSet<int> remaining = Enumerable.Range(0, n).ToHashSet();
        Order scc = new();
        while (remaining.Count > 0)
        {
            int v = remaining.Min();
            List<int> group = remaining.Where(u => connected[v, u] && connected[u, v]).Order().ToList();
            remaining.ExceptWith(group);
            if (group.Count > 1) scc.Add(group);
        }
        return new Analysis(sources, sinks, isolated, components, scc);
    }
    static Model BuildModel(Graph graph, int[] heights, List<Edge> dag, bool[] removed)
    {
        int n = graph.Nodes.Count, h = heights.Max();
        int[] raw = heights.Select(v => h - v).ToArray();
        HashSet<int> used = raw.ToHashSet();
        for (int i = 0; i < dag.Count; i++) if (!removed[i]) for (int level = raw[dag[i].A] + 1; level < raw[dag[i].B]; level++) used.Add(level);
        Dictionary<int, int> numbering = used.Order().Select((v, i) => (Value: v, Index: i)).ToDictionary(p => p.Value, p => p.Index);
        List<int> layer = raw.Select(v => numbering[v]).ToList(), width = graph.Nodes.Select(node => node.Label.Length + 2).ToList();
        Order chains = graph.Edges.Select(_ => new List<int>()).ToList();
        for (int i = 0; i < dag.Count; i++) if (!removed[i])
        {
            var (a, b) = dag[i];
            chains[i].Add(a);
            for (int l = layer[a] + 1; l < layer[b]; l++) {
                chains[i].Add(layer.Count);
                layer.Add(l);
                width.Add(1);
            }
            chains[i].Add(b);
        }
        List<List<Segment>> gaps = Enumerable.Range(0, Math.Max(0, used.Count - 1)).Select(_ => new List<Segment>()).ToList();
        Order upper = layer.Select(_ => new List<int>()).ToList(), lower = layer.Select(_ => new List<int>()).ToList();
        for (int i = 0; i < chains.Count; i++) for (int j = 1; j < chains[i].Count; j++)
        {
            int p = chains[i][j - 1], q = chains[i][j];
            gaps[layer[p]].Add(new Segment(p, q, i));
            upper[q].Add(p);
            lower[p].Add(q);
        }
        Order initial = Enumerable.Range(0, used.Count).Select(_ => new List<int>()).ToList();
        bool[] visited = new bool[layer.Count];
        void Visit(int v)
        {
            if (visited[v]) return;
            visited[v] = true;
            initial[layer[v]].Add(v);
            foreach (int w in lower[v]) Visit(w);
        }
        for (int v = 0; v < n; v++) Visit(v);
        return new Model(layer, width, chains, gaps, upper, lower, initial);
    }
    static Reduction ReduceCrossings(Graph graph, Model model)
    {
        int n = model.Layer.Count;
        long random = graph.Settings.Integer("seed");
        List<string> records = new(), csv = new();
        Order adopted = CopyOrder(model.Initial);
        int bestCount = int.MaxValue, bestRun = 0, bestSweep = 0, initial = 0;
        for (int run = 0; run <= graph.Settings.Integer("restarts"); run++)
        {
            Order order = CopyOrder(model.Initial);
            if (run > 0) foreach (List<int> row in order) for (int j = row.Count - 1; j >= 1; j--)
            {
                random = 48271L * random % 2147483647L;
                int k = (int)(random % (j + 1));
                (row[j], row[k]) = (row[k], row[j]);
            }
            int count = Crossing.Total(model.Gaps, order, n);
            if (run == 0) initial = count;
            int runCount = count, runSweep = 0;
            Order runOrder = CopyOrder(order);
            List<Order> history = new() {
                CopyOrder(order)
            };
            List<int> counts = new() {
                count
            };
            records.Add($"sweep {run} 0 initial crossings {count}");
            csv.Add($"{graph.Name},{run},0,{count}");
            for (int sweep = 1; sweep <= graph.Settings.Integer("sweeps"); sweep++)
            {
                int last = sweep - 1;
                if (counts[last] == 0 || last >= 2 && SameOrder(history[last], history[last - 2])) break;
                int[] old = Crossing.Positions(order, n);
                List<int> layers = sweep % 2 == 1 ? Enumerable.Range(1, Math.Max(0, order.Count - 1)).ToList() : Enumerable.Range(0, Math.Max(0, order.Count - 1)).Reverse().ToList();
                Order reference = sweep % 2 == 1 ? model.Upper : model.Lower;
                foreach (int i in layers)
                {
                    int[] pos = Crossing.Positions(order, n);
                    (int P, int Q) Key(int v)
                    {
                        List<int> values = reference[v].Select(u => pos[u]).Order().ToList();
                        return graph.Settings.Text("heuristic") == "median" ? (values[(values.Count - 1) / 2] + values[values.Count / 2], 1) : (values.Sum(), values.Count);
                    }
                    List<int> moving = order[i].Where(v => reference[v].Count > 0).OrderBy(v => v, Comparer<int>.Create((a, b) =>
                    {
                        var x = Key(a);
                        var y = Key(b);
                        int comparison = (x.P * y.Q).CompareTo(y.P * x.Q);
                        return comparison != 0 ? comparison : pos[a].CompareTo(pos[b]);
                    })).ToList();
                    int next = 0;
                    for (int j = 0; j < order[i].Count; j++) if (reference[order[i][j]].Count > 0) order[i][j] = moving[next++];
                }
                int[] positions = Crossing.Positions(order, n);
                int moved = Enumerable.Range(0, n).Count(v => positions[v] != old[v]), swaps = 0;
                while (true)
                {
                    bool changed = false;
                    for (int i = 0; i < order.Count; i++) for (int j = 0; j < order[i].Count - 1; j++)
                    {
                        int v = order[i][j], w = order[i][j + 1];
                        if (Crossing.Adjacent(v, w, model.Upper, model.Lower, positions) > Crossing.Adjacent(w, v, model.Upper, model.Lower, positions))
                        {
                            order[i][j] = w;
                            order[i][j + 1] = v;
                            positions[v] = j + 1;
                            positions[w] = j;
                            swaps++;
                            changed = true;
                        }
                    }
                    if (!changed) break;
                }
                int currentCount = Crossing.Total(model.Gaps, order, n);
                history.Add(CopyOrder(order));
                counts.Add(currentCount);
                records.Add($"sweep {run} {sweep} {(sweep % 2 == 1 ? "down" : "up")} moved {moved} swaps {swaps} crossings {currentCount}");
                csv.Add($"{graph.Name},{run},{sweep},{currentCount}");
                if (currentCount < runCount) {
                    runCount = currentCount;
                    runSweep = sweep;
                    runOrder = CopyOrder(order);
                }
            }
            if (runCount < bestCount) {
                bestCount = runCount;
                bestRun = run;
                bestSweep = runSweep;
                adopted = runOrder;
            }
        }
        records.Add($"best run {bestRun} sweep {bestSweep} crossings {bestCount}");
        if (graph.Settings.On("sifting"))
        {
            int round = 0;
            while (true)
            {
                round++;
                int moves = 0;
                for (int v = 0; v < n; v++)
                {
                    int i = model.Layer[v], old = adopted[i].IndexOf(v);
                    List<int> basis = new(adopted[i]);
                    basis.RemoveAt(old);
                    List<int> costs = new();
                    for (int p = 0; p <= basis.Count; p++)
                    {
                        List<int> row = new(basis);
                        row.Insert(p, v);
                        adopted[i] = row;
                        costs.Add(Crossing.Total(model.Gaps, adopted, n));
                    }
                    int minimum = costs.Min(), position = costs[old] == minimum ? old : costs.IndexOf(minimum);
                    basis.Insert(position, v);
                    adopted[i] = basis;
                    if (position != old) moves++;
                }
                records.Add($"sift {round} moves {moves} crossings {Crossing.Total(model.Gaps, adopted, n)}");
                if (moves == 0) break;
            }
        }
        return new Reduction(adopted, records, csv, initial, bestCount, bestRun, bestSweep);
    }
    static Geometry BuildGeometry(Graph graph, Model model, Order order, Coordinates coordinates)
    {
        int[] x = coordinates.X;
        List<int> tracks = new(), gaps = new();
        List<int?[]> offsets = new();
        foreach (List<Segment> segments in model.Gaps)
        {
            Dictionary<int, int> counts = segments.Where(s => x[s.P] != x[s.Q]).GroupBy(s => s.P).ToDictionary(g => g.Key, g => g.Count());
            var groups = Enumerable.Range(0, segments.Count).Where(i => x[segments[i].P] != x[segments[i].Q]).GroupBy(i => counts[segments[i].P] >= 2 ? new VertexPair(0, segments[i].P) : new VertexPair(1, segments[i].Q));
            List<Bus> buses = groups.Select(g => new Bus(g.Min(i => Math.Min(x[segments[i].P], x[segments[i].Q])), g.Max(i => Math.Max(x[segments[i].P], x[segments[i].Q])), g.Key.A, x[g.Key.B], g.ToList())).OrderBy(b => b.Lo).ThenBy(b => b.Hi).ThenBy(b => b.Side).ThenBy(b => b.X).ToList();
            List<int> ends = new();
            int?[] assignments = new int?[segments.Count];
            foreach (Bus bus in buses)
            {
                int track = ends.FindIndex(e => e + 1 < bus.Lo);
                if (track < 0) {
                    track = ends.Count;
                    ends.Add(bus.Hi);
                } else ends[track] = bus.Hi;
                foreach (int k in bus.Members) assignments[k] = track + 1;
            }
            int gap = Math.Max(graph.Settings.Integer("layer_gap"), ends.Count + 2);
            tracks.Add(ends.Count);
            gaps.Add(gap);
            offsets.Add(assignments.Select(a => a is {
            } v ? (int?)(v + (gap - 2 - ends.Count) / 2) : null).ToArray());
        }
        bool vertical = graph.Settings.Text("direction") is "TB" or "BT";
        int[] thickness = order.Select(row => vertical ? 1 : row.Max(v => model.Width[v])).ToArray(), starts = new int[order.Count];
        for (int i = 1; i < order.Count; i++) starts[i] = starts[i - 1] + thickness[i - 1] + gaps[i - 1];
        return new Geometry(tracks, gaps, offsets, thickness, starts, starts[^1] + thickness[^1], Enumerable.Range(0, model.Layer.Count).Max(v => x[v] + coordinates.Right[v]) + 1);
    }
    static List<int>? ShortestPath(Graph graph, bool[] removed)
    {
        if (graph.Path is not {
        } endpoints) return null;
        var (start, goal) = endpoints;
        int[] parent = Enumerable.Repeat(-1, graph.Nodes.Count).ToArray();
        bool[] visited = new bool[graph.Nodes.Count];
        Queue<int> queue = new();
        visited[start] = true;
        queue.Enqueue(start);
        while (queue.TryDequeue(out int a))
        {
            int[] neighbors = Enumerable.Range(0, graph.Edges.Count).Where(i => !removed[i] && graph.Edges[i].A == a).Select(i => graph.Edges[i].B).Order().ToArray();
            foreach (int b in neighbors) if (!visited[b]) {
                visited[b] = true;
                parent[b] = a;
                queue.Enqueue(b);
            }
        }
        if (!visited[goal]) return null;
        List<int> path = new() {
            goal
        };
        int current = goal;
        while (current != start) {
            current = parent[current];
            path.Add(current);
        }
        path.Reverse();
        return path;
    }
    static Drawing Draw(Graph graph, Model model, Coordinates c, Geometry geo, bool[] reversed, bool[] removed, List<int>? path)
    {
        string direction = graph.Settings.Text("direction");
        bool vertical = direction is "TB" or "BT";
        Canvas canvas = new(geo.Main, geo.Secondary, direction);
        for (int v = 0; v < model.Layer.Count; v++)
        {
            int i = model.Layer[v];
            if (v >= graph.Nodes.Count) for (int j = 0; j < geo.Thickness[i]; j++) canvas.Line(geo.Starts[i] + j, c.X[v], true);
            else if (!vertical && model.Lower[v].Count > 0) for (int j = model.Width[v]; j < geo.Thickness[i]; j++) canvas.Line(geo.Starts[i] + j, c.X[v], true);
        }
        for (int i = 0; i < model.Gaps.Count; i++)
        {
            List<Segment> segments = model.Gaps[i];
            int g0 = geo.Starts[i] + geo.Thickness[i], gap = geo.Gaps[i];
            for (int k = 0; k < segments.Count; k++)
            {
                Segment segment = segments[k];
                int p = c.X[segment.P], q = c.X[segment.Q];
                if (geo.Offsets[i][k] is {
                } offset)
                {
                    for (int j = 0; j < offset; j++) canvas.Line(g0 + j, p, true);
                    canvas.Corner(g0 + offset, p);
                    canvas.Corner(g0 + offset, q);
                    for (int x = Math.Min(p, q) + 1; x < Math.Max(p, q); x++) canvas.Line(g0 + offset, x, false);
                    for (int j = offset + 1; j < gap; j++) canvas.Line(g0 + j, q, true);
                }
                else for (int j = 0; j < gap; j++) canvas.Line(g0 + j, p, true);
            }
        }
        List<List<Cell>> routes = graph.Edges.Select(_ => new List<Cell>()).ToList();
        int[] lengths = new int[graph.Edges.Count], bends = new int[graph.Edges.Count];
        for (int e = 0; e < model.Chains.Count; e++) if (!removed[e])
        {
            List<int> chain = model.Chains[e];
            int a = chain[0], b = chain[^1];
            var upper = (Main: geo.Starts[model.Layer[a]] + (vertical ? 1 : model.Width[a]), Secondary: c.X[a]);
            var lower = (Main: geo.Starts[model.Layer[b]] - 1, Secondary: c.X[b]);
            List<(int Main, int Secondary)> points = new() {
                upper
            };
            for (int j = 1; j < chain.Count; j++)
            {
                int p = chain[j - 1], q = chain[j], i = model.Layer[p];
                int k = model.Gaps[i].FindIndex(s => s.P == p && s.Q == q);
                if (geo.Offsets[i][k] is {
                } offset)
                {
                    int main = geo.Starts[i] + geo.Thickness[i] + offset;
                    points.Add((main, c.X[p]));
                    points.Add((main, c.X[q]));
                    bends[e] += 2;
                }
            }
            points.Add(lower);
            List<Cell> mapped = points.Select(p => canvas.Map(p.Main, p.Secondary)).ToList();
            if (reversed[e]) {
                mapped.Reverse();
                canvas.Arrow(upper.Main, upper.Secondary, true);
            }
            else canvas.Arrow(lower.Main, lower.Secondary, false);
            lengths[e] = 1 + Enumerable.Range(1, mapped.Count - 1).Sum(j => Math.Abs(mapped[j - 1].Row - mapped[j].Row) + Math.Abs(mapped[j - 1].Column - mapped[j].Column));
            routes[e] = mapped;
        }
        HashSet<int> onPath = path?.ToHashSet() ?? new();
        if (path is not null) for (int j = 1; j < path.Count; j++)
        {
            int e = graph.Edges.FindIndex(edge => edge.A == path[j - 1] && edge.B == path[j]);
            for (int k = 1; k < routes[e].Count; k++)
            {
                Cell a = routes[e][k - 1], b = routes[e][k];
                if (a.Row == b.Row) for (int column = Math.Min(a.Column, b.Column); column <= Math.Max(a.Column, b.Column); column++) canvas.Highlight(a.Row, column);
                else for (int row = Math.Min(a.Row, b.Row); row <= Math.Max(a.Row, b.Row); row++) canvas.Highlight(row, a.Column);
            }
        }
        for (int v = 0; v < graph.Nodes.Count; v++)
        {
            int i = model.Layer[v];
            string label = (onPath.Contains(v) ? "{" : "[") + graph.Nodes[v].Label + (onPath.Contains(v) ? "}" : "]");
            Cell cell = vertical ? canvas.Map(geo.Starts[i], c.X[v] - c.Left[v]) : direction == "LR" ? new Cell(c.X[v], geo.Starts[i]) : new Cell(c.X[v], geo.Main - geo.Starts[i] - model.Width[v]);
            canvas.Label(cell.Row, cell.Column, label);
        }
        return new Drawing(canvas, routes, lengths, bends);
    }
    static Processed Process(Graph graph)
    {
        int n = graph.Nodes.Count;
        string Id(int v) => graph.Nodes[v].Id.ToString(CultureInfo.InvariantCulture);
        string EdgeName(int e) => Id(graph.Edges[e].A) + "->" + Id(graph.Edges[e].B);
        Analysis analysis = Analyze(graph);
        List<int> sequence = AcyclicLayering.Sequence(n, graph.Edges);
        int[] position = new int[n];
        for (int i = 0; i < sequence.Count; i++) position[sequence[i]] = i;
        bool[] reversed = graph.Edges.Select(e => position[e.A] > position[e.B]).ToArray();
        List<Edge> dag = graph.Edges.Select((e, i) => reversed[i] ? new Edge(e.B, e.A) : e).ToList();
        bool[,] reachable = Reachability(n, dag);
        bool[] removed = dag.Select((e, i) => graph.Settings.On("reduce") && !reversed[i] && dag.Any(f => f.A == e.A && f.B != e.B && reachable[f.B, e.B])).ToArray();
        List<Edge> drawn = dag.Where((_, i) => !removed[i]).ToList();
        Layering layering = AcyclicLayering.Assign(n, drawn, graph.Settings.Text("layering") == "coffman", graph.Settings.Integer("width"), graph.Settings.On("promotion"));
        Model model = BuildModel(graph, layering.Heights, dag, removed);
        Reduction reduced = ReduceCrossings(graph, model);
        Coordinates c = Coordinates.Assign(n, reduced.Order, model.Layer, model.Upper, model.Lower, model.Width, graph.Settings.Text("direction") is "TB" or "BT", graph.Settings.Integer("node_sep"), graph.Settings.Integer("dummy_sep"));
        Geometry geo = BuildGeometry(graph, model, reduced.Order, c);
        List<int>? path = ShortestPath(graph, removed);
        Drawing drawing = Draw(graph, model, c, geo, reversed, removed, path);
        Canvas canvas = drawing.Canvas;
        int vertices = model.Layer.Count;
        string Name(int v) => v < n ? Id(v) : "d" + (v - n + 1).ToString(CultureInfo.InvariantCulture);
        int[] positions = Crossing.Positions(reduced.Order, vertices), counts = model.Gaps.Select((g, i) => Crossing.Count(g, positions, reduced.Order[i + 1].Count)).ToArray();
        int finalCount = counts.Sum(), brute = model.Gaps.Sum(g => Crossing.Brute(g, positions));
        int[] edgeCrossings = new int[graph.Edges.Count];
        foreach (List<Segment> gap in model.Gaps) for (int i = 0; i < gap.Count; i++) for (int j = i + 1; j < gap.Count; j++) if (Crossing.Crosses(gap[i], gap[j], positions)) {
            edgeCrossings[gap[i].Edge]++;
            edgeCrossings[gap[j].Edge]++;
        }
        string settings = string.Join(" ", Settings.Names.Zip(graph.Settings.Values, (name, value) => name + "=" + value));
        List<string> layout = new() {
            "graph " + graph.Name, "settings " + settings, "acyclic " + string.Join(" ", sequence.Select(Id))
        };
        if (graph.Settings.Text("layering") == "coffman") layout.Add("labels " + string.Join(" ", Enumerable.Range(0, n).Select(v => $"{Id(v)}:{layering.Labels[v]}")));
        foreach (Promotion p in layering.Promotions) layout.Add($"promote {p.Round} {Id(p.Vertex)} {p.Diff}");
        layout.AddRange(reduced.Records);
        for (int i = 0; i < reduced.Order.Count; i++)
        {
            List<int> row = reduced.Order[i];
            int start = geo.Starts[i], end = start + geo.Thickness[i] - 1;
            bool backwards = graph.Settings.Text("direction") is "BT" or "RL";
            int bandLo = backwards ? geo.Main - 1 - end : start, bandHi = backwards ? geo.Main - 1 - start : end;
            int lo = row.Min(v => c.X[v] - c.Left[v]), hi = row.Max(v => c.X[v] + c.Right[v]);
            layout.Add($"layer {i} band {bandLo} {bandHi} extent {lo} {hi} : " + string.Join(" ", row.Select(v => $"{Name(v)}@{c.X[v]}")));
        }
        for (int i = 0; i < model.Gaps.Count; i++) layout.Add($"between {i} {i + 1} segments {model.Gaps[i].Count} crossings {counts[i]} tracks {geo.Tracks[i]} gap {geo.Gaps[i]}");
        string[] variants = ["ul", "ur", "dl", "dr"];
        layout.Add($"bk conflicts {c.Conflicts} " + string.Join(" ", Enumerable.Range(0, 4).Select(i => $"{variants[i]}={c.Blocks[i]}/{c.Widths[i]}")) + " smallest " + variants[c.Smallest]);
        foreach (List<int> row in reduced.Order) foreach (int v in row) layout.Add($"vertex {Name(v)} layer {model.Layer[v]} pos {positions[v]} ul {c.Aligned[0][v]} ur {c.Aligned[1][v]} dl {c.Aligned[2][v]} dr {c.Aligned[3][v]} x {c.X[v]}");
        for (int e = 0; e < graph.Edges.Count; e++)
        {
            var (a, b) = graph.Edges[e];
            if (removed[e]) layout.Add($"edge {Id(a)} {Id(b)} transitive");
            else
            {
                List<int> chain = (reversed[e] ? model.Chains[e].AsEnumerable().Reverse() : model.Chains[e]).ToList();
                string pathText = string.Join(" ", chain.Select(v => c.X[v])), route = string.Join(" ", drawing.Routes[e].Select(p => $"{p.Row},{p.Column}"));
                layout.Add($"edge {Id(a)} {Id(b)}{(reversed[e] ? " reversed" : "")} span {chain.Count - 1} crossings {edgeCrossings[e]} bends {drawing.Bends[e]} path {pathText} route {route}");
            }
        }
        layout.Add("end");
        List<string> stats = new() {
            "graph " + graph.Name, $"nodes {n} edges {graph.Edges.Count} self_loops {graph.Loops} duplicates {graph.Duplicates}", $"sources {analysis.Sources} sinks {analysis.Sinks} isolated {analysis.Isolated} components {analysis.Components}"
        };
        foreach (List<int> component in analysis.Scc) stats.Add("scc " + string.Join(" ", component.Select(Id)));
        foreach (var (label, flags) in new[] {
            ("reversed", reversed), ("transitive", removed)
        })
        {
            List<string> names = Enumerable.Range(0, graph.Edges.Count).Where(i => flags[i]).Select(EdgeName).ToList();
            stats.Add($"{label} {names.Count}" + (names.Count == 0 ? "" : " " + string.Join(" ", names)));
        }
        stats.Add($"layers {reduced.Order.Count} max_nodes {reduced.Order.Max(row => row.Count(v => v < n))} max_vertices {reduced.Order.Max(row => row.Count)}");
        stats.Add(graph.Settings.On("promotion") ? $"promotion rounds {layering.Rounds} accepted {layering.Promotions.Count} dummies_before {layering.Before}" : "promotion off");
        var spans = model.Chains.Where(chain => chain.Count > 0).GroupBy(chain => chain.Count - 1).OrderBy(g => g.Key).ToList();
        int spanTotal = model.Chains.Where(chain => chain.Count > 0).Sum(chain => chain.Count - 1);
        stats.Add($"dummies {vertices - n} span_total {spanTotal} span_max {(spans.Count == 0 ? 0 : spans.Max(g => g.Key))}");
        stats.Add("spans " + (spans.Count == 0 ? "none" : string.Join(" ", spans.Select(g => $"{g.Key}:{g.Count()}"))));
        Order longEdges = model.Chains.Where(chain => chain.Count >= 3).ToList();
        int vertical = longEdges.Count(chain => chain.Skip(1).Take(chain.Count - 2).All(v => c.X[v] == c.X[chain[1]]));
        stats.Add($"long_edges {longEdges.Count} vertical {vertical}");
        stats.Add($"crossings initial {reduced.Initial} swept {reduced.Swept} best_run {reduced.Run} best_sweep {reduced.Sweep} final {finalCount} brute {brute}");
        List<Segment> segments = model.Gaps.SelectMany(g => g).ToList();
        int straight = segments.Count(s => c.X[s.P] == c.X[s.Q]), offset = segments.Sum(s => Math.Abs(c.X[s.P] - c.X[s.Q]));
        stats.Add($"segments {segments.Count} straight {straight} bent {segments.Count - straight} offset {offset}");
        int[] longest = Enumerable.Range(0, graph.Edges.Count).Where(i => !removed[i]).OrderByDescending(i => drawing.Lengths[i]).ThenBy(i => i).Take(1).ToArray();
        stats.Add($"routes length {drawing.Lengths.Sum()} bends {drawing.Bends.Sum()}" + (longest.Length == 0 ? "" : $" longest {EdgeName(longest[0])} {drawing.Lengths[longest[0]]}"));
        stats.Add($"canvas width {canvas.Columns} height {canvas.Rows} crossing_cells {canvas.Crossings()}");
        if (graph.Path is {
        } endpoints) stats.Add(path is null ? $"path {Id(endpoints.A)} {Id(endpoints.B)} none" : $"path {Id(endpoints.A)} {Id(endpoints.B)} hops {path.Count - 1} : " + string.Join(" ", path.Select(Id)));
        stats.Add("end");
        List<string> drawings = new() {
            $"graph {graph.Name} {canvas.Columns}x{canvas.Rows}"
        };
        drawings.AddRange(canvas.Report());
        return new Processed(layout, stats, reduced.Csv, drawings, new[] {
            n, graph.Edges.Count, vertices - n, reduced.Initial, finalCount
        });
    }
    static void Write(string name, List<string> lines)
    {
        Directory.CreateDirectory("output");
        File.WriteAllText("output/" + name, lines.Count == 0 ? "" : string.Join("\n", lines) + "\n", new UTF8Encoding(false));
    }
    static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        CultureInfo.CurrentUICulture = CultureInfo.InvariantCulture;
        List<Graph> graphs = GraphIO.Read();
        List<string> layout = new(), stats = new(), drawings = new(), csv = new() {
            "graph,run,sweep,crossings"
        };
        int[] totals = new int[5];
        int errors = 0;
        foreach (Graph graph in graphs)
        {
            if (drawings.Count > 0) drawings.Add("");
            if (graph.Error is {
            } error)
            {
                errors++;
                string[] block = ["graph " + graph.Name, $"error {error.Kind} line {error.Line}", "end"];
                layout.AddRange(block);
                stats.AddRange(block);
                drawings.Add($"graph {graph.Name} error {error.Kind}");
            }
            else
            {
                Processed output = Process(graph);
                layout.AddRange(output.Layout);
                stats.AddRange(output.Stats);
                csv.AddRange(output.Csv);
                drawings.AddRange(output.Drawings);
                for (int i = 0; i < 5; i++) totals[i] += output.Totals[i];
            }
        }
        stats.Add($"summary graphs {graphs.Count} laid_out {graphs.Count - errors} errors {errors} nodes {totals[0]} edges {totals[1]} dummies {totals[2]} crossings_initial {totals[3]} crossings_final {totals[4]}");
        Write("layout.txt", layout);
        Write("stats.txt", stats);
        Write("crossings.csv", csv);
        Write("drawings.txt", drawings);
    }
}
