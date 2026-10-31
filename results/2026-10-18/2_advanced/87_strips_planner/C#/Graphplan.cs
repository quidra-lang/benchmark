readonly record struct MutexPair
{
    public int A {
        get;
    }
    public int B {
        get;
    }
    public MutexPair(int a, int b) {
        A = Math.Min(a, b);
        B = Math.Max(a, b);
    }
}
sealed record GraphElement(int? Action, State Pre, State Add, State Del);
sealed record GraphLevel(List<GraphElement> Elements, HashSet<MutexPair> Mutex);
readonly record struct MemoKey(int Level, string Goals);
sealed class Extractor
{
    public List<GraphLevel> Levels {
        get;
    } = new();
    readonly HashSet<MemoKey> memo = new();
    public int Searched {
        get;
        private set;
    }
    public int Hits {
        get;
        private set;
    }
    public int Tried {
        get;
        private set;
    }
    public List<List<int>>? Extract(int level, List<int> goals)
    {
        if (level == 0) return new();
        MemoKey key = new(level, string.Join(",", goals));
        if (memo.Contains(key)) {
            Hits++;
            return null;
        }
        Searched++;
        List<List<int>>? result = Assign(level, goals, 0, new());
        if (result is null) memo.Add(key);
        return result;
    }
    List<List<int>>? Assign(int j, List<int> goals, int position, List<int> chosen)
    {
        GraphLevel level = Levels[j - 1];
        int k = position;
        while (k < goals.Count && chosen.Any(x => level.Elements[x].Add.Contains(goals[k]))) k++;
        if (k == goals.Count)
        {
            List<int> previous = chosen.SelectMany(x => level.Elements[x].Pre).Distinct().Order().ToList();
            List<List<int>>? plan = Extract(j - 1, previous);
            if (plan is null) return null;
            plan.Add(chosen.Where(x => level.Elements[x].Action is not null).Select(x => level.Elements[x].Action!.Value).Order().ToList());
            return plan;
        }
        int goal = goals[k];
        int[] achievers = Enumerable.Range(0, level.Elements.Count).Where(x => level.Elements[x].Add.Contains(goal)).OrderBy(x => level.Elements[x].Action is null ? 0 : 1).ThenBy(x => level.Elements[x].Action ?? 0).ToArray();
        foreach (int x in achievers) if (chosen.All(y => x == y || !level.Mutex.Contains(new MutexPair(x, y))))
        {
            Tried++;
            List<List<int>>? plan = Assign(j, goals, k + 1, chosen.Append(x).ToList());
            if (plan is not null) return plan;
        }
        return null;
    }
}
sealed record GraphResult(SearchResult Search, List<List<int>> Layers, List<string> Records, int Hits);
static class GraphPlan
{
    static bool Compatible(State pre, HashSet<MutexPair> mutex) => pre.All(p => pre.All(q => p == q || !mutex.Contains(new MutexPair(p, q))));
    public static GraphResult Run(List<GroundAction> actions, State initial, State goals, int limit)
    {
        Extractor extractor = new();
        State facts = initial;
        HashSet<MutexPair> mutex = new();
        (int Facts, int Mutex)? previous = null;
        List<string> records = new();
        List<List<int>> answer = new();
        string status = "level limit";
        for (int i = 0; i <= limit; i++)
        {
            records.Add($"fact level {i}: facts={facts.Count} mutexes={mutex.Count}");
            bool extract = goals.IsSubsetOf(facts) && Compatible(goals, mutex);
            if (extract)
            {
                int before = extractor.Searched, hits = extractor.Hits;
                List<List<int>>? result = extractor.Extract(i, goals.Order().ToList());
                records.Add($"extract level {i}: {(result is null ? "fail" : "success")} searched={extractor.Searched - before} memo_hits={extractor.Hits - hits}");
                if (result is not null) {
                    answer = result;
                    status = "solved";
                    break;
                }
            }
            else if (previous is { } old && old.Facts == facts.Count && old.Mutex == mutex.Count) {
                status = "unreachable";
                break;
            }
            if (i == limit) break;
            previous = (facts.Count, mutex.Count);
            List<GraphElement> elements = actions.Select((a, index) => (Action: a, Index: index)).Where(p => p.Action.Pre.IsSubsetOf(facts) && Compatible(p.Action.Pre, mutex)).Select(p => new GraphElement(p.Index, p.Action.Pre, p.Action.Add, p.Action.Del)).ToList();
            int real = elements.Count;
            foreach (int fact in facts.Order()) elements.Add(new GraphElement(null, new() {
                fact
            }, new() {
                fact
            }, new()));
            HashSet<MutexPair> actionMutex = new();
            for (int x = 0; x < elements.Count; x++) for (int y = x + 1; y < elements.Count; y++)
            {
                GraphElement a = elements[x], b = elements[y];
                bool interference = a.Del.Overlaps(b.Pre) || a.Del.Overlaps(b.Add) || b.Del.Overlaps(a.Pre) || b.Del.Overlaps(a.Add);
                bool competing = a.Pre.Any(p => b.Pre.Any(q => p != q && mutex.Contains(new MutexPair(p, q))));
                if (interference || competing) actionMutex.Add(new MutexPair(x, y));
            }
            records.Add($"action level {i}: actions={real} noops={facts.Count} mutexes={actionMutex.Count}");
            State next = elements.SelectMany(e => e.Add).ToHashSet();
            int[] values = next.Order().ToArray();
            HashSet<MutexPair> nextMutex = new();
            for (int x = 0; x < values.Length; x++) for (int y = x + 1; y < values.Length; y++)
            {
                int p = values[x], q = values[y];
                bool impossible = Enumerable.Range(0, elements.Count).Where(a => elements[a].Add.Contains(p)).All(a => Enumerable.Range(0, elements.Count).Where(b => elements[b].Add.Contains(q)).All(b => a != b && actionMutex.Contains(new MutexPair(a, b))));
                if (impossible) nextMutex.Add(new MutexPair(p, q));
            }
            extractor.Levels.Add(new GraphLevel(elements, actionMutex));
            facts = next;
            mutex = nextMutex;
        }
        return new GraphResult(new SearchResult(status, answer.SelectMany(l => l).ToList(), extractor.Searched, extractor.Tried), answer, records, extractor.Hits);
    }
}
