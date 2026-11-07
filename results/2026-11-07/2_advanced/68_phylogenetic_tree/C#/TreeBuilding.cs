using System;
using System.Collections.Generic;
using System.Linq;
public static class TreeBuilding {
    public record Edge(int first, int second, double length);
    public sealed class Tree {
        public int size, nextNode, negative;
        public List<SortedDictionary<int, double>> adjacent = new();
        public Tree(int size, List<int> taxa) {
            this.size = size;
            nextNode = size;
            for (int i = 0; i < 2 * size + 1; i++)
                adjacent.Add(new());
        }
        public int Internal() => nextNode++;
        public void Connect(int a, int b, double length = 0) {
            adjacent[a][b] = length;
            adjacent[b][a] = length;
        }
        public double Disconnect(int a, int b) {
            double value = adjacent[a][b];
            adjacent[a].Remove(b);
            adjacent[b].Remove(a);
            return value;
        }
        public Tree Copy() {
            Tree copy = new(size, new());
            copy.nextNode = nextNode;
            copy.negative = negative;
            for (int i = 0; i < adjacent.Count; i++)
                foreach (var e in adjacent[i])
                    copy.adjacent[i][e.Key] = e.Value;
            return copy;
        }
        public List<int>
        Taxa() => Enumerable.Range(0, size).Where(i => adjacent[i].Count != 0).ToList();
        public List<int> Internals() => Enumerable.Range(size, nextNode - size).ToList();
        public List<Edge> Edges() {
            List<Edge> result = new();
            for (int a = 0; a < nextNode; a++)
                foreach (var e in adjacent[a])
                    if (a < e.Key)
                        result.Add(new(a, e.Key, e.Value));
            return result;
        }
        public Rooted Rooted(int outgroup) => new(this, outgroup);
    }
    public sealed class Rooted {
        public Tree tree;
        public int outgroup, root, ingroup;
        public int[] parents, masks;
        public List<List<int>> children = new();
        public List<int> order = new();
        public Rooted(Tree tree, int outgroup) {
            this.tree = tree;
            this.outgroup = outgroup;
            root = tree.adjacent[outgroup].First().Key;
            parents = new int[tree.nextNode];
            masks = new int[tree.nextNode];
            Array.Fill(parents, -1);
            for (int i = 0; i < tree.nextNode; i++)
                children.Add(new());
            Visit(root, -1);
            ingroup = masks[root] ^ (1 << outgroup);
        }
        public void Visit(int node, int parent) {
            parents[node] = parent;
            order.Add(node);
            int mask = node < tree.size ? 1 << node : 0;
            foreach (int child in tree.adjacent[node].Keys)
                if (child != parent) {
                    children[node].Add(child);
                    Visit(child, node);
                    mask |= masks[child];
                }
            masks[node] = mask;
        }
        public HashSet<int> Splits() {
            HashSet<int> result = new();
            foreach (int node in tree.Internals())
                if (node != root)
                    result.Add(masks[node]);
            return result;
        }
        public Dictionary<int, double> BranchLengths() {
            Dictionary<int, double> result = new();
            foreach (int node in order)
                if (node != root)
                    result[node == outgroup ? ingroup : masks[node]] =
                        tree.adjacent[node][parents[node]];
            return result;
        }
    }
    public static Tree Star(int size, List<int> taxa) {
        Tree tree = new(size, taxa);
        int root = tree.Internal();
        foreach (int t in taxa)
            tree.Connect(root, t);
        return tree;
    }
    public static Tree Nj(double[][] matrix, List<int> taxa) {
        List<int> active = new(taxa);
        Tree tree = new(matrix.Length, taxa);
        double[][] distances = Enumerable.Range(0, 2 * matrix.Length + 1)
                                   .Select(
                                       _ => new double[2 * matrix.Length + 1])
                                   .ToArray();
        foreach (int i in taxa)
            foreach (int j in taxa)
                distances[i][j] = matrix[i][j];
        while (active.Count >= 4) {
            int r = active.Count;
            double[] totals = new double[distances.Length];
            foreach (int x in active)
                foreach (int y in active)
                    if (x != y)
                        totals[x] += distances[x][y];
            double best = double.PositiveInfinity;
            int first = -1, second = -1;
            for (int i = 0; i < r; i++)
                for (int j = i + 1; j < r; j++) {
                    int x = active[i], y = active[j];
                    double q = (r - 2) * distances[x][y] - totals[x] - totals[y];
                    if (q < best) {
                        best = q;
                        first = x;
                        second = y;
                    }
                }
            int node = tree.Internal();
            double d = distances[first][second],
                   left = d / 2 + (totals[first] - totals[second]) / (2 * (r - 2));
            tree.Connect(first, node, left);
            tree.Connect(second, node, d - left);
            List<int> remaining = new();
            foreach (int k in active)
                if (k != first && k != second) {
                    remaining.Add(k);
                    distances[node][k] = distances[k][node] =
                        (distances[first][k] + distances[second][k] - d) / 2;
                }
            remaining.Add(node);
            active = remaining;
        }
        int a = active[0], b = active[1], c = active[2], u = tree.Internal();
        double ab = distances[a][b], ac = distances[a][c], bc = distances[b][c];
        tree.Connect(a, u, (ab + ac - bc) / 2);
        tree.Connect(b, u, (ab + bc - ac) / 2);
        tree.Connect(c, u, (ac + bc - ab) / 2);
        foreach (Edge edge in tree.Edges())
            if (edge.length < 0) {
                tree.Connect(edge.first, edge.second, 0);
                tree.negative++;
            }
        return tree;
    }
    public static void Paths(Tree tree, int node, int parent, bool unit, double[] distances) {
        foreach (var e in tree.adjacent[node])
            if (e.Key != parent) {
                distances[e.Key] = distances[node] + (unit ? 1 : e.Value);
                Paths(tree, e.Key, node, unit, distances);
            }
    }
    public static double[] Paths(Tree tree, int start, bool unit) {
        double[] result = new double[tree.nextNode];
        Paths(tree, start, -1, unit, result);
        return result;
    }
    public static double[][] Patristic(Tree tree) {
        double[][] result = Enumerable.Range(0, tree.size)
                                .Select(
                                    _ => new double[tree.size])
                                .ToArray();
        List<int> taxa = tree.Taxa();
        for (int i = 0; i < taxa.Count; i++) {
            int first = taxa[i];
            double[] paths = Paths(tree, first, false);
            for (int j = i + 1; j < taxa.Count; j++) {
                int second = taxa[j];
                result[first][second] = result[second][first] = paths[second];
            }
        }
        return result;
    }
}
