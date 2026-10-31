using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

class Problem(string message) : Exception("ERROR " + message) { }

class Edge(int u, int v, int capacity, int cost)
{
    public int U = u, V = v, Capacity = capacity, Cost = cost, Lower, Flow;
    public Edge Copy() => new(U, V, Capacity, Cost) { Lower = this.Lower, Flow = this.Flow };
}

record Augmentation(List<int> Path, int Amount, int Stage, int UnitCost);

record Piece(bool Cycle, int Start, List<int> Path, int Amount);

class Search(int n)
{
    public int[] Level = Enumerable.Repeat(-1, n).ToArray(), Parent = new int[n];
}

class Graph
{
    public List<string> Names = [];
    public List<Edge> Edges = [];

    public Graph Copy(bool keepFlow)
    {
        Graph g = new();
        g.Names.AddRange(Names);
        foreach (Edge e in Edges)
        {
            Edge f = e.Copy();
            if (!keepFlow) f.Flow = 0;
            g.Edges.Add(f);
        }
        return g;
    }

    public int Add(int u, int v, int capacity, int cost)
    {
        Edges.Add(new(u, v, capacity, cost));
        return Edges.Count;
    }
    public Edge EdgeOf(int arc) => Edges[Math.Abs(arc) - 1];
    public int From(int arc) => arc > 0 ? EdgeOf(arc).U : EdgeOf(arc).V;
    public int To(int arc) => arc > 0 ? EdgeOf(arc).V : EdgeOf(arc).U;
    public int Residual(int arc) => arc > 0 ? EdgeOf(arc).Capacity - EdgeOf(arc).Flow : EdgeOf(arc).Flow;
    public int Cost(int arc) => arc > 0 ? EdgeOf(arc).Cost : -EdgeOf(arc).Cost;

    public List<int> Arcs(int u)
    {
        List<int> result = [];
        for (int i = 0; i < Edges.Count; i++) if (Edges[i].U == u) result.Add(i + 1);
        for (int i = 0; i < Edges.Count; i++) if (Edges[i].V == u) result.Add(-i - 1);
        return result;
    }

    public int[] Balances()
    {
        int[] result = new int[Names.Count];
        foreach (Edge e in Edges)
        {
            result[e.U] += e.Flow;
            result[e.V] -= e.Flow;
        }
        return result;
    }
    public int TotalCost() => Edges.Sum(e => e.Flow * e.Cost);
    public int Bottleneck(List<int> path) => path.Min(Residual);

    public void Push(List<int> path, int amount)
    {
        foreach (int a in path) EdgeOf(a).Flow += a > 0 ? amount : -amount;
    }
    public string Notation(int start, List<int> path) => Names[start] + string.Concat(path.Select(a => $" {(a > 0 ? "+" : "-")}{Math.Abs(a)} {Names[To(a)]}"));

    public Search Bfs(int source, int threshold)
    {
        Search search = new(Names.Count);
        Queue<int> queue = new();
        search.Level[source] = 0;
        queue.Enqueue(source);
        while (queue.Count != 0)
        {
            int u = queue.Dequeue();
            foreach (int a in Arcs(u))
            {
                int v = To(a);
                if (Residual(a) >= threshold && search.Level[v] < 0)
                {
                    search.Level[v] = search.Level[u] + 1;
                    search.Parent[v] = a;
                    queue.Enqueue(v);
                }
            }
        }
        return search;
    }

    public List<int> Path(int source, int target, int[] parent)
    {
        List<int> result = [];
        for (int v = target; v != source; v = From(parent[v])) result.Add(parent[v]);
        result.Reverse();
        return result;
    }

