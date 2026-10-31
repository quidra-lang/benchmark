sealed record Relaxed(long Value, List<int> Plan, List<int> Helpful);
static class Heuristics
{
    public const long Infinity = 1_000_000_000_000;
    static long Aggregate(IEnumerable<long> input, bool maximum)
    {
        List<long> values = input.ToList();
        return values.Any(v => v >= Infinity) ? Infinity : maximum ? values.DefaultIfEmpty(0).Max() : values.Sum();
    }
    static long[] Costs(Grounding g, State state, bool maximum)
    {
        long[] costs = Enumerable.Repeat(Infinity, g.Facts.Count).ToArray();
        foreach (int fact in state) costs[fact] = 0;
        while (true)
        {
            bool changed = false;
            foreach (GroundAction action in g.Actions)
            {
                long previous = Aggregate(action.Pre.Select(p => costs[p]), maximum);
                if (previous >= Infinity) continue;
                long value = previous + action.Cost;
                foreach (int fact in action.Add) if (value < costs[fact]) {
                    costs[fact] = value;
                    changed = true;
                }
            }
            if (!changed) return costs;
        }
    }
    public static Relaxed Relax(Grounding g, State state)
    {
        long[] costs = Costs(g, state, false);
        if (g.Goals.Any(p => costs[p] >= Infinity)) return new Relaxed(Infinity, new(), new());
        int Achiever(int fact) => Enumerable.Range(0, g.Actions.Count).Where(i => g.Actions[i].Add.Contains(fact) && g.Actions[i].Pre.All(p => costs[p] < Infinity)).OrderBy(i => g.Actions[i].Cost + g.Actions[i].Pre.Sum(p => costs[p])).ThenBy(i => i).First();
        State chosen = new();
        List<int> pending = g.Goals.Except(state).Order().ToList();
        while (pending.Count > 0)
        {
            int fact = pending[^1];
            pending.RemoveAt(pending.Count - 1);
            int action = Achiever(fact);
            if (chosen.Add(action)) pending.AddRange(g.Actions[action].Pre.Except(state).Order());
        }
        List<int> plan = chosen.Order().ToList();
        return new Relaxed(plan.Sum(i => (long)g.Actions[i].Cost), plan, plan.Where(i => Search.Applicable(g.Actions[i], state)).ToList());
    }
    public static State? Landmarks(Grounding g, State state)
    {
        int[] factLevel = Enumerable.Repeat(int.MaxValue, g.Facts.Count).ToArray(), actionLevel = Enumerable.Repeat(int.MaxValue, g.Actions.Count).ToArray();
        foreach (int fact in state) factLevel[fact] = 0;
        for (int k = 0; ; k++)
        {
            bool added = false;
            for (int i = 0; i < g.Actions.Count; i++) if (actionLevel[i] == int.MaxValue && g.Actions[i].Pre.All(p => factLevel[p] <= k))
            {
                actionLevel[i] = k;
                foreach (int fact in g.Actions[i].Add) if (factLevel[fact] == int.MaxValue) {
                    factLevel[fact] = k + 1;
                    added = true;
                }
            }
            if (!added) break;
        }
        if (g.Goals.Any(p => factLevel[p] == int.MaxValue)) return null;
        State landmarks = g.Goals.Except(state).ToHashSet();
        while (true)
        {
            int before = landmarks.Count;
            foreach (int fact in landmarks.Order().ToArray())
            {
                int[] achievers = Enumerable.Range(0, g.Actions.Count).Where(i => actionLevel[i] != int.MaxValue && actionLevel[i] + 1 == factLevel[fact] && g.Actions[i].Add.Contains(fact)).ToArray();
                State candidates = new(g.Actions[achievers[0]].Pre);
                foreach (int i in achievers.Skip(1)) candidates.IntersectWith(g.Actions[i].Pre);
                foreach (int candidate in candidates.Except(state).Order()) if (!landmarks.Contains(candidate))
                {
                    State reachable = new(state);
                    while (true)
                    {
                        int old = reachable.Count;
                        foreach (GroundAction a in g.Actions) if (!a.Add.Contains(candidate) && a.Pre.IsSubsetOf(reachable)) reachable.UnionWith(a.Add);
                        if (old == reachable.Count) break;
                    }
                    if (!g.Goals.IsSubsetOf(reachable)) landmarks.Add(candidate);
                }
            }
            if (before == landmarks.Count) return landmarks;
        }
    }
    public static long Value(Grounding g, State state, string name)
    {
        if (name == "none") return 0;
        if (name == "goalcount") return g.Goals.Except(state).Count();
        if (name is "hmax" or "hadd")
        {
            bool maximum = name == "hmax";
            long[] costs = Costs(g, state, maximum);
            return Aggregate(g.Goals.Select(p => costs[p]), maximum);
        }
        if (name == "ff") return Relax(g, state).Value;
        State? landmarks = Landmarks(g, state);
        return landmarks is null ? Infinity : landmarks.Count;
    }
    public static List<long> Values(Grounding g, State state) => new[] {
        "goalcount", "hmax", "hadd", "ff", "lmcount"
    }.Select(h => Value(g, state, h)).ToList();
}
