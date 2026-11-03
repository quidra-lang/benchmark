enum MatcherKind {
    Any, Aliphatic, Aromatic, AtomList
}
sealed record Matcher(MatcherKind Kind, List<(string Element, bool Aromatic)>? Atoms = null);
sealed record Pattern(Molecule Graph, List<Matcher> Atoms)
{
    public static Pattern Parse(string text, Elements elements)
    {
        Parsed parsed = SmilesParser.Parse(text, elements, true);
        return new Pattern(parsed.Molecule, parsed.Matchers);
    }
    public static Pattern FromMolecule(Molecule m) => new(m, m.Atoms.Select(a => new Matcher(MatcherKind.AtomList, new() {
        (a.Element, a.Aromatic)
    })).ToList());
}
sealed record Matches(int Count, int Unique, List<int> First);
sealed class Fingerprint
{
    public HashSet<int> Bits {
        get;
    } = new();
    public int Paths {
        get;
        set;
    }
}
readonly record struct Ratio(int P, int Q) : IComparable<Ratio>
{
    public int CompareTo(Ratio other) => (P * other.Q).CompareTo(other.P * Q);
    public override string ToString()
    {
        int a = P, b = Q;
        while (b != 0) {
            int r = a % b;
            a = b;
            b = r;
        }
        return $"{P / a}/{Q / a}";
    }
}
static class Search
{
    public static (Matcher Matcher, int Length) PatternAtom(string s, int column)
    {
        switch (s[0])
        {
            case '*': return (new Matcher(MatcherKind.Any), 1);
            case 'A': return (new Matcher(MatcherKind.Aliphatic), 1);
            case 'a': return (new Matcher(MatcherKind.Aromatic), 1);
            case '[':
            int end = s.IndexOf(']');
            if (end < 0) throw new MoleculeError("unclosed bracket", column);
            List<(string, bool)> atoms = new();
            foreach (string part in s[1..end].Split(','))
            {
                var (element, aromatic, n) = SmilesParser.Organic(part) ?? throw new MoleculeError("bad bracket atom", column);
                if (n != part.Length) throw new MoleculeError("bad bracket atom", column);
                atoms.Add((element, aromatic));
            }
            return (new Matcher(MatcherKind.AtomList, atoms), end + 1);
            default:
            var organic = SmilesParser.Organic(s) ?? throw new MoleculeError("unexpected character", column);
            return (new Matcher(MatcherKind.AtomList, new() {
                (organic.Element, organic.Aromatic)
            }), organic.Length);
        }
    }
    public static Matches Embeddings(Pattern pattern, Molecule m)
    {
        List<int> map = new(), first = new();
        bool[] used = new bool[m.Atoms.Count];
        HashSet<string> sets = new(StringComparer.Ordinal);
        int count = 0;
        void Visit()
        {
            int a = map.Count;
            if (a == pattern.Atoms.Count)
            {
                count++;
                if (first.Count == 0) first = map.Select(i => i + 1).ToList();
                sets.Add(string.Join(",", map.Order()));
                return;
            }
            for (int b = 0; b < m.Atoms.Count; b++) if (!used[b])
            {
                Atom atom = m.Atoms[b];
                Matcher matcher = pattern.Atoms[a];
                bool matches = matcher.Kind switch
                {
                    MatcherKind.Any => true, MatcherKind.Aliphatic => !atom.Aromatic, MatcherKind.Aromatic => atom.Aromatic,
                    _ => matcher.Atoms!.Contains((atom.Element, atom.Aromatic))
                };
                if (!matches) continue;
                bool bonds = true;
                foreach (var (v, edge) in pattern.Graph.Neighbors[a].Where(n => n.Atom < a))
                {
                    int? f = m.BondIndex(b, map[v]);
                    int kind = pattern.Graph.Bonds[edge].Kind;
                    if (f is null || !(kind == 5 || kind == 0 && m.Bonds[f.Value].Kind is 1 or 4 || kind == m.Bonds[f.Value].Kind)) {
                        bonds = false;
                        break;
                    }
                }
                if (bonds) {
                    used[b] = true;
                    map.Add(b);
                    Visit();
                    map.RemoveAt(map.Count - 1);
                    used[b] = false;
                }
            }
        }
        Visit();
        return new Matches(count, sets.Count, first);
    }
    public static Fingerprint Fingerprint(Molecule m, Elements elements)
    {
        int[] codes = m.Atoms.Select((a, i) => 16 * elements[a.Element].Number + (a.Aromatic ? 8 : 0) + m.Neighbors[i].Count).ToArray();
        Fingerprint result = new();
        List<int> path = new();
        void Walk(int hash)
        {
            result.Paths++;
            result.Bits.Add(hash % 1024);
            if (path.Count == 6) return;
            foreach (var (b, edge) in m.Neighbors[path[^1]]) if (!path.Contains(b))
            {
                int h = ((hash * 31 + m.Bonds[edge].Kind) % 1000003 * 31 + codes[b]) % 1000003;
                path.Add(b);
                Walk(h);
                path.RemoveAt(path.Count - 1);
            }
        }
        for (int i = 0; i < m.Atoms.Count; i++) {
            path.Clear();
            path.Add(i);
            Walk(codes[i]);
        }
        return result;
    }
    public static Ratio Similarity(Fingerprint a, Fingerprint b)
    {
        int common = a.Bits.Count(b.Bits.Contains);
        return new Ratio(common, a.Bits.Count + b.Bits.Count - common);
    }
}