    public List<Augmentation> Maximum(int source, int target, string method)
    {
        List<Augmentation> result = [];
        if (method == "DINIC")
        {
            int phase = 0;
            while (true)
            {
                Search search = Bfs(source, 1);
                if (search.Level[target] < 0) break;
                phase++;
                List<int>[] lists = Enumerable.Range(0, Names.Count).Select(Arcs).ToArray();
                int[] pointer = new int[Names.Count];
                List<int> path = [];
                int u = source;
                while (true)
                {
                    if (u == target)
                    {
                        int amount = Bottleneck(path);
                        result.Add(new([.. path], amount, phase, 0));
                        Push(path, amount);
                        path.Clear();
                        u = source;
                    }
                    else if (pointer[u] == lists[u].Count)
                    {
                        if (u == source) break;
                        u = From(path[^1]);
                        path.RemoveAt(path.Count - 1);
                        pointer[u]++;
                    }
                    else
                    {
                        int a = lists[u][pointer[u]], v = To(a);
                        if (Residual(a) > 0 && search.Level[v] == search.Level[u] + 1)
                        {
                            path.Add(a);
                            u = v;
                        }
                        else pointer[u]++;
                    }
                }
            }
            return result;
        }
        int threshold = 1;
        if (method == "SCALING")
        {
            int largest = Edges.Select(e => e.Capacity).DefaultIfEmpty().Max();
            while (threshold <= largest / 2) threshold *= 2;
        }
        do
        {
            while (true)
            {
                Search search = Bfs(source, threshold);
                if (search.Level[target] < 0) break;
                List<int> path = Path(source, target, search.Parent);
                int amount = Bottleneck(path);
                Push(path, amount);
                result.Add(new(path, amount, threshold, 0));
                if (method == "AUGMENT") return result;
            }
            threshold /= 2;
        }
        while (threshold > 0);
        return result;
    }

    public bool NegativeCycle(bool subtractLower)
    {
        int[] distance = new int[Names.Count];
        for (int pass = 0; pass < Names.Count; pass++)
        {
            bool changed = false;
            foreach (Edge e in Edges) if (e.Capacity - (subtractLower ? e.Lower : 0) > 0 && distance[e.V] > distance[e.U] + e.Cost)
            {
                distance[e.V] = distance[e.U] + e.Cost;
                changed = true;
            }
            if (!changed) return false;
        }
        return Names.Count != 0;
    }

    public List<Augmentation> Cheapest(int source, int target, int wanted)
    {
        List<Augmentation> result = [];
        int pushed = 0;
        while (wanted < 0 || pushed < wanted)
        {
            List<int> usable = [];
            for (int i = 1; i <= Edges.Count; i++) if (Residual(i) > 0) usable.Add(i);
            for (int i = 1; i <= Edges.Count; i++) if (Residual(-i) > 0) usable.Add(-i);
            int?[] distance = new int?[Names.Count];
            int[] parent = new int[Names.Count];
            distance[source] = 0;
            bool changed;
            do
            {
                changed = false;
                foreach (int a in usable)
                {
                    int u = From(a), v = To(a);
                    if (distance[u].HasValue && (!distance[v].HasValue || distance[u]!.Value + Cost(a) < distance[v]!.Value))
                    {
                        distance[v] = distance[u]!.Value + Cost(a);
                        parent[v] = a;
                        changed = true;
                    }
                }
            }
            while (changed);
            if (!distance[target].HasValue) break;
            List<int> path = Path(source, target, parent);
            int amount = Bottleneck(path);
            if (wanted >= 0) amount = Math.Min(amount, wanted - pushed);
            Push(path, amount);
            pushed += amount;
            result.Add(new(path, amount, 0, distance[target]!.Value));
        }
        return result;
    }

