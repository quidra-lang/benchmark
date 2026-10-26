import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

public class Main {
    public static void main(String[] args) {
        int[][] edges = {{0, 1, 7}, {0, 2, 3}, {0, 3, 9}, {1, 2, 2}, {2, 4, 6}, {1, 3, 3},
            {3, 4, 4}, {3, 5, 5}, {4, 5, 3}, {4, 6, 8}, {5, 6, 4}};
        int[][] weight = new int[7][7];
        for (int[] edge : edges) {
            weight[edge[0]][edge[1]] = edge[2];
            weight[edge[1]][edge[0]] = edge[2];
        }
        int[] distance = new int[7], previous = new int[7];
        Arrays.fill(distance, Integer.MAX_VALUE);
        Arrays.fill(previous, -1);
        distance[0] = 0;
        boolean[] done = new boolean[7];
        for (int count = 0; count < 7; count++) {
            int u = -1;
            for (int v = 0; v < 7; v++) {
                if (!done[v] && (u < 0 || distance[v] < distance[u])) {
                    u = v;
                }
            }
            done[u] = true;
            for (int v = 0; v < 7; v++) {
                if (weight[u][v] > 0 && distance[u] + weight[u][v] < distance[v]) {
                    distance[v] = distance[u] + weight[u][v];
                    previous[v] = u;
                }
            }
        }
        for (int v = 0; v < 7; v++) {
            List<String> path = new ArrayList<>();
            for (int u = v; u >= 0; u = previous[u]) {
                path.add(String.valueOf((char)('A' + u)));
            }
            Collections.reverse(path);
            System.out.println((char)('A' + v) + ": distance=" + distance[v] + " path=" + String.join("-", path));
        }
    }
}
