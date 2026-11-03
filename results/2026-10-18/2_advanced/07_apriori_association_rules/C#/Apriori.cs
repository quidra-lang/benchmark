record CandidateLevel(int Joined, int Excluded, int Pruned, List<Itemset> Itemsets);
static class Apriori
{
    public static List<Itemset> SmallerSubsets(Itemset itemset)
    {
        string[] items = itemset.Items;
        return Enumerable.Range(0, items.Length).Select(index => Itemset.Of(items.Where((_, j) => j != index))).ToList();
    }
    public static CandidateLevel Generate(List<Itemset> previous, int size, Dictionary<string, string>? taxonomy)
    {
        List<Itemset> ordered = previous.Order().ToList(), survivors = [];
        HashSet<Itemset> known = new(previous);
        int joined = 0, excluded = 0, pruned = 0;
        for (int i = 0; i < ordered.Count; i++) for (int j = i + 1; j < ordered.Count; j++)
        {
            string[] first = ordered[i].Items, second = ordered[j].Items;
            if (!first.Take(size - 2).SequenceEqual(second.Take(size - 2))) break;
            Itemset candidate = Itemset.Of(first.Append(second[^1])); joined++;
            if (taxonomy != null && size == 2 && ((taxonomy.TryGetValue(first[0], out string? category) && category == second[0]) || (taxonomy.TryGetValue(second[0], out category) && category == first[0]))) { excluded++; continue; }
            if (SmallerSubsets(candidate).Any(subset => !known.Contains(subset))) pruned++;
            else survivors.Add(candidate);
        }
        return new(joined, excluded, pruned, survivors);
    }
    public static long CountSupport(List<Itemset> baskets, Itemset itemset) => baskets.LongCount(basket => basket.Contains(itemset));
    public static Dictionary<Itemset, long> CountSupports(List<Itemset> baskets, List<Itemset> candidates)
    {
        Dictionary<Itemset, long> counts = candidates.Distinct().ToDictionary(itemset => itemset, _ => 0L);
        Dictionary<string, List<Itemset>> byFirst = counts.Keys.GroupBy(itemset => itemset.Items[0], StringComparer.Ordinal).ToDictionary(group => group.Key, group => group.ToList(), StringComparer.Ordinal);
        foreach (Itemset basket in baskets) foreach (string item in basket.Items)
            if (byFirst.TryGetValue(item, out List<Itemset>? found)) foreach (Itemset candidate in found) if (basket.Contains(candidate)) counts[candidate]++;
        return counts;
    }
}
