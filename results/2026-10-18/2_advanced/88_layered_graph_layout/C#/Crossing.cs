sealed record Segment(int P, int Q, int Edge);
static class Crossing
{
    public static int[] Positions(Order order, int n)
    {
        int[] positions = new int[n];
        foreach (List<int> row in order) for (int i = 0; i < row.Count; i++) positions[row[i]] = i;
        return positions;
    }
    public static int Count(List<Segment> segments, int[] positions, int width)
    {
        var pairs = segments.Select(s => (P: positions[s.P], Q: positions[s.Q])).OrderBy(p => p.P).ThenBy(p => p.Q);
        int c = 1, count = 0;
        while (c < width) c *= 2;
        int[] tree = new int[2 * c - 1];
        foreach (var (_, q) in pairs)
        {
            int k = q + c - 1;
            tree[k]++;
            while (k > 0) {
                if (k % 2 == 1) count += tree[k + 1];
                k = (k - 1) / 2;
                tree[k]++;
            }
        }
        return count;
    }
    public static bool Crosses(Segment a, Segment b, int[] positions) => positions[a.P] < positions[b.P] && positions[a.Q] > positions[b.Q] || positions[a.P] > positions[b.P] && positions[a.Q] < positions[b.Q];
    public static int Brute(List<Segment> segments, int[] positions)
    {
        int count = 0;
        for (int i = 0; i < segments.Count; i++) for (int j = i + 1; j < segments.Count; j++) if (Crosses(segments[i], segments[j], positions)) count++;
        return count;
    }
    public static int Total(List<List<Segment>> gaps, Order order, int n)
    {
        int[] positions = Positions(order, n);
        return gaps.Select((g, i) => Count(g, positions, order[i + 1].Count)).Sum();
    }
    public static int Adjacent(int v, int w, Order upper, Order lower, int[] positions) => upper[v].Sum(a => upper[w].Count(b => positions[a] > positions[b])) + lower[v].Sum(a => lower[w].Count(b => positions[a] > positions[b]));
}
