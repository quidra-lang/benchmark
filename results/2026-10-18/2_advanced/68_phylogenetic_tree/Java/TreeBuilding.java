import java.util.*;
final class TreeBuilding {
    record Edge(int first, int second, double length) {}
    static final class Tree {
        int size, nextNode, negative;
        List<TreeMap<Integer, Double>> adjacent = new ArrayList<>();
        Tree(int size, List<Integer> taxa) {
            this.size = size;
            nextNode = size;
            for (int i = 0; i < 2 * size + 1; i++)
                adjacent.add(new TreeMap<>());
        }
        int internal() { return nextNode++; }
        void connect(int a, int b, double length) {
            adjacent.get(a).put(b, length);
            adjacent.get(b).put(a, length);
        }
        void connect(int a, int b) { connect(a, b, 0); }
        double disconnect(int a, int b) {
            double value = adjacent.get(a).remove(b);
            adjacent.get(b).remove(a);
            return value;
        }
        Tree copy() {
            Tree copy = new Tree(size, List.of());
            copy.nextNode = nextNode;
            copy.negative = negative;
            for (int i = 0; i < adjacent.size(); i++)
                copy.adjacent.get(i).putAll(adjacent.get(i));
            return copy;
        }
        List<Integer> taxa() {
            List<Integer> result = new ArrayList<>();
            for (int i = 0; i < size; i++)
                if (!adjacent.get(i).isEmpty())
                    result.add(i);
            return result;
        }
        List<Integer> internals() {
            List<Integer> result = new ArrayList<>();
            for (int i = size; i < nextNode; i++)
                result.add(i);
            return result;
        }
        List<Edge> edges() {
            List<Edge> result = new ArrayList<>();
            for (int a = 0; a < nextNode; a++)
                for (var entry : adjacent.get(a).entrySet())
                    if (a < entry.getKey())
                        result.add(new Edge(a, entry.getKey(), entry.getValue()));
            return result;
        }
        Rooted rooted(int outgroup) { return new Rooted(this, outgroup); }
    }
    static final class Rooted {
        Tree tree;
        int outgroup, root, ingroup;
        int[] parents, masks;
        List<List<Integer>> children = new ArrayList<>();
        List<Integer> order = new ArrayList<>();
        Rooted(Tree tree, int outgroup) {
            this.tree = tree;
            this.outgroup = outgroup;
            root = tree.adjacent.get(outgroup).firstKey();
            parents = new int[tree.nextNode];
            masks = new int[tree.nextNode];
            Arrays.fill(parents, -1);
            for (int i = 0; i < tree.nextNode; i++)
                children.add(new ArrayList<>());
            visit(root, -1);
            ingroup = masks[root] ^ (1 << outgroup);
        }
        void visit(int node, int parent) {
            parents[node] = parent;
            order.add(node);
            int mask = node < tree.size ? 1 << node : 0;
            for (int child : tree.adjacent.get(node).keySet())
                if (child != parent) {
                    children.get(node).add(child);
                    visit(child, node);
                    mask |= masks[child];
                }
            masks[node] = mask;
        }
        Set<Integer> splits() {
            Set<Integer> result = new HashSet<>();
            for (int node : tree.internals())
                if (node != root)
                    result.add(masks[node]);
            return result;
        }
        Map<Integer, Double> branchLengths() {
            Map<Integer, Double> result = new HashMap<>();
            for (int node : order)
                if (node != root)
                    result.put(node == outgroup ? ingroup : masks[node],
                               tree.adjacent.get(node).get(parents[node]));
            return result;
        }
    }
    static Tree star(int size, List<Integer> taxa) {
        Tree tree = new Tree(size, taxa);
        int root = tree.internal();
        for (int t : taxa)
            tree.connect(root, t);
        return tree;
    }
    static Tree nj(double[][] matrix, List<Integer> taxa) {
        List<Integer> active = new ArrayList<>(taxa);
        Tree tree = new Tree(matrix.length, taxa);
        double[][] distances = new double[2 * matrix.length + 1][2 * matrix.length + 1];
        for (int i : taxa)
            for (int j : taxa)
                distances[i][j] = matrix[i][j];
        while (active.size() >= 4) {
            int r = active.size();
            double[] totals = new double[distances.length];
            for (int a : active)
                for (int b : active)
                    if (a != b)
                        totals[a] += distances[a][b];
            double best = Double.POSITIVE_INFINITY;
            int first = -1, second = -1;
            for (int i = 0; i < r; i++)
                for (int j = i + 1; j < r; j++) {
                    int a = active.get(i), b = active.get(j);
                    double q = (r - 2) * distances[a][b] - totals[a] - totals[b];
                    if (q < best) {
                        best = q;
                        first = a;
                        second = b;
                    }
                }
            int u = tree.internal();
            double d = distances[first][second],
                   left = d / 2 + (totals[first] - totals[second]) / (2 * (r - 2));
            tree.connect(first, u, left);
            tree.connect(second, u, d - left);
            List<Integer> remaining = new ArrayList<>();
            for (int k : active)
                if (k != first && k != second) {
                    remaining.add(k);
                    distances[u][k] = distances[k][u] =
                        (distances[first][k] + distances[second][k] - d) / 2;
                }
            remaining.add(u);
            active = remaining;
        }
        int a = active.get(0), b = active.get(1), c = active.get(2), u = tree.internal();
        double ab = distances[a][b], ac = distances[a][c], bc = distances[b][c];
        tree.connect(a, u, (ab + ac - bc) / 2);
        tree.connect(b, u, (ab + bc - ac) / 2);
        tree.connect(c, u, (ac + bc - ab) / 2);
        for (Edge edge : tree.edges())
            if (edge.length() < 0) {
                tree.connect(edge.first(), edge.second(), 0);
                tree.negative++;
            }
        return tree;
    }
    static void paths(Tree tree, int node, int parent, boolean unit, double[] distances) {
        for (var entry : tree.adjacent.get(node).entrySet())
            if (entry.getKey() != parent) {
                distances[entry.getKey()] = distances[node] + (unit ? 1 : entry.getValue());
                paths(tree, entry.getKey(), node, unit, distances);
            }
    }
    static double[] paths(Tree tree, int start, boolean unit) {
        double[] result = new double[tree.nextNode];
        paths(tree, start, -1, unit, result);
        return result;
    }
    static double[][] patristic(Tree tree) {
        double[][] result = new double[tree.size][tree.size];
        List<Integer> taxa = tree.taxa();
        for (int i = 0; i < taxa.size(); i++) {
            int first = taxa.get(i);
            double[] paths = paths(tree, first, false);
            for (int j = i + 1; j < taxa.size(); j++) {
                int second = taxa.get(j);
                result[first][second] = result[second][first] = paths[second];
            }
        }
        return result;
    }
}