    public List<Piece> Decompose()
    {
        int[] remaining = Edges.Select(e => e.Flow).ToArray(), balance = Balances();
        List<Piece> result = [];
        while (remaining.Any(x => x > 0))
        {
            int start = Array.FindIndex(balance, x => x > 0);
            if (start < 0) start = Edges[Array.FindIndex(remaining, x => x > 0)].U;
            List<int> vertices = [start], path = [];
            while (true)
            {
                int u = vertices[^1], i = 0;
                while (Edges[i].U != u || remaining[i] == 0) i++;
                int v = Edges[i].V;
                path.Add(i + 1);
                int repeated = vertices.IndexOf(v);
                if (repeated >= 0)
                {
                    List<int> cycle = path.GetRange(repeated, path.Count - repeated);
                    int amount = cycle.Min(a => remaining[a - 1]);
                    foreach (int a in cycle) remaining[a - 1] -= amount;
                    result.Add(new(true, v, cycle, amount));
                    break;
                }
                vertices.Add(v);
                if (balance[v] < 0)
                {
                    int amount = Math.Min(Math.Min(balance[start], -balance[v]), path.Min(a => remaining[a - 1]));
                    foreach (int a in path) remaining[a - 1] -= amount;
                    balance[start] -= amount;
                    balance[v] += amount;
                    result.Add(new(false, start, path, amount));
                    break;
                }
            }
        }
        return result;
    }
}

class Program
{
    Graph network = new();
    readonly List<int> demand = [];
    int owner, source, target;

    static void Fail(string message) => throw new Problem(message);

    int Node(string name)
    {
        int index = network.Names.IndexOf(name);
        if (index < 0) Fail("UNKNOWN NODE " + name);
        return index;
    }

    Edge CheckedEdge(string text)
    {
        int number = int.Parse(text);
        if (number < 1 || number > network.Edges.Count) Fail("UNKNOWN EDGE " + text);
        return network.Edges[number - 1];
    }
    (int, int) Endpoints(string s, string t)
    {
        int u = Node(s), v = Node(t);
        if (u == v) Fail("SAME NODE");
        return (u, v);
    }

    int Start(int s, int t)
    {
        if (owner != 1 || source != s || target != t) foreach (Edge e in network.Edges) e.Flow = 0;
        owner = 1;
        source = s;
        target = t;
        return network.Balances()[s];
    }
    List<string> Flows() => network.Edges.Select((e, i) => $"FLOW {i + 1} {network.Names[e.U]} {network.Names[e.V]} {e.Flow}/{e.Capacity}").ToList();

    void CopyFlows(Graph g, bool lower)
    {
        for (int i = 0; i < network.Edges.Count; i++) network.Edges[i].Flow = g.Edges[i].Flow + (lower ? network.Edges[i].Lower : 0);
    }

    static string Join(List<string> names) => names.Count == 0 ? "-" : string.Join(",", names);

