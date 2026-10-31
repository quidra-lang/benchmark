import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Deque;
import java.util.List;

public class Main {
    static void dfs(int v, boolean[][] graph, boolean[] seen, List<Integer> order) {
        seen[v] = true;
        order.add(v);
        for (int w = 0; w < graph.length; w++) {
            if (graph[v][w] && !seen[w]) {
                dfs(w, graph, seen, order);
            }
        }
    }

    static String joined(List<Integer> values) {
        return String.join(" ", values.stream().map(String::valueOf).toList());
    }

    public static void main(String[] args) {
        boolean[][] graph = new boolean[9][9];
        int[][] edges = {{5, 0}, {3, 8}, {7, 2}, {1, 6}, {0, 2}, {5, 3}, {7, 5}, {6, 4}, {8, 7}};
        for (int[] edge : edges) {
            graph[edge[0]][edge[1]] = true;
            graph[edge[1]][edge[0]] = true;
        }
        List<Integer> depth = new ArrayList<>();
        dfs(0, graph, new boolean[9], depth);
        boolean[] seen = new boolean[9];
        Deque<Integer> queue = new ArrayDeque<>();
        List<Integer> breadth = new ArrayList<>();
        seen[0] = true;
        queue.add(0);
        while (!queue.isEmpty()) {
            int v = queue.remove();
            breadth.add(v);
            for (int w = 0; w < 9; w++) {
                if (graph[v][w] && !seen[w]) {
                    seen[w] = true;
                    queue.add(w);
                }
            }
        }
        List<List<Integer>> components = new ArrayList<>();
        Arrays.fill(seen, false);
        for (int v = 0; v < 9; v++) {
            if (!seen[v]) {
                List<Integer> component = new ArrayList<>();
                dfs(v, graph, seen, component);
                Collections.sort(component);
                components.add(component);
            }
        }
        System.out.println("DFS: " + joined(depth));
        System.out.println("BFS: " + joined(breadth));
        System.out.println("components: " + components.size());
        for (int i = 0; i < components.size(); i++) {
            System.out.println("component " + (i + 1) + ": " + joined(components.get(i)));
        }
    }
}
