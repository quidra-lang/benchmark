import java.nio.file.*;
import java.util.*;
final class TreeIo {
    static String real(double value, int places) {
        String text = String.format(Locale.ROOT, "%." + places + "f", value);
        return text.startsWith("-") && Double.parseDouble(text) == 0 ? text.substring(1) : text;
    }
    static String symbols(int mask, int count) {
        StringBuilder text = new StringBuilder();
        for (int t = 0; t < count; t++)
            text.append((mask & (1 << t)) != 0 ? '*' : '.');
        return text.toString();
    }
    static List<List<Integer>> childOrder(TreeBuilding.Rooted rooted, List<String> names) {
        String[] minimum = new String[rooted.tree.nextNode];
        List<List<Integer>> children = new ArrayList<>();
        for (int i = 0; i < minimum.length; i++)
            children.add(new ArrayList<>());
        for (int i = rooted.order.size() - 1; i >= 0; i--) {
            int node = rooted.order.get(i);
            if (node < rooted.tree.size)
                minimum[node] = names.get(node);
            else {
                children.get(node).addAll(rooted.children.get(node));
                children.get(node).sort(Comparator.comparing(child -> minimum[child]));
                minimum[node] = minimum[children.get(node).getFirst()];
            }
        }
        return children;
    }
    static String nodeText(int node, TreeBuilding.Rooted rooted, List<List<Integer>> children,
                           List<String> names, boolean lengths, Map<Integer, Integer> support) {
        String text;
        if (node < rooted.tree.size)
            text = names.get(node);
        else {
            List<String> parts = new ArrayList<>();
            for (int child : children.get(node))
                parts.add(nodeText(child, rooted, children, names, lengths, support));
            text = "(" + String.join(",", parts) + ")";
            if (support != null && node != rooted.root)
                text += support.getOrDefault(rooted.masks[node], 0);
        }
        if (lengths && node != rooted.root)
            text += ":" + real(rooted.tree.adjacent.get(node).get(rooted.parents[node]), 5);
        return text;
    }
    static String newick(TreeBuilding.Tree tree, List<String> names, int outgroup, boolean lengths,
                         Map<Integer, Integer> support) {
        TreeBuilding.Rooted rooted = tree.rooted(outgroup);
        return nodeText(rooted.root, rooted, childOrder(rooted, names), names, lengths, support) +
            ";";
    }
    static String newick(TreeBuilding.Tree tree, List<String> names, int outgroup) {
        return newick(tree, names, outgroup, false, null);
    }
    static void descend(int node, String prefix, TreeBuilding.Rooted rooted,
                        List<List<Integer>> children, List<String> names,
                        Map<Integer, Integer> support, List<String> lines) {
        List<Integer> list = children.get(node);
        for (int i = 0; i < list.size(); i++) {
            int child = list.get(i);
            boolean last = i == list.size() - 1;
            String label = child < rooted.tree.size
                               ? names.get(child)
                               : "[" + support.getOrDefault(rooted.masks[child], 0) + "]";
            lines.add(prefix + (last ? "`-- " : "|-- ") + label);
            descend(child, prefix + (last ? "    " : "|   "), rooted, children, names, support,
                    lines);
        }
    }
    static List<String> cladogram(TreeBuilding.Tree tree, List<String> names, int outgroup,
                                  Map<Integer, Integer> support) {
        TreeBuilding.Rooted rooted = tree.rooted(outgroup);
        List<String> lines = new ArrayList<>();
        lines.add("*");
        descend(rooted.root, "", rooted, childOrder(rooted, names), names, support, lines);
        return lines;
    }
    static void write(String name, List<String> lines) throws Exception {
        Files.createDirectories(Path.of("output"));
        Files.writeString(Path.of("output", name), String.join("\n", lines) + "\n");
    }
}