    List<string> Command(string line)
    {
        string[] w = line.Split(' ');
        string c = w[0];
        List<string> output = [];
        switch (c)
        {
            case "NODE":
            {
                HashSet<string> seen = new(network.Names, StringComparer.Ordinal);
                foreach (string name in w.Skip(1)) if (!seen.Add(name)) Fail("DUPLICATE NODE " + name);
                if (network.Names.Count + w.Length - 1 > 20) Fail("TOO MANY NODES");
                foreach (string name in w.Skip(1))
                {
                    network.Names.Add(name);
                    demand.Add(0);
                }
                output.Add($"NODE added={w.Length - 1} total={network.Names.Count}");
                break;
            }
            case "EDGE":
            {
                int u = Node(w[1]), v = Node(w[2]);
                if (u == v) Fail("SELF LOOP");
                if (network.Edges.Count == 60) Fail("TOO MANY EDGES");
                int capacity = int.Parse(w[3]), cost = w.Length == 5 ? int.Parse(w[4]) : 0;
                int number = network.Add(u, v, capacity, cost);
                output.Add($"EDGE {number} {w[1]} {w[2]} cap={capacity} cost={cost}");
                break;
            }
            case "LOWER":
            case "CAP":
            case "COST":
            {
                Edge e = CheckedEdge(w[1]);
                int value = int.Parse(w[2]);
                if (c == "LOWER")
                {
                    if (value > e.Capacity) Fail("BAD BOUND");
                    e.Lower = value;
                    output.Add($"LOWER {w[1]} low={value} cap={e.Capacity}");
                }
                else if (c == "CAP")
                {
                    if (value < e.Lower) Fail("BAD BOUND");
                    if (value < e.Flow) Fail("BELOW FLOW");
                    e.Capacity = value;
                    output.Add($"CAP {w[1]} low={e.Lower} cap={value}");
                }
                else
                {
                    e.Cost = value;
                    output.Add($"COST {w[1]} cost={value}");
                }
                break;
            }
            case "DEMAND":
            {
                int u = Node(w[1]), value = int.Parse(w[2]);
                demand[u] = value;
                output.Add($"DEMAND {w[1]} {value} total={demand.Sum()}");
                break;
            }
            case "RESET":
            {
                int count = network.Edges.Count(e => e.Flow != 0);
                foreach (Edge e in network.Edges) e.Flow = 0;
                owner = 0;
                output.Add($"RESET edges={count}");
                break;
            }
            case "CLEAR":
                output.Add($"CLEAR nodes={network.Names.Count} edges={network.Edges.Count}");
                network = new();
                demand.Clear();
                owner = 0;
                break;
            case "SHOW":
            {
                output.Add($"NETWORK nodes={network.Names.Count} edges={network.Edges.Count}");
                output.Add(owner == 0 ? "STATE none" : owner == 2 ? $"STATE circulation cost={network.TotalCost()}" : $"STATE flow {network.Names[source]} {network.Names[target]} value={network.Balances()[source]} cost={network.TotalCost()}");
                for (int u = 0; u < network.Names.Count; u++) output.Add($"NODE {network.Names[u]} demand={demand[u]} out={network.Edges.Where(e => e.U == u).Sum(e => e.Flow)} in={network.Edges.Where(e => e.V == u).Sum(e => e.Flow)}");
                output.AddRange(network.Edges.Select((e, i) => $"EDGE {i + 1} {network.Names[e.U]} {network.Names[e.V]} cap={e.Capacity} cost={e.Cost} low={e.Lower} flow={e.Flow}"));
                break;
            }
            case "AUGMENT":
            case "MAXFLOW":
            case "DINIC":
            case "SCALING":
            case "MINCUT":
            {
                (int s, int t) = Endpoints(w[1], w[2]);
                int initial = Start(s, t);
                List<Augmentation> paths = network.Maximum(s, t, c);
                string heading = $"{c} {w[1]} {w[2]} value={network.Balances()[s]}";
                if (c == "AUGMENT") output.Add(heading + (paths.Count == 0 ? " none" : $" amount={paths[0].Amount} {network.Notation(s, paths[0].Path)}"));
                else if (c == "MINCUT")
                {
                    Search search = network.Bfs(s, 1);
                    List<int> cut = Enumerable.Range(0, network.Edges.Count).Where(i => search.Level[network.Edges[i].U] >= 0 && search.Level[network.Edges[i].V] < 0).ToList();
                    output.Add($"{heading} edges={cut.Count}");
                    foreach (bool reachable in new[] { true, false }) output.Add((reachable ? "SOURCE" : "SINK") + string.Concat(Enumerable.Range(0, network.Names.Count).Where(u => (search.Level[u] >= 0) == reachable).Select(u => " " + network.Names[u])));
                    foreach (int i in cut)
                    {
                        Edge e = network.Edges[i];
                        output.Add($"CUT {i + 1} {network.Names[e.U]} {network.Names[e.V]} {e.Capacity}");
                    }
                }
                else
                {
                    output.Add($"{heading} start={initial}" + (c == "DINIC" ? $" phases={(paths.Count == 0 ? 0 : paths[^1].Stage)}" : "") + $" paths={paths.Count}");
                    for (int i = 0; i < paths.Count; i++)
                    {
                        Augmentation a = paths[i];
                        output.Add($"AUG {i + 1}" + (c == "DINIC" ? $" phase={a.Stage}" : c == "SCALING" ? $" delta={a.Stage}" : "") + $" amount={a.Amount} {network.Notation(s, a.Path)}");
                    }
                    output.AddRange(Flows());
                }
                break;
            }
            case "SENSITIVITY":
            {
                (int s, int t) = Endpoints(w[1], w[2]);
                Graph g = network.Copy(false);
                g.Maximum(s, t, "MAXFLOW");
                int value = g.Balances()[s], upCount = 0, downCount = 0;
                List<string> critical = [];
                for (int i = 0; i < network.Edges.Count; i++)
                {
                    g = network.Copy(false);
                    g.Edges[i].Capacity++;
                    g.Maximum(s, t, "MAXFLOW");
                    bool up = g.Balances()[s] > value, down = false;
                    if (network.Edges[i].Capacity > 0)
                    {
                        g = network.Copy(false);
                        g.Edges[i].Capacity--;
                        g.Maximum(s, t, "MAXFLOW");
                        down = g.Balances()[s] < value;
                    }
                    if (up) upCount++;
                    if (down) downCount++;
                    Edge e = network.Edges[i];
                    if (up || down) critical.Add($"CRITICAL {i + 1} {network.Names[e.U]} {network.Names[e.V]} up={(up ? "yes" : "no")} down={(down ? "yes" : "no")}");
                }
                output.Add($"SENSITIVITY {w[1]} {w[2]} value={value} up={upCount} down={downCount}");
                output.AddRange(critical);
                break;
            }
            case "MINCOST":
            {
                (int s, int t) = Endpoints(w[1], w[2]);
                if (network.NegativeCycle(false)) Fail("NEGATIVE CYCLE");
                int wanted = w[3] == "MAX" ? -1 : int.Parse(w[3]);
                Graph g = network.Copy(false);
                List<Augmentation> paths = g.Cheapest(s, t, wanted);
                int amount = g.Balances()[s];
                string heading = $"MINCOST {w[1]} {w[2]} k={w[3]}";
                if (wanted >= 0 && amount < wanted) output.Add($"{heading} infeasible max={amount}");
                else
                {
                    CopyFlows(g, false);
                    owner = 1;
                    source = s;
                    target = t;
                    output.Add($"{heading} flow={amount} cost={g.TotalCost()}");
                    for (int i = 0; i < paths.Count; i++)
                    {
                        Augmentation a = paths[i];
                        output.Add($"AUG {i + 1} amount={a.Amount} cost={a.UnitCost} {g.Notation(s, a.Path)}");
                    }
                    output.AddRange(Flows());
                }
                break;
            }
            case "DISJOINT":
            {
                (int s, int t) = Endpoints(w[1], w[2]);
                int n = network.Names.Count;
                Graph g = new();
                g.Names.AddRange(network.Names);
                int[] exit = new int[n];
                for (int u = 0; u < n; u++)
                {
                    exit[u] = u;
                    if (w[3] == "VERTEX" && u != s && u != t)
                    {
                        exit[u] = g.Names.Count;
                        g.Names.Add(network.Names[u]);
                    }
                }
                foreach (Edge e in network.Edges) g.Add(exit[e.U], e.V, e.Capacity == 0 ? 0 : 1, 0);
                for (int u = 0; u < n; u++) if (exit[u] != u) g.Add(u, exit[u], 1, 0);
                g.Maximum(s, t, "MAXFLOW");
                List<Piece> pieces = g.Decompose().Where(p => !p.Cycle).ToList();
                output.Add($"DISJOINT {w[1]} {w[2]} {w[3]} count={pieces.Count}");
                for (int i = 0; i < pieces.Count; i++) output.Add($"PATH {i + 1} {w[1]}" + string.Concat(pieces[i].Path.Where(a => a <= network.Edges.Count).Select(a => $" +{a} {network.Names[network.Edges[a - 1].V]}")));
                break;
            }
            case "DECOMPOSE":
            {
                List<Piece> pieces = network.Decompose();
                int cycles = pieces.Count(p => p.Cycle), pathNumber = 0, cycleNumber = 0;
                output.Add($"DECOMPOSE paths={pieces.Count - cycles} cycles={cycles}");
                foreach (Piece p in pieces) output.Add((p.Cycle ? $"CYCLE {++cycleNumber}" : $"PATH {++pathNumber}") + $" amount={p.Amount} {network.Notation(p.Start, p.Path)}");
                break;
            }
            case "VERIFY":
            {
                List<string> violations = [];
                for (int i = 0; i < network.Edges.Count; i++)
                {
                    Edge e = network.Edges[i];
                    if (e.Flow < e.Lower) violations.Add($"LOW {i + 1} flow={e.Flow} low={e.Lower}");
                }
                int[] balance = network.Balances();
                for (int u = 0; u < network.Names.Count; u++) if (owner != 1 || (u != source && u != target))
                {
                    int need = owner == 1 ? 0 : demand[u];
                    if (-balance[u] != need) violations.Add($"BALANCE {network.Names[u]} net={-balance[u]} need={need}");
                }
                output.Add(violations.Count == 0 ? "VERIFY ok" : $"VERIFY violations={violations.Count}");
                output.AddRange(violations);
                break;
            }
            case "CIRCULATION":
            {
                bool cheapest = w[1] == "MINCOST";
                if (cheapest && network.NegativeCycle(true)) Fail("NEGATIVE CYCLE");
                int sum = demand.Sum();
                if (sum != 0)
                {
                    output.Add($"CIRCULATION infeasible unbalanced={sum}");
                    break;
                }
                Graph g = network.Copy(false);
                int n = g.Names.Count, required = 0;
                g.Names.AddRange(["source", "sink"]);
                int[] remaining = demand.ToArray();
                foreach (Edge e in g.Edges)
                {
                    remaining[e.U] += e.Lower;
                    remaining[e.V] -= e.Lower;
                    e.Capacity -= e.Lower;
                }
                for (int u = 0; u < n; u++) if (remaining[u] < 0) g.Add(n, u, -remaining[u], 0);
                for (int u = 0; u < n; u++) if (remaining[u] > 0)
                {
                    g.Add(u, n + 1, remaining[u], 0);
                    required += remaining[u];
                }
                if (cheapest) g.Cheapest(n, n + 1, -1);
                else g.Maximum(n, n + 1, "MAXFLOW");
                int achieved = -g.Balances()[n + 1];
                if (achieved < required)
                {
                    output.Add($"CIRCULATION infeasible required={required} achieved={achieved}");
                    Search search = g.Bfs(n, 1);
                    output.Add("CUT" + string.Concat(Enumerable.Range(0, n).Where(u => search.Level[u] >= 0).Select(u => " " + network.Names[u])));
                }
                else
                {
                    CopyFlows(g, true);
                    owner = 2;
                    output.Add($"CIRCULATION feasible required={required} cost={network.TotalCost()}");
                    output.AddRange(Flows());
                }
                break;
            }
            case "MATCH":
                output.AddRange(Matching(w));
                break;
            case "ASSIGN":
                output.AddRange(Assignment(w));
                break;
        }
        return output;
    }

