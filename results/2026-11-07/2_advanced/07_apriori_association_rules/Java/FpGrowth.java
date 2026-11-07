import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.Deque;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;

record PatternBase(List<String> items, long weight) {}
final class FpNode {
    final String item;
    final FpNode parent;
    long count;
    final Map<String, FpNode> children = new HashMap<>();
    FpNode(String item, FpNode parent) { this.item = item; this.parent = parent; }
}
final class FpTree {
    final List<String> header;
    final FpNode root = new FpNode("", null);
    final Map<String, List<FpNode>> links = new HashMap<>();
    int nodes;
    FpTree(List<PatternBase> patterns, long minimum) {
        Map<String, Long> counts = new HashMap<>();
        for (PatternBase pattern : patterns) for (String item : pattern.items()) counts.merge(item, pattern.weight(), Long::sum);
        header = counts.keySet().stream().filter(item -> counts.get(item) >= minimum).sorted(Comparator.<String>comparingLong(counts::get).reversed().thenComparing(Comparator.naturalOrder())).toList();
        Map<String, Integer> order = new HashMap<>();
        for (int j = 0; j < header.size(); j++) { order.put(header.get(j), j); links.put(header.get(j), new ArrayList<>()); }
        for (PatternBase pattern : patterns) {
            FpNode node = root;
            for (String item : pattern.items().stream().filter(order::containsKey).sorted(Comparator.comparingInt(order::get)).toList()) {
                FpNode child = node.children.get(item);
                if (child == null) { child = new FpNode(item, node); node.children.put(item, child); links.get(item).add(child); nodes++; }
                child.count += pattern.weight(); node = child;
            }
        }
    }
    long support(String item) { return links.get(item).stream().mapToLong(node -> node.count).sum(); }
    List<PatternBase> conditional(String item) {
        List<PatternBase> base = new ArrayList<>();
        for (FpNode node : links.get(item)) {
            List<String> path = new ArrayList<>();
            for (FpNode parent = node.parent; parent != root; parent = parent.parent) path.addFirst(parent.item);
            base.add(new PatternBase(path, node.count));
        }
        return base;
    }
}
final class GrowthResult {
    final int header, nodes;
    int conditionalTrees, conditionalNodes;
    final Map<Itemset, Long> itemsets = new TreeMap<>();
    GrowthResult(int header, int nodes) { this.header = header; this.nodes = nodes; }
}
final class FpGrowth {
    private record Work(FpTree tree, Itemset suffix) {}
    static GrowthResult run(List<Itemset> baskets, long minimum, int maximum) {
        FpTree whole = new FpTree(baskets.stream().map(basket -> new PatternBase(basket.items(), 1)).toList(), minimum);
        GrowthResult result = new GrowthResult(whole.header.size(), whole.nodes);
        Deque<Work> stack = new ArrayDeque<>(); stack.push(new Work(whole, Itemset.empty()));
        while (!stack.isEmpty()) {
            Work current = stack.pop();
            for (String item : current.tree.header.reversed()) {
                Itemset suffix = current.suffix.union(Itemset.of(item)); result.itemsets.put(suffix, current.tree.support(item));
                if (suffix.size() < maximum) {
                    FpTree conditional = new FpTree(current.tree.conditional(item), minimum);
                    if (conditional.nodes > 0) { result.conditionalTrees++; result.conditionalNodes += conditional.nodes; stack.push(new Work(conditional, suffix)); }
                }
            }
        }
        return result;
    }
}
