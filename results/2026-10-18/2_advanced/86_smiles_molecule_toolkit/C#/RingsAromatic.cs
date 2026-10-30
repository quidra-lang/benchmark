static class RingsAromatic
{
    public static HashSet<int> EdgeSet(Molecule m, List<int> ring) => Enumerable.Range(0, ring.Count).Select(i => m.BondIndex(ring[i], ring[(i + 1) % ring.Count])!.Value).ToHashSet();
    public static void Detect(Molecule m)
    {
        int n = m.Atoms.Count;
        List<(List<int> Ring, HashSet<int> Edges)> candidates = new();
        HashSet<string> seen = new(StringComparer.Ordinal);
        for (int root = 0; root < n; root++)
        {
            int[] parent = Enumerable.Repeat(-1, n).ToArray();
            bool[] visited = new bool[n];
            Queue<int> queue = new();
            visited[root] = true;
            queue.Enqueue(root);
            while (queue.TryDequeue(out int a))
            {
                foreach (var (b, _) in m.Neighbors[a]) if (!visited[b]) {
                    visited[b] = true;
                    parent[b] = a;
                    queue.Enqueue(b);
                }
            }
            List<int> Path(int atom)
            {
                List<int> result = new() {
                    atom
                };
                int x = atom;
                while (parent[x] >= 0) {
                    x = parent[x];
                    result.Add(x);
                }
                return result;
            }
            foreach (Bond bond in m.Bonds)
            {
                if (parent[bond.A] == bond.B || parent[bond.B] == bond.A) continue;
                List<int> a = Path(bond.A), b = Path(bond.B);
                if (a.Any(x => x != root && b.Contains(x))) continue;
                List<int> ring = a.AsEnumerable().Reverse().Concat(b.Take(b.Count - 1)).ToList();
                HashSet<int> edges = EdgeSet(m, ring);
                if (seen.Add(string.Join(",", edges.Order()))) candidates.Add((ring, edges));
            }
        }
        Dictionary<int, HashSet<int>> basis = new();
        List<List<int>> selected = new();
        foreach (var (ring, edges) in candidates.OrderBy(c => c.Ring.Count))
        {
            HashSet<int> vector = new(edges);
            while (vector.Count > 0)
            {
                int pivot = vector.Max();
                if (basis.TryGetValue(pivot, out HashSet<int>? b)) vector.SymmetricExceptWith(b);
                else {
                    basis[pivot] = vector;
                    selected.Add(ring);
                    break;
                }
            }
        }
        m.Rings = selected.Select(r =>
        {
            int k = r.IndexOf(r.Min());
            List<int> rotated = r.Skip(k).Concat(r.Take(k)).ToList();
            return rotated[1] < rotated[^1] ? rotated : new[] {
                rotated[0]
            }.Concat(rotated.Skip(1).Reverse()).ToList();
        }).OrderBy(r => r.Count).ThenBy(r => r, Comparer<List<int>>.Create(Canonical.LexCompare)).ToList();
        foreach (List<int> ring in m.Rings) foreach (int edge in EdgeSet(m, ring)) m.Bonds[edge].Ring = true;
    }
    public static void Kekulize(Molecule m, Elements elements)
    {
        HashSet<int> remaining = Enumerable.Range(0, m.Atoms.Count).Where(i => m.NeedsPi(i, elements, true)).ToHashSet();
        Dictionary<int, int> paired = new();
        bool Matching(HashSet<int> system)
        {
            int[] unpaired = system.Where(i => !paired.ContainsKey(i)).Order().ToArray();
            if (unpaired.Length == 0) return true;
            int u = unpaired[0];
            foreach (var (v, edge) in m.Neighbors[u]) if (system.Contains(v) && !paired.ContainsKey(v) && m.Bonds[edge].Kind == 4)
            {
                paired[u] = v;
                paired[v] = u;
                if (Matching(system)) return true;
                paired.Remove(u);
                paired.Remove(v);
            }
            return false;
        }
        while (remaining.Count > 0)
        {
            int start = remaining.Min();
            HashSet<int> system = new();
            Stack<int> stack = new();
            stack.Push(start);
            remaining.Remove(start);
            while (stack.TryPop(out int a))
            {
                system.Add(a);
                foreach (var (b, edge) in m.Neighbors[a]) if (m.Bonds[edge].Kind == 4 && remaining.Remove(b)) stack.Push(b);
            }
            if (!Matching(system)) throw new MoleculeError("kekulization failed", m.Atoms[system.Min()].Column);
        }
        foreach (Bond b in m.Bonds) b.Multiplicity = b.Kind == 4 ? paired.TryGetValue(b.A, out int mate) && mate == b.B ? 2 : 1 : b.Kind;
    }
}
