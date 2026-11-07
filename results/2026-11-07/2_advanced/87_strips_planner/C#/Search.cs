sealed class SearchResult(string status, List<int>? plan = null, int expanded = 0, int generated = 0)
{
    public string Status {
        get;
        set;
    } = status;
    public List<int> Plan {
        get;
        set;
    } = plan ?? new();
    public int Expanded {
        get;
        set;
    } = expanded;
    public int Generated {
        get;
        set;
    } = generated;
}
sealed record SearchNode(State State, long G, int Depth, int? Parent, int? Action);
static class Search
{
    public static bool Applicable(GroundAction action, State state) => action.Pre.IsSubsetOf(state) && !action.Neg.Overlaps(state);
    public static State Apply(GroundAction action, State state) => state.Except(action.Del).Concat(action.Add).ToHashSet();
    public static SearchResult Run(Grounding g, State start, string algorithm, string heuristic, int budget, int weight)
    {
        if (algorithm == "ehc") return Ehc(g, start, heuristic, budget);
        SearchResult result = new("exhausted");
        long initialH = Heuristics.Value(g, start, heuristic);
        if (initialH >= Heuristics.Infinity) {
            result.Status = "dead end";
            return result;
        }
        List<SearchNode> nodes = new() {
            new SearchNode(start, 0, 0, null, null)
        };
        PriorityQueue<int, (long F, long H, int Serial)> frontier = new();
        Dictionary<State, long> table = new(HashSet<int>.CreateSetComparer()) {
            [start] = 0
        };
        (long, long, int) Key(long cost, int depth, long h, int serial) => (algorithm switch {
            "bfs" => depth, "ucs" => cost, "gbfs" => h, "astar" => cost + h, _ => cost + weight * h
        }, h, serial);
        frontier.Enqueue(0, Key(0, 0, initialH, 0));
        while (frontier.TryDequeue(out int index, out _))
        {
            SearchNode node = nodes[index];
            State state = node.State;
            if (algorithm is "ucs" or "astar" or "wastar" && node.G > table[state]) continue;
            if (g.Goals.IsSubsetOf(state))
            {
                result.Status = "solved";
                int current = index;
                List<int> plan = new();
                while (nodes[current].Parent is {
                } parent) {
                    plan.Add(nodes[current].Action!.Value);
                    current = parent;
                }
                plan.Reverse();
                result.Plan = plan;
                return result;
            }
            if (result.Expanded == budget) {
                result.Status = "budget";
                return result;
            }
            result.Expanded++;
            for (int a = 0; a < g.Actions.Count; a++) if (Applicable(g.Actions[a], state))
            {
                result.Generated++;
                State next = Apply(g.Actions[a], state);
                long cost = node.G + g.Actions[a].Cost;
                if (table.TryGetValue(next, out long old) && (algorithm is "bfs" or "gbfs" || old <= cost)) continue;
                table[next] = cost;
                long h = Heuristics.Value(g, next, heuristic);
                if (h >= Heuristics.Infinity) continue;
                int serial = nodes.Count;
                nodes.Add(new SearchNode(next, cost, node.Depth + 1, index, a));
                frontier.Enqueue(serial, Key(cost, node.Depth + 1, h, serial));
            }
        }
        return result;
    }
    static SearchResult Ehc(Grounding g, State start, string heuristic, int budget)
    {
        SearchResult result = new("stuck");
        State current = start;
        long hc = Heuristics.Value(g, start, heuristic);
        if (hc >= Heuristics.Infinity) {
            result.Status = "dead end";
            return result;
        }
        while (true)
        {
            if (g.Goals.IsSubsetOf(current)) {
                result.Status = "solved";
                return result;
            }
            Queue<(State State, List<int> Path)> queue = new();
            queue.Enqueue((current, new()));
            HashSet<State> visited = new(HashSet<int>.CreateSetComparer()) {
                current
            };
            (State State, long H, List<int> Path)? improvement = null;
            while (queue.Count > 0 && improvement is null)
            {
                var (state, path) = queue.Dequeue();
                if (result.Expanded == budget) {
                    result.Status = "budget";
                    return result;
                }
                result.Expanded++;
                foreach (int action in Heuristics.Relax(g, state).Helpful)
                {
                    result.Generated++;
                    State next = Apply(g.Actions[action], state);
                    if (!visited.Add(next)) continue;
                    long h = Heuristics.Value(g, next, heuristic);
                    if (h >= Heuristics.Infinity) continue;
                    List<int> nextPath = path.Append(action).ToList();
                    if (h < hc) {
                        improvement = (next, h, nextPath);
                        break;
                    }
                    queue.Enqueue((next, nextPath));
                }
            }
            if (improvement is not {
            } found) return result;
            current = found.State;
            hc = found.H;
            result.Plan.AddRange(found.Path);
        }
    }
}
