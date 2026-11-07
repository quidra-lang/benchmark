static class Canonical
{
    public static int LexCompare(List<int> a, List<int> b)
    {
        for (int i = 0; i < Math.Min(a.Count, b.Count); i++) if (a[i] != b[i]) return a[i].CompareTo(b[i]);
        return a.Count.CompareTo(b.Count);
    }
    static List<int> Dense(List<List<int>> values)
    {
        List<List<int>> sorted = values.DistinctBy(v => string.Join(",", v)).OrderBy(v => v, Comparer<List<int>>.Create(LexCompare)).ToList();
        return values.Select(v => sorted.FindIndex(w => v.SequenceEqual(w)) + 1).ToList();
    }
    static List<int> Refine(Molecule m, List<int> input)
    {
        List<int> ranks = input;
        while (true)
        {
            int classes = ranks.Distinct().Count();
            List<List<int>> values = Enumerable.Range(0, m.Atoms.Count).Select(i => new[] {
                ranks[i]
            }.Concat(m.Neighbors[i].Select(n => (Rank: ranks[n.Atom], Kind: m.Bonds[n.Bond].Kind)).OrderBy(n => n.Rank).ThenBy(n => n.Kind).SelectMany(n => new[] {
                n.Rank, n.Kind
            })).ToList()).ToList();
            ranks = Dense(values);
            if (ranks.Distinct().Count() == classes) return ranks;
        }
    }
    static (List<int> Ranks, int Classes) Ranks(Molecule m, Elements elements)
    {
        List<List<int>> values = m.Atoms.Select((a, i) => new List<int> {
            m.Neighbors[i].Count, elements[a.Element].Number, a.Mass, a.Charge, a.Hydrogens, a.Aromatic ? 1 : 0
        }).ToList();
        List<int> ranks = Refine(m, Dense(values));
        int classes = ranks.Distinct().Count();
        while (ranks.Distinct().Count() < m.Atoms.Count)
        {
            int tied = ranks.GroupBy(r => r).Where(g => g.Count() > 1).Min(g => g.Key);
            int atom = ranks.IndexOf(tied);
            ranks = Refine(m, Dense(ranks.Select((r, i) => new List<int> {
                r * 2 - (i == atom ? 1 : 0)
            }).ToList()));
        }
        return (ranks, classes);
    }
    static string AtomText(Molecule m, int i, Elements elements)
    {
        Atom a = m.Atoms[i];
        string symbol = a.Aromatic ? a.Element.ToLowerInvariant() : a.Element;
        bool allowed = new[] {
            "B", "C", "N", "O", "P", "S", "F", "Cl", "Br", "I"
        }.Contains(a.Element) && (!a.Aromatic || new[] {
            "B", "C", "N", "O", "P", "S"
        }.Contains(a.Element));
        if (allowed && a.Mass == 0 && a.Charge == 0 && (!a.Aromatic || m.NeedsPi(i, elements, true) == m.NeedsPi(i, elements, false)) && m.OrganicHydrogens(i, elements) == a.Hydrogens) return symbol;
        StringBuilder text = new("[");
        if (a.Mass != 0) text.Append(a.Mass);
        text.Append(symbol);
        if (a.Hydrogens > 0) {
            text.Append('H');
            if (a.Hydrogens > 1) text.Append(a.Hydrogens);
        }
        if (a.Charge != 0) {
            text.Append(a.Charge > 0 ? '+' : '-');
            if (Math.Abs(a.Charge) > 1) text.Append(Math.Abs(a.Charge));
        }
        return text.Append(']').ToString();
    }
    static string BondText(Molecule m, int edge)
    {
        Bond b = m.Bonds[edge];
        bool aromatic = m.Atoms[b.A].Aromatic && m.Atoms[b.B].Aromatic && b.Ring;
        return b.Kind switch {
            1 => aromatic ? "-" : "", 2 => "=", 3 => "#", _ => aromatic ? "" : ":"
        };
    }
    public static (string Text, int Classes) Smiles(Molecule m, Elements elements)
    {
        var (ranks, classes) = Ranks(m, elements);
        int start = ranks.IndexOf(1), serial = 0;
        int[] visited = new int[m.Atoms.Count], kinds = new int[m.Bonds.Count];
        List<List<(int Atom, int Edge)>> children = Enumerable.Range(0, m.Atoms.Count).Select(_ => new List<(int Atom, int Edge)>()).ToList();
        Dictionary<int, int> assigned = new();
        void Visit(int a, int? incoming)
        {
            visited[a] = ++serial;
            foreach (var (b, edge) in m.Neighbors[a].OrderBy(n => ranks[n.Atom]))
            {
                if (edge == incoming || kinds[edge] == 2) continue;
                if (visited[b] == 0) {
                    kinds[edge] = 1;
                    children[a].Add((b, edge));
                    Visit(b, edge);
                }
                else kinds[edge] = 2;
            }
        }
        string Write(int a)
        {
            StringBuilder text = new(AtomText(m, a, elements));
            foreach (var (_, edge) in m.Neighbors[a].Where(n => kinds[n.Bond] == 2).OrderBy(n => visited[n.Atom]))
            {
                int number;
                if (assigned.Remove(edge, out int old)) number = old;
                else
                {
                    number = 1;
                    while (assigned.Values.Contains(number)) number++;
                    assigned[edge] = number;
                    text.Append(BondText(m, edge));
                }
                text.Append(number < 10 ? number.ToString(CultureInfo.InvariantCulture) : "%" + number.ToString("D2", CultureInfo.InvariantCulture));
            }
            for (int i = 0; i < children[a].Count; i++)
            {
                var (child, edge) = children[a][i];
                bool branch = i + 1 < children[a].Count;
                if (branch) text.Append('(');
                text.Append(BondText(m, edge)).Append(Write(child));
                if (branch) text.Append(')');
            }
            return text.ToString();
        }
        Visit(start, null);
        return (Write(start), classes);
    }
}
