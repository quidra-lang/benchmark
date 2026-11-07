import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

record Decision(Node node, int rows, int leafError, int subtreeError, boolean pruned) {}
record PruningResult(PrunedTree tree, List<Decision> decisions) {}
record SequenceTree(Fraction alpha, PrunedTree tree) {}

final class Pruning {
    static PruningResult reducedError(Node root, List<Row> rows) {
        Map<Integer, int[]> reached = new HashMap<>();
        PrunedTree tree = new PrunedTree(root);
        for (Row row : rows)
            for (Node node : tree.route(row).path()) {
                int[] tally = reached.computeIfAbsent(node.number, ignored -> new int[2]);
                tally[0]++;
                if (node.prediction != row.label()) tally[1]++;
            }
        List<Decision> decisions = new ArrayList<>();
        Set<Integer> cut = new HashSet<>();
        decide(root, reached, decisions, cut);
        return new PruningResult(new PrunedTree(root, cut), decisions);
    }
    static int decide(Node node, Map<Integer, int[]> reached, List<Decision> decisions, Set<Integer> cut) {
        int[] tally = reached.getOrDefault(node.number, new int[2]);
        int leafError = tally[1];
        if (node.split == null) return leafError;
        int subtreeError = decide(node.left, reached, decisions, cut) + decide(node.right, reached, decisions, cut);
        boolean pruned = leafError <= subtreeError;
        decisions.add(new Decision(node, tally[0], leafError, subtreeError, pruned));
        if (pruned) cut.add(node.number);
        return pruned ? leafError : subtreeError;
    }
    static List<SequenceTree> costComplexity(Node root) {
        PrunedTree tree = new PrunedTree(root);
        List<SequenceTree> sequence = new ArrayList<>(List.of(new SequenceTree(new Fraction(0, 1), tree)));
        while (!tree.isLeaf(root)) {
            Fraction alpha = null;
            Set<Integer> weakest = new HashSet<>();
            for (Node node : tree.internalNodes()) {
                List<Node> leaves = tree.leaves(node);
                Fraction value = new Fraction(node.errors - leaves.stream().mapToInt(leaf -> leaf.errors).sum(), leaves.size() - 1);
                if (alpha == null || value.compareTo(alpha) < 0) { alpha = value; weakest.clear(); weakest.add(node.number); }
                else if (value.compareTo(alpha) == 0) weakest.add(node.number);
            }
            Set<Integer> cut = new HashSet<>(tree.cut);
            cut.addAll(weakest);
            tree = new PrunedTree(root, cut);
            sequence.add(new SequenceTree(alpha, tree));
        }
        return sequence;
    }
}
