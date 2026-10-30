sealed record Crossing(Point Point, int Ar, int Ae, int Br, int Be, Fraction T, Fraction U);
sealed record Node(Point Point, int? Crossing = null, bool Enter = false);

sealed class Graph
{
    readonly List<List<Node>>[] nodes = [new(), new()];
    readonly (int Ring, int Index)[][] locations;
    readonly List<int> order = new();
    public List<(Point Point, bool Enter)> Ordered { get; } = new();
    public int Na { get; }
    public int Nb { get; }
    public Graph(Rings a, Rings b)
    {
        Na = a.Count(r => RingOps.Interior(r[0], b));
        Nb = b.Count(r => RingOps.Interior(r[0], a));
        List<Crossing> crossings = new();
        for (int ar = 0; ar < a.Count; ar++) for (int ae = 0; ae < a[ar].Count; ae++)
            for (int br = 0; br < b.Count; br++) for (int be = 0; be < b[br].Count; be++)
            {
                var found = Intersections.Crossing(a[ar][ae], a[ar][(ae + 1) % a[ar].Count], b[br][be], b[br][(be + 1) % b[br].Count]);
                if (found is { } c) crossings.Add(new Crossing(c.Point, ar, ae, br, be, c.T, c.U));
            }
        locations = Enumerable.Range(0, crossings.Count).Select(_ => new (int, int)[2]).ToArray();
        for (int side = 0; side < 2; side++)
        {
            Rings p = side == 0 ? a : b, q = side == 0 ? b : a;
            for (int ri = 0; ri < p.Count; ri++)
            {
                Ring ring = p[ri];
                List<Node> list = new();
                bool inside = RingOps.Interior(ring[0], q);
                for (int edge = 0; edge < ring.Count; edge++)
                {
                    list.Add(new Node(ring[edge]));
                    int r = ri, e = edge, s = side;
                    IEnumerable<int> on = Enumerable.Range(0, crossings.Count).Where(i => s == 0 ? crossings[i].Ar == r && crossings[i].Ae == e : crossings[i].Br == r && crossings[i].Be == e).OrderBy(i => s == 0 ? crossings[i].T : crossings[i].U);
                    foreach (int id in on)
                    {
                        locations[id][side] = (ri, list.Count);
                        list.Add(new Node(crossings[id].Point, id, !inside));
                        if (side == 0) { order.Add(id); Ordered.Add((crossings[id].Point, !inside)); }
                        inside = !inside;
                    }
                }
                nodes[side].Add(list);
            }
        }
    }
    public Region Result(string kind)
    {
        bool[] inverted = kind == "UNION" ? [true, true] : kind == "DIFFERENCE" ? [true, false] : [false, false];
        bool[] visited = new bool[locations.Length];
        Rings rings = new();
        foreach (int start in order) if (!visited[start])
        {
            int side = 0, id = start;
            Ring points = new();
            while (true)
            {
                var (ri, index) = locations[id][side];
                List<Node> list = nodes[side][ri];
                Node node = list[index];
                visited[id] = true;
                points.Add(node.Point);
                bool forward = node.Enter != inverted[side];
                int next = index;
                do
                {
                    next = forward ? (next + 1) % list.Count : (next + list.Count - 1) % list.Count;
                    if (list[next].Crossing is null) points.Add(list[next].Point);
                } while (list[next].Crossing is null);
                int found = list[next].Crossing!.Value;
                if (found == start) break;
                id = found;
                side = 1 - side;
            }
            rings.Add(points);
        }
        for (int side = 0; side < 2; side++)
        {
            Rings other = nodes[1 - side].Select(l => l.Select(n => n.Point).ToList()).ToList();
            foreach (List<Node> list in nodes[side]) if (list.All(n => n.Crossing is null) && RingOps.Interior(list[0].Point, other) != inverted[side]) rings.Add(list.Select(n => n.Point).ToList());
        }
        return RingOps.Assemble(rings);
    }
}
