sealed record Promotion(int Round, int Vertex, int Diff);
sealed record Layering(int[] Heights, int[] Labels, int Before, int Rounds, List<Promotion> Promotions);
static class AcyclicLayering
{
    public static int LexCompare(List<int> a, List<int> b)
    {
        for (int i = 0; i < Math.Min(a.Count, b.Count); i++) if (a[i] != b[i]) return a[i].CompareTo(b[i]);
        return a.Count.CompareTo(b.Count);
    }
    public static List<int> Sequence(int n, List<Edge> edges)
    {
        HashSet<int> remaining = Enumerable.Range(0, n).ToHashSet();
        List<int> head = new(), tail = new();
        while (remaining.Count > 0)
        {
            var degrees = remaining.Order().Select(v => (Vertex: v, Out: edges.Count(e => e.A == v && remaining.Contains(e.B)), In: edges.Count(e => e.B == v && remaining.Contains(e.A)))).ToList();
            int chosen;
            var sinks = degrees.Where(d => d.Out == 0).ToList();
            var sources = degrees.Where(d => d.In == 0).ToList();
            if (sinks.Count > 0) {
                chosen = sinks[0].Vertex;
                tail.Insert(0, chosen);
            }
            else if (sources.Count > 0) {
                chosen = sources[0].Vertex;
                head.Add(chosen);
            }
            else {
                chosen = degrees.OrderByDescending(d => d.Out - d.In).ThenBy(d => d.Vertex).First().Vertex;
                head.Add(chosen);
            }
            remaining.Remove(chosen);
        }
        return head.Concat(tail).ToList();
    }
    public static Layering Assign(int n, List<Edge> edges, bool coffman, int width, bool promotion)
    {
        Order upper = Enumerable.Range(0, n).Select(_ => new List<int>()).ToList(), lower = Enumerable.Range(0, n).Select(_ => new List<int>()).ToList();
        foreach (var (a, b) in edges) {
            upper[b].Add(a);
            lower[a].Add(b);
        }
        for (int i = 0; i < n; i++) {
            upper[i].Sort();
            lower[i].Sort();
        }
        int[] labels = new int[n], heights = Enumerable.Repeat(-1, n).ToArray();
        if (coffman)
        {
            for (int k = 1; k <= n; k++)
            {
                int chosen = Enumerable.Range(0, n).Where(v => labels[v] == 0 && upper[v].All(u => labels[u] > 0)).OrderBy(v => upper[v].Select(u => labels[u]).OrderDescending().ToList(), Comparer<List<int>>.Create(LexCompare)).ThenBy(v => v).First();
                labels[chosen] = k;
            }
            int current = 0, count = 0;
            for (int k = 0; k < n; k++)
            {
                int chosen = Enumerable.Range(0, n).Where(v => heights[v] < 0 && lower[v].All(u => heights[u] >= 0)).OrderByDescending(v => labels[v]).First();
                if (count == width || lower[chosen].Any(u => heights[u] == current)) {
                    current++;
                    count = 0;
                }
                heights[chosen] = current;
                count++;
            }
        }
        else
        {
            int Height(int v)
            {
                if (heights[v] >= 0) return heights[v];
                return heights[v] = lower[v].Select(u => Height(u) + 1).DefaultIfEmpty(0).Max();
            }
            for (int v = 0; v < n; v++) Height(v);
        }
        int before = edges.Sum(e => heights[e.A] - heights[e.B] - 1), rounds = 0;
        List<Promotion> promotions = new();
        if (promotion)
        {
            int Promote(int v)
            {
                int diff = 0;
                foreach (int u in upper[v]) if (heights[u] == heights[v] + 1) diff += Promote(u);
                heights[v]++;
                return diff + lower[v].Count - upper[v].Count;
            }
            while (true)
            {
                rounds++;
                bool changed = false;
                for (int v = 0; v < n; v++) if (upper[v].Count > 0)
                {
                    int[] saved = (int[])heights.Clone();
                    int diff = Promote(v);
                    if (diff < 0) {
                        promotions.Add(new Promotion(rounds, v, diff));
                        changed = true;
                    }
                    else heights = saved;
                }
                if (!changed) break;
            }
        }
        return new Layering(heights, labels, before, rounds, promotions);
    }
}
