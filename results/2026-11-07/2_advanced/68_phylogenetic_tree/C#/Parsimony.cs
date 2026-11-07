using System;
using System.Collections.Generic;
using System.Linq;
using System.Numerics;
using System.Text;
public static class Parsimony {
    public record MergeResult(int set, int changes);
    public record ProvisionalResult(int[] sets, int changes);
    public record Branch(int mask, int first, int second);
    public record Candidate(int mask, int swap, TreeBuilding.Tree tree);
    public record Ends(int first, int second) {
        public static Ends Of(int a, int b) => new(Math.Min(a, b), Math.Max(a, b));
    }
    public record Reconstruction(Dictionary<int, string> ancestors,
                                 Dictionary<Ends, int> branchChanges, int[] siteChanges);
    public static MergeResult Merge(int a, int b) {
        int common = a & b;
        return common != 0 ? new(common, 0) : new(a | b, 1);
    }
    public static ProvisionalResult Provisional(TreeBuilding.Rooted rooted, int[] pattern) {
        int[] sets = new int[rooted.tree.nextNode];
        int changes = 0;
        for (int i = rooted.order.Count - 1; i >= 0; i--) {
            int node = rooted.order[i];
            if (node < rooted.tree.size)
                sets[node] = pattern[node];
            else {
                List<int> children = new(rooted.children[node]);
                children.Remove(rooted.outgroup);
                MergeResult m = Merge(sets[children[0]], sets[children[1]]);
                sets[node] = m.set;
                changes += m.changes;
                if (node == rooted.root)
                    changes += Merge(sets[node], sets[rooted.outgroup]).changes;
            }
        }
        return new(sets, changes);
    }
    public static int[] PatternScores(TreeBuilding.Tree tree, Alignment.Patterns patterns,
                                      int outgroup) {
        TreeBuilding.Rooted rooted = tree.Rooted(outgroup);
        int[] scores = new int[patterns.patterns.Count];
        for (int i = 0; i < scores.Length; i++)
            scores[i] = Provisional(rooted, patterns.encoded[i]).changes;
        return scores;
    }
    public static int Score(TreeBuilding.Tree tree, Alignment.Patterns patterns, int outgroup) {
        int[] scores = PatternScores(tree, patterns, outgroup);
        int total = 0;
        for (int i = 0; i < scores.Length; i++)
            total += scores[i] * patterns.weights[i];
        return total;
    }
    public static Reconstruction Reconstruct(TreeBuilding.Tree tree, Alignment.Patterns patterns,
                                             int outgroup) {
        TreeBuilding.Rooted rooted = tree.Rooted(outgroup);
        Dictionary<int, StringBuilder> statesByPattern = new();
        foreach (int node in tree.Internals())
            statesByPattern[node] = new();
        Dictionary<Ends, int> branchChanges = new();
        foreach (TreeBuilding.Edge e in tree.Edges())
            branchChanges[Ends.Of(e.first, e.second)] = 0;
        int[] scores = new int[patterns.patterns.Count];
        for (int i = 0; i < scores.Length; i++) {
            ProvisionalResult p = Provisional(rooted, patterns.encoded[i]);
            int[] sets = p.sets, states = new int[tree.nextNode];
            scores[i] = p.changes;
            int combined = Merge(sets[rooted.root], sets[outgroup]).set,
                first = combined & -combined;
            foreach (int node in new[] { rooted.root, outgroup })
                states[node] = (sets[node] & first) != 0 ? first : sets[node] & -sets[node];
            foreach (int node in rooted.order)
                if (node != rooted.root && node != outgroup) {
                    int parent = states[rooted.parents[node]];
                    states[node] = (sets[node] & parent) != 0 ? parent : sets[node] & -sets[node];
                }
            foreach (int node in tree.Internals())
                statesByPattern[node].Append(
                    Alignment.BASES[BitOperations.TrailingZeroCount((uint)states[node])]);
            foreach (Ends edge in branchChanges.Keys.ToList())
                if (states[edge.first] != states[edge.second])
                    branchChanges[edge] += patterns.weights[i];
        }
        Dictionary<int, string> ancestors = new();
        foreach (var e in statesByPattern) {
            StringBuilder sequence = new();
            foreach (int index in patterns.columns)
                sequence.Append(e.Value[index]);
            ancestors[e.Key] = sequence.ToString();
        }
        int[] sites = new int[patterns.columns.Length];
        for (int i = 0; i < sites.Length; i++)
            sites[i] = scores[patterns.columns[i]];
        return new(ancestors, branchChanges, sites);
    }
    public static List<Branch> Branches(TreeBuilding.Tree tree, int outgroup) {
        TreeBuilding.Rooted rooted = tree.Rooted(outgroup);
        List<Branch> result = new();
        foreach (int child in rooted.order)
            if (child != rooted.root)
                result.Add(new(child == outgroup ? rooted.ingroup : rooted.masks[child],
                               rooted.parents[child], child));
        result.Sort((a, b) => a.mask.CompareTo(b.mask));
        return result;
    }
    public static TreeBuilding.Tree Insert(TreeBuilding.Tree tree, int first, int second,
                                           int taxon) {
        TreeBuilding.Tree result = tree.Copy();
        result.Disconnect(first, second);
        int node = result.Internal();
        result.Connect(first, node);
        result.Connect(second, node);
        result.Connect(taxon, node);
        return result;
    }
    public static List<Candidate> Nni(TreeBuilding.Tree tree, int outgroup) {
        TreeBuilding.Rooted rooted = tree.Rooted(outgroup);
        List<Candidate> result = new();
        foreach (Branch edge in Branches(tree, outgroup)) {
            int u = edge.first, v = edge.second;
            if (u < tree.size || v < tree.size)
                continue;
            int sibling = -1;
            foreach (int child in rooted.children[u])
                if (child != v && child != outgroup)
                    sibling = child;
            List<int> children = new(rooted.children[v]);
            children.Sort((a, b) => rooted.masks[a].CompareTo(rooted.masks[b]));
            for (int i = 0; i < children.Count; i++) {
                int child = children[i];
                TreeBuilding.Tree candidate = tree.Copy();
                double a = candidate.Disconnect(u, sibling), b = candidate.Disconnect(v, child);
                candidate.Connect(u, child, b);
                candidate.Connect(v, sibling, a);
                result.Add(new(edge.mask, i + 1, candidate));
            }
        }
        return result;
    }
}
