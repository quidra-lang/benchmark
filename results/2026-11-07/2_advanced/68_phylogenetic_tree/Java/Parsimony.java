import java.util.*;
final class Parsimony {
    record Merge(int set, int changes) {}
    record Provisional(int[] sets, int changes) {}
    record Branch(int mask, int first, int second) {}
    record Candidate(int mask, int swap, TreeBuilding.Tree tree) {}
    record Ends(int first, int second) {
        static Ends of(int a, int b) { return new Ends(Math.min(a, b), Math.max(a, b)); }
    }
    record Reconstruction(Map<Integer, String> ancestors, Map<Ends, Integer> branchChanges,
                          int[] siteChanges) {}
    static Merge merge(int a, int b) {
        int common = a & b;
        return common != 0 ? new Merge(common, 0) : new Merge(a | b, 1);
    }
    static Provisional provisional(TreeBuilding.Rooted rooted, int[] pattern) {
        int[] sets = new int[rooted.tree.nextNode];
        int changes = 0;
        for (int i = rooted.order.size() - 1; i >= 0; i--) {
            int node = rooted.order.get(i);
            if (node < rooted.tree.size)
                sets[node] = pattern[node];
            else {
                List<Integer> children = new ArrayList<>(rooted.children.get(node));
                children.remove(Integer.valueOf(rooted.outgroup));
                Merge m = merge(sets[children.get(0)], sets[children.get(1)]);
                sets[node] = m.set();
                changes += m.changes();
                if (node == rooted.root)
                    changes += merge(sets[node], sets[rooted.outgroup]).changes();
            }
        }
        return new Provisional(sets, changes);
    }
    static int[] patternScores(TreeBuilding.Tree tree, Alignment.Patterns patterns, int outgroup) {
        TreeBuilding.Rooted rooted = tree.rooted(outgroup);
        int[] scores = new int[patterns.patterns.size()];
        for (int i = 0; i < scores.length; i++)
            scores[i] = provisional(rooted, patterns.encoded.get(i)).changes();
        return scores;
    }
    static int score(TreeBuilding.Tree tree, Alignment.Patterns patterns, int outgroup) {
        int[] scores = patternScores(tree, patterns, outgroup);
        int total = 0;
        for (int i = 0; i < scores.length; i++)
            total += scores[i] * patterns.weights.get(i);
        return total;
    }
    static Reconstruction reconstruct(TreeBuilding.Tree tree, Alignment.Patterns patterns,
                                      int outgroup) {
        TreeBuilding.Rooted rooted = tree.rooted(outgroup);
        Map<Integer, StringBuilder> statesByPattern = new HashMap<>();
        for (int node : tree.internals())
            statesByPattern.put(node, new StringBuilder());
        Map<Ends, Integer> branchChanges = new HashMap<>();
        for (TreeBuilding.Edge edge : tree.edges())
            branchChanges.put(Ends.of(edge.first(), edge.second()), 0);
        int[] scores = new int[patterns.patterns.size()];
        for (int i = 0; i < scores.length; i++) {
            Provisional p = provisional(rooted, patterns.encoded.get(i));
            int[] sets = p.sets(), states = new int[tree.nextNode];
            scores[i] = p.changes();
            int combined = merge(sets[rooted.root], sets[outgroup]).set(), first =
                                                                               combined & -combined;
            for (int node : new int[] {rooted.root, outgroup})
                states[node] = (sets[node] & first) != 0 ? first : sets[node] & -sets[node];
            for (int node : rooted.order)
                if (node != rooted.root && node != outgroup) {
                    int parent = states[rooted.parents[node]];
                    states[node] = (sets[node] & parent) != 0 ? parent : sets[node] & -sets[node];
                }
            for (int node : tree.internals())
                statesByPattern.get(node).append(
                    Alignment.BASES.charAt(Integer.numberOfTrailingZeros(states[node])));
            for (var entry : branchChanges.entrySet())
                if (states[entry.getKey().first()] != states[entry.getKey().second()])
                    entry.setValue(entry.getValue() + patterns.weights.get(i));
        }
        Map<Integer, String> ancestors = new HashMap<>();
        for (var entry : statesByPattern.entrySet()) {
            StringBuilder sequence = new StringBuilder();
            for (int index : patterns.columns)
                sequence.append(entry.getValue().charAt(index));
            ancestors.put(entry.getKey(), sequence.toString());
        }
        int[] sites = new int[patterns.columns.length];
        for (int i = 0; i < sites.length; i++)
            sites[i] = scores[patterns.columns[i]];
        return new Reconstruction(ancestors, branchChanges, sites);
    }
    static List<Branch> branches(TreeBuilding.Tree tree, int outgroup) {
        TreeBuilding.Rooted rooted = tree.rooted(outgroup);
        List<Branch> result = new ArrayList<>();
        for (int child : rooted.order)
            if (child != rooted.root)
                result.add(new Branch(child == outgroup ? rooted.ingroup : rooted.masks[child],
                                      rooted.parents[child], child));
        result.sort(Comparator.comparingInt(Branch::mask));
        return result;
    }
    static TreeBuilding.Tree insert(TreeBuilding.Tree tree, int first, int second, int taxon) {
        TreeBuilding.Tree result = tree.copy();
        result.disconnect(first, second);
        int node = result.internal();
        result.connect(first, node);
        result.connect(second, node);
        result.connect(taxon, node);
        return result;
    }
    static List<Candidate> nni(TreeBuilding.Tree tree, int outgroup) {
        TreeBuilding.Rooted rooted = tree.rooted(outgroup);
        List<Candidate> result = new ArrayList<>();
        for (Branch edge : branches(tree, outgroup)) {
            int u = edge.first(), v = edge.second();
            if (u < tree.size || v < tree.size)
                continue;
            int sibling = -1;
            for (int child : rooted.children.get(u))
                if (child != v && child != outgroup)
                    sibling = child;
            List<Integer> children = new ArrayList<>(rooted.children.get(v));
            children.sort(Comparator.comparingInt(node -> rooted.masks[node]));
            for (int i = 0; i < children.size(); i++) {
                int child = children.get(i);
                TreeBuilding.Tree candidate = tree.copy();
                double a = candidate.disconnect(u, sibling), b = candidate.disconnect(v, child);
                candidate.connect(u, child, b);
                candidate.connect(v, sibling, a);
                result.add(new Candidate(edge.mask(), i + 1, candidate));
            }
        }
        return result;
    }
}