    static List<string> Matching(string[] w)
    {
        List<string> left = [.. w[1].Split(',')], right = [.. w[2].Split(',')];
        HashSet<string> seen = new(StringComparer.Ordinal);
        foreach (string name in left) if (!seen.Add(name)) Fail("DUPLICATE VERTEX " + name);
        foreach (string name in right) if (!seen.Add(name)) Fail("DUPLICATE VERTEX " + name);
        List<(int U, int V)> pairs = [];
        HashSet<string> pairSeen = new(StringComparer.Ordinal);
        if (w[3] != "-") foreach (string pair in w[3].Split(','))
        {
            string[] p = pair.Split('-');
            int u = left.IndexOf(p[0]), v = right.IndexOf(p[1]);
            if (u < 0) Fail("UNKNOWN VERTEX " + p[0]);
            if (v < 0) Fail("UNKNOWN VERTEX " + p[1]);
            if (!pairSeen.Add(pair)) Fail("DUPLICATE PAIR " + pair);
            pairs.Add((u, v));
        }
        int[] a = Enumerable.Repeat(-1, left.Count).ToArray(), b = Enumerable.Repeat(-1, right.Count).ToArray();
        bool Visit(int u, bool[] examined)
        {
            foreach ((int x, int v) in pairs) if (x == u && !examined[v])
            {
                examined[v] = true;
                if (b[v] < 0 || Visit(b[v], examined))
                {
                    b[v] = u;
                    a[u] = v;
                    return true;
                }
            }
            return false;
        }
        for (int u = 0; u < a.Length; u++) Visit(u, new bool[b.Length]);
        bool[] za = new bool[a.Length], zb = new bool[b.Length];
        Queue<int> queue = new();
        List<string> freeA = [], freeB = [], cover = [], hallA = [], hallB = [];
        for (int u = 0; u < a.Length; u++) if (a[u] < 0)
        {
            za[u] = true;
            queue.Enqueue(u);
            freeA.Add(left[u]);
        }
        while (queue.Count > 0)
        {
            int u = queue.Dequeue();
            foreach ((int x, int v) in pairs) if (x == u && a[u] != v && !zb[v])
            {
                zb[v] = true;
                if (b[v] >= 0 && !za[b[v]])
                {
                    za[b[v]] = true;
                    queue.Enqueue(b[v]);
                }
            }
        }
        List<string> output = [$"MATCH size={a.Length - freeA.Count} left={a.Length} right={b.Length}"];
        for (int u = 0; u < a.Length; u++)
        {
            if (a[u] >= 0) output.Add($"PAIR {left[u]} {right[a[u]]}");
            if (za[u]) hallA.Add(left[u]);
            else cover.Add(left[u]);
        }
        for (int v = 0; v < b.Length; v++)
        {
            if (b[v] < 0) freeB.Add(right[v]);
            if (zb[v])
            {
                cover.Add(right[v]);
                hallB.Add(right[v]);
            }
        }
        output.Add($"FREE {Join(freeA)} {Join(freeB)}");
        output.Add($"COVER size={cover.Count}" + (cover.Count == 0 ? "" : " " + string.Join(" ", cover)));
        if (freeA.Count != 0) output.Add($"HALL {Join(hallA)} {Join(hallB)}");
        return output;
    }

