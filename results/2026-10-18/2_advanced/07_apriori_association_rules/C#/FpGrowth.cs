record PatternBase(string[] Items, long Weight);
sealed class FpNode(string item, FpNode? parent)
{
    public string Item = item;
    public FpNode? Parent = parent;
    public long Count;
    public Dictionary<string, FpNode> Children = new(StringComparer.Ordinal);
}
sealed class FpTree
{
    public List<string> Header;
    public FpNode Root = new("", null);
    public Dictionary<string, List<FpNode>> Links;
    public int Nodes;
    public FpTree(List<PatternBase> patterns, long minimum)
    {
        Dictionary<string, long> counts = new(StringComparer.Ordinal);
        foreach (PatternBase pattern in patterns) foreach (string item in pattern.Items) counts[item] = counts.GetValueOrDefault(item) + pattern.Weight;
        Header = counts.Keys.Where(item => counts[item] >= minimum).OrderByDescending(item => counts[item]).ThenBy(item => item, StringComparer.Ordinal).ToList();
        Dictionary<string, int> order = Header.Select((item, index) => (item, index)).ToDictionary(pair => pair.item, pair => pair.index, StringComparer.Ordinal);
        Links = Header.ToDictionary(item => item, _ => new List<FpNode>(), StringComparer.Ordinal);
        foreach (PatternBase pattern in patterns)
        {
            FpNode node = Root;
            foreach (string item in pattern.Items.Where(order.ContainsKey).OrderBy(item => order[item]))
            {
                if (!node.Children.TryGetValue(item, out FpNode? child))
                {
                    child = new(item, node); node.Children[item] = child; Links[item].Add(child); Nodes++;
                }
                child.Count += pattern.Weight; node = child;
            }
        }
    }
    public long Support(string item) => Links[item].Sum(node => node.Count);
    public List<PatternBase> Conditional(string item)
    {
        List<PatternBase> patterns = [];
        foreach (FpNode node in Links[item])
        {
            List<string> path = [];
            for (FpNode? parent = node.Parent; parent != Root; parent = parent!.Parent) path.Add(parent!.Item);
            path.Reverse(); patterns.Add(new(path.ToArray(), node.Count));
        }
        return patterns;
    }
}
sealed class GrowthResult(int header, int nodes)
{
    public int Header = header, Nodes = nodes, ConditionalTrees, ConditionalNodes;
    public Dictionary<Itemset, long> Itemsets = new();
}
static class FpGrowth
{
    public static GrowthResult Run(List<Itemset> baskets, long minimum, int maximum)
    {
        FpTree whole = new(baskets.Select(basket => new PatternBase(basket.Items, 1)).ToList(), minimum);
        GrowthResult result = new(whole.Header.Count, whole.Nodes);
        Stack<(FpTree Tree, Itemset Suffix)> stack = new(); stack.Push((whole, Itemset.Empty));
        while (stack.TryPop(out var current)) foreach (string item in current.Tree.Header.AsEnumerable().Reverse())
        {
            Itemset suffix = Itemset.Of(current.Suffix.Items.Append(item)); result.Itemsets[suffix] = current.Tree.Support(item);
            if (suffix.Size < maximum)
            {
                FpTree conditional = new(current.Tree.Conditional(item), minimum);
                if (conditional.Nodes > 0) { result.ConditionalTrees++; result.ConditionalNodes += conditional.Nodes; stack.Push((conditional, suffix)); }
            }
        }
        return result;
    }
}
