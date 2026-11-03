record Neighbor(double Distance, Row Row);
record Vote(string Label, double Share, string? Runner, double RunnerShare);
static class Neighbors
{
    public static double Distance(double[] a, double[] b, string metric)
    {
        double total = 0, first = 0, second = 0;
        for (int j = 0; j < a.Length; j++)
        {
            double delta = a[j] - b[j];
            if (metric == "squared_euclidean") total += delta * delta;
            else if (metric == "manhattan") total += Math.Abs(delta);
            else if (metric == "chebyshev") total = Math.Max(total, Math.Abs(delta));
            else { total += a[j] * b[j]; first += a[j] * a[j]; second += b[j] * b[j]; }
        }
        if (metric != "cosine") return total;
        double na = Math.Sqrt(first), nb = Math.Sqrt(second); return na == 0 || nb == 0 ? 1 : 1 - total / (na * nb);
    }
    public static List<Neighbor> Order(double[] query, List<(double[] Vector, Row Row)> references, string metric) => references.Select(reference => new Neighbor(Distance(query, reference.Vector, metric), reference.Row)).OrderBy(neighbor => neighbor.Distance).ThenBy(neighbor => neighbor.Row.Id, StringComparer.Ordinal).ToList();
    sealed class Tally(string label)
    {
        public string Label = label;
        public int Count;
        public double Distances, Weights;
    }
    public static Vote Vote(List<Neighbor> nearest, string weighting)
    {
        Dictionary<string, Tally> tallies = new(StringComparer.Ordinal); double total = 0;
        foreach (Neighbor neighbor in nearest)
        {
            double weight = 1 / (neighbor.Distance + 0.000000001); string label = neighbor.Row.Label!;
            if (!tallies.TryGetValue(label, out Tally? tally)) tallies[label] = tally = new(label);
            tally.Count++; tally.Distances += neighbor.Distance; tally.Weights += weight; total += weight;
        }
        List<Tally> ranked = tallies.Values.ToList();
        ranked.Sort((a, b) => {
            int comparison = weighting == "uniform" ? b.Count.CompareTo(a.Count) : b.Weights.CompareTo(a.Weights);
            if (comparison == 0) comparison = a.Distances.CompareTo(b.Distances);
            return comparison == 0 ? StringComparer.Ordinal.Compare(a.Label, b.Label) : comparison;
        });
        double Share(Tally tally) => weighting == "uniform" ? (double)tally.Count / nearest.Count : tally.Weights / total;
        return new(ranked[0].Label, Share(ranked[0]), ranked.Count == 1 ? null : ranked[1].Label, ranked.Count == 1 ? 0 : Share(ranked[1]));
    }
    public static double Estimate(List<Neighbor> nearest, string weighting)
    {
        double total = 0, weights = 0;
        foreach (Neighbor neighbor in nearest)
        {
            if (weighting == "uniform") total += neighbor.Row.Target!.Value;
            else { double weight = 1 / (neighbor.Distance + 0.000000001); total += weight * neighbor.Row.Target!.Value; weights += weight; }
        }
        return weighting == "uniform" ? total / nearest.Count : total / weights;
    }
}