    static List<string> Assignment(string[] w)
    {
        int n = int.Parse(w[2]);
        if (n < 1 || n > 8) Fail("BAD SIZE");
        if (w.Length - 3 != n * n) Fail("BAD LENGTH");
        int?[,] values = new int?[n, n];
        for (int i = 0; i < n * n; i++) if (w[i + 3] != "x") values[i / n, i % n] = int.Parse(w[i + 3]);
        int best = 0, count = 0;
        int[] chosen = [], current = new int[n];
        void Visit(int row, int used, int sum)
        {
            if (row == n)
            {
                if (count == 0 || (w[1] == "MIN" ? sum < best : sum > best))
                {
                    best = sum;
                    count = 1;
                    chosen = (int[])current.Clone();
                }
                else if (sum == best) count++;
                return;
            }
            for (int col = 0; col < n; col++) if ((used & (1 << col)) == 0 && values[row, col].HasValue)
            {
                current[row] = col;
                Visit(row + 1, used | (1 << col), sum + values[row, col]!.Value);
            }
        }
        Visit(0, 0, 0);
        string heading = $"ASSIGN {w[1]} n={n}";
        List<string> output = [];
        if (count == 0) output.Add(heading + " infeasible");
        else
        {
            output.Add($"{heading} total={best} optimal={count}");
            for (int row = 0; row < n; row++) output.Add($"MATE {row + 1} {chosen[row] + 1} {values[row, chosen[row]]}");
        }
        return output;
    }

    static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Program solver = new();
        int n = int.Parse(Console.ReadLine()!);
        for (int i = 0; i < n; i++)
        {
            try
            {
                foreach (string line in solver.Command(Console.ReadLine()!)) Console.WriteLine(line);
            }
            catch (Problem e)
            {
                Console.WriteLine(e.Message);
            }
        }
    }
}
