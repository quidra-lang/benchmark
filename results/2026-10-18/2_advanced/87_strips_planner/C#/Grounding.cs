sealed record GroundAction(int Source, string Name, List<string> Args, int Cost, State Pre, State Neg, State Add, State Del)
{
    public string Text => new Atom(Name, Args).Text;
}
sealed record Grounding(List<Atom> Facts, List<GroundAction> Actions, State Initial, State Goals, List<Atom> Unreachable,
int[][] Stats, HashSet<string> Fluent, int StaticCount);
sealed class GroundCandidate(int source, List<string> args)
{
    public int Source {
        get;
    } = source;
    public List<string> Args {
        get;
    } = args;
    public HashSet<Atom> Pre {
        get;
    } = new();
    public HashSet<Atom> Neg {
        get;
    } = new();
    public HashSet<Atom> Add {
        get;
    } = new();
    public HashSet<Atom> Del {
        get;
    } = new();
}
static class Grounder
{
    public static int LexCompare(List<int> a, List<int> b)
    {
        for (int i = 0; i < Math.Min(a.Count, b.Count); i++) if (a[i] != b[i]) return a[i].CompareTo(b[i]);
        return a.Count.CompareTo(b.Count);
    }
    public static bool Subtype(Domain domain, string type, string expected)
    {
        string current = type;
        while (true)
        {
            if (current == expected) return true;
            if (!domain.Parents.TryGetValue(current, out string? parent)) return false;
            current = parent;
        }
    }
    public static HashSet<string> Fluents(Domain domain) => domain.Actions.SelectMany(a => a.Effects.Select(l => l.Atom.Predicate)).ToHashSet(StringComparer.Ordinal);
    public static Grounding Ground(Domain domain, Problem problem)
    {
        HashSet<string> fluent = Fluents(domain);
        HashSet<Atom> initial = problem.Initial.ToHashSet();
        int[][] stats = domain.Actions.Select(_ => new int[3]).ToArray();
        List<GroundCandidate> candidates = new();
        for (int source = 0; source < domain.Actions.Count; source++)
        {
            Schema action = domain.Actions[source];
            List<List<string>> choices = action.Parameters.Select(p => problem.Objects.Where(o => Subtype(domain, o.Type, p.Type)).Select(o => o.Name).ToList()).ToList();
            List<List<string>> all = new();
            List<string> current = new();
            void Combinations(int i)
            {
                if (i == choices.Count) {
                    all.Add(new(current));
                    return;
                }
                foreach (string obj in choices[i]) {
                    current.Add(obj);
                    Combinations(i + 1);
                    current.RemoveAt(current.Count - 1);
                }
            }
            Combinations(0);
            stats[source][0] = all.Count;
            foreach (List<string> args in all)
            {
                Dictionary<string, string> values = action.Parameters.Select((p, i) => (p.Name, Value: args[i])).ToDictionary(p => p.Name, p => p.Value, StringComparer.Ordinal);
                GroundCandidate candidate = new(source, args);
                bool valid = true;
                foreach (Literal literal in action.Pre)
                {
                    Atom atom = literal.Atom.Replace(values);
                    if (atom.Predicate == "=" || !fluent.Contains(atom.Predicate))
                    {
                        bool truth = atom.Predicate == "=" ? atom.Terms[0] == atom.Terms[1] : initial.Contains(atom);
                        if (truth == literal.Negative) {
                            valid = false;
                            break;
                        }
                    }
                    else if (literal.Negative) candidate.Neg.Add(atom);
                    else candidate.Pre.Add(atom);
                }
                if (!valid) continue;
                foreach (Literal literal in action.Effects)
                {
                    Atom atom = literal.Atom.Replace(values);
                    if (literal.Negative) candidate.Del.Add(atom);
                    else candidate.Add.Add(atom);
                }
                candidate.Del.ExceptWith(candidate.Add);
                stats[source][1]++;
                candidates.Add(candidate);
            }
        }
        HashSet<Atom> reachable = initial.Where(a => fluent.Contains(a.Predicate)).ToHashSet();
        HashSet<int> kept = new();
        while (true)
        {
            int before = kept.Count;
            for (int i = 0; i < candidates.Count; i++) if (candidates[i].Pre.IsSubsetOf(reachable)) {
                kept.Add(i);
                reachable.UnionWith(candidates[i].Add);
            }
            if (kept.Count == before) break;
        }
        Dictionary<string, int> predicates = domain.Predicates.Select((p, i) => (p.Name, Index: i)).ToDictionary(p => p.Name, p => p.Index, StringComparer.Ordinal);
        Dictionary<string, int> objects = problem.Objects.Select((o, i) => (o.Name, Index: i)).ToDictionary(p => p.Name, p => p.Index, StringComparer.Ordinal);
        List<Atom> facts = reachable.OrderBy(a => predicates[a.Predicate]).ThenBy(a => a.Terms.Select(t => objects[t]).ToList(), Comparer<List<int>>.Create(LexCompare)).ToList();
        Dictionary<Atom, int> numbering = facts.Select((a, i) => (Atom: a, Index: i)).ToDictionary(p => p.Atom, p => p.Index);
        State Numbers(IEnumerable<Atom> atoms) => atoms.Where(numbering.ContainsKey).Select(a => numbering[a]).ToHashSet();
        List<GroundAction> actions = new();
        foreach (int i in kept.Order())
        {
            GroundCandidate c = candidates[i];
            Schema a = domain.Actions[c.Source];
            stats[c.Source][2]++;
            actions.Add(new GroundAction(c.Source, a.Name, c.Args, a.Cost, Numbers(c.Pre), Numbers(c.Neg), Numbers(c.Add), Numbers(c.Del)));
        }
        State goals = new();
        List<Atom> unreachable = new();
        foreach (Atom atom in problem.Goals)
        {
            if (numbering.TryGetValue(atom, out int i)) goals.Add(i);
            else if (fluent.Contains(atom.Predicate) || !initial.Contains(atom)) unreachable.Add(atom);
        }
        return new Grounding(facts, actions, Numbers(initial), goals, unreachable, stats, fluent, problem.Initial.Count(a => !fluent.Contains(a.Predicate)));
    }
}
