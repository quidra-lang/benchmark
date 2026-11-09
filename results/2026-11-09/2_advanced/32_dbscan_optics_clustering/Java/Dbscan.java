import java.util.*;

record Clustering(int[] labels, boolean[] core) {}
final class Dbscan {
    static Clustering cluster(int[][] neighborhoods, int minimum) {
        int[] labels = new int[neighborhoods.length];
        Arrays.fill(labels, -2);
        boolean[] core = new boolean[labels.length];
        for (int i = 0; i < core.length; i++)
            core[i] = neighborhoods[i].length >= minimum;
        int cluster = 0;
        for (int p = 0; p < labels.length; p++) {
            if (labels[p] != -2)
                continue;
            if (!core[p]) {
                labels[p] = -1;
                continue;
            }
            labels[p] = cluster;
            Deque<Integer> queue = new ArrayDeque<>();
            for (int q : neighborhoods[p])
                queue.addLast(q);
            while (!queue.isEmpty()) {
                int q = queue.removeFirst();
                if (labels[q] == -1)
                    labels[q] = cluster;
                else if (labels[q] == -2) {
                    labels[q] = cluster;
                    if (core[q])
                        for (int neighbor : neighborhoods[q])
                            queue.addLast(neighbor);
                }
            }
            cluster++;
        }
        return new Clustering(labels, core);
    }
}
