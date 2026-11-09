import java.util.*;

final class Agglomerative {
    record Merge(int a, int b, double height, int size) {}
    record Edge(int parent, int child, double weight) {}
    record Coefficients(double alphaA, double alphaB, double beta, double gamma) {}

    static Coefficients coefficients(String method, int a, int b, int k) {
        int merged = a + b, total = merged + k;
        return switch (method) {
            case "single" -> new Coefficients(0.5, 0.5, 0.0, -0.5);
            case "complete" -> new Coefficients(0.5, 0.5, 0.0, 0.5);
            case "average" -> new Coefficients((double) a / merged, (double) b / merged, 0.0, 0.0);
            case "weighted" -> new Coefficients(0.5, 0.5, 0.0, 0.0);
            case "centroid" -> new Coefficients((double) a / merged, (double) b / merged, (double) -(a * b) / (merged * merged), 0.0);
            case "median" -> new Coefficients(0.5, 0.5, -0.25, 0.0);
            default -> new Coefficients((double) (a + k) / total, (double) (b + k) / total, (double) -k / total, 0.0);
        };
    }

    static List<Merge> cluster(double[][] delta, String method) {
        int count = delta.length, capacity = 2 * count - 1;
        boolean squared = Set.of("centroid", "median", "ward").contains(method);
        double[][] values = new double[capacity][capacity];
        for (int u = 0; u < count; u++) for (int w = 0; w < count; w++) values[u][w] = squared ? delta[u][w] * delta[u][w] : delta[u][w];
        int[] sizes = new int[capacity]; Arrays.fill(sizes, 0, count, 1);
        List<Integer> active = new ArrayList<>(); for (int u = 0; u < count; u++) active.add(u);
        List<Merge> merges = new ArrayList<>();
        for (int step = 0; step < count - 1; step++) {
            int a = active.get(0), b = active.get(1);
            double best = values[a][b];
            for (int position = 0; position < active.size(); position++) for (int next = position + 1; next < active.size(); next++) {
                int first = active.get(position), second = active.get(next);
                if (values[first][second] < best) { a = first; b = second; best = values[a][b]; }
            }
            int node = count + step;
            sizes[node] = sizes[a] + sizes[b];
            merges.add(new Merge(a, b, squared ? Math.sqrt(best) : best, sizes[node]));
            for (int k : active) {
                if (k == a || k == b) continue;
                Coefficients c = coefficients(method, sizes[a], sizes[b], sizes[k]);
                double value = c.alphaA * values[a][k] + c.alphaB * values[b][k] + c.beta * values[a][b] + c.gamma * Math.abs(values[a][k] - values[b][k]);
                values[node][k] = values[k][node] = value;
            }
            active.remove(Integer.valueOf(a)); active.remove(Integer.valueOf(b)); active.add(node);
        }
        return merges;
    }

    static List<Edge> minimumSpanningTree(double[][] delta) {
        int count = delta.length;
        boolean[] inTree = new boolean[count]; inTree[0] = true;
        double[] key = delta[0].clone(); int[] parent = new int[count];
        List<Edge> edges = new ArrayList<>();
        for (int step = 0; step < count - 1; step++) {
            int chosen = -1;
            for (int u = 0; u < count; u++) if (!inTree[u] && (chosen < 0 || key[u] < key[chosen])) chosen = u;
            inTree[chosen] = true; edges.add(new Edge(parent[chosen], chosen, key[chosen]));
            for (int u = 0; u < count; u++) if (!inTree[u] && delta[chosen][u] < key[u]) { key[u] = delta[chosen][u]; parent[u] = chosen; }
        }
        return edges;
    }
}
