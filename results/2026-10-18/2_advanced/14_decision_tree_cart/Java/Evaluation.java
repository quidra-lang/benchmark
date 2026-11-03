import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

record Step(Node node, boolean left, String method) {}
record Route(List<Node> path, List<Step> steps) { Node leaf() { return path.getLast(); } }

final class PrunedTree {
    final Node root;
    final Set<Integer> cut;
    PrunedTree(Node root) { this(root, Set.of()); }
    PrunedTree(Node root, Set<Integer> cut) { this.root = root; this.cut = new HashSet<>(cut); }
    boolean isLeaf(Node node) { return node.split == null || cut.contains(node.number); }
    List<Node> preorder() { return preorder(root); }
    List<Node> preorder(Node start) {
        List<Node> nodes = new ArrayList<>(), pending = new ArrayList<>(List.of(start));
        while (!pending.isEmpty()) {
            Node node = pending.removeLast();
            nodes.add(node);
            if (!isLeaf(node)) { pending.add(node.right); pending.add(node.left); }
        }
        return nodes;
    }
    List<Node> leaves() { return leaves(root); }
    List<Node> leaves(Node start) { return preorder(start).stream().filter(this::isLeaf).toList(); }
    List<Node> internalNodes() { return preorder().stream().filter(node -> !isLeaf(node)).toList(); }
    int depth() { return leaves().stream().mapToInt(node -> node.depth).max().orElseThrow(); }
    int trainingErrors() { return leaves().stream().mapToInt(node -> node.errors).sum(); }
    Route route(Row row) {
        Node node = root;
        List<Node> path = new ArrayList<>(List.of(node));
        List<Step> steps = new ArrayList<>();
        while (!isLeaf(node)) {
            boolean left = node.defaultLeft;
            String method = "default";
            int value = row.value(node.split.attribute());
            if (value >= 0) { left = node.split.goesLeft(value); method = "primary"; }
            else for (Surrogate surrogate : node.surrogates)
                if (row.value(surrogate.split().attribute()) >= 0) {
                    left = surrogate.goesLeft(row.value(surrogate.split().attribute()));
                    method = "surrogate";
                    break;
                }
            steps.add(new Step(node, left, method));
            node = left ? node.left : node.right;
            path.add(node);
        }
        return new Route(path, steps);
    }
    Node leafOf(Row row) { return route(row).leaf(); }
    int predict(Row row) { return leafOf(row).prediction; }
    int correct(List<Row> rows) { return (int) rows.stream().filter(row -> predict(row) == row.label()).count(); }
}

final class Evaluation {
    static String real(double value) { return real(value, 4); }
    static String real(double value, int places) {
        String text = String.format(Locale.ROOT, "%." + places + "f", value);
        return text.equals("-0." + "0".repeat(places)) ? text.substring(1) : text;
    }
    static String ratio(long numerator, long denominator) {
        return denominator == 0 ? "0/0 -" : numerator + "/" + denominator + " " + real((double) numerator / denominator);
    }
    static long gcd(long first, long second) {
        first = Math.abs(first);
        while (second != 0) { long next = first % second; first = second; second = next; }
        return first;
    }
    static String fraction(long numerator, long denominator) { return fraction(numerator, denominator, 4); }
    static String fraction(long numerator, long denominator, int places) {
        if (denominator == 0) return "- -";
        long divisor = gcd(numerator, denominator);
        return numerator / divisor + "/" + denominator / divisor + " " + real((double) numerator / denominator, places);
    }
    static List<String> classification(String title, List<String> classes, List<Row> rows, List<Integer> predictions) {
        int size = classes.size(), correct = 0;
        int[][] matrix = new int[size][size];
        for (int i = 0; i < rows.size(); i++) matrix[rows.get(i).label()][predictions.get(i)]++;
        for (int i = 0; i < size; i++) correct += matrix[i][i];
        List<String> lines = new ArrayList<>(List.of("confusion " + title + " correct " + correct + "/" + rows.size()
            + " accuracy " + fraction(correct, rows.size()), "actual\\predicted " + String.join(" ", classes)));
        for (int i = 0; i < size; i++) lines.add(classes.get(i) + " " + Main.countsText(matrix[i]));
        double total = 0;
        int available = 0;
        for (int i = 0; i < size; i++) {
            int hits = matrix[i][i], predicted = 0, support = Arrays.stream(matrix[i]).sum();
            for (int[] row : matrix) predicted += row[i];
            if (predicted + support > 0) { total += (double) (2 * hits) / (predicted + support); available++; }
            lines.add("class " + classes.get(i) + " precision " + fraction(hits, predicted) + " recall " + fraction(hits, support)
                + " f1 " + fraction(2 * hits, predicted + support) + " support " + support);
        }
        lines.add("macro_f1 " + real(total / available));
        return lines;
    }
}
