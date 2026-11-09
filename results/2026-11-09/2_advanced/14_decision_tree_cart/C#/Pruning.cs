#nullable enable
using System;
using System.Linq;
using System.Collections.Generic;

sealed record Decision(Node Node, int Rows, int LeafError, int SubtreeError, bool Pruned);
sealed record PruningResult(PrunedTree Tree, List<Decision> Decisions);
sealed record SequenceTree(Fraction Alpha, PrunedTree Tree);

static class Pruning
{
    public static PruningResult ReducedError(Node root, List<Row> rows)
    {
        var reached = new Dictionary<int, int[]>();
        var tree = new PrunedTree(root);
        foreach (Row row in rows)
            foreach (Node node in tree.Route(row).Path)
            {
                if (!reached.ContainsKey(node.Number)) reached[node.Number] = new int[2];
                reached[node.Number][0]++;
                if (node.Prediction != row.Label) reached[node.Number][1]++;
            }
        var decisions = new List<Decision>();
        var cut = new HashSet<int>();
        int Decide(Node node)
        {
            int[] tally = reached.GetValueOrDefault(node.Number) ?? new int[2];
            int leafError = tally[1];
            if (node.Split is null) return leafError;
            int subtreeError = Decide(node.Left) + Decide(node.Right);
            bool pruned = leafError <= subtreeError;
            decisions.Add(new Decision(node, tally[0], leafError, subtreeError, pruned));
            if (pruned) cut.Add(node.Number);
            return pruned ? leafError : subtreeError;
        }
        Decide(root);
        return new PruningResult(new PrunedTree(root, cut), decisions);
    }
    public static List<SequenceTree> CostComplexity(Node root)
    {
        var tree = new PrunedTree(root);
        var sequence = new List<SequenceTree> { new(new Fraction(0, 1), tree) };
        while (!tree.IsLeaf(root))
        {
            Fraction? alpha = null;
            var weakest = new HashSet<int>();
            foreach (Node node in tree.InternalNodes())
            {
                List<Node> leaves = tree.Leaves(node);
                var value = new Fraction(node.Errors - leaves.Sum(leaf => leaf.Errors), leaves.Count - 1);
                if (alpha is null || value.CompareTo(alpha.Value) < 0) { alpha = value; weakest.Clear(); weakest.Add(node.Number); }
                else if (value.CompareTo(alpha.Value) == 0) weakest.Add(node.Number);
            }
            var cut = tree.Cut.ToHashSet();
            cut.UnionWith(weakest);
            tree = new PrunedTree(root, cut);
            sequence.Add(new SequenceTree(alpha!.Value, tree));
        }
        return sequence;
    }
}
