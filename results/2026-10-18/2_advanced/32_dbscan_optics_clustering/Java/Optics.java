import java.util.*;

final class Optics {
    static final int INF = Integer.MAX_VALUE;
    final int[] core, reach, predecessor;
    final List<Integer> order = new ArrayList<>();
    Optics(List<Point> points, int[][] neighborhoods, int minimum) {
        int count = points.size();
        core = new int[count];
        reach = new int[count];
        predecessor = new int[count];
        Arrays.fill(core, INF);
        Arrays.fill(reach, INF);
        Arrays.fill(predecessor, -1);
        boolean[] processed = new boolean[count], seeds = new boolean[count];
        for (int i = 0; i < count; i++)
            if (neighborhoods[i].length >= minimum) {
                int[] distances = new int[neighborhoods[i].length];
                for (int j = 0; j < distances.length; j++)
                    distances[j] = GridIndex.distance(points.get(i), points.get(neighborhoods[i][j]));
                Arrays.sort(distances);
                core[i] = distances[minimum - 1];
            }
        for (int start = 0; start < count; start++) {
            if (processed[start])
                continue;
            seeds[start] = true;
            while (true) {
                int current = -1;
                for (int i = 0; i < count; i++)
                    if (seeds[i] && (current < 0 || reach[i] < reach[current]))
                        current = i;
                if (current < 0)
                    break;
                seeds[current] = false;
                processed[current] = true;
                order.add(current);
                if (core[current] == INF)
                    continue;
                for (int other : neighborhoods[current])
                    if (!processed[other]) {
                        int distance = Math.max(core[current],
                                                GridIndex.distance(points.get(current), points.get(other)));
                        if (distance < reach[other]) {
                            reach[other] = distance;
                            predecessor[other] = current;
                            seeds[other] = true;
                        }
                    }
            }
        }
    }
}
