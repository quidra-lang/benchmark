sealed record Analysis(string Name, Molecule Graph, string Smiles, int Classes, string Formula, int Weight,
int Heavy, int Rotatable, int Donors, int Acceptors, string Lipinski, int Charge, string? Scaffold, Fingerprint Fingerprint);
sealed record RingSystem(List<int> Rings, string Kind, int Atoms);
sealed class QueryError(string reason) : Exception(reason)
{
    public string Reason {
        get;
    } = reason;
}
sealed class Query(string kind, string id, string[] args)
{
    public string Kind {
        get;
    } = kind;
    public string Id {
        get;
    } = id;
    public string[] Args {
        get;
    } = args;
    public List<int> Indices {
        get;
    } = new();
    public Pattern? Pattern {
        get;
        set;
    }
    public int Count {
        get;
        set;
    }
    public Ratio Threshold {
        get;
        set;
    } = new(0, 1);
}
static class Program
{
    static bool ValidName(string text) => text.Length is >= 1 and <= 32 && text.All(c => c is >= 'A' and <= 'Z' or >= 'a' and <= 'z' or >= '0' and <= '9' or '_' or '-');
    static int? Number(string text, int low, int high)
    {
        if (text.Length == 0 || text.Length > 1 && text[0] == '0' || !text.All(c => c is >= '0' and <= '9')) return null;
        return int.TryParse(text, NumberStyles.None, CultureInfo.InvariantCulture, out int n) && n >= low && n <= high ? n : null;
    }
    static Ratio? Threshold(string text)
    {
        string[] a = text.Split('/');
        if (a.Length != 2 || Number(a[0], 0, 99) is not {
        } p || Number(a[1], 1, 99) is not {
        } q || p > q) return null;
        return new Ratio(p, q);
    }
    static Molecule Analyze(string text, Elements elements)
    {
        Molecule m = SmilesParser.Parse(text, elements).Molecule;
        RingsAromatic.Detect(m);
        foreach (Bond b in m.Bonds) if (b.Kind == 0) b.Kind = m.Atoms[b.A].Aromatic && m.Atoms[b.B].Aromatic && b.Ring ? 4 : 1;
        RingsAromatic.Kekulize(m, elements);
        for (int i = 0; i < m.Atoms.Count; i++)
        {
            Atom a = m.Atoms[i];
            if (a.Bracket)
            {
                if (m.Multiplicity(i) + a.Hydrogens > elements[a.Element].Valences[^1] + Math.Abs(a.Charge)) throw new MoleculeError("bad valence", a.Column);
            }
            else m.Atoms[i] = a with {
                Hydrogens = m.OrganicHydrogens(i, elements) ?? throw new MoleculeError("bad valence", a.Column)
            };
        }
        return m;
    }
    static string? Scaffold(Molecule m, Elements elements)
    {
        if (m.Rings.Count == 0) return null;
        HashSet<int> ringAtoms = m.Rings.SelectMany(r => r).ToHashSet();
        HashSet<int> remaining = Enumerable.Range(0, m.Atoms.Count).ToHashSet();
        while (true)
        {
            int[] remove = remaining.Order().Where(i => !ringAtoms.Contains(i) && m.Neighbors[i].Count(n => remaining.Contains(n.Atom)) == 1).Take(1).ToArray();
            if (remove.Length == 0) break;
            remaining.Remove(remove[0]);
        }
        HashSet<int> core = new(remaining);
        foreach (Bond b in m.Bonds) if (b.Kind == 2)
        {
            if (core.Contains(b.A)) remaining.Add(b.B);
            if (core.Contains(b.B)) remaining.Add(b.A);
        }
        Molecule graph = new();
        Dictionary<int, int> index = new();
        foreach (int i in remaining.Order())
        {
            index[i] = graph.Atoms.Count;
            int extra = m.Neighbors[i].Where(n => !remaining.Contains(n.Atom)).Sum(n => m.Bonds[n.Bond].Multiplicity);
            graph.Atoms.Add(m.Atoms[i] with {
                Hydrogens = m.Atoms[i].Hydrogens + extra
            });
        }
        foreach (Bond b in m.Bonds) if (remaining.Contains(b.A) && remaining.Contains(b.B)) graph.Bonds.Add(b with {
            A = index[b.A], B = index[b.B]
        });
        graph.Rebuild();
        return Canonical.Smiles(graph, elements).Text;
    }
    static Analysis Properties(string name, Molecule m, Elements elements)
    {
        Dictionary<string, int> counts = new(StringComparer.Ordinal);
        int weight = 0, hydrogens = 0;
        foreach (Atom a in m.Atoms)
        {
            counts[a.Element] = counts.GetValueOrDefault(a.Element) + 1;
            hydrogens += a.Hydrogens;
            weight += a.Mass == 0 ? elements[a.Element].Mass : a.Mass * 1000;
        }
        counts["H"] = counts.GetValueOrDefault("H") + hydrogens;
        weight += hydrogens * elements["H"].Mass;
        if (counts["H"] == 0) counts.Remove("H");
        List<string> order = new();
        if (counts.ContainsKey("C")) {
            order.Add("C");
            if (counts.ContainsKey("H")) order.Add("H");
        }
        order.AddRange(counts.Keys.Where(k => !order.Contains(k)).Order(StringComparer.Ordinal));
        string formula = string.Concat(order.Select(k => k + (counts[k] > 1 ? counts[k].ToString(CultureInfo.InvariantCulture) : "")));
        int heavy = m.Atoms.Count(a => a.Element != "H");
        int[] heavyDegree = m.Neighbors.Select(ns => ns.Count(n => m.Atoms[n.Atom].Element != "H")).ToArray();
        bool[] triple = m.Neighbors.Select(ns => ns.Any(n => m.Bonds[n.Bond].Multiplicity == 3)).ToArray();
        int rotatable = m.Bonds.Count(b => b.Multiplicity == 1 && !b.Ring && heavyDegree[b.A] >= 2 && heavyDegree[b.B] >= 2 && !triple[b.A] && !triple[b.B]);
        int acceptors = m.Atoms.Count(a => a.Element is "N" or "O");
        int donors = Enumerable.Range(0, m.Atoms.Count).Count(i => m.Atoms[i].Element is "N" or "O" && (m.Atoms[i].Hydrogens > 0 || m.Neighbors[i].Any(n => m.Atoms[n.Atom].Element == "H")));
        int violations = (weight > 500000 ? 1 : 0) + (donors > 5 ? 1 : 0) + (acceptors > 10 ? 1 : 0);
        var (smiles, classes) = Canonical.Smiles(m, elements);
        return new Analysis(name, m, smiles, classes, formula, weight, heavy, rotatable, donors, acceptors, violations <= 1 ? "pass" : "fail", m.Atoms.Sum(a => a.Charge), Scaffold(m, elements), Search.Fingerprint(m, elements));
    }
    static List<RingSystem> RingSystems(Molecule m)
    {
        HashSet<int> remaining = Enumerable.Range(0, m.Rings.Count).ToHashSet();
        List<RingSystem> result = new();
        while (remaining.Count > 0)
        {
            int start = remaining.Min();
            HashSet<int> group = new();
            Stack<int> stack = new();
            stack.Push(start);
            remaining.Remove(start);
            while (stack.TryPop(out int i))
            {
                group.Add(i);
                int[] neighbors = remaining.Where(j => m.Rings[i].Intersect(m.Rings[j]).Any()).Order().ToArray();
                foreach (int j in neighbors) {
                    remaining.Remove(j);
                    stack.Push(j);
                }
            }
            List<int> rings = group.Order().ToList();
            string kind = rings.Count == 1 ? "isolated" : "spiro";
            for (int x = 0; x < rings.Count; x++) for (int y = x + 1; y < rings.Count; y++)
            {
                List<int> common = m.Rings[rings[x]].Intersect(m.Rings[rings[y]]).ToList();
                if (common.Count >= 2)
                {
                    if (common.Count == 2 && m.BondIndex(common[0], common[1]) is not null) {
                        if (kind != "bridged") kind = "fused";
                    }
                    else kind = "bridged";
                }
            }
            result.Add(new RingSystem(rings, kind, rings.SelectMany(i => m.Rings[i]).Distinct().Count()));
        }
        return result;
    }
    static void Paragraph(List<string> output, IEnumerable<string> lines)
    {
        if (output.Count > 0) output.Add("");
        output.AddRange(lines);
    }
    static List<string> CanonicalReport(List<Analysis> molecules)
    {
        List<string> result = new();
        Paragraph(result, new[] {
            $"CANONICAL molecules={molecules.Count} unique={molecules.Select(m => m.Smiles).Distinct().Count()}"
        }.Concat(molecules.Select(m => $"{m.Name} {m.Smiles} classes={m.Classes} charge={(m.Charge > 0 ? "+" : "")}{m.Charge}")));
        string Names(IEnumerable<int> ids) => string.Join(",", ids.Select(i => molecules[i].Name));
        var duplicates = Enumerable.Range(0, molecules.Count).GroupBy(i => molecules[i].Smiles, StringComparer.Ordinal).Where(g => g.Count() >= 2).OrderBy(g => g.First()).ToList();
        Paragraph(result, new[] {
            $"DUPLICATES groups={duplicates.Count} molecules={duplicates.Sum(g => g.Count())}"
        }.Concat(duplicates.Select((g, i) => $"group {i + 1} {g.Key} members={Names(g)}")));
        var isomers = Enumerable.Range(0, molecules.Count).GroupBy(i => molecules[i].Formula, StringComparer.Ordinal).Where(g => g.Select(i => molecules[i].Smiles).Distinct().Count() >= 2).OrderBy(g => g.First()).ToList();
        Paragraph(result, new[] {
            $"ISOMERS groups={isomers.Count}"
        }.Concat(isomers.Select((g, i) => $"isomer {i + 1} {g.Key} forms={g.Select(j => molecules[j].Smiles).Distinct().Count()} members={Names(g)}")));
        var scaffolds = Enumerable.Range(0, molecules.Count).Where(i => molecules[i].Scaffold is not null).GroupBy(i => molecules[i].Scaffold!, StringComparer.Ordinal).OrderByDescending(g => g.Count()).ThenBy(g => g.Key, StringComparer.Ordinal).ToList();
        Paragraph(result, new[] {
            $"SCAFFOLDS distinct={scaffolds.Count} acyclic={molecules.Count(m => m.Scaffold is null)}"
        }.Concat(scaffolds.Select((g, i) => $"scaffold {i + 1} {g.Key} count={g.Count()} members={Names(g)}")));
        return result;
    }
    static List<string> RingsReport(List<Analysis> molecules)
    {
        List<string> result = new();
        int total = 0, aromatic = 0, cyclic = 0;
        SortedDictionary<int, int> sizes = new();
        string[] kinds = ["isolated", "fused", "spiro", "bridged"];
        int[] kindCounts = new int[4];
        foreach (Analysis m in molecules.Where(m => m.Graph.Rings.Count > 0))
        {
            Molecule graph = m.Graph;
            int aromaticCount = graph.Rings.Count(r => r.All(i => graph.Atoms[i].Aromatic));
            List<RingSystem> systems = RingSystems(graph);
            cyclic++;
            total += graph.Rings.Count;
            aromatic += aromaticCount;
            List<string> lines = new() {
                $"MOLECULE {m.Name} atoms={graph.Atoms.Count} bonds={graph.Bonds.Count} rings={graph.Rings.Count} aromatic={aromaticCount} systems={systems.Count} ring_atoms={graph.Rings.SelectMany(r => r).Distinct().Count()} ring_bonds={graph.Bonds.Count(b => b.Ring)}"
            };
            for (int i = 0; i < graph.Rings.Count; i++)
            {
                List<int> ring = graph.Rings[i];
                sizes[ring.Count] = sizes.GetValueOrDefault(ring.Count) + 1;
                lines.Add($"ring {i + 1} size={ring.Count} aromatic={(ring.All(a => graph.Atoms[a].Aromatic) ? "yes" : "no")} hetero={ring.Count(a => graph.Atoms[a].Element != "C")} atoms={string.Join("-", ring.Select(a => a + 1))}");
            }
            for (int i = 0; i < systems.Count; i++)
            {
                RingSystem system = systems[i];
                kindCounts[Array.IndexOf(kinds, system.Kind)]++;
                lines.Add($"system {i + 1} kind={system.Kind} rings={string.Join(",", system.Rings.Select(r => r + 1))} atoms={system.Atoms}");
            }
            List<string> doubles = graph.Bonds.Where(b => b.Kind == 4 && b.Multiplicity == 2).Select(b => $"{b.A + 1}={b.B + 1}").ToList();
            lines.Add("kekule " + (doubles.Count == 0 ? "-" : string.Join(" ", doubles)));
            Paragraph(result, lines);
        }
        string sizeText = sizes.Count == 0 ? "-" : string.Join(" ", sizes.Select(p => $"{p.Key}={p.Value}"));
        Paragraph(result, new[] {
            $"SUMMARY molecules={molecules.Count} cyclic={cyclic} rings={total} aromatic={aromatic}", $"sizes {sizeText}", $"systems isolated={kindCounts[0]} fused={kindCounts[1]} spiro={kindCounts[2]} bridged={kindCounts[3]}"
        });
        return result;
    }
    static Query ReadQuery(string[] a, Dictionary<string, int> names, Elements elements)
    {
        string kind = a[0];
        string[] args = a.Skip(2).ToArray();
        bool valid = kind is "MATCH" or "CLUSTER" ? args.Length == 1 : kind == "MATRIX" ? args.Length is >= 2 and <= 12 : args.Length == 2;
        if (!valid) throw new QueryError("bad arguments");
        Query q = new(kind, a[1], args);
        int Index(string name) => names.TryGetValue(name, out int index) ? index : throw new QueryError($"unknown molecule {name}");
        switch (kind)
        {
            case "MATCH":
            try {
                q.Pattern = Pattern.Parse(args[0], elements);
            }
            catch (MoleculeError e) {
                throw new QueryError($"bad pattern {e.Reason} at column {e.Column}");
            }
            break;
            case "CLUSTER": q.Threshold = Threshold(args[0]) ?? throw new QueryError("bad threshold");
            break;
            case "NEAREST":
            case "WITHIN":
            q.Indices.Add(Index(args[0]));
            if (kind == "NEAREST") q.Count = Number(args[1], 1, 99) ?? throw new QueryError("bad count");
            else q.Threshold = Threshold(args[1]) ?? throw new QueryError("bad threshold");
            break;
            default:
            foreach (string name in args) q.Indices.Add(Index(name));
            if (q.Indices.Distinct().Count() != q.Indices.Count) throw new QueryError("repeated molecule");
            break;
        }
        return q;
    }
    static void Process(Query q, List<Analysis> molecules, List<string> sub, List<string> similarity, int[] counts)
    {
        Ratio Sim(int a, int b) => Search.Similarity(molecules[a].Fingerprint, molecules[b].Fingerprint);
        switch (q.Kind)
        {
            case "MATCH":
            counts[0]++;
            Pattern pattern = q.Pattern!;
            var matches = molecules.Select((m, i) => (Index: i, Match: Search.Embeddings(pattern, m.Graph))).Where(p => p.Match.Count > 0).ToList();
            counts[1] += matches.Count;
            List<string> matchLines = new() {
                $"MATCH {q.Id} {q.Args[0]} atoms={pattern.Graph.Atoms.Count} bonds={pattern.Graph.Bonds.Count} hits={matches.Count} embeddings={matches.Sum(p => p.Match.Count)}"
            };
            foreach (var (i, match) in matches) matchLines.Add($"{molecules[i].Name} count={match.Count} unique={match.Unique} map={string.Join(",", match.First)}");
            if (matches.Count > 0)
            {
                var top = matches.OrderByDescending(p => p.Match.Count).ThenBy(p => p.Index).First();
                matchLines.Add($"top {molecules[top.Index].Name} count={top.Match.Count}");
            }
            Paragraph(sub, matchLines);
            break;
            case "CONTAINS":
            counts[2]++;
            Matches contained = Search.Embeddings(Pattern.FromMolecule(molecules[q.Indices[0]].Graph), molecules[q.Indices[1]].Graph);
            string answer = "no";
            if (contained.Count > 0) {
                counts[3]++;
                answer = $"yes count={contained.Count} unique={contained.Unique} map={string.Join(",", contained.First)}";
            }
            Paragraph(sub, new[] {
                $"CONTAINS {q.Id} {q.Args[0]} {q.Args[1]} result={answer}"
            });
            break;
            case "MATRIX":
            List<string> matrix = new() {
                $"MATRIX {q.Id} size={q.Indices.Count}"
            };
            foreach (int a in q.Indices) matrix.Add($"row {molecules[a].Name} " + string.Join(" ", q.Indices.Select(b => Sim(a, b))));
            int bestA = 0, bestB = 1;
            Ratio best = Sim(q.Indices[0], q.Indices[1]);
            for (int a = 0; a < q.Indices.Count; a++) for (int b = a + 1; b < q.Indices.Count; b++)
            {
                Ratio s = Sim(q.Indices[a], q.Indices[b]);
                if (s.CompareTo(best) > 0) {
                    bestA = a;
                    bestB = b;
                    best = s;
                }
            }
            matrix.Add($"best {q.Args[bestA]} {q.Args[bestB]} {best}");
            Paragraph(similarity, matrix);
            break;
            case "NEAREST":
            case "WITHIN":
            int x = q.Indices[0];
            var results = Enumerable.Range(0, molecules.Count).Where(i => i != x).Select(i => (Index: i, Similarity: Sim(x, i))).OrderByDescending(p => p.Similarity).ThenBy(p => p.Index).ToList();
            results = q.Kind == "NEAREST" ? results.Take(q.Count).ToList() : results.Where(p => p.Similarity.CompareTo(q.Threshold) >= 0).ToList();
            string first = q.Kind == "NEAREST" ? $"NEAREST {q.Id} {q.Args[0]} count={results.Count}" : $"WITHIN {q.Id} {q.Args[0]} threshold={q.Threshold} count={results.Count}";
            Paragraph(similarity, new[] {
                first
            }.Concat(results.Select((p, i) => $"{i + 1} {molecules[p.Index].Name} {p.Similarity} common={p.Similarity.P}")));
            break;
            case "COMPARE":
            Analysis left = molecules[q.Indices[0]], right = molecules[q.Indices[1]];
            Ratio ratio = Search.Similarity(left.Fingerprint, right.Fingerprint);
            Paragraph(similarity, new[] {
                $"COMPARE {q.Id} {q.Args[0]} {q.Args[1]} bits={left.Fingerprint.Bits.Count},{right.Fingerprint.Bits.Count} common={ratio.P} union={ratio.Q} tanimoto={ratio} identical={(left.Smiles == right.Smiles ? "yes" : "no")}"
            });
            break;
            case "CLUSTER":
            List<List<int>> neighbors = Enumerable.Range(0, molecules.Count).Select(i => Enumerable.Range(0, molecules.Count).Where(j => j != i && Sim(i, j).CompareTo(q.Threshold) >= 0).ToList()).ToList();
            int[] order = Enumerable.Range(0, molecules.Count).OrderByDescending(i => neighbors[i].Count).ThenBy(i => i).ToArray();
            HashSet<int> used = new();
            List<List<int>> clusters = new();
            foreach (int i in order) if (used.Add(i))
            {
                List<int> members = new() {
                    i
                };
                foreach (int j in neighbors[i]) if (used.Add(j)) members.Add(j);
                clusters.Add(members);
            }
            Paragraph(similarity, new[] {
                $"CLUSTER {q.Id} threshold={q.Threshold} clusters={clusters.Count} singletons={clusters.Count(c => c.Count == 1)}"
            }.Concat(clusters.Where(c => c.Count > 1).Select((c, i) => $"cluster {i + 1} centroid={molecules[c[0]].Name} size={c.Count} members={string.Join(",", c.Select(j => molecules[j].Name))}")));
            break;
        }
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
        Elements elements = Molecule.ReadElements();
        List<Analysis> molecules = new();
        HashSet<string> seen = new(StringComparer.Ordinal);
        List<string> moleculeErrors = new();
        Dictionary<string, int> causes = new(StringComparer.Ordinal);
        int moleculeLines = 0;
        void Cause(string reason) => causes[reason] = causes.GetValueOrDefault(reason) + 1;
        string[] moleculeSource = File.ReadAllLines("input/molecules.smi");
        for (int i = 0; i < moleculeSource.Length; i++)
        {
            string line = moleculeSource[i];
            if (line.Length == 0 || line.StartsWith('#')) continue;
            moleculeLines++;
            string[] a = line.Split(' ');
            if (a.Length != 2 || a[0].Length == 0 || !ValidName(a[1])) {
                moleculeErrors.Add($"line {i + 1}: bad line");
                Cause("bad line");
            }
            else if (!seen.Add(a[1])) {
                moleculeErrors.Add($"line {i + 1} {a[1]}: duplicate name");
                Cause("duplicate name");
            }
            else
            {
                try {
                    molecules.Add(Properties(a[1], Analyze(a[0], elements), elements));
                }
                catch (MoleculeError e) {
                    moleculeErrors.Add($"line {i + 1} {a[1]}: {e.Reason} at column {e.Column}");
                    Cause(e.Reason);
                }
            }
        }
        Dictionary<string, int> names = molecules.Select((m, i) => (m.Name, Index: i)).ToDictionary(p => p.Name, p => p.Index, StringComparer.Ordinal);
        List<string> propertyLines = new() {
            "name,formula,weight,heavy_atoms,rings,rotatable,donors,acceptors,lipinski"
        };
        foreach (Analysis m in molecules)
        {
            string weight = (m.Weight / 1000).ToString(CultureInfo.InvariantCulture) + "." + (m.Weight % 1000).ToString("D3", CultureInfo.InvariantCulture);
            propertyLines.Add($"{m.Name},{m.Formula},{weight},{m.Heavy},{m.Graph.Rings.Count},{m.Rotatable},{m.Donors},{m.Acceptors},{m.Lipinski}");
        }
        List<string> substructure = new(), similarity = new() {
            $"FINGERPRINTS molecules={molecules.Count} size=1024 depth=5"
        };
        similarity.AddRange(molecules.Select(m => $"{m.Name} bits={m.Fingerprint.Bits.Count} paths={m.Fingerprint.Paths}"));
        HashSet<string> identifiers = new(StringComparer.Ordinal);
        List<string> queryErrors = new();
        int queryLines = 0, queryValid = 0;
        int[] counts = new int[4];
        string[] querySource = File.ReadAllLines("input/queries.txt");
        for (int i = 0; i < querySource.Length; i++)
        {
            string line = querySource[i];
            if (line.Length == 0 || line.StartsWith('#')) continue;
            queryLines++;
            string[] a = line.Split(' ');
            if (!new[] {
                "MATCH", "CONTAINS", "MATRIX", "NEAREST", "WITHIN", "COMPARE", "CLUSTER"
            }.Contains(a[0])) {
                queryErrors.Add($"line {i + 1}: unknown query");
                Cause("unknown query");
            }
            else if (a.Length == 1 || !ValidName(a[1])) {
                queryErrors.Add($"line {i + 1} {a[0]}: bad id");
                Cause("bad id");
            }
            else
            {
                try
                {
                    if (!identifiers.Add(a[1])) throw new QueryError("duplicate id");
                    Query q = ReadQuery(a, names, elements);
                    queryValid++;
                    Process(q, molecules, substructure, similarity, counts);
                }
                catch (QueryError e)
                {
                    queryErrors.Add($"line {i + 1} {a[0]} {a[1]}: {e.Reason}");
                    Cause(e.Reason.StartsWith("bad pattern ", StringComparison.Ordinal) ? "bad pattern" : e.Reason.StartsWith("unknown molecule ", StringComparison.Ordinal) ? "unknown molecule" : e.Reason);
                }
            }
        }
        Paragraph(substructure, new[] {
            $"SUMMARY patterns={counts[0]} hits={counts[1]} contains={counts[2]} found={counts[3]}"
        });
        List<string> errors = new();
        Paragraph(errors, new[] {
            $"MOLECULES lines={moleculeLines} valid={molecules.Count} errors={moleculeErrors.Count}"
        }.Concat(moleculeErrors));
        Paragraph(errors, new[] {
            $"QUERIES lines={queryLines} valid={queryValid} errors={queryErrors.Count}"
        }.Concat(queryErrors));
        Paragraph(errors, new[] {
            $"CAUSES kinds={causes.Count}"
        }.Concat(causes.OrderByDescending(p => p.Value).ThenBy(p => p.Key, StringComparer.Ordinal).Select(p => $"{p.Key}={p.Value}")));
        Write("properties.csv", propertyLines);
        Write("canonical.txt", CanonicalReport(molecules));
        Write("rings.txt", RingsReport(molecules));
        Write("substructure.txt", substructure);
        Write("similarity.txt", similarity);
        Write("errors.txt", errors);
    }
}
